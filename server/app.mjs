import http from 'node:http';
import { mkdir, readFile, writeFile, rename, readdir, stat, open, rm } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { timingSafeEqual } from 'node:crypto';

export const MAX_BYTES = 2_000_000_000;
export const CHUNK_BYTES = 8 * 1024 * 1024;
const MAX_STORED_BYTES = 8_000_000_000;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const busyStates = new Set(['queued', 'processing', 'analyzing']);
const terminalStates = new Set(['complete', 'failed']);

class HTTPError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function json(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  response.end(JSON.stringify(body));
}

async function body(request, maximum) {
  const length = Number(request.headers['content-length']);
  if (Number.isFinite(length) && length > maximum) throw new HTTPError(413, 'This upload chunk is too large.');
  const chunks = [];
  let size = 0;
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maximum) throw new HTTPError(413, 'The request is too large.');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function jsonBody(request) {
  try { return JSON.parse((await body(request, 16_384)).toString('utf8')); }
  catch (error) { if (error instanceof HTTPError) throw error; throw new HTTPError(400, 'Send a valid JSON request.'); }
}

export function validateMetadata(input) {
  if (!input || typeof input !== 'object' || !UUID.test(input.id ?? '')) throw new HTTPError(400, 'A valid session ID is required.');
  for (const [key, max] of [['title', 120], ['activity', 80], ['goal', 2000], ['criteria', 4000]]) {
    if (typeof input[key] !== 'string' || input[key].length > max || (['title', 'activity'].includes(key) && !input[key].trim())) {
      throw new HTTPError(400, `Provide a valid ${key} (up to ${max} characters).`);
    }
  }
  if (!Number.isSafeInteger(input.byteCount) || input.byteCount <= 0 || input.byteCount > MAX_BYTES) {
    throw new HTTPError(400, 'Choose a video smaller than 2 GB.');
  }
  if (!Number.isFinite(input.durationSeconds) || input.durationSeconds <= 0 || input.durationSeconds > 3601) {
    throw new HTTPError(400, 'Choose a video up to 60 minutes long.');
  }
  if (!['video/mp4', 'video/quicktime'].includes(input.mimeType)) throw new HTTPError(400, 'Choose an MP4 or MOV video.');
  return Object.fromEntries(['id', 'title', 'activity', 'goal', 'criteria', 'byteCount', 'durationSeconds', 'mimeType'].map(key => [key, input[key]]));
}

