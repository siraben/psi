import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import { bootPsi, psiPath } from './guest.mjs';

const container = document.querySelector('#terminal');
const status = document.querySelector('#status');
const term = new Terminal({ cursorBlink: true, screenReaderMode: true });
const fit = new FitAddon();
term.loadAddon(fit);
term.open(container);
fit.fit();

let vm;
let input;
let resize;
let observer;
try {
  if (typeof WebAssembly.Suspending !== 'function') {
    throw new Error('Use a browser with WebAssembly JSPI support.');
  }
  const guest = await fetch(new URL('./psi-aarch64', import.meta.url));
  if (!guest.ok) throw new Error(`Downloading psi: HTTP ${guest.status}`);
  vm = await bootPsi(new Uint8Array(await guest.arrayBuffer()));
  const pty = await vm.spawn(psiPath, [], {
    cols: term.cols, rows: term.rows, env: { TERM: 'xterm-256color' },
  });
  const output = pty.output.pipeTo(new WritableStream({
    write: bytes => new Promise(resolve => term.write(bytes, resolve)),
  }));
  input = term.onData(data => {
    void Promise.resolve(pty.write(data)).catch(() => {}); // May close during input.
  });
  resize = term.onResize(({ cols, rows }) => pty.resize(cols, rows));
  observer = new ResizeObserver(() => fit.fit());
  observer.observe(container);
  status.textContent = 'psi is running offline.';
  term.focus();
  const [ended] = await Promise.all([pty.ended, output]);
  status.textContent = `psi exited (${ended.code ?? ended.signal ?? ended.type}). Reload to restart.`;
} catch (error) {
  status.textContent = `Could not run psi: ${error.message}`;
  console.error(error);
} finally {
  input?.dispose();
  resize?.dispose();
  observer?.disconnect();
  await vm?.stop();
}
