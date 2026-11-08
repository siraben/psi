# Website dependency graph

The website uses two committed CycloneDX snapshots:
`assets/sbom/psi-runtime.cdx.json` and `assets/sbom/psi-buildtime.cdx.json`.
Their provenance files record the source commit, platform, generation command,
and SHA-256 digest. They use release `v0.2.0` on x86_64 Linux, Nix `.#default`.
This is not the portable binary's link graph or a vulnerability assessment.

The view shows the complete runtime closure plus psi's direct build inputs.
The full build closure has 918 packages and is downloadable separately. The diagram shows all runtime relationships and root-to-input build relationships. Solid edges are recorded in
the runtime SBOM; dashed edges occur only in the build SBOM. Build-only packages
also have dashed outlines. Classification uses exact `bom-ref` identities, not
package names. Different versions remain distinct; unknown references fail
rather than silently disappearing. The source snapshots are never inferred
from the diagram.

Graphviz lays out static SVGs, so rendering needs no chart library or client-side
requests. JavaScript adds selection and package details. The HTML dependency
table and downloadable SBOMs remain available without JavaScript. Runtime and Build toggles select either group or both, with at least one
required. Each combination has its own precomputed layout. Build means the
additional build-only direct inputs; inputs already retained remain in Runtime.
Mobile uses a scrollable graph to keep package labels readable.

To refresh, use the repository's pinned sbomnix against the desired Linux build,
once normally and once with `--buildtime`, with `--exclude-cpe-matching` to
avoid heuristic product-name matches. Preserve its outputs, update provenance
and hashes, then regenerate with Graphviz 15.1.1:

```sh
python3 scripts/generate-dependency-graph.py
python3 scripts/generate-dependency-graph.py --check
python3 scripts/test-dependency-graph.py
node --check script.js
```

Pass `--dot /path/to/dot` if Graphviz is not on PATH. Commit snapshots,
provenance, and generated `index.html` together. Review the source data before
publication; do not include private checkout paths or host metadata. Any
metadata corrections must have explicit evidence and be recorded in provenance.

License enrichment is recorded in `license-evidence.json`. Run
`python3 scripts/enrich-sbom-licenses.py` before rendering after a refresh.
It fills only missing fields with exact derivation matches and records pre- and
post-enrichment hashes. These are package-level Nix license declarations, not
per-file license analysis or inferred AND/OR expressions. In particular, xgcc
represents its libgcc runtime output; no runtime licensing exception is inferred.
