import { existsSync } from 'node:fs';
import { createApp } from './app.mjs';
import { GeminiClient } from './gemini.mjs';

if (existsSync('.env')) process.loadEnvFile('.env');
const apiKey = process.env.GEMINI_API_KEY ?? '';
const model = process.env.GEMINI_MODEL || 'gemini-4-argon';
const app = await createApp({
  dataDir: process.env.DATA_DIR || './server/data',
  token: process.env.APP_TOKEN,
  provider: new GeminiClient({ apiKey, model }),
  configured: Boolean(apiKey)
});
const port = Number(process.env.PORT || 8787);
app.server.listen(port, process.env.HOST || '127.0.0.1', () => {
  console.log(`Replay server listening on port ${port}. Model: ${model}.`);
  if (!apiKey) console.log('Add GEMINI_API_KEY to .env to enable video reviews.');
});
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, async () => { await app.close(); process.exit(0); });
