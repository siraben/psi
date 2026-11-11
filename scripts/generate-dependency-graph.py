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


DOWNLOAD_ICON = '<svg class="arrow-icon" aria-hidden="true" focusable="false" viewBox="0 0 24 24" fill="none"><path fill-rule="evenodd" clip-rule="evenodd" d="M12 1.25C12.4142 1.25 12.75 1.58579 12.75 2V12.9726L14.4306 11.0119C14.7001 10.6974 15.1736 10.661 15.4881 10.9306C15.8026 11.2001 15.839 11.6736 15.5694 11.9881L12.5694 15.4881C12.427 15.6543 12.2189 15.75 12 15.75C11.7811 15.75 11.573 15.6543 11.4306 15.4881L8.43056 11.9881C8.16099 11.6736 8.19741 11.2001 8.51191 10.9306C8.8264 10.661 9.29988 10.6974 9.56944 11.0119L11.25 12.9726V2C11.25 1.58579 11.5858 1.25 12 1.25ZM6.99583 8.25196C7.41003 8.24966 7.74768 8.58357 7.74999 8.99778C7.7523 9.41199 7.41838 9.74964 7.00418 9.75194C5.91068 9.75803 5.1356 9.78643 4.54735 9.89448C3.98054 9.99859 3.65246 10.1658 3.40901 10.4092C3.13225 10.686 2.9518 11.0746 2.85315 11.8083C2.75159 12.5637 2.75 13.5648 2.75 15.0002V16.0002C2.75 17.4356 2.75159 18.4367 2.85315 19.1921C2.9518 19.9259 3.13225 20.3144 3.40901 20.5912C3.68577 20.868 4.07435 21.0484 4.80812 21.1471C5.56347 21.2486 6.56458 21.2502 8 21.2502H16C17.4354 21.2502 18.4365 21.2486 19.1919 21.1471C19.9257 21.0484 20.3142 20.868 20.591 20.5912C20.8678 20.3144 21.0482 19.9259 21.1469 19.1921C21.2484 18.4367 21.25 17.4356 21.25 16.0002V15.0002C21.25 13.5648 21.2484 12.5637 21.1469 11.8083C21.0482 11.0746 20.8678 10.686 20.591 10.4092C20.3475 10.1658 20.0195 9.99859 19.4527 9.89448C18.8644 9.78643 18.0893 9.75803 16.9958 9.75194C16.5816 9.74964 16.2477 9.41199 16.25 8.99778C16.2523 8.58357 16.59 8.24966 17.0042 8.25196C18.0857 8.25799 18.9871 8.28387 19.7236 8.41916C20.4816 8.55839 21.1267 8.82364 21.6517 9.34857C22.2536 9.95048 22.5125 10.7084 22.6335 11.6085C22.75 12.4754 22.75 13.5778 22.75 14.9453V16.0551C22.75 17.4227 22.75 18.525 22.6335 19.392C22.5125 20.2921 22.2536 21.0499 21.6517 21.6519C21.0497 22.2538 20.2919 22.5127 19.3918 22.6337C18.5248 22.7503 17.4225 22.7502 16.0549 22.7502H7.94513C6.57754 22.7502 5.47522 22.7503 4.60825 22.6337C3.70814 22.5127 2.95027 22.2538 2.34835 21.6519C1.74643 21.0499 1.48754 20.2921 1.36652 19.392C1.24996 18.525 1.24998 17.4227 1.25 16.0551V14.9453C1.24998 13.5778 1.24996 12.4754 1.36652 11.6085C1.48754 10.7084 1.74643 9.95048 2.34835 9.34857C2.87328 8.82363 3.51835 8.55839 4.27635 8.41916C5.01291 8.28387 5.9143 8.25798 6.99583 8.25196Z" fill="currentColor"/></svg>'


