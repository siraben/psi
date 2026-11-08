#!/usr/bin/env python3
"""Render a CycloneDX dependency snapshot into the static website.

Requires Graphviz's dot. Edges come exclusively from dependsOn records; component
identity is bom-ref, never a package name. No network requests are performed.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

NS = '{http://www.w3.org/2000/svg}'
ET.register_namespace('', NS[1:-1])


def read_graph(document):
    if document.get('bomFormat') != 'CycloneDX':
        raise ValueError('Expected a CycloneDX SBOM')
    root = document.get('metadata', {}).get('component', {})
    root_ref = root.get('bom-ref')
    if not root_ref:
        raise ValueError('SBOM metadata.component needs a bom-ref')
    components = {}
    for component in [root, *document.get('components', [])]:
        ref = component.get('bom-ref')
        if not ref or not component.get('name'):
            raise ValueError('Every component needs a bom-ref and name')
        licenses = []
        for entry in component.get('licenses', []):
            license = entry.get('license', {})
            value = entry.get('expression') or license.get('id') or license.get('name')
            if value:
                licenses.append(value)
        value = {'id': ref, 'name': component['name'],
                 'version': component.get('version', 'Not recorded'),
                 'licenses': sorted(set(licenses))}
        if ref in components and components[ref] != value:
            raise ValueError(f'Conflicting component identity: {ref}')
        components[ref] = value
    edges = set()
    for item in document.get('dependencies', []):
        source = item['ref']
        if source not in components:
            raise ValueError(f'Unknown dependency source: {source}')
        for target in item.get('dependsOn', []):
            if target not in components:
                raise ValueError(f'Unknown dependency target: {target}')
            edges.add((source, target))
    if not document.get('dependencies'):
        raise ValueError('SBOM has no dependency records')
    nodes = sorted(components.values(), key=lambda n: (n['id'] != root_ref, n['name'], n['version'], n['id']))
    ids = {n['id']: 'pkg-' + hashlib.sha256(n['id'].encode()).hexdigest()[:12] for n in nodes}
    for node in nodes:
        node['ref'] = node['id']
        node['id'] = ids[node['id']]
    return {'root': ids[root_ref], 'nodes': nodes,
            'edges': [{'source': ids[a], 'target': ids[b]} for a,b in sorted(edges)]}


def render_svg(graph, dot, orientation):
    # Graphviz handles shared transitive dependencies and cycles without inventing edges.
    lines = ['digraph dependencies {',
             f'graph [rankdir={orientation}, bgcolor="transparent", pad="0.25", nodesep="0.32", ranksep="0.65", splines=polyline];',
             'node [shape=box, style="rounded,filled", margin="0.17,0.13", fontname="DM Sans", fontsize=13, color="#bcc3b2", fillcolor="#f5f3ec", fontcolor="#232820", penwidth=1.2];',
             'edge [color="#b6bfae", arrowsize=0.55, penwidth=1.2];']
    for node in graph['nodes']:
        attrs = f'id="{node["id"]}", label={json.dumps(node["name"] + chr(10) + node["version"])}'
        if node['id'] == graph['root']:
            attrs += ', fillcolor="#a83e24", fontcolor="#ffffff", color="#a83e24"'
        lines.append(f'"{node["id"]}" [{attrs}];')
    for i,edge in enumerate(graph['edges']):
        lines.append(f'"{edge["source"]}" -> "{edge["target"]}" [id="edge-{i}"];')
    lines.append('}')
    result = subprocess.run([dot, '-Tsvg'], input='\n'.join(lines), text=True, capture_output=True, check=True)
    svg = ET.fromstring(result.stdout)
    svg.attrib.pop('width', None); svg.attrib.pop('height', None)
    svg.set('class', 'dependency-svg')
    svg.set('role', 'group'); svg.set('aria-label', 'Runtime package dependency graph; select a package for details')
    nodes = {n['id']: n for n in graph['nodes']}
    for element in svg.iter():
        identity = element.get('id')
        if identity in nodes:
            node = nodes[identity]
            element.set('data-package', identity)
            element.set('role', 'button'); element.set('tabindex', '0')
            element.set('aria-label', f'{node["name"]} {node["version"]}: inspect dependencies')
            element.set('aria-pressed', 'false')
        elif identity and identity.startswith('edge-'):
            edge = graph['edges'][int(identity[5:])]
            element.set('data-source', edge['source']); element.set('data-target', edge['target'])
            element.set('aria-hidden', 'true')
        if identity:
            element.set('id', f'{orientation.lower()}-{identity}')
    # Tooltips should show package names, not internal Graphviz IDs.
    for element in svg.findall(f'.//{NS}g[@class="node"]'):
        title = element.find(f'{NS}title')
        if title is not None:
            title.text = nodes[element.get('data-package')]['name']
    return ET.tostring(svg, encoding='unicode')


def build_section(graph, provenance, source_path, dot):
    esc = html.escape
    by_id = {n['id']: n for n in graph['nodes']}
    rows = []
    for node in graph['nodes']:
        dependencies = [by_id[e['target']]['name'] for e in graph['edges'] if e['source'] == node['id']]
        rows.append('<tr><th scope="row">'+esc(node['name'])+'</th><td>'+esc(node['version'])+'</td><td>'+esc(', '.join(sorted(dependencies)) or 'None recorded')+'</td><td>'+esc(', '.join(node['licenses']) or 'Not recorded')+'</td></tr>')
    payload = json.dumps(graph, separators=(',', ':')).replace('<','\\u003c')
    commit = provenance['source_commit']
    if not re.fullmatch('[a-f0-9]{40}', commit):
        raise ValueError('Provenance requires a full source commit hash')
    return f'''<section class="dependency-section wrap" id="dependencies" aria-labelledby="dependency-heading">
      <div class="dependency-heading"><div><p class="eyebrow">Open to inspection</p><h2 id="dependency-heading">Dependencies, in the open.</h2></div><p>Follow the packages behind a Linux build.<br>Every connection comes from its software bill of materials.</p></div>
      <div class="dependency-card">
        <div class="dependency-toolbar"><div><span class="dependency-dot" aria-hidden="true"></span><strong>Runtime dependencies</strong><span class="dependency-platform">Linux · x86_64</span></div><span>{len(graph['nodes'])} packages <span aria-hidden="true">/</span> {len(graph['edges'])} connections</span></div>
        <div class="dependency-layout">
          <div class="dependency-canvas"><p class="dependency-hint">Select a package to follow its connections.</p><div class="dependency-landscape">{render_svg(graph,dot,'LR')}</div><div class="dependency-portrait">{render_svg(graph,dot,'TB')}</div><p class="dependency-key"><span aria-hidden="true">A → B</span><span>A depends on B</span><button type="button" class="dependency-reset" hidden>Show all connections</button></p></div>
          <aside class="dependency-details" aria-labelledby="dependency-detail-name"><p class="eyebrow">Package details</p><h3 id="dependency-detail-name">Explore the graph</h3><p class="dependency-detail-version">Select any package.</p><p class="dependency-detail-license">Versions, licenses, and direct connections are recorded in the SBOM.</p><div class="dependency-relations" hidden><h4>Depends on</h4><ul class="dependency-outgoing"></ul><h4>Used by</h4><ul class="dependency-incoming"></ul></div><p class="dependency-status sr-only" aria-live="polite"></p></aside>
        </div>
        <div class="dependency-footnote"><p>Snapshot of the Nix runtime closure for <code>.#default</code> at <a href="https://github.com/siraben/psi/commit/{commit}">{commit[:7]}</a>. Other platforms and static builds differ. Build tools and source-only dependencies are outside this graph.</p><a href="{esc(source_path,quote=True)}" download>Download SBOM <svg class="arrow-icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24"><path d="M12 4v16m-7-7 7 7 7-7"/></svg></a></div>
      </div>
      <details class="dependency-table"><summary>Read the dependency list</summary><div class="dependency-table-scroll" role="region" aria-label="Package dependency list" tabindex="0"><table><caption>Packages and direct relationships recorded in this runtime SBOM</caption><thead><tr><th scope="col">Package</th><th scope="col">Version</th><th scope="col">Depends on</th><th scope="col">License</th></tr></thead><tbody>{''.join(rows)}</tbody></table></div></details>
      <script type="application/json" id="dependency-data">{payload}</script>
    </section>'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sbom', type=Path, default=Path('assets/sbom/psi-runtime.cdx.json'))
    parser.add_argument('--provenance', type=Path, default=Path('assets/sbom/provenance.json'))
    parser.add_argument('--dot', default='dot')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sbom = root / args.sbom; provenance = json.loads((root / args.provenance).read_text())
    graph = read_graph(json.loads(sbom.read_text()))
    if hashlib.sha256(sbom.read_bytes()).hexdigest() != provenance['sbom_sha256']:
        raise ValueError('SBOM hash does not match its provenance')
    section = build_section(graph, provenance, str(args.sbom), args.dot)
    page = root / 'index.html'; text = page.read_text()
    begin, end = '<!-- dependency-graph:start -->', '<!-- dependency-graph:end -->'
    if begin not in text:
        text = text.replace('    <section class="portability-section"', f'    {begin}\n    {end}\n    <section class="portability-section"', 1)
    result = re.sub(re.escape(begin)+'.*?'+re.escape(end), lambda _:begin+'\n    '+section+'\n    '+end, text, flags=re.S)
    if args.check:
        if result != page.read_text():
            raise SystemExit('Dependency graph is stale; regenerate it.')
    else:
        page.write_text(result)
    print(f'{len(graph["nodes"])} packages, {len(graph["edges"])} recorded relationships; graph '+('verified' if args.check else 'generated'))

if __name__ == '__main__':
    main()
