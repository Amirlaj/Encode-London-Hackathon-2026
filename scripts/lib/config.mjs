import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { parseEnv } from 'node:util';

export async function readEnvironment(root = process.cwd(), environment = process.env) {
  let file = {};
  let hasEnvFile = true;
  try { file = parseEnv(await readFile(resolve(root, '.env'), 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; hasEnvFile = false; }
  return { env: { ...file, ...environment }, hasEnvFile };
}

export function atLeast(version, major, minor = 0) {
  const match = /^v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(version ?? '');
  return Boolean(match && (Number(match[1]) > major || (Number(match[1]) === major && Number(match[2]) >= minor)));
}

export function serverOrigin(value = 'http://127.0.0.1:8787') {
  let url;
  try { url = new URL(value); } catch { throw new Error('SERVER_URL must be a valid HTTP or HTTPS origin.'); }
  const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && loopback)) {
    throw new Error('Use HTTPS for a nonlocal SERVER_URL to protect the connection token. HTTP is allowed only on localhost.');
  }
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw new Error('SERVER_URL must contain only the scheme, hostname and optional port.');
  }
  return url.origin;
}
