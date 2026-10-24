import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { createApp, validateMetadata, MAX_BYTES } from '../app.mjs';
import { GeminiClient } from '../gemini.mjs';
import { extractOutput, validateReport } from '../report.mjs';

const token = 'test-token-only-not-a-real-secret-123456789';
const report = {
  verdict: 'needs_work', headline: 'Recover after the shot', summary: 'Recovery is late after a wide forehand.',
  confidence: 'medium', strengths: ['Early shoulder turn'], improvements: ['Recover toward the centre'],
  moments: [{ seconds: 1, title: 'Late recovery', observation: 'The player stays wide.', suggestion: 'Take two recovery steps.', kind: 'improvement' }],
  criteria: [{ name: 'Recovery', assessment: 'partly_met', evidence: 'Visible delay after contact.' }],
  nextPractice: 'Practice recovery steps for five minutes.', limitations: ['One camera angle.']
};
const metadata = (extra = {}) => ({ id: randomUUID(), title: 'Practice', activity: 'Tennis', goal: 'Recover earlier', criteria: '', durationSeconds: 4, byteCount: 16, mimeType: 'video/mp4', ...extra });

async function fixture(t, { provider, configured = true, dataDir } = {}) {
  const dir = dataDir ?? await mkdtemp(join(tmpdir(), 'replay-test-'));
  let uploads = 0;
  const defaultProvider = {
    model: 'gemini-4-argon',
    async analyze(job, path, update) {
      const bytes = await readFile(path);
      assert.equal(bytes.length, job.byteCount);
      uploads++;
      await update({ status: 'analyzing' });
      return structuredClone(report);
    },
    async cleanup() { return true; }
  };
  const app = await createApp({ dataDir: dir, token, configured, provider: provider ?? defaultProvider });
  await new Promise(resolve => app.server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${app.server.address().port}`;
  t.after(async () => { await app.close(); if (!dataDir) await rm(dir, { recursive: true, force: true }); });
  const request = async (path, { method = 'GET', value, bytes, offset, auth = token } = {}) => {
    const headers = { Authorization: `Bearer ${auth}` };
    if (value) headers['Content-Type'] = 'application/json';
    if (offset !== undefined) headers['Upload-Offset'] = String(offset);
    const response = await fetch(`${origin}${path}`, { method, headers, body: value ? JSON.stringify(value) : bytes });
    return { status: response.status, body: await response.json() };
  };
  return { app, dir, request, uploads: () => uploads };
}

async function finish(request, id) {
  for (let index = 0; index < 100; index++) {
    const response = await request(`/api/sessions/${id}`);
    if (['complete', 'failed'].includes(response.body.status)) return response.body;
    await delay(10);
  }
  throw new Error('Review did not finish');
}

test('accepts hour-long metadata, rejects oversize, invalid duration, and path traversal', () => {
  assert.equal(validateMetadata(metadata({ durationSeconds: 3600, byteCount: 1_100_000_000 })).durationSeconds, 3600);
  for (const invalid of [{ byteCount: MAX_BYTES + 1 }, { durationSeconds: 3602 }, { durationSeconds: NaN }, { id: '../outside' }, { mimeType: 'text/html' }]) {
    assert.throws(() => validateMetadata(metadata(invalid)));
  }
});

test('requires token and never exposes provider credentials in config', async t => {
  const { request } = await fixture(t);
  assert.equal((await request('/api/config', { auth: 'wrong' })).status, 401);
  const config = await request('/api/config');
  assert.equal(config.status, 200);
  assert.equal(config.body.model, 'gemini-4-argon');
  assert.equal(config.body.chunkBytes, 8 * 1024 * 1024);
  assert.equal(JSON.stringify(config.body).includes(token), false);
});

test('resumes chunks, rejects stale offsets, analyzes once and deletes uploaded video', async t => {
  const { request, dir, uploads } = await fixture(t);
  const input = metadata();
  const path = `/api/sessions/${input.id}`;
  assert.equal((await request('/api/sessions', { method: 'POST', value: input })).status, 201);
  assert.equal((await request('/api/sessions', { method: 'POST', value: input })).status, 200);
  const first = await request(`${path}/video`, { method: 'PUT', bytes: Buffer.alloc(8, 1), offset: 0 });
  assert.equal(first.body.uploadedBytes, 8);
  assert.equal((await request(`${path}/video`, { method: 'PUT', bytes: Buffer.alloc(8), offset: 0 })).status, 409);
  assert.equal((await request(`${path}/analyze`, { method: 'POST' })).status, 409);
  await request(`${path}/video`, { method: 'PUT', bytes: Buffer.alloc(8, 2), offset: 8 });
  assert.equal((await request(`${path}/analyze`, { method: 'POST' })).status, 202);
  const complete = await finish(request, input.id);
  assert.equal(complete.status, 'complete');
  assert.deepEqual(complete.report, report);
  assert.equal(complete.uploadedBytes, input.byteCount);
  await assert.rejects(readFile(join(dir, `${input.id}.video`)), { code: 'ENOENT' });
  assert.equal((await request(`${path}/analyze`, { method: 'POST' })).status, 200);
  assert.equal(uploads(), 1);
  assert.equal((await request(path, { method: 'DELETE' })).status, 200);
  assert.equal((await request(path)).status, 404);
});

test('resume offset survives a server restart', async t => {
  const first = await fixture(t);
  const input = metadata();
  const path = `/api/sessions/${input.id}`;
  await first.request('/api/sessions', { method: 'POST', value: input });
  await first.request(`${path}/video`, { method: 'PUT', bytes: Buffer.from('abcdefgh'), offset: 0 });
  await first.app.close();
  const second = await fixture(t, { dataDir: first.dir });
  assert.equal((await second.request(path)).body.uploadedBytes, 8);
  await second.request(`${path}/video`, { method: 'PUT', bytes: Buffer.from('ijklmnop'), offset: 8 });
  assert.equal((await readFile(join(first.dir, `${input.id}.video`))).toString(), 'abcdefghijklmnop');
  await second.app.close();
});

test('concurrent identical chunks cannot append duplicate data', async t => {
  const { request } = await fixture(t);
  const input = metadata();
  await request('/api/sessions', { method: 'POST', value: input });
  const results = await Promise.all([1, 2].map(() => request(`/api/sessions/${input.id}/video`, { method: 'PUT', bytes: Buffer.alloc(8), offset: 0 })));
  assert.deepEqual(results.map(result => result.status).sort(), [200, 409]);
  assert.equal((await request(`/api/sessions/${input.id}`)).body.uploadedBytes, 8);
});

test('missing API key reports setup requirement without fabricating feedback', async t => {
  const { request } = await fixture(t, { configured: false });
  const input = metadata();
  await request('/api/sessions', { method: 'POST', value: input });
  const response = await request(`/api/sessions/${input.id}/analyze`, { method: 'POST' });
  assert.equal(response.status, 503);
  assert.match(response.body.error, /GEMINI_API_KEY/);
  assert.equal((await request(`/api/sessions/${input.id}`)).body.report, null);
});

test('failed analysis remains retryable and returns an actionable error', async t => {
  let attempts = 0;
  const { request } = await fixture(t, { provider: {
    model: 'gemini-4-argon',
    async analyze() { if (++attempts === 1) throw new Error('Gemini quota reached. Try later.'); return report; },
    async cleanup() { return true; }
  } });
  const input = metadata();
  const path = `/api/sessions/${input.id}`;
  await request('/api/sessions', { method: 'POST', value: input });
  await request(`${path}/video`, { method: 'PUT', bytes: Buffer.alloc(16), offset: 0 });
  await request(`${path}/analyze`, { method: 'POST' });
  const failed = await finish(request, input.id);
  assert.equal(failed.status, 'failed');
  assert.match(failed.error, /quota/);
  await request(`${path}/analyze`, { method: 'POST' });
  assert.equal((await finish(request, input.id)).status, 'complete');
});

test('rejects malformed reports and out-of-bounds timestamps', () => {
  assert.deepEqual(validateReport(structuredClone(report), 4), report);
  assert.throws(() => validateReport({ ...report, moments: [{ ...report.moments[0], seconds: 20 }] }, 4));
  assert.throws(() => validateReport({ ...report, summary: null }, 4));
  assert.throws(() => validateReport({ ...report, verdict: 'perfect' }, 4));
  assert.equal(extractOutput({ steps: [{ type: 'thought', content: [{ type: 'text', text: 'hidden' }] }, { type: 'model_output', content: [{ type: 'text', text: 'result' }] }] }), 'result');
});

test('Gemini request uses the exact model, agentic video, background execution, and structured output', async () => {
  const calls = [];
  const client = new GeminiClient({ apiKey: 'test-key', pollMs: 1, fetchImpl: async (url, options) => {
    calls.push({ url, options });
    if (url.endsWith('/files/test-video')) return Response.json({ name: 'files/test-video', uri: 'https://generativelanguage.googleapis.com/v1beta/files/test-video', state: 'ACTIVE' });
    if (options.method === 'POST') return Response.json({ id: 'interaction-123', status: 'in_progress' });
    return Response.json({ id: 'interaction-123', status: 'completed', steps: [{ type: 'model_output', content: [{ type: 'text', text: JSON.stringify(report) }] }] });
  } });
  const job = { ...metadata(), googleFile: { name: 'files/test-video' } };
  const result = await client.analyze(job, '/unused', async patch => Object.assign(job, patch), new AbortController().signal);
  assert.deepEqual(result, report);
  const posted = JSON.parse(calls.find(call => call.options.method === 'POST').options.body);
  assert.equal(posted.model, 'gemini-4-argon');
  assert.equal(posted.background, true);
  assert.equal(posted.input[0].processing, 'agentic');
  assert.equal(posted.response_format.mime_type, 'application/json');
  assert.match(posted.system_instruction, /cannot_assess/);
  assert.equal(job.interactionID, 'interaction-123');
});

test('Gemini access failures produce useful messages without leaking a key', async () => {
  const client = new GeminiClient({ apiKey: 'private-api-key', fetchImpl: async () => new Response('', { status: 403 }) });
  await assert.rejects(client.request('files/example'), error => /access/.test(error.message) && !error.message.includes('private-api-key'));
});

test('cleanup succeeds when Google already deleted the remote resources', async () => {
  const client = new GeminiClient({ apiKey: 'test-key', fetchImpl: async () => new Response('', { status: 404 }) });
  assert.equal(await client.cleanup({ googleFile: { name: 'files/expired' }, interactionID: 'expired' }), true);
});
