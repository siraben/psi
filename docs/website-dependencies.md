# Website dependency graph

The website renders the committed CycloneDX snapshot in
`assets/sbom/psi-runtime.cdx.json`. Its provenance file records the source commit,
platform, generation command, and SHA-256 digest. This is the x86_64 Linux Nix
runtime closure of `.#default`, not the full build-time dependency set, the
portable binary's link graph, or a vulnerability assessment.

The generator uses component `bom-ref` identities and only explicit
`dependencies[].dependsOn` relationships. Different versions remain distinct;
unknown references fail generation. No relationships are inferred from names.
Graphviz lays out static SVGs, so the graph renders without a chart library or
client-side requests. JavaScript adds selection and package details; the full
HTML dependency table and downloadable SBOM remain available without it.

To refresh, use the repository's pinned sbomnix against the desired Linux build,
with `--exclude-cpe-matching` to avoid heuristic product-name matches. Preserve
its output, update provenance and its hash, then regenerate with Graphviz 15.1.1:

```sh
python3 scripts/generate-dependency-graph.py
python3 scripts/generate-dependency-graph.py --check
python3 scripts/test-dependency-graph.py
node --check script.js
```

Pass `--dot /path/to/dot` if Graphviz is not on PATH. Commit the snapshot,
provenance, and generated `index.html` together. Review the source data before
publication; do not include private checkout paths or host metadata.
