import { readFile, writeFile, access } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';

try {
  await access('.env');
  console.log('.env already exists; left your settings unchanged.');
} catch {
  const template = await readFile('.env.example', 'utf8');
  await writeFile('.env', template.replace('APP_TOKEN=\n', `APP_TOKEN=${randomBytes(32).toString('hex')}\n`), { mode: 0o600, flag: 'wx' });
  console.log('Created .env with a random connection token. Add GEMINI_API_KEY, then run npm start.');
}
