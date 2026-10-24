import test from 'node:test';
import assert from 'node:assert/strict';
import { GeminiClient } from '../gemini.mjs';
import { validateVerification } from '../verification.mjs';

const candidate = {
  verdict: 'needs_work', headline: 'Check panel alignment', summary: 'One edge is uneven.', confidence: 'medium',
  issues: [{ seconds: 1, title: 'Uneven edge', observation: 'The right edge sits higher.', whyItMatters: 'It may prevent the next part fitting.', howToFix: 'Align the edges before fastening.' }],
  strengths: ['Parts are laid out'], improvements: ['Align the panel'],
  moments: [{ seconds: 1, title: 'Alignment', observation: 'An edge is uneven.', suggestion: 'Align the edges.', kind: 'improvement' }],
  criteria: [{ name: 'Alignment', assessment: 'not_met', evidence: 'Uneven edge at one second.' }],
  nextPractice: 'Check the alignment.', limitations: ['One angle.']
};
const metadata = () => ({ id: 'test', title: 'Assembly', activity: 'General', goal: 'Assemble a panel', criteria: 'Edges should align.', mimeType: 'video/mp4', durationSeconds: 4, byteCount: 16 });
const verified = () => ({
  decisions: [{ candidateIndex: 0, decision: 'confirmed', reason: 'At one second the right edge remains raised after fastening.' }],
  revisedReport: { ...structuredClone(candidate), issues: candidate.issues.map(issue => ({ ...issue, candidateIndex: 0 })), criteria: candidate.criteria.map(item => ({ ...item, candidateIndex: 0 })) }
});
const interaction = (id, value) => ({ id, status: 'completed', steps: [{ type: 'model_output', content: [{ type: 'text', text: JSON.stringify(value) }] }] });
function fakeSDK({ review = candidate, recheck = verified(), get, create, remove } = {}) {
  const calls = [];
  let count = 0;
  const sdk = {
    files: {
      async upload(params) { calls.push(['upload', params]); return { name: 'files/video', uri: 'https://generativelanguage.googleapis.com/v1beta/files/video', state: 'PROCESSING' }; },
      async get(params) { calls.push(['fileGet', params]); return { name: 'files/video', uri: 'https://generativelanguage.googleapis.com/v1beta/files/video', state: 'ACTIVE' }; },
      async delete(params) { calls.push(['fileDelete', params]); if (remove) return remove(params); }
    },
    interactions: {
      async create(params, options) { calls.push(['create', params, options]); return create ? create(params, ++count) : { id: `interaction-${++count}`, status: 'in_progress' }; },
      async get(id, params, options) { calls.push(['get', id, params, options]); return get ? get(id) : interaction(id, id === 'interaction-1' ? review : recheck); },
      async delete(id, params, options) { calls.push(['delete', id, params, options]); if (remove) return remove(id); }
    }
  };
  return { sdk, calls };
}
async function analyze(client, job = metadata(), update = async patch => Object.assign(job, patch), signal = new AbortController().signal) {
  return client.analyze(job, '/tmp/replay-test.video', update, signal);
}

test('official SDK adapter uploads a file path and makes two background Argon video interactions before publishing', async () => {
  const { sdk, calls } = fakeSDK();
  const client = new GeminiClient({ sdk, pollMs: 1 });
  const job = metadata();
  const states = [];
  const result = await analyze(client, job, async patch => { Object.assign(job, patch); states.push(structuredClone(job)); });
  assert.equal(calls.find(call => call[0] === 'upload')[1].file, '/tmp/replay-test.video');
  assert.equal(calls.find(call => call[0] === 'upload')[1].config.mimeType, 'video/mp4');
  const creates = calls.filter(call => call[0] === 'create');
  assert.equal(creates.length, 2);
  for (const [, params, options] of creates) {
    assert.equal(params.model, 'gemini-4-argon');
    assert.equal(params.background, true);
    assert.equal(params.input[0].processing, 'agentic');
    assert.equal(params.input[0].type, 'video');
    assert.equal(params.generation_config.thinking_level, 'medium');
    assert.equal(params.response_format.mime_type, 'application/json');
    assert.equal(options.maxRetries, 0);
    assert.ok(options.signal instanceof AbortSignal);
    for (const obsolete of ['temperature', 'top_p', 'top_k', 'thinking_budget']) assert.equal(params.generation_config[obsolete], undefined);
  }
  assert.equal(creates[0][1].input[0].uri, creates[1][1].input[0].uri);
  assert.ok(creates[0][1].response_format.schema.required.includes('issues'));
  assert.ok(creates[1][1].response_format.schema.required.includes('decisions'));
  assert.match(creates[1][1].input[1].text, /Uneven edge/);
  assert.ok(states.some(state => state.status === 'verifying' && state.candidateReport && !state.verificationInteractionID));
  assert.equal(job.interactionID, 'interaction-1');
  assert.equal(job.verificationInteractionID, 'interaction-2');
  assert.equal(result.verification.status, 'completed');
  assert.equal(result.verification.confirmedIssueCount, 1);
  assert.match(result.verification.summary, /AI evidence recheck, not proof/);
  assert.equal(result.issues[0].candidateIndex, undefined);
  assert.ok(job.reviewTiming.totalSeconds >= 0);
});

