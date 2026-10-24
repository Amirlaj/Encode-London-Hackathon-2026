import { open, readFile, stat, mkdir, writeFile, rename } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { basename, dirname, extname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { readEnvironment, serverOrigin } from './lib/config.mjs';

const HELP = `Usage: npm run rehearse -- --video demo-videos/clip.mp4 --duration 25
  [--task "Describe the work and intended result"] [--criteria-file rubric.txt]
  [--resume artifacts/rehearsal-SESSION-ID.json]

This sends the selected video to your Replay server and Google Gemini for paid
analysis. Use a consented MP4 or MOV clip (up to 60 minutes and 2 GB).
--duration is the actual clip duration in seconds; this tool does not measure it.
APP_TOKEN and optional SERVER_URL are read from .env or the environment.
SERVER_URL defaults to http://127.0.0.1:8787; remote servers require HTTPS.

The tool uploads in bounded chunks, resumes from the server's offset, and waits
through verification. Private timing and actual report JSON go into artifacts/.
Resume an interrupted run with the same video, duration, task and criteria.
No mock fallback is used. A completed verification is not proof of accuracy.
Exit codes: 0 verified completion within 180s; 1 setup/server/model failure;
2 verified completion over 180s or no completion within 15 minutes.
The 180s clock includes upload and any pause before resuming. --help is offline.`;

export function parseArguments(args) {
  if (args.includes('--help') || args.includes('-h')) return { help: true };
  const allowed = new Map([['--video', 'video'], ['--duration', 'duration'], ['--task', 'task'], ['--criteria-file', 'criteriaFile'], ['--resume', 'resume']]);
  const result = { task: '' };
  const seen = new Set();
  for (let index = 0; index < args.length; index += 2) {
    const name = allowed.get(args[index]);
    if (!name || args[index + 1] === undefined || args[index + 1].startsWith('--')) throw new Error(`Invalid or incomplete option: ${args[index]}. Use --help.`);
    if (seen.has(name)) throw new Error(`Repeated option: ${args[index]}.`);
    seen.add(name);
    result[name] = args[index + 1];
  }
  if (!result.video) throw new Error('Provide --video with the path to a consented MP4 or MOV clip.');
  result.duration = Number(result.duration);
  if (!Number.isFinite(result.duration) || result.duration <= 0 || result.duration > 3600) throw new Error('Provide --duration in seconds, greater than zero and no more than 3600.');
  if (result.task.length > 2000) throw new Error('--task must be no more than 2000 characters.');
  return result;
}

export class RehearsalError extends Error {
  constructor(kind, message, status) { super(message); this.kind = kind; this.status = status; }
}

export function createClient({ origin, token, fetchImpl = fetch }) {
  origin = serverOrigin(origin);
  return async function request(path, { method = 'GET', body, headers = {} } = {}) {
    let response;
    try {
      response = await fetchImpl(`${origin}${path}`, {
        method, body, headers: { ...headers, Authorization: `Bearer ${token}` },
        redirect: 'error', signal: AbortSignal.timeout(60_000)
      });
    } catch { throw new RehearsalError('server_error', 'Could not reach the server or the request timed out. Check the server, then resume this artifact.'); }
    let payload;
    try { payload = await response.json(); } catch { throw new RehearsalError('server_error', 'The server returned an invalid JSON response.', response.status); }
    if (!response.ok) throw new RehearsalError('server_error', `Server HTTP ${response.status}: ${typeof payload.error === 'string' ? payload.error : 'request rejected'}`, response.status);
    return payload;
  };
}

// The file reader and transport are injected so tests never contact Google.
export async function runRehearsal({ artifact, request, readChunk, save, now = Date.now, sleep = ms => new Promise(resolveSleep => setTimeout(resolveSleep, ms)), log = console.log, pollMs = 2000, maxWaitMs = 15 * 60_000 }) {
  const runStart = now();
  const start = Date.parse(artifact.startedAt);
  const elapsed = () => Math.max(0, (now() - start) / 1000);
  async function checkpoint(stage) {
    const timestamp = now();
    const previous = artifact.stages.at(-1);
    if (previous?.stage !== stage) {
      if (previous && !previous.endedAt) { previous.endedAt = new Date(timestamp).toISOString(); previous.seconds = (timestamp - Date.parse(previous.startedAt)) / 1000; }
      artifact.stages.push({ stage, startedAt: new Date(timestamp).toISOString() });
      log(`${stage} — ${elapsed().toFixed(1)}s elapsed`);
    }
    artifact.elapsedSeconds = elapsed();
    artifact.updatedAt = new Date(timestamp).toISOString();
    await save(artifact);
  }
  const path = `/api/sessions/${artifact.session.id}`;
  try {
    await checkpoint('connecting');
    const config = await request('/api/config');
    if (!config.configured) throw new RehearsalError('setup_error', 'The server has no Gemini API key. Configure it and restart the server.');
    if (config.model !== 'gemini-4-argon') throw new RehearsalError('setup_error', 'This submission rehearsal requires the server model gemini-4-argon.');
    artifact.model = config.model;
    if (artifact.session.byteCount > config.maxBytes || artifact.session.durationSeconds > config.maxDurationSeconds) throw new RehearsalError('setup_error', 'The clip exceeds this server’s video size or duration limit.');
    const chunkSize = Math.min(8 * 1024 * 1024, config.chunkBytes);
    if (!Number.isSafeInteger(chunkSize) || chunkSize <= 0) throw new RehearsalError('server_error', 'The server advertised an invalid upload chunk size.');
    let job = await request('/api/sessions', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(artifact.session) });
    if (job.reviewTiming) artifact.reviewTiming = job.reviewTiming;
    if (job.status === 'uploading') {
      await checkpoint('uploading');
      let retries = 0;
      const validateOffset = () => {
        if (!Number.isSafeInteger(job.uploadedBytes) || job.uploadedBytes < 0 || job.uploadedBytes > artifact.session.byteCount) throw new RehearsalError('server_error', 'The server returned an invalid upload offset.');
      };
      validateOffset();
      while (job.uploadedBytes < artifact.session.byteCount) {
        const offset = job.uploadedBytes;
        const chunk = await readChunk(offset, Math.min(chunkSize, artifact.session.byteCount - offset));
        if (!chunk.length) throw new RehearsalError('setup_error', 'The video changed or ended unexpectedly during upload.');
        try {
          job = await request(`${path}/video`, { method: 'PUT', headers: { 'Content-Type': artifact.session.mimeType, 'Upload-Offset': String(offset) }, body: chunk });
          if (job.uploadedBytes <= offset) throw new RehearsalError('server_error', 'The server did not advance the upload offset.');
          retries = 0;
        } catch (error) {
          if (!(error instanceof RehearsalError) || (error.status && error.status !== 409 && error.status < 500) || ++retries > 3) throw error;
          await sleep(500 * retries);
          // A lost response may still have committed the chunk. Never send it twice.
          job = await request(path);
          if (job.status !== 'uploading') break;
        }
        validateOffset();
        artifact.uploadedBytes = job.uploadedBytes;
        await checkpoint('uploading');
      }
      if (job.status === 'uploading') job = await request(`${path}/analyze`, { method: 'POST' });
    }
    while (true) {
      if (job.model) artifact.model = job.model;
      if (job.reviewTiming) artifact.reviewTiming = job.reviewTiming;
      if (job.status === 'failed') throw new RehearsalError('model_error', job.error || 'The server’s Gemini review failed. No feedback was substituted.');
      if (job.status === 'complete') {
        artifact.report = job.report;
        artifact.verification = job.report?.verification ?? null;
        if (artifact.model !== 'gemini-4-argon' || artifact.verification?.status !== 'completed' || artifact.verification.model !== 'gemini-4-argon') throw new RehearsalError('verification_error', 'The report did not contain a completed Argon verification. This is not a successful rehearsal.');
        const { candidateIssueCount, confirmedIssueCount, removedIssueCount } = artifact.verification;
        if (![candidateIssueCount, confirmedIssueCount, removedIssueCount].every(count => Number.isSafeInteger(count) && count >= 0) || candidateIssueCount !== confirmedIssueCount + removedIssueCount || !Array.isArray(job.report.issues) || job.report.issues.length !== confirmedIssueCount) {
          throw new RehearsalError('verification_error', 'The verification counts do not match the published report. This is not a successful rehearsal.');
        }
        await checkpoint('complete');
        artifact.completedWithinDemoWindow = elapsed() <= 180;
        artifact.outcome = artifact.completedWithinDemoWindow ? 'completed' : 'too_slow';
        artifact.elapsedSeconds = elapsed();
        artifact.finishedAt = new Date(now()).toISOString();
        await save(artifact);
        return artifact;
      }
      if (!['queued', 'processing', 'analyzing', 'verifying'].includes(job.status)) throw new RehearsalError('server_error', `Unexpected server status: ${job.status}.`);
      await checkpoint(job.status);
      if (now() - runStart >= maxWaitMs) throw new RehearsalError('latency_timeout', 'The review did not finish within 15 minutes. It may still be running; resume this artifact to retrieve it.');
      await sleep(pollMs);
      job = await request(path);
    }
  } catch (error) {
    artifact.outcome = error.kind ?? 'client_error';
    artifact.error = error.message;
    artifact.completedWithinDemoWindow = false;
    await checkpoint(artifact.outcome);
    throw error;
  }
}

