import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { createApp, validateMetadata, MAX_BYTES } from '../app.mjs';
import { extractOutput, validateReport } from '../report.mjs';

const token = 'test-token-only-not-a-real-secret-123456789';
const report = {
  verdict: 'needs_work', headline: 'Align the panel before fastening', summary: 'The panel edges are uneven when secured.',
  confidence: 'medium', strengths: ['Parts are laid out first'], improvements: ['Check alignment before securing the panel'],
  issues: [{ seconds: 1, title: 'Panel is misaligned', observation: 'One panel edge sits higher than the other.', whyItMatters: 'The next part may not fit correctly.', howToFix: 'Line up the edges before securing the panel.' }],
  moments: [{ seconds: 1, title: 'Uneven edges', observation: 'The panel is not aligned.', suggestion: 'Check alignment before fastening.', kind: 'improvement' }],
  criteria: [{ name: 'Alignment', assessment: 'not_met', evidence: 'Uneven edges are visible.' }],
  nextPractice: 'Recheck alignment and inspect the completed work.', limitations: ['One camera angle.'],
  verification: { status: 'completed', model: 'gemini-4-argon', candidateIssueCount: 1, confirmedIssueCount: 1, removedIssueCount: 0, summary: 'Test AI evidence recheck.', completedAt: '2026-10-24T12:00:00.000Z' }
};
const metadata = (extra = {}) => ({ id: randomUUID(), title: 'Assembly', activity: 'General', goal: 'Assemble the panels correctly', criteria: '', durationSeconds: 4, byteCount: 16, mimeType: 'video/mp4', ...extra });

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

test('problem feedback requires evidence and fixes, but does not require invented faults', () => {
  const issue = report.issues[0];
  for (const invalid of [{ seconds: 5 }, { seconds: -1 }, { howToFix: '' }, { whyItMatters: null }, { observation: '' }]) {
    assert.throws(() => validateReport({ ...report, issues: [{ ...issue, ...invalid }] }, 4));
  }
  assert.throws(() => validateReport({ ...report, issues: [] }, 4));
  assert.doesNotThrow(() => validateReport({ ...report, issues: [{ ...issue, seconds: null }] }, 4));
  assert.doesNotThrow(() => validateReport({ ...report, verdict: 'on_track', issues: [], improvements: [], moments: [] }, 4));
  assert.doesNotThrow(() => validateReport({ ...report, verdict: 'cannot_assess', issues: [], improvements: [], moments: [] }, 4));
});

const deferred = () => {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
};

async function queueReview(request, input) {
  const path = `/api/sessions/${input.id}`;
  await request('/api/sessions', { method: 'POST', value: input });
  await request(`${path}/video`, { method: 'PUT', bytes: Buffer.alloc(input.byteCount), offset: 0 });
  await request(`${path}/analyze`, { method: 'POST' });
  return path;
}

test('candidate feedback is never published when the evidence recheck has not completed', async t => {
  const { verification, ...unverified } = report;
  const { request } = await fixture(t, { provider: { model: 'gemini-4-argon', async analyze() { return unverified; }, async cleanup() { return true; } } });
  const input = metadata();
  await queueReview(request, input);
  const failed = await finish(request, input.id);
  assert.equal(failed.status, 'failed');
  assert.equal(failed.report, null);
  assert.match(failed.error, /No unverified feedback/);
});

