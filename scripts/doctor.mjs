import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { atLeast, readEnvironment, serverOrigin } from './lib/config.mjs';

export async function diagnose({ root = process.cwd(), environment = process.env, nodeVersion = process.versions.node } = {}) {
  const { env, hasEnvFile } = await readEnvironment(root, environment);
  const checks = [];
  const add = (ok, label, fix) => checks.push({ ok, label, ...(ok ? {} : { fix }) });
  add(atLeast(nodeVersion, 22, 13), `Node ${nodeVersion} (requires 22.13+)`, 'Install Node 24 or newer.');
  let sdkVersion;
  try { sdkVersion = JSON.parse(await readFile(resolve(root, 'node_modules/@google/genai/package.json'), 'utf8')).version; } catch { /* Report below. */ }
  add(atLeast(sdkVersion, 2, 3), `Official Gemini SDK ${sdkVersion ?? 'not installed'} (requires 2.3+)`, 'Run npm ci.');
  add(hasEnvFile, '.env exists', 'Run npm run setup, then fill in GEMINI_API_KEY.');
  add(Boolean(env.GEMINI_API_KEY?.trim()), 'Gemini API key is present (value hidden)', 'Add your event API key to .env. No live access check is performed.');
  add((env.APP_TOKEN?.trim().length ?? 0) >= 32, 'Connection token has at least 32 characters (value hidden)', 'Run npm run setup, or generate APP_TOKEN with openssl rand -hex 32.');
  add(env.GEMINI_MODEL === 'gemini-4-argon', 'GEMINI_MODEL is gemini-4-argon', 'Set GEMINI_MODEL=gemini-4-argon in .env.');
  try { serverOrigin(env.SERVER_URL); add(true, 'Server URL protects the connection token'); }
  catch (error) { add(false, 'Server URL protects the connection token', error.message); }
  for (const file of ['.env', 'server/data/private.json', 'artifacts/rehearsal-check.json', 'demo-videos/private.mp4']) {
    const ignored = spawnSync('git', ['check-ignore', '--quiet', '--no-index', file], { cwd: root, stdio: 'ignore' }).status === 0;
    const tracked = spawnSync('git', ['ls-files', '--error-unmatch', file], { cwd: root, stdio: 'ignore' }).status === 0;
    add(ignored && !tracked, `${file} is ignored and not tracked`, 'Keep credentials, reports and private videos out of Git; check .gitignore and the Git index.');
  }
  return checks;
}

async function main() {
  if (process.argv.includes('--help')) {
    console.log('Usage: npm run doctor\nLocal setup and Git-ignore checks only. Makes no network requests and spends no API credits.');
    return;
  }
  console.log('Replay local readiness checks — no network requests or API charges.');
  const checks = await diagnose();
  for (const check of checks) console.log(`${check.ok ? 'PASS' : 'FAIL'} ${check.label}${check.fix ? `\n     ${check.fix}` : ''}`);
  const failures = checks.filter(check => !check.ok).length;
  console.log(failures ? `\n${failures} setup check(s) need attention.` : '\nLocal setup checks passed. Live model access and video feedback remain untested.');
  console.log('Next: start the server, then run npm run rehearse -- --help. A real named user, consented clip and recorded demo are still needed for submission.');
  process.exitCode = failures ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(() => { console.error('Could not read local setup. Check .env permissions and Git availability. No secrets were printed.'); process.exitCode = 1; });
}