ADVANCES = {' ':266,'!':250,'"':291,'#':804,'$':580,'%':786,'&':734,"'":159,'(':373,')':373,'*':480,'+':550,',':182,'-':541,'.':198,'/':392,'0':684,'1':312,'2':576,'3':591,'4':607,'5':610,'6':628,'7':534,'8':608,'9':628,':':202,';':227,'<':550,'=':550,'>':550,'?':524,'@':1005,'A':664,'B':603,'C':717,'D':688,'E':565,'F':535,'G':758,'H':681,'I':234,'J':501,'K':584,'L':527,'M':841,'N':691,'O':774,'P':580,'Q':774,'R':594,'S':580,'T':561,'U':655,'V':669,'W':968,'X':603,'Y':580,'Z':541,'[':314,'\\':392,']':314,'^':622,'_':660,'`':213,'a':544,'b':626,'c':572,'d':627,'e':568,'f':340,'g':558,'h':575,'i':240,'j':243,'k':504,'l':223,'m':891,'n':574,'o':593,'p':626,'q':627,'r':370,'s':502,'t':392,'u':573,'v':527,'w':763,'x':496,'y':556,'z':458,'{':427,'|':234,'}':427,'~':550}
NODE_FONT = 11
NODE_PAD = 10
NODE_HEIGHT = 24
ARROW = 6
SLOT = 6.5
LANE_STEP = 7
CLEARANCE = 4


def node_width(node):
    text = node['name'] + ' ' + node['version']
    return sum(ADVANCES.get(char, 560) for char in text) * NODE_FONT / 1000 * 1.04 + 2 * NODE_PAD


def label_nodes(svg, nodes, root):
    for group in list(svg.iter(f'{NS}g')):
        node = nodes.get(group.get('id')) if group.get('class') == 'node' else None
        rect = group.find(f'{NS}rect') if node else None
        if rect is None:
            continue
        cx = float(rect.get('x')) + float(rect.get('width')) / 2
        cy = float(rect.get('y')) + float(rect.get('height')) / 2
        is_root = node['id'] == root
        text = ET.SubElement(group, f'{NS}text', {'x': f'{cx:g}', 'y': f'{cy:g}', 'dy': '.35em', 'text-anchor': 'middle', 'font-family': 'DM Sans, sans-serif', 'font-size': str(NODE_FONT), 'fill': '#ffffff' if is_root else '#2a2826'})
        text.text = node['name'] + ' '
        version = ET.SubElement(text, f'{NS}tspan', {'fill': '#f6d3e0' if is_root else '#9a958f'})
        version.text = node['version']


