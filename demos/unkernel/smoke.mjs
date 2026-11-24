import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { bootPsi, psiPath } from './guest.mjs';

const deadline = setTimeout(() => {
  console.error('Timed out booting unkernel or running psi');
  process.exit(1);
}, 30_000);
let vm;
try {
  vm = await bootPsi(await readFile(new URL('./dist/psi-aarch64', import.meta.url)));
  const arch = await vm.exec('/bin/uname', ['-m']);
  assert.equal(arch.exitCode, 0, arch.stderr);
  assert.equal(arch.stdout.trim(), 'aarch64');
  const version = await vm.exec(psiPath, ['--version']);
  assert.equal(version.exitCode, 0, version.stderr);
  assert.match(version.stdout, /\b\d+\.\d+\.\d+\b/);
  console.log(`unkernel (${arch.stdout.trim()}): ${version.stdout.trim()}`);
} finally {
  await vm?.stop();
  clearTimeout(deadline);
}
