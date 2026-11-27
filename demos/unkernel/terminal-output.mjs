const ESC = '\x1b';
const BEL = '\x07';
const limit = 16_384;

function safeLink(value) {
  if (!/^https?:\/\//i.test(value) || /[\s\x00-\x1f\x7f-\x9f\\]/u.test(value)) return false;
  try {
    const url = new URL(value);
    return !url.username && !url.password;
  } catch {
    return false;
  }
}

// Parse OSC across PTY writes. OSC 52 is write-only and always needs a
// browser gesture. Leave printable output and other escape sequences to Ghostty.
export function terminalOutput(onCopy) {
  const decoder = new TextDecoder();
  let escape = false;
  let osc = null;
  let overflow = false;
  let oscEscape = false;
  function finish() {
    const value = osc;
    osc = null;
    if (overflow) return '';
    if (/^0*52;/.test(value)) {
      const encoded = /^0*52;[csp0-7]*;([A-Za-z0-9+/]+={0,2})$/.exec(value)?.[1];
      if (encoded) {
        try {
          const text = new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(atob(encoded), c => c.charCodeAt(0)));
          onCopy(text);
        } catch { /* Ignore malformed data. */ }
      }
      return '';
    }
    if (/^0*8;/.test(value)) {
      const url = /^0*8;[^;]*;(.*)$/.exec(value)?.[1];
      if (url !== '' && !safeLink(url || '')) return `${ESC}]8;;${BEL}`;
    }
    return `${ESC}]${value}${BEL}`;
  }
  return bytes => {
    let out = '';
    for (const char of decoder.decode(bytes, { stream: true })) {
      if (osc !== null) {
        if (char === BEL || char === '\x9c' || (oscEscape && char === '\\')) {
          out += finish();
          oscEscape = false;
        } else {
          if (oscEscape) overflow = true;
          oscEscape = char === ESC;
          if (!oscEscape && !overflow) {
            if (osc.length >= limit) overflow = true;
            else osc += char;
          }
        }
      } else if (char === '\x9d' || (escape && char === ']')) {
        osc = '';
        overflow = false;
        escape = false;
      } else {
        if (escape) out += ESC;
        escape = char === ESC;
        if (!escape) out += char;
      }
    }
    return out;
  };
}