test('a pending verification never returns a candidate report and resumes an existing verification ID', async () => {
  const controller = new AbortController();
  const { sdk, calls } = fakeSDK({ get: async id => { controller.abort(new Error('server restarting')); return { id, status: 'in_progress' }; } });
  const job = { ...metadata(), status: 'verifying', candidateReport: structuredClone(candidate), googleFile: { name: 'files/video', uri: 'https://example.invalid/video' }, interactionID: 'original', verificationInteractionID: 'existing-recheck' };
  await assert.rejects(analyze(new GeminiClient({ sdk, pollMs: 1 }), job, async patch => Object.assign(job, patch), controller.signal));
  assert.equal(job.report, undefined);
  assert.equal(calls.some(call => call[0] === 'create'), false);
  const resumed = fakeSDK({ get: async id => interaction(id, verified()) });
  const report = await analyze(new GeminiClient({ sdk: resumed.sdk }), job);
  assert.equal(report.verification.status, 'completed');
  assert.deepEqual(resumed.calls.filter(call => call[0] === 'get').map(call => call[1]), ['existing-recheck']);
  assert.equal(resumed.calls.some(call => ['create', 'upload'].includes(call[0])), false);
});

test('restart after the first pass creates only the missing evidence recheck', async () => {
  const job = { ...metadata(), status: 'verifying', googleFile: { name: 'files/video', uri: 'https://example.invalid/video' }, candidateReport: structuredClone(candidate), interactionID: 'original' };
  const { sdk, calls } = fakeSDK({ get: async id => interaction(id, verified()) });
  const report = await analyze(new GeminiClient({ sdk }), job);
  assert.equal(report.verification.status, 'completed');
  assert.equal(calls.filter(call => call[0] === 'create').length, 1);
  assert.equal(calls.some(call => call[0] === 'upload'), false);
  assert.equal(job.interactionID, 'original');
});

for (const decision of ['unsupported', 'uncertain']) {
  test(`${decision} candidate is removed from all actionable report sections and changes the verdict`, async () => {
    const revisedReport = {
      verdict: decision === 'unsupported' ? 'on_track' : 'cannot_assess', headline: 'No confirmed visible issue',
      summary: 'The recording does not establish an alignment fault.', confidence: 'low', issues: [], strengths: [], improvements: [], moments: [],
      criteria: [{ name: 'Alignment', assessment: 'not_visible', evidence: 'The camera angle obscures the join.', candidateIndex: null }],
      nextPractice: 'Film the join from the side.', limitations: ['The join is obscured.']
    };
    const recheck = { decisions: [{ candidateIndex: 0, decision, reason: 'The angled view does not establish a raised edge.' }], revisedReport };
    const { sdk } = fakeSDK({ recheck });
    const result = await analyze(new GeminiClient({ sdk }));
    assert.equal(result.verdict, revisedReport.verdict);
    assert.equal(result.issues.length, 0);
    assert.equal(result.improvements.length, 0);
    assert.equal(result.moments.length, 0);
    assert.equal(result.criteria[0].assessment, 'not_visible');
    assert.equal(result.nextPractice, 'Film the join from the side.');
    assert.equal(result.summary, revisedReport.summary);
    assert.equal(result.verification.removedIssueCount, 1);
    assert.equal(result.verification.decisions[0].decision, decision);
  });
}

test('decision and report validation rejects missing, duplicated, unknown, or unmapped claims', () => {
  const mutations = [
    value => { value.decisions = []; },
    value => { value.decisions.push(value.decisions[0]); },
    value => { value.decisions[0].candidateIndex = 2; },
    value => { value.decisions[0].decision = 'maybe'; },
    value => { value.decisions[0].reason = ''; },
    value => { value.revisedReport.issues[0].candidateIndex = 1; },
    value => { value.revisedReport.issues.push(value.revisedReport.issues[0]); },
    value => { value.revisedReport.criteria[0].candidateIndex = 1; },
    value => { value.decisions[0].decision = 'unsupported'; },
    value => { value.revisedReport.verdict = 'on_track'; },
    value => { value.revisedReport.issues[0].seconds = 100; }
  ];
  for (const mutate of mutations) {
    const value = verified(); mutate(value);
    assert.throws(() => validateVerification(value, candidate, 4, 'gemini-4-argon'));
  }
});