export async function createApp({ dataDir, token, provider, configured = true, retentionMs = 24 * 60 * 60 * 1000 }) {
  if (typeof token !== 'string' || token.length < 32) throw new Error('Set APP_TOKEN to a random token of at least 32 characters.');
  const root = resolve(dataDir);
  await mkdir(root, { recursive: true, mode: 0o700 });
  const jobs = new Map();
  const locks = new Map();
  let working = false;
  let closing = false;
  let workerPromise;
  let controller;
  const metadataPath = id => join(root, `${id}.json`);
  const videoPath = id => join(root, `${id}.video`);

  async function save(job) {
    job.updatedAt = new Date().toISOString();
    const target = metadataPath(job.id);
    await writeFile(`${target}.tmp`, JSON.stringify(job), { mode: 0o600 });
    await rename(`${target}.tmp`, target);
  }

  async function lock(id, fn) {
    const previous = locks.get(id) ?? Promise.resolve();
    const current = previous.catch(() => {}).then(fn);
    locks.set(id, current);
    try { return await current; }
    finally { if (locks.get(id) === current) locks.delete(id); }
  }

  async function uploadedBytes(job) {
    if (job.status === 'complete') return job.byteCount;
    try { return (await stat(videoPath(job.id))).size; }
    catch (error) { if (error.code === 'ENOENT') return 0; throw error; }
  }

  async function publicJob(job) {
    return {
      id: job.id, status: job.status, byteCount: job.byteCount,
      uploadedBytes: await uploadedBytes(job), report: job.report ?? null,
      error: job.error ?? null, model: provider.model, updatedAt: job.updatedAt
    };
  }

  for (const filename of await readdir(root)) {
    if (!filename.endsWith('.json') || !UUID.test(filename.slice(0, -5))) continue;
    let job;
    try { job = JSON.parse(await readFile(join(root, filename), 'utf8')); }
    catch { console.warn(`Skipped unreadable session metadata: ${filename}`); continue; }
    if (job.id !== filename.slice(0, -5)) continue;
    if (busyStates.has(job.status)) job.status = 'queued';
    jobs.set(job.id, job);
  }

  async function cleanupRemote(job) {
    if (!job.googleFile && !job.interactionID) return true;
    let cleaned = false;
    try { cleaned = await provider.cleanup(job); } catch { /* Retried by the retention sweep. */ }
    if (cleaned) { delete job.googleFile; delete job.interactionID; await save(job); }
    return cleaned;
  }

  async function sweep() {
    for (const job of jobs.values()) {
      if (busyStates.has(job.status) || locks.has(job.id)) continue;
      await lock(job.id, async () => {
        const expired = Date.now() - Date.parse(job.createdAt) > retentionMs;
        if (terminalStates.has(job.status) || expired) await cleanupRemote(job);
        if (expired && !job.googleFile && !job.interactionID) {
          await rm(videoPath(job.id), { force: true });
          await rm(metadataPath(job.id), { force: true });
          jobs.delete(job.id);
        }
      });
    }
  }

  function startWorker() {
    if (working || closing || !configured) return;
    working = true;
    workerPromise = (async () => {
      while (!closing) {
        const job = [...jobs.values()].find(item => item.status === 'queued');
        if (!job) break;
        controller = new AbortController();
        const signal = AbortSignal.any([controller.signal, AbortSignal.timeout(2 * 60 * 60 * 1000)]);
        const update = async patch => { Object.assign(job, patch); await save(job); };
        try {
          await update({ status: 'processing', error: null });
          const report = await provider.analyze(job, videoPath(job.id), update, signal);
          await update({ status: 'complete', report });
          await rm(videoPath(job.id), { force: true });
        } catch (error) {
          if (closing) { await update({ status: 'queued' }); break; }
          const message = signal.aborted
            ? 'The review took too long. Retry or choose a shorter recording.'
            : error.message || 'The analysis was interrupted. Please retry.';
          await update({ status: 'failed', error: message });
        }
        await cleanupRemote(job);
        controller = undefined;
      }
    })().catch(error => console.error('Worker could not save a session:', error.code ?? 'storage error'))
      .finally(() => {
        working = false;
        if (!closing && [...jobs.values()].some(job => job.status === 'queued')) queueMicrotask(startWorker);
      });
  }

  const server = http.createServer(async (request, response) => {
    try {
      const url = new URL(request.url, 'http://localhost');
      if (request.method === 'GET' && url.pathname === '/health') {
        return json(response, 200, { ok: true });
      }
      const supplied = Buffer.from(request.headers.authorization ?? '');
      const expected = Buffer.from(`Bearer ${token}`);
      if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) throw new HTTPError(401, 'The connection token is incorrect. Update it in Settings.');
      if (request.method === 'GET' && url.pathname === '/api/config') {
        return json(response, 200, { configured, model: provider.model, maxBytes: MAX_BYTES, maxDurationSeconds: 3600, chunkBytes: CHUNK_BYTES });
      }
      if (request.method === 'POST' && url.pathname === '/api/sessions') {
        const input = validateMetadata(await jsonBody(request));
        return await lock('create', async () => {
          const existing = jobs.get(input.id);
          if (existing) {
            if (Object.keys(input).some(key => existing[key] !== input[key])) throw new HTTPError(409, 'This session already exists with different video details.');
            return json(response, 200, await publicJob(existing));
          }
          const reserved = [...jobs.values()].filter(job => job.status !== 'complete').reduce((sum, job) => sum + job.byteCount, 0);
          if (jobs.size >= 100 || reserved + input.byteCount > MAX_STORED_BYTES) throw new HTTPError(429, 'The review server is full. Remove an old session or try again later.');
          const job = { ...input, status: 'uploading', createdAt: new Date().toISOString() };
          await save(job);
          jobs.set(job.id, job);
          json(response, 201, await publicJob(job));
        });
      }
      const match = url.pathname.match(/^\/api\/sessions\/([^/]+)(?:\/(video|analyze))?$/);
      if (!match || !UUID.test(match[1])) throw new HTTPError(404, 'Session not found.');
      const [, id, action] = match;
      const job = jobs.get(id);
      if (!job) throw new HTTPError(404, 'This server session has expired. Upload the video again.');
      if (request.method === 'GET' && !action) return json(response, 200, await publicJob(job));
      await lock(id, async () => {
        if (request.method === 'PUT' && action === 'video') {
          if (job.status !== 'uploading') throw new HTTPError(409, 'This session is already being reviewed.');
          const offset = Number(request.headers['upload-offset']);
          const size = await uploadedBytes(job);
          if (request.headers['upload-offset'] === undefined || !Number.isSafeInteger(offset) || offset !== size) {
            throw new HTTPError(409, 'Upload offset changed. Resume from the server’s current offset.');
          }
          const chunk = await body(request, CHUNK_BYTES);
          if (!chunk.length || size + chunk.length > job.byteCount) throw new HTTPError(400, 'This upload does not match the expected video size.');
          const file = await open(videoPath(id), 'a', 0o600);
          try { await file.writeFile(chunk); await file.sync(); } finally { await file.close(); }
          await save(job);
          return json(response, 200, await publicJob(job));
        }
        if (request.method === 'POST' && action === 'analyze') {
          if (!configured) throw new HTTPError(503, 'Add GEMINI_API_KEY to the server’s .env file and restart the server to enable reviews.');
          if (job.status === 'complete' || busyStates.has(job.status)) return json(response, 200, await publicJob(job));
          if (await uploadedBytes(job) !== job.byteCount) throw new HTTPError(409, 'Finish uploading the video before requesting a review.');
          // Never reuse a failed/expired interaction on a deliberate retry.
          if (!await cleanupRemote(job)) throw new HTTPError(503, 'The previous review is still being cleaned up. Please retry shortly.');
          job.status = 'queued'; job.error = null;
          await save(job);
          json(response, 202, await publicJob(job));
          startWorker();
          return;
        }
        if (request.method === 'DELETE' && !action) {
          if (busyStates.has(job.status)) throw new HTTPError(409, 'Wait for the current review to finish before deleting this session.');
          if (!await cleanupRemote(job)) throw new HTTPError(503, 'Could not remove the remote video yet. Please try again shortly.');
          await rm(videoPath(id), { force: true });
          await rm(metadataPath(id), { force: true });
          jobs.delete(id);
          return json(response, 200, { deleted: true });
        }
        throw new HTTPError(405, 'This action is not supported.');
      });
    } catch (error) {
      if (!response.headersSent && !response.destroyed) json(response, error.status ?? 500, {
        error: error instanceof HTTPError ? error.message : 'The server could not finish this request. Please try again.'
      });
    }
  });
  server.requestTimeout = 5 * 60 * 1000;
  server.headersTimeout = 30_000;
  const sweeper = setInterval(() => { sweep().catch(() => console.warn('Session cleanup will retry.')); }, 60_000);
  sweeper.unref();
  await sweep();
  startWorker();
  return {
    server,
    async close() {
      closing = true;
      clearInterval(sweeper);
      controller?.abort();
      await workerPromise;
      if (server.listening) {
        server.closeIdleConnections();
        await new Promise((resolveClose, reject) => server.close(error => error ? reject(error) : resolveClose()));
      }
    }
  };
}