def route_edges(svg, nodes, edges):
    boxes = {}
    for group in svg.iter(f'{NS}g'):
        rect = group.find(f'{NS}rect') if group.get('class') == 'node' and group.get('id') in nodes else None
        if rect is not None:
            boxes[group.get('id')] = tuple(float(rect.get(key)) for key in ('x', 'y', 'width', 'height'))
    if not boxes:
        return
    columns = []
    for center in sorted(x + w / 2 for x, y, w, h in boxes.values()):
        if columns and center - columns[-1][-1] <= 2:
            columns[-1].append(center)
        else:
            columns.append([center])
    means = [sum(column) / len(column) for column in columns]
    rank_of = {ident: min(range(len(means)), key=lambda r: abs(means[r] - (x + w / 2))) for ident, (x, y, w, h) in boxes.items()}
    left = {r: min(boxes[i][0] for i in boxes if rank_of[i] == r) for r in range(len(means))}
    right = {r: max(boxes[i][0] + boxes[i][2] for i in boxes if rank_of[i] == r) for r in range(len(means))}
    middle = {r: (right[r] + left[r + 1]) / 2 for r in range(len(means) - 1)}

    def blocked(y, x0, x1, skip):
        return any(ident not in skip and ny - CLEARANCE < y < ny + h + CLEARANCE and x < x1 and x + w > x0 for ident, (x, ny, w, h) in boxes.items())

    rows = sorted({round(y - CLEARANCE - 3, 2) for x, y, w, h in boxes.values()} | {round(y + h + CLEARANCE + 3, 2) for x, y, w, h in boxes.values()})
    used = []
    plan = {}
    arrivals = {}
    for index, edge in enumerate(edges):
        if edge['source'] in boxes and edge['target'] in boxes and rank_of[edge['target']] > rank_of[edge['source']]:
            arrivals.setdefault(edge['target'], []).append(index)
    slot_of = {}
    for target, indexes in arrivals.items():
        indexes.sort(key=lambda i: boxes[edges[i]['source']][1] + boxes[edges[i]['source']][3] / 2)
        pitch = min(SLOT, (boxes[target][3] - 8) / max(len(indexes) - 1, 1))
        for k, i in enumerate(indexes):
            slot_of[i] = (k - (len(indexes) - 1) / 2) * pitch
    for index, edge in enumerate(edges):
        source, target = edge['source'], edge['target']
        if source not in boxes or target not in boxes or rank_of[target] <= rank_of[source]:
            continue
        sx, sy = boxes[source][0] + boxes[source][2], boxes[source][1] + boxes[source][3] / 2
        tx, ty = boxes[target][0], boxes[target][1] + boxes[target][3] / 2 + slot_of.get(index, 0)
        skip = {source, target}
        first, last = rank_of[source], rank_of[target]
        if abs(sy - ty) < 0.5:
            if not blocked(sy, sx, tx, skip):
                plan[index] = {'kind': 'straight', 'sx': sx, 'sy': sy, 'tx': tx, 'ty': ty}
                continue
        else:
            for gap in [first] + list(range(last - 1, first, -1)):
                if left[gap + 1] - right[gap] >= 12 and not blocked(sy, sx, middle[gap], skip) and not blocked(ty, middle[gap], tx, skip):
                    plan[index] = {'kind': 'direct', 'gap': gap, 'sx': sx, 'sy': sy, 'tx': tx, 'ty': ty}
                    break
            if index in plan:
                continue
        if last - first >= 2 and left[first + 1] - right[first] >= 12 and left[last] - right[last - 1] >= 12 and not blocked(sy, sx, middle[first], skip) and not blocked(ty, middle[last - 1], tx, skip):
            x0, x1 = middle[first], middle[last - 1]
            for row in sorted(rows, key=lambda y: abs(y - sy) + abs(y - ty)):
                if blocked(row, x0, x1, skip) or any(abs(row - other) < 5 and other_x0 < x1 and x0 < other_x1 for other, other_x0, other_x1 in used):
                    continue
                used.append((row, x0, x1))
                plan[index] = {'kind': 'corridor', 'first': first, 'last': last - 1, 'row': row, 'sx': sx, 'sy': sy, 'tx': tx, 'ty': ty}
                break

    lanes = {}

    def register(key, starts, ends):
        lane = lanes.setdefault(key, {'starts': set(), 'ends': set()})
        lane['starts'].update(starts); lane['ends'].update(ends)

    def keys_for(index):
        step, edge = plan[index], edges[index]
        scope = edge.get('scope')
        if step['kind'] == 'direct':
            return [('out', step['gap'], edge['source'], scope)]
        if step['kind'] == 'corridor':
            return [('out', step['first'], edge['source'], scope), ('in', step['last'], edge['target'], scope, index)]
        return []

    for index, step in plan.items():
        keys = keys_for(index)
        if step['kind'] == 'direct':
            register(keys[0], [step['sy']], [step['ty']])
        elif step['kind'] == 'corridor':
            register(keys[0], [step['sy']], [step['row']])
            register(keys[1], [step['row']], [step['ty']])

    def span(key):
        values = lanes[key]['starts'] | lanes[key]['ends']
        return min(values), max(values)

    def crossings(a, b):
        low_a, high_a = span(a)
        low_b, high_b = span(b)
        return sum(1 for y in lanes[b]['starts'] if low_a < y < high_a) + sum(1 for y in lanes[a]['ends'] if low_b < y < high_b)

    lane_x = {}
    gaps = {}
    for key in lanes:
        gaps.setdefault(key[1], []).append(key)
    for gap, keys in gaps.items():
        keys.sort(key=lambda key: min(lanes[key]['starts']))
        for _ in range(len(keys) * len(keys)):
            swapped = False
            for k in range(len(keys) - 1):
                if crossings(keys[k + 1], keys[k]) < crossings(keys[k], keys[k + 1]):
                    keys[k], keys[k + 1] = keys[k + 1], keys[k]; swapped = True
            if not swapped:
                break
        step = min(LANE_STEP, (left[gap + 1] - right[gap] - 10) / max(len(keys) - 1, 1))
        for k, key in enumerate(keys):
            lane_x[key] = middle[gap] + (k - (len(keys) - 1) / 2) * step

    for group in svg.iter(f'{NS}g'):
        ident = group.get('id') or ''
        if group.get('class') != 'edge' or not ident.startswith('edge-') or int(ident[5:]) not in plan:
            continue
        index = int(ident[5:])
        step = plan[index]
        path = group.find(f'{NS}path'); head = group.find(f'{NS}polygon')
        if path is None or head is None:
            continue
        sx, sy, tx, ty = step['sx'], step['sy'], step['tx'], step['ty']
        end = tx - ARROW
        keys = keys_for(index)
        if step['kind'] == 'straight':
            d = f'M{sx:.2f},{sy:.2f}H{end:.2f}'
        elif step['kind'] == 'direct':
            d = f'M{sx:.2f},{sy:.2f}H{lane_x[keys[0]]:.2f}V{ty:.2f}H{end:.2f}'
        else:
            d = f'M{sx:.2f},{sy:.2f}H{lane_x[keys[0]]:.2f}V{step["row"]:.2f}H{lane_x[keys[1]]:.2f}V{ty:.2f}H{end:.2f}'
        path.set('d', d)
        head.set('points', f'{tx:.2f},{ty:.2f} {end:.2f},{ty - ARROW * 0.4:.2f} {end:.2f},{ty + ARROW * 0.4:.2f} {tx:.2f},{ty:.2f}')
        head.attrib.pop('stroke-dasharray', None)


