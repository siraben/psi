import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { bootPsi, psiPath } from './guest.mjs';
import { pumpTerminal, terminalOutput } from './terminal-output.mjs';

const clipboard = [];
const filter = terminalOutput(value => clipboard.push(value));
const bytes = new TextEncoder();
assert.equal(filter(bytes.encode('─\x1b]5')), '─');
assert.equal(filter(bytes.encode('2;c;aMOpbGxv\x1b')), '');
assert.equal(filter(bytes.encode('\\x\x1b]52;c;?\x07')), 'x');
assert.deepEqual(clipboard, ['héllo']);
assert.equal(filter(bytes.encode('\x1b]8;;javascript:alert(1)\x07')), '\x1b]8;;\x07');
assert.equal(filter(bytes.encode('\x1b]8;;https://psicode.ai/\x07')), '\x1b]8;;https://psicode.ai/\x07');
assert.equal(filter(bytes.encode('\x1b]52;c;' + 'a'.repeat(17_000) + '\x07Z')), 'Z');

const received = [];
const yieldedAfter = [];
const burst = new ReadableStream({ start(controller) {
  for (let i = 0; i < 5; i++) controller.enqueue(new Uint8Array(32 * 1024).fill(i));
  controller.close();
} });
await pumpTerminal(burst, chunk => received.push(chunk[0]), {
  now: () => 0, yieldTask: async () => { yieldedAfter.push(received.length); },
});
assert.deepEqual(received, [0, 1, 2, 3, 4]);
assert.deepEqual(yieldedAfter, [2, 4]);
assert.equal(burst.locked, false);

const deadline = setTimeout(() => {
  console.error('Timed out booting unkernel or running psi');
  process.exit(1);
}, 30_000);
let vm;
try {
  const binary = await readFile(new URL('./dist/psi-aarch64', import.meta.url));
  await assert.rejects(bootPsi(binary, { relay: 'ws://example.com' }), /secure Wisp relay/);
  await assert.rejects(bootPsi(binary, { relay: 'wss://example.com' }), /CA bundle/);
  vm = await bootPsi(binary);
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
