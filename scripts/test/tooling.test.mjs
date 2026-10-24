import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { atLeast, readEnvironment, serverOrigin } from '../lib/config.mjs';
import { diagnose } from '../doctor.mjs';
import { parseArguments, createClient, runRehearsal } from '../rehearse.mjs';

test('argument parser requires a real clip path and explicit valid duration', () => {
  assert.deepEqual(parseArguments(['--help']), { help: true });
  assert.equal(parseArguments(['--video', 'my clip.mp4', '--duration', '25.5']).duration, 25.5);
  for (const args of [[], ['--video', 'a.mp4'], ['--video', 'a.mp4', '--duration', '3601'], ['--video', 'a.mp4', '--duration', 'NaN'], ['--video', 'a.mp4', '--duration', '0'], ['--video', 'a.mp4', '--duration', '4', '--unknown', 'x'], ['--video', 'a.mp4', '--duration', '4', '--task', 'a', '--task', 'b']]) assert.throws(() => parseArguments(args));
});

test('connection origins allow HTTP only on loopback and reject credential or path tricks', () => {
  assert.equal(serverOrigin(), 'http://127.0.0.1:8787');
  assert.equal(serverOrigin('http://[::1]:8787/'), 'http://[::1]:8787');
  assert.equal(serverOrigin('https://replay.example.com'), 'https://replay.example.com');
  for (const url of ['http://192.168.1.2:8787', 'http://localhost.example.com', 'http://example.com', 'https://user:secret@example.com', 'https://example.com/api', 'https://example.com?token=x', 'file:///tmp/server']) assert.throws(() => serverOrigin(url));
});

test('doctor detects missing key and checks ignored private paths without printing credentials', async () => {
  const root = await mkdtemp(join(tmpdir(), 'replay-doctor-'));
  try {
    execFileSync('git', ['init', '--quiet', root]);
    await mkdir(join(root, 'node_modules/@google/genai'), { recursive: true });
    await writeFile(join(root, 'node_modules/@google/genai/package.json'), '{"version":"2.31.0"}');
    await writeFile(join(root, '.gitignore'), '.env\nserver/data/\nartifacts/\ndemo-videos/\n');
    await writeFile(join(root, '.env'), `GEMINI_API_KEY=\nAPP_TOKEN=${'fake-local-token-'.repeat(3)}\nGEMINI_MODEL=gemini-4-argon\n`);
    const checks = await diagnose({ root, environment: {}, nodeVersion: '24.0.0' });
    assert.deepEqual(checks.filter(item => !item.ok).map(item => item.label), ['Gemini API key is present (value hidden)']);
    const key = 'fake-key-used-only-in-tests';
    const valid = await diagnose({ root, environment: { GEMINI_API_KEY: key }, nodeVersion: '24.0.0' });
    assert.ok(valid.every(item => item.ok));
    assert.ok(!JSON.stringify(valid).includes(key));
    assert.ok(!JSON.stringify(valid).includes('fake-local-token-'));
    assert.equal((await readEnvironment(root, { GEMINI_MODEL: 'override' })).env.GEMINI_MODEL, 'override');
    assert.equal(atLeast('22.12.9', 22, 13), false);
    assert.equal(atLeast('22.13.0', 22, 13), true);
    assert.equal(atLeast('2.2.9', 2, 3), false);
  } finally { await rm(root, { recursive: true, force: true }); }
});

