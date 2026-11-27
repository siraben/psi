import { copyFile, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = fileURLToPath(new URL('.', import.meta.url));
const guest = process.argv[2] ? resolve(process.argv[2])
  : resolve(here, '../../build/psi-unkernel-aarch64/bin/psi');
const relay = process.env.PSI_DEMO_WISP_URL;
const caBundle = process.env.PSI_DEMO_CA_BUNDLE || '/etc/ssl/certs/ca-certificates.crt';
if (relay) {
  const url = new URL(relay);
  if (url.protocol !== 'wss:' || url.username || url.password || url.search || url.hash) {
    throw new Error('PSI_DEMO_WISP_URL must be a wss:// URL without credentials, query or fragment');
  }
}
const assets = {
  'psi-aarch64': guest,
  'index.html': 'index.html',
  'guest.mjs': 'guest.mjs',
  'terminal.mjs': 'terminal.mjs',
  'terminal-output.mjs': 'terminal-output.mjs',
  'demo.css': 'demo.css',
  'fonts/dm-sans.871fd1188d.woff2': 'fonts/dm-sans.871fd1188d.woff2',
  'fonts/ibm-plex-mono.65b0e6c0be.woff2': 'fonts/ibm-plex-mono.65b0e6c0be.woff2',
  'fonts/dm-sans-OFL.txt': 'fonts/dm-sans-OFL.txt',
  'fonts/ibm-plex-mono-OFL.txt': 'fonts/ibm-plex-mono-OFL.txt',
  ...(relay ? { 'ca-bundle.crt': caBundle } : {}),
  'vendor/unkernel/web.mjs': 'node_modules/unkernel/dist/web.mjs',
  'vendor/unkernel/_chunks/core.mjs': 'node_modules/unkernel/dist/_chunks/core.mjs',
  'vendor/unkernel/unkernel.wasm': 'node_modules/unkernel/dist/unkernel.wasm',
  'vendor/unkernel/LICENSE': 'node_modules/unkernel/LICENSE',
  'vendor/unkernel/LICENSE-MIT': 'node_modules/unkernel/LICENSE-MIT',
  'vendor/ghostty/ghostty-vt.wasm': 'node_modules/ghostty-web/dist/ghostty-vt.wasm',
  'vendor/ghostty/LICENSE': 'node_modules/ghostty-web/LICENSE',
};

for (const [dest, source] of Object.entries(assets)) {
  const target = resolve(here, 'dist', dest);
  await mkdir(dirname(target), { recursive: true });
  // copyFile preserves the source mode, which can be read-only in the Nix store.
  await rm(target, { force: true });
  await copyFile(resolve(here, source), target);
}
// Canvas dimensions truncate to integers. Ghostty Web 0.4.0 compares
// against fractional DPR products and otherwise reallocates every frame.
const ghosttySource = await readFile(resolve(here, 'node_modules/ghostty-web/dist/ghostty-web.js'), 'utf8');
const dimensions = /this\.canvas\.(width|height) !== (D\.(?:cols|rows) \* this\.metrics\.\1 \* this\.devicePixelRatio)/g;
if ([...ghosttySource.matchAll(dimensions)].length !== 2) {
  throw new Error('Recheck the Ghostty fractional-DPR canvas fix after upgrading');
}
const ghostty = resolve(here, 'dist/vendor/ghostty/ghostty-web.js');
await rm(ghostty, { force: true });
await writeFile(ghostty, ghosttySource.replace(dimensions, 'this.canvas.$1 !== Math.trunc($2)'));
await writeFile(resolve(here, 'dist/config.mjs'), `export const relay = ${JSON.stringify(relay || '')};\n`);
if (!relay) await rm(resolve(here, 'dist/ca-bundle.crt'), { force: true });
console.log('Built demos/unkernel/dist/');
