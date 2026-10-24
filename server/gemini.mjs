import { createReadStream } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { reportSchema, systemInstruction, reviewPrompt, extractOutput, validateReport } from './report.mjs';

const base = 'https://generativelanguage.googleapis.com';

export class GeminiClient {
  constructor({ apiKey, model = 'gemini-4-argon', fetchImpl = fetch, pollMs = 5000 }) {
    this.apiKey = apiKey;
    this.model = model;
    this.fetch = fetchImpl;
    this.pollMs = pollMs;
  }

  async request(path, options = {}) {
    const response = await this.fetch(`${base}/v1beta/${path}`, {
      ...options,
      headers: { 'x-goog-api-key': this.apiKey, 'Content-Type': 'application/json', ...options.headers },
      signal: options.signal ?? AbortSignal.timeout(90_000)
    });
    if (options.method === 'DELETE' && response.status === 404) return null;
    if (!response.ok) throw this.apiError(response.status);
    return response.status === 204 ? null : response.json();
  }

  apiError(status) {
    const messages = {
      400: 'Gemini could not process this video or request. Check the video format and configured model.',
      401: 'The server’s Gemini API key was rejected. Update GEMINI_API_KEY.',
      403: 'The Gemini API key does not have access to this model. Check access and billing in Google AI Studio.',
      404: 'Gemini could not find the configured model or uploaded file. Check GEMINI_MODEL or retry.',
      429: 'Gemini’s quota or rate limit was reached. Check billing or try again later.'
    };
    return new Error(messages[status] ?? `Gemini is temporarily unavailable (HTTP ${status}). Please retry later.`);
  }

  async upload(job, path, signal) {
    const started = await this.fetch(`${base}/upload/v1beta/files`, {
      method: 'POST',
      headers: {
        'x-goog-api-key': this.apiKey,
        'Content-Type': 'application/json',
        'X-Goog-Upload-Protocol': 'resumable',
        'X-Goog-Upload-Command': 'start',
        'X-Goog-Upload-Header-Content-Length': String(job.byteCount),
        'X-Goog-Upload-Header-Content-Type': job.mimeType
      },
      body: JSON.stringify({ file: { display_name: `Replay ${job.id}` } }),
      signal: AbortSignal.any([signal, AbortSignal.timeout(90_000)])
    });
    if (!started.ok) throw this.apiError(started.status);
    const uploadURL = started.headers.get('x-goog-upload-url');
    const parsed = uploadURL && new URL(uploadURL);
    if (!parsed || parsed.protocol !== 'https:' ||
        !(parsed.hostname === 'generativelanguage.googleapis.com' || parsed.hostname.endsWith('.googleapis.com'))) {
      throw new Error('Gemini did not return a valid upload destination. Please retry.');
    }
    const stream = createReadStream(path);
    try {
      const response = await this.fetch(uploadURL, {
        method: 'POST',
        headers: {
          'Content-Length': String(job.byteCount),
          'Content-Type': job.mimeType,
          'X-Goog-Upload-Offset': '0',
          'X-Goog-Upload-Command': 'upload, finalize'
        },
        body: stream,
        duplex: 'half',
        signal
      });
      if (!response.ok) throw this.apiError(response.status);
      const result = await response.json();
      if (!result.file?.name || !result.file?.uri) throw new Error('Gemini did not accept the uploaded video.');
      return result.file;
    } finally {
      stream.destroy();
    }
  }

  async analyze(job, path, update, signal) {
    if (!job.googleFile) {
      const file = await this.upload(job, path, signal);
      await update({ googleFile: file });
    }
    if (!job.interactionID) {
      let file = await this.request(job.googleFile.name, { signal });
      while (file.state === 'PROCESSING') {
        await delay(this.pollMs, undefined, { signal });
        file = await this.request(job.googleFile.name, { signal });
      }
      if (file.state !== 'ACTIVE') throw new Error('Gemini could not read this video. Try exporting it as an MP4.');
      await update({ status: 'analyzing' });
      const interaction = await this.request('interactions', {
        method: 'POST',
        body: JSON.stringify({
          model: this.model,
          background: true,
          system_instruction: systemInstruction,
          input: [
            { type: 'video', uri: file.uri, mime_type: job.mimeType, processing: 'agentic' },
            { type: 'text', text: reviewPrompt(job) }
          ],
          generation_config: { thinking_level: 'medium', max_output_tokens: 16_384 },
          response_format: { type: 'text', mime_type: 'application/json', schema: reportSchema }
        }),
        signal: AbortSignal.any([signal, AbortSignal.timeout(120_000)])
      });
      if (!interaction.id) throw new Error('Gemini did not create the analysis. Please retry.');
      await update({ interactionID: interaction.id });
    }
    let interaction = await this.request(`interactions/${encodeURIComponent(job.interactionID)}`, { signal });
    while (['in_progress', 'queued'].includes(interaction.status)) {
      await delay(this.pollMs, undefined, { signal });
      interaction = await this.request(`interactions/${encodeURIComponent(job.interactionID)}`, { signal });
    }
    if (interaction.status !== 'completed') {
      throw new Error('Gemini could not complete this analysis. Try a clearer or shorter recording.');
    }
    let parsed;
    try { parsed = JSON.parse(extractOutput(interaction)); }
    catch { throw new Error('Gemini returned an unreadable report. Please retry the analysis.'); }
    return validateReport(parsed, job.durationSeconds);
  }

  async cleanup(job) {
    const tasks = [];
    if (job.googleFile?.name) tasks.push(this.request(job.googleFile.name, { method: 'DELETE' }));
    if (job.interactionID) tasks.push(this.request(`interactions/${encodeURIComponent(job.interactionID)}`, { method: 'DELETE' }));
    const results = await Promise.allSettled(tasks);
    return results.every(result => result.status === 'fulfilled');
  }
}