test('delayed terminal cleanup and concurrent DELETE cannot race saves or resurrect a deleted session', async t => {
  const cleaning = deferred(); const release = deferred();
  let cleanups = 0;
  t.after(() => release.resolve());
  const { request, dir } = await fixture(t, { provider: {
    model: 'gemini-4-argon',
    async analyze(job, path, update) {
      await update({ googleFile: { name: 'files/test' }, interactionID: 'analysis', verificationInteractionID: 'recheck' });
      return structuredClone(report);
    },
    async cleanup() { cleanups++; cleaning.resolve(); await release.promise; return true; }
  } });
  const input = metadata();
  const path = await queueReview(request, input);
  await cleaning.promise;
  assert.equal((await request(path)).body.status, 'complete');
  let deleted = false;
  const deletion = request(path, { method: 'DELETE' }).then(result => { deleted = true; return result; });
  await delay(25);
  assert.equal(deleted, false);
  release.resolve();
  assert.equal((await deletion).status, 200);
  assert.equal(cleanups, 1);
  assert.equal((await request(path)).status, 404);
  await assert.rejects(readFile(join(dir, `${input.id}.json`)), { code: 'ENOENT' });
});

test('delayed failure cleanup serializes a concurrent retry and discards the old hypothesis', async t => {
  const cleaning = deferred(); const release = deferred();
  let attempts = 0;
  t.after(() => release.resolve());
  const { request } = await fixture(t, { provider: {
    model: 'gemini-4-argon',
    async analyze(job, path, update) {
      if (++attempts === 1) {
        await update({ googleFile: { name: 'files/old' }, interactionID: 'old-analysis', verificationInteractionID: 'old-recheck', candidateReport: report });
        throw new Error('Recheck was interrupted.');
      }
      assert.equal(job.googleFile, undefined);
      assert.equal(job.interactionID, undefined);
      assert.equal(job.verificationInteractionID, undefined);
      assert.equal(job.candidateReport, undefined);
      return structuredClone(report);
    },
    async cleanup() { cleaning.resolve(); await release.promise; return true; }
  } });
  const input = metadata();
  const path = await queueReview(request, input);
  await cleaning.promise;
  let retried = false;
  const retry = request(`${path}/analyze`, { method: 'POST' }).then(result => { retried = true; return result; });
  await delay(25);
  assert.equal(retried, false);
  release.resolve();
  assert.equal((await retry).status, 202);
  assert.equal((await finish(request, input.id)).status, 'complete');
  assert.equal(attempts, 2);
});

test('verifying is busy, survives restart, and exposes no candidate while the second pass is pending', async t => {
  const started = deferred();
  const firstProvider = {
    model: 'gemini-4-argon',
    async analyze(job, path, update, signal) {
      await update({ status: 'verifying', candidateReport: report, googleFile: { name: 'files/persisted' }, interactionID: 'first-pass', verificationInteractionID: 'second-pass' });
      started.resolve();
      await new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(signal.reason), { once: true }));
    },
    async cleanup() { throw new Error('Restart should preserve remote work'); }
  };
  const first = await fixture(t, { provider: firstProvider });
  const input = metadata();
  const path = await queueReview(first.request, input);
  await started.promise;
  const pending = await first.request(path);
  assert.equal(pending.body.status, 'verifying');
  assert.equal(pending.body.report, null);
  assert.equal(pending.body.candidateReport, undefined);
  assert.equal((await first.request(path, { method: 'DELETE' })).status, 409);
  assert.equal((await first.request(`${path}/analyze`, { method: 'POST' })).status, 200);
  await first.app.close();
  const second = await fixture(t, { dataDir: first.dir, provider: {
    model: 'gemini-4-argon',
    async analyze(job) {
      assert.equal(job.interactionID, 'first-pass');
      assert.equal(job.verificationInteractionID, 'second-pass');
      assert.deepEqual(job.candidateReport, report);
      return structuredClone(report);
    },
    async cleanup() { return true; }
  } });
  assert.equal((await finish(second.request, input.id)).status, 'complete');
  await second.app.close();
  const persisted = JSON.parse(await readFile(join(first.dir, `${input.id}.json`), 'utf8'));
  assert.equal(persisted.candidateReport, undefined);
  assert.equal(persisted.verificationInteractionID, undefined);
  assert.equal(persisted.interactionID, undefined);
  assert.equal(persisted.googleFile, undefined);
  assert.equal(persisted.report.verification.status, 'completed');
});
