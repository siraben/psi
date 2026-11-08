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


def include_build_inputs(runtime, build):
    """Show the runtime closure plus root's direct build inputs, preserving identities."""
    if runtime['root'] != build['root']:
        raise ValueError('Runtime and build snapshots have different roots')
    retained = {n['id'] for n in runtime['nodes']}
    direct = {e['target'] for e in build['edges'] if e['source'] == build['root']}
    visible = retained | direct
    nodes = {n['id']: dict(n, scope='build') for n in build['nodes'] if n['id'] in visible}
    nodes.update({n['id']: dict(n, scope='runtime') for n in runtime['nodes']})
    edges = {(e['source'],e['target']): dict(e,scope='build') for e in build['edges']
             if e['source'] == build['root'] and e['target'] in visible}
    edges.update({(e['source'],e['target']): dict(e,scope='runtime') for e in runtime['edges']})
    return {'root':runtime['root'], 'nodes': sorted(nodes.values(),key=lambda n:(n['id'] != runtime['root'],n['scope'] != 'runtime',n['name'],n['version'],n['ref'])),
            'edges': [edges[k] for k in sorted(edges)],
            'runtime_count':len(retained), 'build_count':len(build['nodes']),
            'build_edges':len(build['edges'])}


def render_svg(graph, dot, orientation):
    # Graphviz handles shared transitive dependencies and cycles without inventing edges.
    lines = ['digraph dependencies {',
             f'graph [rankdir=LR, bgcolor="transparent", pad="0.25", nodesep="0.32", ranksep="0.65", splines=polyline];',
             'node [shape=box, style="rounded,filled", margin="0.17,0.13", fontname="DM Sans", fontsize=13, color="#bcc3b2", fillcolor="#f5f3ec", fontcolor="#232820", penwidth=1.2];',
             'edge [color="#b6bfae", arrowsize=0.55, penwidth=1.2];']
    for node in graph['nodes']:
        attrs = f'id="{node["id"]}", label={json.dumps(node["name"] + chr(10) + node["version"])}'
        if node['id'] == graph['root']:
            attrs += ', fillcolor="#a83e24", fontcolor="#ffffff", color="#a83e24"'
        elif node.get('scope') == 'build':
            attrs += ', style="rounded,filled,dashed"'
        lines.append(f'"{node["id"]}" [{attrs}];')
    build_ids = [n['id'] for n in graph['nodes'] if n.get('scope') == 'build']
    if build_ids:
        lines.append('subgraph cluster_build { label="Build-only inputs"; fontname="DM Sans"; fontsize=12; fontcolor="#59634f"; color="#d0d5c5"; style="rounded,dashed"; margin=16;')
        groups = [build_ids[i:i+3] for i in range(0,len(build_ids),3)]
        for group in groups:
            lines.append('{rank=same; ' + ';'.join('"'+node+'"' for node in group) + ';}')
        for a,b in zip(groups,groups[1:]):
            lines.append(f'"{a[0]}" -> "{b[0]}" [style=invis, weight=100];')
        lines.append('}')
    for i,edge in enumerate(graph['edges']):
        style = 'dashed' if edge.get('scope') == 'build' else 'solid'
        lines.append(f'"{edge["source"]}" -> "{edge["target"]}" [id="edge-{i}", style="{style}"];')
    lines.append('}')
    result = subprocess.run([dot, '-Tsvg'], input='\n'.join(lines), text=True, capture_output=True, check=True)
    svg = ET.fromstring(result.stdout)
    svg.attrib.pop('width', None); svg.attrib.pop('height', None)
    svg.set('class', 'dependency-svg')
    svg.set('role', 'group'); svg.set('aria-label', 'Runtime dependencies and direct build inputs; select a package for details')
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
    views = {}
    for scope in ['runtime', 'build']:
        nodes = [n for n in graph['nodes'] if n['id'] == graph['root'] or n['scope'] == scope]
        ids = {n['id'] for n in nodes}
        edges = [e for e in graph['edges'] if e['scope'] == scope and e['source'] in ids and e['target'] in ids]
        views[scope] = {'root':graph['root'], 'nodes':nodes, 'edges':edges}
    views['both'] = {k:graph[k] for k in ['root','nodes','edges']}
    graph['views'] = views
    diagrams = ''.join('<div class="dependency-view" data-view="'+name+'"'+(' hidden' if name != 'both' else '')+'>'+render_svg(view,dot,name)+'</div>' for name,view in views.items())
    payload = json.dumps(graph, separators=(',', ':')).replace('<','\\u003c')
    commit = provenance['source_commit']
    if not re.fullmatch('[a-f0-9]{40}', commit):
        raise ValueError('Provenance requires a full source commit hash')
    return f'''<section class="dependency-section wrap" id="dependencies" aria-labelledby="dependency-heading">
      <div class="dependency-heading"><div><p class="eyebrow">Open to inspection</p><h2 id="dependency-heading">Dependencies, in the open.</h2></div><p>What stays with psi, and what builds it.<br>Connections come from its software bills of materials.</p></div>
      <div class="dependency-card">
        <div class="dependency-toolbar"><div class="dependency-controls" role="group" aria-label="Dependency types"><button type="button" data-scope="runtime" aria-pressed="true">Runtime</button><button type="button" data-scope="build" aria-pressed="true">Build</button></div><div class="dependency-toolbar-title"><span class="dependency-dot" aria-hidden="true"></span><strong>Dependency map</strong><span class="dependency-platform">Linux · x86_64</span></div><span class="dependency-count">{len(graph['nodes'])} packages / {len(graph['edges'])} connections</span></div>
        <div class="dependency-layout">
          <div class="dependency-canvas"><p class="dependency-hint">Select a package to follow its connections.</p>{diagrams}<p class="dependency-key"><span class="dependency-legend-solid">Retained at runtime</span><span class="dependency-legend-dashed">Build-time only</span><span>A → B: A depends on B</span><button type="button" class="dependency-reset" hidden>Show all connections</button></p></div>
          <aside class="dependency-details" aria-labelledby="dependency-detail-name"><p class="eyebrow">Package details</p><h3 id="dependency-detail-name">Explore the graph</h3><p class="dependency-detail-version">Select any package.</p><p class="dependency-detail-license">Select a node to see its version, package license metadata, and shown connections.</p><div class="dependency-relations" hidden><h4>Shown dependencies</h4><ul class="dependency-outgoing"></ul><h4>Shown dependents</h4><ul class="dependency-incoming"></ul></div><p class="dependency-status sr-only" aria-live="polite"></p></aside>
        </div>
        <div class="dependency-footnote"><p>Nix runtime closure + direct build inputs for <code>.#default</code> at <a href="https://github.com/siraben/psi/commit/{commit}">{commit[:7]}</a>. Other platforms and static builds differ. The full build closure contains {graph.get("build_count",len(graph["nodes"]))} packages; the diagram shows runtime relationships and direct build-input relationships.</p><a href="{esc(source_path,quote=True)}" download>Runtime SBOM <svg class="arrow-icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24"><path d="M12 4v16m-7-7 7 7 7-7"/></svg></a><a href="assets/sbom/psi-buildtime.cdx.json" download>Full build SBOM <svg class="arrow-icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24"><path d="M12 4v16m-7-7 7 7 7-7"/></svg></a></div>
      </div>
      <details class="dependency-table"><summary>Read the dependency list</summary><div class="dependency-table-scroll" role="region" aria-label="Package dependency list" tabindex="0"><table><caption>Shown packages and their visible relationships from the runtime and build SBOMs</caption><thead><tr><th scope="col">Package</th><th scope="col">Version</th><th scope="col">Shown dependencies</th><th scope="col">License</th></tr></thead><tbody>{''.join(rows)}</tbody></table></div></details>
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
    build_path = root / 'assets/sbom/psi-buildtime.cdx.json'
    build_provenance = json.loads((root / 'assets/sbom/build-provenance.json').read_text())
    if hashlib.sha256(build_path.read_bytes()).hexdigest() != build_provenance['sbom_sha256']:
        raise ValueError('Build SBOM hash does not match provenance')
    if build_provenance['source_commit'] != provenance['source_commit']:
        raise ValueError('Snapshot source commits differ')
    graph = include_build_inputs(graph, read_graph(json.loads(build_path.read_text())))
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
