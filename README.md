# psi website

Static source for <https://psicode.ai/>, served by GitHub Pages from the root of
the `gh-pages` branch in `siraben/psi`. No build step is required.

The commands below refer to the development checkout, where these files live in
`website/`. The deployment branch contains that directory's contents at its root.

## Preview

From the repository root:

```sh
python3 -m http.server 8765 --directory website
```

Open <http://localhost:8765/>. The site includes responsive layouts, keyboard
operable demo and installation tabs, copyable commands, and self-hosted terminal players.

## Publish

```sh
bash scripts/deploy-website.sh
```

The script clones `gh-pages` into a temporary directory and publishes only
`website/`. It preserves the deployment branch history and leaves the current
development branch alone. Requires Git, rsync, and existing GitHub SSH access.

## Hosting

- Canonical hostname: `psicode.ai`, also recorded in `CNAME`.
- GitHub Pages source: `gh-pages`, `/`, legacy static publishing.
- Cloudflare DNS-only apex `A` records: `185.199.108.153`, `185.199.109.153`,
  `185.199.110.153`, `185.199.111.153`.
- Cloudflare DNS-only apex `AAAA` records: `2606:50c0:8000::153`,
  `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`.
- DNS-only `www` CNAME: `siraben.github.io`.
- HTTPS is enforced by GitHub Pages for the apex and `www` hostnames.
- `.nojekyll` keeps this a plain static site.

See [GitHub's custom-domain documentation](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
for current DNS guidance.

## Terminal player

`assets/player/` vendors the standalone JS/CSS from `asciinema-player` 3.18.0
(npm), with its license. No player CDN or asciinema account is required.
The four replay tabs cover editing code, changing the live theme, adding a Lua
command, and exploring psi’s own codebase. Each has a recording, poster, caption,
and download links under `assets/demos/`. Switching tabs pauses hidden players
and preserves their playback position. Recordings load only when played.

These demos run inside a clean chroot with direct Anthropic Claude Opus 5.5.
The older `psi-terminal.*` assets remain available for existing download links;
those used OpenRouter. See the capture provenance for precise recording details.

See [CAPTURES.md](CAPTURES.md) for the screenshots' source, guest versions, and
recording provenance.

## Asset optimization

Displayed screenshots use content-hashed, lossless WebP files with responsive
`srcset`/`sizes`, explicit dimensions, and lazy loading below the hero. The hero
is eager/high priority. Original PNG downloads and the social PNG stay intact.
Full-size WebPs decode pixel-for-pixel identically to the originals. Resized
variants use Lanczos; variants heavier than larger alternatives are omitted
from delivery. Fonts are self-hosted WOFF2 subsets with their license notices.
The replay library and its stylesheet load on the first Play click.

After changing a source screenshot, run from the repository:

```sh
python3 scripts/optimize-website-images.py
python3 scripts/prepare-website-assets.py
```

The second command also updates CSS/JS cache versions after those files change.
GitHub Pages controls HTTP cache lifetimes; content hashes avoid stale images
without claiming custom immutable-cache headers.
