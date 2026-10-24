import { GoogleGenAI } from '@google/genai';
import { AsyncLocalStorage } from 'node:async_hooks';
import { setTimeout as delay } from 'node:timers/promises';
import { reportSchema, systemInstruction, reviewPrompt, extractOutput, validateReport } from './report.mjs';
import { verificationSchema, verificationInstruction, verificationPrompt, validateVerification } from './verification.mjs';

export class GeminiClient {
  constructor({ apiKey, model = 'gemini-4-argon', sdk, pollMs = 5000, transport = fetch }) {
    this.model = model;
    this.requestContext = new AsyncLocalStorage();
    // Inject only the SDK interface in tests. Production always uses Google's SDK.
    this.sdk = sdk ?? (apiKey ? new GoogleGenAI({ apiKey, vertexai: false, httpOptions: {
      timeout: 120_000,
      fetch: (resource, options) => {
        // SDK 2.31's path uploader does not forward config.abortSignal to every
        // chunk. Its supported transport hook applies our deadline to them all.
        const signal = this.requestContext.getStore();
        if (!signal) return transport(resource, options);
        const sdkSignal = options?.signal ?? (resource instanceof Request ? resource.signal : undefined);
        return transport(resource, { ...options, signal: AbortSignal.any([signal, sdkSignal].filter(Boolean)) });
      }
    } }) : null);
    this.pollMs = pollMs;
  }

  apiError(status) {
    const messages = {
      400: 'Gemini could not process this video or request. Check the video format and configured model.',
      401: 'The server’s Gemini API key was rejected. Update GEMINI_API_KEY.',
      403: 'The Gemini API key does not have access to this model. Check access and billing in Google AI Studio.',
      404: 'Gemini could not find the configured model or uploaded file. Check GEMINI_MODEL or retry.',
      429: 'Gemini’s quota or rate limit was reached. Check billing or try again later.'
    };
    return new Error(messages[status] ?? 'Gemini is temporarily unavailable. Please retry later.');
  }

  async call(operation, { signal, deleting = false } = {}) {
    if (!this.sdk) throw new Error('Add GEMINI_API_KEY to the server to enable reviews.');
    signal?.throwIfAborted();
    try { return await this.requestContext.run(signal, operation); }
    catch (error) {
      if (signal?.aborted) throw signal.reason;
      const status = Number(error.status ?? error.statusCode ?? error.response?.status);
      if (deleting && status === 404) return null;
      // Provider error bodies can contain request data. Return only safe, useful messages.
      throw this.apiError(status);
    }
  }

  options(signal) {
    return { signal: AbortSignal.any([signal, AbortSignal.timeout(120_000)]), timeout_ms: 120_000, maxRetries: 0 };
  }

  async upload(job, path, signal) {
    // Passing a path lets the official Node SDK upload in bounded 8 MiB chunks.
    const file = await this.call(() => this.sdk.files.upload({
      file: path,
      config: { mimeType: job.mimeType, displayName: `Replay ${job.id}`, abortSignal: signal }
    }), { signal });
    if (!file?.name || !file?.uri) throw new Error('Gemini did not accept the uploaded video.');
    return file;
  }

  async completed(id, signal, stage) {
    let interaction;
    do {
      interaction = await this.call(() => this.sdk.interactions.get(id, {}, this.options(signal)), { signal });
      if (['in_progress', 'queued'].includes(interaction.status)) await delay(this.pollMs, undefined, { signal });
    } while (['in_progress', 'queued'].includes(interaction.status));
    if (interaction.status !== 'completed') {
      throw new Error(`Gemini could not complete the ${stage}. No unverified feedback was published. Try a clearer or shorter recording.`);
    }
    try { return JSON.parse(extractOutput(interaction)); }
    catch { throw new Error(`Gemini returned an unreadable ${stage}. No unverified feedback was published. Please retry.`); }
  }

  async createInteraction(job, instruction, prompt, schema, signal) {
    const interaction = await this.call(() => this.sdk.interactions.create({
      model: this.model,
      background: true,
      system_instruction: instruction,
      input: [
        { type: 'video', uri: job.googleFile.uri, mime_type: job.mimeType, processing: 'agentic' },
        { type: 'text', text: prompt }
      ],
      generation_config: { thinking_level: 'medium', max_output_tokens: 16_384 },
      response_format: { type: 'text', mime_type: 'application/json', schema }
    }, this.options(signal)), { signal });
    if (!interaction.id) throw new Error('Gemini did not create the review. Please retry.');
    return interaction.id;
  }

  async analyze(job, path, update, signal) {
    const mark = async patch => update({ reviewTiming: { ...job.reviewTiming, ...patch } });
    if (!job.reviewTiming?.startedAt) await mark({ startedAt: new Date().toISOString() });
    if (!job.googleFile) {
      const file = await this.upload(job, path, signal);
      await update({ googleFile: file });
    }
    if (!job.interactionID && !job.candidateReport) {
      let file = await this.call(() => this.sdk.files.get({ name: job.googleFile.name, config: { abortSignal: signal } }), { signal });
      while (file.state === 'PROCESSING') {
        await delay(this.pollMs, undefined, { signal });
        file = await this.call(() => this.sdk.files.get({ name: job.googleFile.name, config: { abortSignal: signal } }), { signal });
      }
      if (file.state !== 'ACTIVE' || !file.uri) throw new Error('Gemini could not read this video. Try exporting it as an MP4.');
      await update({ googleFile: file, status: 'analyzing' });
      await mark({ analysisStartedAt: new Date().toISOString() });
      const interactionID = await this.createInteraction(job, systemInstruction, reviewPrompt(job), reportSchema, signal);
      await update({ interactionID });
    }
    if (!job.candidateReport) {
      await update({ status: 'analyzing' });
      const candidateReport = validateReport(await this.completed(job.interactionID, signal, 'analysis'), job.durationSeconds);
      // Persist the hypothesis before starting the evidence recheck, so a restart
      // resumes the existing work instead of paying for another first pass.
      await update({ candidateReport, status: 'verifying', reviewTiming: { ...job.reviewTiming, analysisCompletedAt: new Date().toISOString() } });
    }
    validateReport(job.candidateReport, job.durationSeconds);
    await update({ status: 'verifying' });
    if (!job.verificationInteractionID) {
      await mark({ verificationStartedAt: new Date().toISOString() });
      const verificationInteractionID = await this.createInteraction(job, verificationInstruction,
        verificationPrompt(job, job.candidateReport), verificationSchema, signal);
      await update({ verificationInteractionID });
    }
    const result = await this.completed(job.verificationInteractionID, signal, 'evidence recheck');
    const completedAt = new Date().toISOString();
    const report = validateVerification(result, job.candidateReport, job.durationSeconds, this.model, completedAt);
    await mark({ completedAt, totalSeconds: Math.max(0, (Date.parse(completedAt) - Date.parse(job.reviewTiming.startedAt)) / 1000) });
    return report;
  }

  async cleanup(job) {
    const tasks = [];
    if (job.googleFile?.name) tasks.push(this.call(() => this.sdk.files.delete({ name: job.googleFile.name }), { deleting: true }));
    for (const id of new Set([job.interactionID, job.verificationInteractionID].filter(Boolean))) {
      tasks.push(this.call(() => this.sdk.interactions.delete(id, {}, { timeout_ms: 90_000, maxRetries: 0 }), { deleting: true }));
    }
    return (await Promise.allSettled(tasks)).every(result => result.status === 'fulfilled');
  }
}