async function main() {
  const args = parseArguments(process.argv.slice(2));
  if (args.help) { console.log(HELP); return; }
  const { env } = await readEnvironment();
  const token = env.APP_TOKEN?.trim();
  if (!token || token.length < 32) throw new Error('Set APP_TOKEN in .env to the same token as your running Replay server (at least 32 characters).');
  const origin = serverOrigin(env.SERVER_URL);
  const video = resolve(args.video);
  const info = await stat(video);
  if (!info.isFile() || info.size <= 0 || info.size > 2_000_000_000) throw new Error('Choose a nonempty video file no larger than 2 GB.');
  const extension = extname(video).toLowerCase();
  if (!['.mp4', '.mov', '.m4v'].includes(extension)) throw new Error('Choose an MP4, M4V or MOV video.');
  const criteria = args.criteriaFile ? await readFile(resolve(args.criteriaFile), 'utf8') : '';
  if (criteria.length > 4000) throw new Error('The criteria file must be no more than 4000 characters.');
  const fingerprint = { path: video, byteCount: info.size, modifiedAt: info.mtimeMs };
  let artifact;
  if (args.resume) {
    artifact = JSON.parse(await readFile(resolve(args.resume), 'utf8'));
    if (artifact.schemaVersion !== 1 || !/^[a-f0-9-]{36}$/i.test(artifact.session?.id ?? '') || !Array.isArray(artifact.stages) || !Number.isFinite(Date.parse(artifact.startedAt))) throw new Error('This is not a valid rehearsal artifact.');
    if (JSON.stringify(artifact.video) !== JSON.stringify(fingerprint) || artifact.serverURL !== origin || artifact.session.durationSeconds !== args.duration || artifact.session.goal !== args.task || artifact.session.criteria !== criteria) throw new Error('Resume requires the original, unchanged video, duration, task, criteria and SERVER_URL.');
    delete artifact.error;
  } else {
    artifact = {
      schemaVersion: 1, startedAt: new Date().toISOString(), serverURL: origin, video: fingerprint, stages: [],
      session: { id: randomUUID(), title: basename(video).slice(0, 120), activity: 'Work review', goal: args.task, criteria, durationSeconds: args.duration, byteCount: info.size, mimeType: extension === '.mov' ? 'video/quicktime' : 'video/mp4' }
    };
  }
  const artifactPath = args.resume ? resolve(args.resume) : resolve('artifacts', `rehearsal-${artifact.session.id}.json`);
  const secrets = [token, env.GEMINI_API_KEY].filter(Boolean);
  const redact = message => secrets.reduce((text, secret) => text.replaceAll(secret, '[redacted]'), message);
  const save = async value => {
    await mkdir(dirname(artifactPath), { recursive: true, mode: 0o700 });
    const content = JSON.stringify({ ...value, ...(value.error ? { error: redact(value.error) } : {}) }, null, 2);
    await writeFile(`${artifactPath}.tmp`, `${content}\n`, { mode: 0o600 });
    await rename(`${artifactPath}.tmp`, artifactPath);
  };
  await save(artifact);
  console.log('This uploads the selected video to your Replay server and Google Gemini for paid analysis.');
  console.log(`Private rehearsal artifact: ${artifactPath}`);
  const file = await open(video, 'r');
  try {
    const result = await runRehearsal({ artifact, request: createClient({ origin, token }), save, readChunk: async (offset, size) => {
      const buffer = Buffer.allocUnsafe(size);
      const { bytesRead } = await file.read(buffer, 0, size, offset);
      return buffer.subarray(0, bytesRead);
    } });
    console.log(`Actual ${result.model} report with completed verification saved (${result.elapsedSeconds.toFixed(1)}s).`);
    console.log(result.completedWithinDemoWindow ? 'Finished within the 180s demo window. Review the saved feedback for accuracy yourself.' : 'Completed, but exceeded the 180s demo window. Rehearse a shorter clip or faster connection.');
    process.exitCode = result.completedWithinDemoWindow ? 0 : 2;
  } catch (error) {
    console.error(redact(error.message));
    console.error(`Details saved in ${artifactPath}. No mock report was used. Resume with --resume and the original arguments.`);
    process.exitCode = error.kind === 'latency_timeout' ? 2 : 1;
  } finally { await file.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