function harness({ lostChunkResponse = false, initialOffset = 0, statuses = ['queued', 'processing', 'analyzing', 'verifying', 'complete'], delayMs = 1000, verification = 'completed', verificationModel = 'gemini-4-argon', verificationCounts = {}, modelFailure = false, configModel = 'gemini-4-argon', maxWaitMs } = {}) {
  let time = Date.parse('2026-10-24T12:00:00.000Z');
  let offset = initialOffset;
  let statusIndex = 0;
  let hasLostResponse = false;
  let analyzing = false;
  let largestRead = 0;
  const requests = [];
  const reads = [];
  const saved = [];
  const report = { headline: 'Observed feedback from fake test transport', issues: [], verification: { status: verification, model: verificationModel, candidateIssueCount: 1, confirmedIssueCount: 0, removedIssueCount: 1, ...verificationCounts } };
  const reviewTiming = { startedAt: '2026-10-24T12:00:00.000Z', analysisStartedAt: '2026-10-24T12:00:01.000Z', analysisCompletedAt: '2026-10-24T12:00:02.000Z', verificationStartedAt: '2026-10-24T12:00:02.000Z', completedAt: '2026-10-24T12:00:03.000Z', totalSeconds: 3 };
  const artifact = { schemaVersion: 1, startedAt: new Date(time).toISOString(), stages: [], session: { id: '33333333-3333-4333-8333-333333333333', title: 'test', activity: 'Work review', goal: '', criteria: '', durationSeconds: 25, byteCount: 10, mimeType: 'video/mp4' } };
  const snapshot = () => ({ id: artifact.session.id, status: analyzing ? (modelFailure ? 'failed' : statuses[statusIndex]) : 'uploading', uploadedBytes: offset, byteCount: 10, model: configModel, reviewTiming: analyzing ? reviewTiming : null, report: analyzing && statuses[statusIndex] === 'complete' ? report : null, error: modelFailure ? 'Model rejected the video.' : null });
  const fetchImpl = async (url, options) => {
    requests.push({ url, options });
    assert.equal(options.redirect, 'error');
    assert.equal(options.headers.Authorization, 'Bearer fake-token-only');
    const path = new URL(url).pathname;
    if (path === '/api/config') return Response.json({ configured: true, model: configModel, maxBytes: 2_000_000_000, maxDurationSeconds: 3600, chunkBytes: 4 });
    if (path === '/api/sessions') return Response.json(snapshot());
    if (path.endsWith('/video')) {
      assert.equal(Number(options.headers['Upload-Offset']), offset);
      assert.ok(options.body.byteLength <= 4);
      offset += options.body.byteLength;
      if (lostChunkResponse && !hasLostResponse) { hasLostResponse = true; throw new TypeError('simulated lost acknowledgement'); }
      return Response.json(snapshot());
    }
    if (path.endsWith('/analyze')) { assert.equal(offset, 10); analyzing = true; return Response.json(snapshot()); }
    if (analyzing) statusIndex = Math.min(statusIndex + 1, statuses.length - 1);
    return Response.json(snapshot());
  };
  const run = () => runRehearsal({ artifact, request: createClient({ origin: 'http://localhost:8787', token: 'fake-token-only', fetchImpl }),
    readChunk: async (position, size) => { reads.push(position); largestRead = Math.max(largestRead, size); return Buffer.alloc(size); },
    save: async value => saved.push(structuredClone(value)), now: () => time, sleep: async () => { time += delayMs; }, log: () => {}, ...(maxWaitMs ? { maxWaitMs } : {}) });
  return { run, artifact, requests, reads, saved, report, reviewTiming, get largestRead() { return largestRead; } };
}

test('rehearsal uploads bounded chunks, recovers a lost response, and saves actual verification and stage timing', async () => {
  const h = harness({ lostChunkResponse: true });
  const result = await h.run();
  assert.equal(result.outcome, 'completed');
  assert.deepEqual(h.reads, [0, 4, 8]);
  assert.equal(h.largestRead, 4);
  assert.ok(result.stages.some(item => item.stage === 'verifying' && item.seconds === 1));
  assert.deepEqual(result.report, h.report);
  assert.deepEqual(result.reviewTiming, h.reviewTiming);
  assert.equal(result.verification.status, 'completed');
  assert.equal(result.model, 'gemini-4-argon');
  assert.equal(result.completedWithinDemoWindow, true);
  assert.ok(h.saved.length > 5);
  assert.ok(!JSON.stringify(h.saved).includes('fake-token-only'));
});

test('rehearsal resumes at the authoritative server offset', async () => {
  const h = harness({ initialOffset: 4 });
  await h.run();
  assert.deepEqual(h.reads, [4, 8]);
});

test('completed but slow analysis is separated from model failures', async () => {
  const slow = harness({ delayMs: 60_000 });
  assert.equal((await slow.run()).outcome, 'too_slow');
  assert.equal(slow.artifact.elapsedSeconds, 240);
  assert.equal(slow.artifact.completedWithinDemoWindow, false);
  const failed = harness({ modelFailure: true });
  await assert.rejects(failed.run(), error => error.kind === 'model_error');
  assert.equal(failed.artifact.outcome, 'model_error');
  assert.equal(failed.artifact.report, undefined);
});

test('missing verification, a different model and an unfinished run cannot pass', async () => {
  const unverified = harness({ verification: 'skipped' });
  await assert.rejects(unverified.run(), error => error.kind === 'verification_error');
  assert.equal(unverified.artifact.outcome, 'verification_error');
  const alternate = harness({ configModel: 'different-model' });
  await assert.rejects(alternate.run(), error => error.kind === 'setup_error');
  assert.equal(alternate.reads.length, 0);
  const timeout = harness({ statuses: ['verifying'], delayMs: 1000, maxWaitMs: 2000 });
  await assert.rejects(timeout.run(), error => error.kind === 'latency_timeout');
  assert.equal(timeout.artifact.outcome, 'latency_timeout');
});

test('HTTP authentication failures remain server errors, never model reports', async () => {
  const request = createClient({ origin: 'http://localhost:8787', token: 'fake-token', fetchImpl: async () => Response.json({ error: 'Incorrect token.' }, { status: 401 }) });
  await assert.rejects(request('/api/config'), error => error.kind === 'server_error' && error.status === 401);
});

test('verification model and issue counts must match the published Argon report', async () => {
  for (const options of [{ verificationModel: 'different-model' }, { verificationCounts: { removedIssueCount: -1 } }, { verificationCounts: { removedIssueCount: 0 } }, { verificationCounts: { confirmedIssueCount: 1, removedIssueCount: 0 } }, { verificationCounts: { candidateIssueCount: 1.5 } }]) {
    const h = harness(options);
    await assert.rejects(h.run(), error => error.kind === 'verification_error');
    assert.equal(h.artifact.outcome, 'verification_error');
    assert.equal(h.artifact.completedWithinDemoWindow, false);
  }
});