test('mixed confirmed and uncertain candidates retain only supported fixes and moments', () => {
  const candidates = structuredClone(candidate);
  candidates.issues.push({ ...candidate.issues[0], title: 'Missing glue', observation: 'No glue is visible.', howToFix: 'Add glue.' });
  const value = verified();
  value.decisions.push({ candidateIndex: 1, decision: 'uncertain', reason: 'Glue application happened off camera.' });
  value.revisedReport.improvements = ['Add glue.']; // Defensively rebuilt from confirmed issues.
  value.revisedReport.moments.push({ ...candidate.moments[0], title: 'Missing glue' });
  const result = validateVerification(value, candidates, 4, 'gemini-4-argon');
  assert.deepEqual(result.improvements, [candidate.issues[0].howToFix]);
  assert.deepEqual(result.moments.map(item => item.title), [candidate.issues[0].title]);
  assert.equal(result.verification.confirmedIssueCount, 1);
  assert.equal(result.verification.removedIssueCount, 1);
});

test('malformed or failed rechecks cannot publish feedback, and cleanup covers both interactions', async () => {
  for (const outcome of [{ id: 'interaction-2', status: 'failed' }, { id: 'interaction-2', status: 'completed', output_text: 'not json' }, interaction('interaction-2', { decisions: [] })]) {
    const { sdk, calls } = fakeSDK({ get: async id => id === 'interaction-1' ? interaction(id, candidate) : outcome });
    const client = new GeminiClient({ sdk });
    const job = metadata();
    await assert.rejects(analyze(client, job));
    assert.equal(job.report, undefined);
    assert.equal(await client.cleanup(job), true);
    assert.deepEqual(calls.filter(call => call[0] === 'delete').map(call => call[1]).sort(), ['interaction-1', 'interaction-2']);
    assert.equal(calls.filter(call => call[0] === 'fileDelete').length, 1);
  }
});

test('provider errors are safe, and cleanup treats only absent resources as already removed', async () => {
  const denied = fakeSDK({ get: async () => { throw Object.assign(new Error('secret-api-key private content'), { status: 403 }); } });
  await assert.rejects(analyze(new GeminiClient({ sdk: denied.sdk })), error => /access/.test(error.message) && !/secret-api-key|private content/.test(error.message));
  for (const [status, expected] of [[404, true], [403, false], [503, false]]) {
    const { sdk } = fakeSDK({ remove: async () => { throw Object.assign(new Error('provider detail'), { status }); } });
    assert.equal(await new GeminiClient({ sdk }).cleanup({ googleFile: { name: 'files/a' }, interactionID: 'a', verificationInteractionID: 'b' }), expected);
  }
});

test('installed official SDK serializes the application Interactions contract without a network call', async () => {
  const requests = [];
  let created = 0;
  const client = new GeminiClient({ apiKey: 'fake-key-for-offline-transport-test',
    transport: async (url, options) => {
      const request = new Request(url, options);
      const path = new URL(request.url).pathname;
      const body = request.method === 'POST' ? await request.json() : undefined;
      requests.push({ path, method: request.method, body });
      if (path.endsWith('/files/video')) return Response.json({ name: 'files/video', uri: 'https://generativelanguage.googleapis.com/v1beta/files/video', state: 'ACTIVE' });
      if (request.method === 'POST') return Response.json({ id: `interaction-${++created}`, status: 'in_progress' });
      const id = path.split('/').at(-1);
      return Response.json(interaction(id, id === 'interaction-1' ? candidate : verified()));
    }
  });
  const job = { ...metadata(), googleFile: { name: 'files/video', uri: 'https://generativelanguage.googleapis.com/v1beta/files/video' } };
  const report = await analyze(client, job);
  assert.equal(report.verification.status, 'completed');
  assert.equal(created, 2);
  const bodies = requests.filter(item => item.method === 'POST').map(item => item.body);
  assert.equal(bodies[0].model, 'gemini-4-argon');
  assert.equal(bodies[1].input[0].processing, 'agentic');
  assert.equal(bodies[1].response_format.mime_type, 'application/json');
});

test('official SDK upload cancellation reaches the resumable file transport', async t => {
  const { mkdtemp, writeFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const dir = await mkdtemp(join(tmpdir(), 'replay-sdk-upload-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const path = join(dir, 'video.mp4');
  await writeFile(path, Buffer.alloc(16));
  const controller = new AbortController();
  let chunkReached = false;
  const client = new GeminiClient({ apiKey: 'offline-test-key', transport: async (resource, options) => {
    const request = new Request(resource, options);
    if (request.headers.get('x-goog-upload-command') === 'start') {
      return new Response('{}', { headers: { 'x-goog-upload-url': 'https://generativelanguage.googleapis.com/upload/test' } });
    }
    chunkReached = true;
    assert.equal(await request.arrayBuffer().then(bytes => bytes.byteLength), 16);
    controller.abort(new Error('stop this upload'));
    assert.equal(options.signal.aborted, true);
    throw options.signal.reason;
  } });
  await assert.rejects(client.upload(metadata(), path, controller.signal), /stop this upload/);
  assert.equal(chunkReached, true);
});