def render_svg(graph, dot, orientation):
    # Graphviz handles shared transitive dependencies and cycles without inventing edges.
    lines = ['digraph dependencies {',
             'graph [rankdir=LR, bgcolor="transparent", pad="0.2", nodesep="0.14", ranksep="0.64", splines=ortho, newrank=true];',
             'node [shape=box, style="filled", margin="0.17,0.08", fontname="DM Sans", fontsize=11, color="#cdc9c4", fillcolor="#faf9f8", fontcolor="#2a2826", penwidth=1];',
             'edge [color="#bdb9b4", arrowsize=0.45, penwidth=1];']
    indegree = {}
    for edge in graph['edges']:
        indegree[edge['target']] = indegree.get(edge['target'], 0) + 1
    for node in graph['nodes']:
        node_height = max(NODE_HEIGHT, SLOT * (indegree.get(node['id'], 1) - 1) + 14)
        attrs = f'id="{node["id"]}", label="", fixedsize=true, width={node_width(node) / 72:.4f}, height={node_height / 72:.4f}'
        if node['id'] == graph['root']:
            attrs += ', fillcolor="#c9507d", color="#c9507d"'
        elif node.get('scope') == 'build':
            attrs += ', style="filled,dashed"'
        lines.append(f'"{node["id"]}" [{attrs}];')
    build_ids = [n['id'] for n in graph['nodes'] if n.get('scope') == 'build']
    if build_ids:
        lines.append('subgraph cluster_build { label="Build-only inputs"; fontname="DM Sans"; fontsize=10; fontcolor="#8a857f"; color="#d3cfca"; style="dashed"; margin=14;')
        groups = [build_ids[i:i+4] for i in range(0,len(build_ids),4)]
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
    for group in svg.iter(f'{NS}g'):
        if group.get('class') not in ('node', 'cluster'):
            continue
        for index, child in enumerate(list(group)):
            if child.tag != f'{NS}polygon':
                continue
            points = [tuple(float(value) for value in point.split(',')) for point in child.get('points').split()]
            xs = [point[0] for point in points]; ys = [point[1] for point in points]
            rect = ET.Element(f'{NS}rect', {key: value for key, value in child.attrib.items() if key != 'points'})
            rect.set('x', f'{min(xs):g}'); rect.set('y', f'{min(ys):g}')
            rect.set('width', f'{max(xs) - min(xs):g}'); rect.set('height', f'{max(ys) - min(ys):g}')
            rect.set('rx', '3' if group.get('class') == 'node' else '5')
            group.remove(child); group.insert(index, rect)
    svg.set('class', 'dependency-svg')
    svg.set('role', 'group'); svg.set('aria-label', 'Runtime dependencies and direct build inputs; select a package for details')
    nodes = {n['id']: n for n in graph['nodes']}
    label_nodes(svg, nodes, graph['root'])
    route_edges(svg, nodes, graph['edges'])
    for element in svg.iter():
        identity = element.get('id')
        if identity in nodes:
            node = nodes[identity]
            element.set('data-package', identity)
            element.set('data-scope', node.get('scope', 'runtime'))
            element.set('role', 'button'); element.set('tabindex', '0')
            element.set('aria-label', f'{node["name"]} {node["version"]}: inspect dependencies')
            element.set('aria-pressed', 'false')
        elif identity and identity.startswith('edge-'):
            edge = graph['edges'][int(identity[5:])]
            element.set('data-source', edge['source']); element.set('data-target', edge['target'])
            element.set('data-scope', edge.get('scope', 'runtime'))
            element.set('aria-hidden', 'true')
        if identity:
            element.set('id', f'{orientation.lower()}-{identity}')
    # Tooltips should show package names, not internal Graphviz IDs.
    for element in svg.findall(f'.//{NS}g[@class="node"]'):
        title = element.find(f'{NS}title')
        if title is not None:
            title.text = nodes[element.get('data-package')]['name']
    return ET.tostring(svg, encoding='unicode')


