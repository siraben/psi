import { copyFile, mkdir, rm } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = fileURLToPath(new URL('.', import.meta.url));
const guest = process.argv[2] ? resolve(process.argv[2])
  : resolve(here, '../../build/psi-unkernel-aarch64/bin/psi');
const assets = {
  'psi-aarch64': guest,
  'index.html': 'index.html',
  'guest.mjs': 'guest.mjs',
  'terminal.mjs': 'terminal.mjs',
  'vendor/unkernel/web.mjs': 'node_modules/unkernel/dist/web.mjs',
  'vendor/unkernel/_chunks/core.mjs': 'node_modules/unkernel/dist/_chunks/core.mjs',
  'vendor/unkernel/unkernel.wasm': 'node_modules/unkernel/dist/unkernel.wasm',
  'vendor/unkernel/LICENSE': 'node_modules/unkernel/LICENSE',
  'vendor/unkernel/LICENSE-MIT': 'node_modules/unkernel/LICENSE-MIT',
  'vendor/xterm/xterm.mjs': 'node_modules/@xterm/xterm/lib/xterm.mjs',
  'vendor/xterm/xterm.css': 'node_modules/@xterm/xterm/css/xterm.css',
  'vendor/xterm/LICENSE': 'node_modules/@xterm/xterm/LICENSE',
  'vendor/addon-fit/addon-fit.mjs': 'node_modules/@xterm/addon-fit/lib/addon-fit.mjs',
  'vendor/addon-fit/LICENSE': 'node_modules/@xterm/addon-fit/LICENSE',
};

for (const [dest, source] of Object.entries(assets)) {
  const target = resolve(here, 'dist', dest);
  await mkdir(dirname(target), { recursive: true });
  // copyFile preserves the source mode, which can be read-only in the Nix store.
  await rm(target, { force: true });
  await copyFile(resolve(here, source), target);
}
console.log('Built demos/unkernel/dist/');
