import { init, Terminal, FitAddon } from 'ghostty-web';
import { bootPsi, psiPath } from './guest.mjs';
import { relay } from './config.mjs';
import { pumpTerminal, terminalOutput } from './terminal-output.mjs';

const form = document.querySelector('#launch');
const network = document.querySelector('#network');
const enabled = document.querySelector('#enable-network');
const provider = document.querySelector('#provider');
const key = document.querySelector('#key');
const button = form.querySelector('button');
const container = document.querySelector('#terminal');
const status = document.querySelector('#status');
const copy = document.querySelector('#copy-terminal');
const paste = document.querySelector('#paste-terminal');
let activeTerminal;
paste.addEventListener('click', async () => {
  const term = activeTerminal;
  try {
    const text = await navigator.clipboard.readText();
    if (term && term === activeTerminal) {
      term.paste(text);
      term.focus();
    }
    clipboardStatus.textContent = '';
  } catch {
    clipboardStatus.textContent = 'Use your browser’s Paste shortcut in the terminal.';
  }
});
const clipboardStatus = document.querySelector('#clipboard-status');
let pendingCopy;
copy.addEventListener('click', async () => {
  const text = pendingCopy;
  if (text === undefined) return;
  try {
    await navigator.clipboard.writeText(text);
    if (pendingCopy === text) {
      pendingCopy = undefined;
      copy.hidden = true;
    }
    clipboardStatus.textContent = 'Copied.';
  } catch {
    clipboardStatus.textContent = 'Clipboard permission denied.';
  }
});
const handleCopy = text => {
  if (!navigator.clipboard?.writeText) {
    clipboardStatus.textContent = 'Clipboard requires HTTPS or localhost.';
    return;
  }
  pendingCopy = text;
  clipboardStatus.textContent = '';
  copy.hidden = false;
};
const keyVars = new Set(['OPENROUTER_API_KEY', 'ANTHROPIC_API_KEY']);
const relayAvailable = Boolean(relay && window.isSecureContext);
form.hidden = !relayAvailable;
network.hidden = !relayAvailable;
let stopSession;
let session;
function syncControls() {
  provider.disabled = !enabled.checked;
  key.disabled = provider.disabled || !keyVars.has(provider.value);
  key.required = !key.disabled;
  if (key.disabled) key.value = '';
  button.disabled = !stopSession || !enabled.checked;
}
enabled.addEventListener('change', syncControls);
provider.addEventListener('change', syncControls);
syncControls();

async function readAsset(name) {
  const response = await fetch(new URL(name, import.meta.url));
  if (!response.ok) throw new Error(`Downloading ${name}: HTTP ${response.status}`);
  return new Uint8Array(await response.arrayBuffer());
}

async function runSession(online) {
  const env = { TERM: 'xterm-256color', LANG: 'C.UTF-8', HOME: '/tmp' };
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
    const filterOutput = terminalOutput(handleCopy);
    const output = pumpTerminal(pty.output, bytes => {
      const text = filterOutput(bytes);
      if (text) term.write(text);
    });
    input = term.onData(data => { void Promise.resolve(pty.write(data)).catch(() => {}); });
    resize = term.onResize(({ cols, rows }) => pty.resize(cols, rows));
    observer = new ResizeObserver(() => fit.fit());
    observer.observe(container);
    if (!online && relayAvailable) {
      stopSession = async () => {
        const guest = vm;
        vm = undefined;
        await guest.stop();
      };
      network.disabled = false;
      syncControls();
    }
    activeTerminal = term;
    paste.hidden = !navigator.clipboard?.readText;
    status.textContent = online ? 'Guest networking is enabled. Reload to discard the session.'
      : relay && !relayAvailable ? 'Offline guest. Use HTTPS to enable networking.' : 'Offline guest. Reload to discard the session.';
    term.focus();
    const [ended] = await Promise.all([pty.ended, output]);
    status.textContent = `Psi exited (${ended.code ?? ended.signal ?? ended.type}). Reload to restart.`;
  } catch (error) {
    status.textContent = `Could not run Psi: ${error.message}`;
  } finally {
    stopSession = undefined;
    activeTerminal = undefined;
    paste.hidden = true;
    button.disabled = true;
    input?.dispose();
    resize?.dispose();
    observer?.disconnect();
    term?.dispose();
    await vm?.stop();
  }
}

form.addEventListener('submit', async event => {
  event.preventDefault();
  if (!relayAvailable || !enabled.checked || !stopSession) return;
  button.disabled = true;
  network.disabled = true;
  try {
    await stopSession();
    await session;
  } catch {
    key.value = '';
    status.textContent = 'Could not restart the guest. Reload and try again.';
    return;
  }
  form.hidden = true;
  pendingCopy = undefined;
  copy.hidden = true;
  clipboardStatus.textContent = '';
  session = runSession(true);
});

session = runSession(false);