def render_tree(graph):
    """Accessible mobile disclosures, following only recorded outgoing edges."""
    esc = html.escape
    nodes = {node['id']: node for node in graph['nodes']}
    outgoing = {identity: [] for identity in nodes}
    for edge in graph['edges']:
        outgoing[edge['source']].append(edge['target'])
    def branch(identity, ancestors):
        node = nodes[identity]
        children = sorted(outgoing[identity], key=lambda key:(nodes[key]['name'],nodes[key]['version'],key))
        cycle = identity in ancestors
        label = '<span class="dependency-tree-name">'+esc(node['name'])+'</span><span class="dependency-tree-version">'+esc(node['version'])+'</span>'
        license_text = esc(', '.join(node['licenses']) or 'Not recorded in the SBOM')
        nested = '' if cycle or not children else '<ul>'+''.join(branch(child, ancestors | {identity}) for child in children)+'</ul>'
        note = '<p class="dependency-tree-note">Already on this path; see the earlier entry.</p>' if cycle else ''
        count = '<span class="dependency-tree-count">'+str(len(children))+' dependencies</span>' if children and not cycle else ''
        return '<li class="dependency-tree-item dependency-tree-'+node['scope']+'"><details><summary>'+label+'</summary><div class="dependency-tree-content"><p class="dependency-tree-license">Package license metadata: '+license_text+'</p>'+count+note+nested+'</div></details></li>'
    root = nodes[graph['root']]
    sections = []
    for scope, title in [('runtime','Runtime'),('build','Build-only inputs')]:
        children = [child for child in outgoing[graph['root']] if nodes[child]['scope'] == scope]
        if children:
            content = '<ul>'+''.join(branch(child,{graph['root']}) for child in sorted(children,key=lambda key:(nodes[key]['name'],nodes[key]['version'],key)))+'</ul>'
            sections.append('<details class="dependency-tree-group"'+(' open' if scope == 'runtime' else '')+'><summary>'+title+'<span>'+str(len(children))+' direct</span></summary>'+content+'</details>')
    return '<div class="dependency-mobile-tree"><div class="dependency-tree-root"><strong>'+esc(root['name'])+'</strong><span>'+esc(root['version'])+'</span></div>'+''.join(sections)+'</div>'


