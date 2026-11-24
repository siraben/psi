# psi in unkernel

Boot Linux in a browser and try the psi terminal UI. Try `/help` or `/model`.
The guest has no networking or persistent storage. It does not call a model,
ask for an API key, or send terminal input anywhere. Reload for a fresh guest.

## Build and run

From the repository root on Linux, with Nix flakes, npm/Node.js 24 or later,
and Python 3:

```sh
nix build .#psi-static-aarch64 --out-link build/psi-unkernel-aarch64
cd demos/unkernel
npm ci
npm run build
npm test
python3 -m http.server 8000 --bind 127.0.0.1 --directory dist
```

Open <http://127.0.0.1:8000/> in a browser with WebAssembly JSPI support
(e.g. Chrome or Edge 137+). The page and guest boot files are all served
from `dist/`; no external assets are loaded at runtime. `npm test` boots
unkernel under Node.js and runs `psi --version` inside the guest.

The compiled WebAssembly is [unkernel's Linux kernel](https://github.com/pithings/unkernel/tree/c08e977),
shipped by the pinned `unkernel` npm package. psi itself is a statically linked
AArch64 Linux executable, not a WASI module. The page copies it into the guest
and runs it on a PTY. The generated `dist/` is not checked into Git.

## How fx handles credentials

[Vercel's hosted fx demo](https://fx.sh/) offers limited keyless inference
through a shared proxy. Visitors can optionally enter their own AI Gateway key
to bypass the proxy and use their own balance. The [fx example README](https://github.com/vercel-labs/fx/blob/main/examples/README.md#run-an-example)
describes the shared limits and how to configure a separate server-side key.
The hosted fx allowance is not used by this psi demo.
