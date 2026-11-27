# Psi browser demo

Run Psi in an AArch64 Linux guest with [unkernel](https://github.com/pithings/unkernel) and [Ghostty Web](https://github.com/coder/ghostty-web). Reload to discard the guest. The default build is offline.

## Build and run

From the repository root on Linux, with Nix flakes, Node.js 24+ and Python 3:

```sh
nix build .#psi-static-aarch64 --out-link build/psi-unkernel-aarch64
cd demos/unkernel
npm ci
npm run build
npm test
python3 -m http.server 8000 --bind 127.0.0.1 --directory dist
```

Open <http://127.0.0.1:8000/> in a browser with WebAssembly JSPI support (such as Chrome or Edge 137+). Psi boots automatically. Try `/help`. Ctrl-click or Command-click an HTTP(S) link to open it in a new tab. Use the browser’s Paste shortcut, or **Paste** when clipboard access is available. A guest OSC 52 write, such as from `/copy`, offers **Copy terminal text** rather than replacing your clipboard automatically; clipboard buttons require HTTPS or localhost. `npm test` boots the guest under Node and checks its architecture and `psi --version`. All browser assets are served from `dist/`.

## Network access

Set `PSI_DEMO_WISP_URL` at build time to your own `wss://` Wisp relay. Serve the page over HTTPS outside localhost. If the build machine stores its CA bundle elsewhere, set `PSI_DEMO_CA_BUNDLE` to a public trust bundle. Do not bundle private roots.

```sh
PSI_DEMO_WISP_URL=wss://relay.example.com/wisp/ npm run build
```

Select **Enable guest networking**, then **Restart with networking** to replace the offline session. Use **No key** for network access without model credentials, or supply an OpenRouter or Anthropic API key to call models. The key goes to the guest process environment, not browser storage or the static server. Guest tools can read it, so use a restricted key with a spending limit. Subscription login and shared demo credits are not included.

The relay operator must restrict page origins and guest destinations, block private and link-local targets, and limit connections and traffic. Do not expose an unrestricted relay. No proxy or model credentials are bundled.