def build_section(graph, provenance, source_path, dot):
    esc = html.escape
    by_id = {n['id']: n for n in graph['nodes']}
    rows = []
    for node in graph['nodes']:
        dependencies = [by_id[e['target']]['name'] for e in graph['edges'] if e['source'] == node['id']]
        rows.append('<tr><th scope="row">'+esc(node['name'])+'</th><td>'+esc(node['version'])+'</td><td>'+esc(', '.join(sorted(dependencies)) or 'None recorded')+'</td><td>'+esc(', '.join(node['licenses']) or 'Not recorded')+'</td></tr>')
    package_items = ''.join('<li><button type="button" data-list="'+esc(n['id'])+'" data-list-scope="'+esc(n.get('scope','runtime'))+'"><span class="dep-ico dep-ico-pkg"></span><span class="dep-item-name">'+esc(n['name'])+'</span></button></li>' for n in sorted(graph['nodes'], key=lambda n: n['name']))
    views = {}
    for scope in ['runtime', 'build']:
        nodes = [n for n in graph['nodes'] if n['id'] == graph['root'] or n['scope'] == scope]
        ids = {n['id'] for n in nodes}
        edges = [e for e in graph['edges'] if e['scope'] == scope and e['source'] in ids and e['target'] in ids]
        views[scope] = {'root':graph['root'], 'nodes':nodes, 'edges':edges}
    views['both'] = {k:graph[k] for k in ['root','nodes','edges']}
    graph['views'] = views
    diagrams = render_svg(views['both'], dot, 'both') + ''.join('<div class="dependency-view" data-view="'+name+'"'+(' hidden' if name != 'both' else '')+'>'+render_tree(view)+'</div>' for name,view in views.items())
    payload = json.dumps(graph, separators=(',', ':')).replace('<','\\u003c')
    commit = provenance['source_commit']
    if not re.fullmatch('[a-f0-9]{40}', commit):
        raise ValueError('Provenance requires a full source commit hash')
    return f'''<section class="dependency-section wrap" id="dependencies" aria-labelledby="dependency-heading">
      <div class="dependency-heading"><div><h2 id="dependency-heading">Dependencies</h2></div></div>
      <div class="dependency-card"><div class="dep-desktop">
        <div class="dep-window dep-main"><div class="dep-bar" aria-hidden="true"><span class="dep-dots"><i></i><i></i><i></i></span><span class="dep-title">Dependency map</span></div><button type="button" class="dep-info" aria-expanded="false" aria-controls="dep-info-pop" aria-label="About this graph"><span class="dep-ico dep-ico-info"></span></button><div class="dependency-footnote dep-info-pop" id="dep-info-pop" role="region" aria-label="About this graph"><p>Nix runtime closure + direct build inputs for <code>.#default</code> at <a href="https://github.com/siraben/psi/commit/{commit}">{commit[:7]}</a>. Other platforms and static builds differ. The full build closure contains {graph.get("build_count",len(graph["nodes"]))} packages; the diagram shows runtime relationships and direct build-input relationships.</p><a href="{esc(source_path,quote=True)}" download>Runtime SBOM {DOWNLOAD_ICON}</a><a href="assets/sbom/psi-buildtime.cdx.json" download>Full build SBOM {DOWNLOAD_ICON}</a></div><div class="dep-body"><nav class="dep-sidebar" aria-label="Dependency types"><p class="dep-side-label">Show</p><div class="dependency-controls" role="group" aria-label="Dependency types"><button type="button" data-scope="runtime" aria-pressed="true"><span class="dep-ico dep-ico-runtime"></span>Runtime</button><button type="button" data-scope="build" aria-pressed="true"><span class="dep-ico dep-ico-build"></span>Build</button></div><div class="dep-group is-open"><button type="button" class="dep-group-toggle" aria-expanded="true" aria-controls="dep-package-list"><span>Packages</span><span class="dep-chev" aria-hidden="true"></span></button><div class="dep-group-body" id="dep-package-list"><ul class="dep-package-list">{package_items}</ul></div></div></nav>
        <div class="dependency-layout">
          <div class="dependency-canvas"><p class="dependency-hint"><span class="dependency-desktop-hint"><span class="hint-select">Select a package to follow its connections.</span><button type="button" class="dependency-reset" tabindex="-1">Exit selected path</button></span><span class="dependency-mobile-hint">Expand a package for its license and dependencies.</span></p>{diagrams}<p class="dependency-key"><span class="dependency-legend-solid">Retained at runtime</span><span class="dependency-legend-dashed">Build-time only</span></p></div>
          
        </div></div>
</div>
        <aside class="dep-window dep-side dependency-details" aria-labelledby="dependency-detail-name"><div class="dep-bar" aria-hidden="true"><span class="dep-dots"><i></i><i></i><i></i></span><span class="dep-title">Package</span></div><div class="dep-side-body"><div class="dep-path" aria-hidden="true"><span class="dep-ico dep-ico-folder"></span><span>Packages</span><i>&rsaquo;</i><span class="dep-path-name">All packages</span></div><div class="dep-side-scroll"><h3 id="dependency-detail-name">Select a package</h3><p class="dependency-detail-version">Select any package.</p><p class="dependency-detail-license">Select a node to see its version, package license metadata, and shown connections.</p><div class="dependency-relations" hidden><div class="dep-folder is-open"><button type="button" class="dep-folder-toggle" aria-expanded="true"><span class="dep-ico dep-ico-folder"></span>Dependencies<span class="dep-count"></span><span class="dep-chev" aria-hidden="true"></span></button><div class="dep-folder-body"><ul class="dependency-outgoing"></ul></div></div><div class="dep-folder is-open"><button type="button" class="dep-folder-toggle" aria-expanded="true"><span class="dep-ico dep-ico-folder"></span>Dependents<span class="dep-count"></span><span class="dep-chev" aria-hidden="true"></span></button><div class="dep-folder-body"><ul class="dependency-incoming"></ul></div></div></div><p class="dependency-status sr-only" aria-live="polite"></p></div><div class="dep-statusbar" aria-hidden="true">Select a package</div></div></aside>
      </div></div>

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
