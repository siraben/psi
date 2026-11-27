import { init, Terminal, FitAddon } from 'ghostty-web';
import { bootPsi, psiPath } from './guest.mjs';
import { relay } from './config.mjs';

const form = document.querySelector('#launch');
const network = document.querySelector('#network');
const enabled = document.querySelector('#enable-network');
const provider = document.querySelector('#provider');
const key = document.querySelector('#key');
const button = form.querySelector('button');
const container = document.querySelector('#terminal');
const status = document.querySelector('#status');
const keyVars = new Set(['OPENROUTER_API_KEY', 'ANTHROPIC_API_KEY']);
network.hidden = !relay || !window.isSecureContext;
if (relay && !window.isSecureContext) status.textContent = 'Serve this page over HTTPS to enable networking.';
function syncControls() {
  provider.disabled = !enabled.checked;
  key.disabled = provider.disabled || !keyVars.has(provider.value);
  key.required = !key.disabled;
  if (key.disabled) key.value = '';
}
enabled.addEventListener('change', syncControls);
provider.addEventListener('change', syncControls);
syncControls();

async function readAsset(name) {
  const response = await fetch(new URL(name, import.meta.url));
  if (!response.ok) throw new Error(`Downloading ${name}: HTTP ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

form.addEventListener('submit', async event => {
  event.preventDefault();
  button.disabled = true;
  const online = Boolean(relay && window.isSecureContext && enabled.checked);
  const env = { TERM: 'xterm-256color', HOME: '/tmp' };
  if (online) {
    env.PSI_CA_BUNDLE = '/mnt/demo/ca-bundle.crt';
    if (keyVars.has(provider.value) && key.value) env[provider.value] = key.value.trim();
  }
  key.value = '';
  network.disabled = true;
  let vm, term, input, resize, observer;
  try {
    if (typeof WebAssembly.Suspending !== 'function') {
      throw new Error('Use a browser with WebAssembly JSPI support.');
    }
    status.textContent = 'Booting Linux…';
    const [guest, caBytes] = await Promise.all([
      readAsset('psi-aarch64'), online ? readAsset('ca-bundle.crt') : null, init(),
      document.fonts.load('14px "IBM Plex Mono"'),
    ]);
    term = new Terminal({ cursorBlink: true, fontSize: 14, fontFamily: 'IBM Plex Mono, monospace',
      theme: { background: '#121314', foreground: '#efedeb', cursor: '#adc394', selectionBackground: '#3a4833' } });
    const fit = new FitAddon();
    term.loadAddon(fit);
    term.open(container);
    fit.fit();
    vm = await bootPsi(guest, { relay: online ? relay : '', caBytes });
    const pty = await vm.spawn(psiPath, [], { cols: term.cols, rows: term.rows, env });
    const output = pty.output.pipeTo(new WritableStream({
      write: bytes => new Promise(resolve => term.write(bytes, resolve)),
    }));
    input = term.onData(data => { void Promise.resolve(pty.write(data)).catch(() => {}); });
    resize = term.onResize(({ cols, rows }) => pty.resize(cols, rows));
    observer = new ResizeObserver(() => fit.fit());
    observer.observe(container);
    status.textContent = online ? 'Guest networking is enabled. Reload to discard the session.' : 'Offline guest. Reload to discard the session.';
    term.focus();
    const [ended] = await Promise.all([pty.ended, output]);
    status.textContent = `Psi exited (${ended.code ?? ended.signal ?? ended.type}). Reload to restart.`;
  } catch (error) {
    status.textContent = `Could not run Psi: ${error.message}`;
    term?.dispose();
    network.disabled = false;
    button.disabled = false;
  } finally {
    input?.dispose();
    resize?.dispose();
    observer?.disconnect();
    await vm?.stop();
  }
});
