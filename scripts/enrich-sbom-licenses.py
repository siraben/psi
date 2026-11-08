#!/usr/bin/env python3
"""Fill missing license metadata only from recorded exact derivation matches."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'assets/sbom'
evidence_path = root / 'license-evidence.json'
evidence = json.loads(evidence_path.read_text())
for filename, provenance_name in [('psi-runtime.cdx.json','provenance.json'), ('psi-buildtime.cdx.json','build-provenance.json')]:
    path = root / filename
    provenance_path = root / provenance_name
    provenance = json.loads(provenance_path.read_text())
    if evidence['source_commit'] != provenance['source_commit']:
        raise ValueError('Evidence source commit does not match snapshot')
    original = path.read_bytes()
    if hashlib.sha256(original).hexdigest() != provenance['sbom_sha256']:
        raise ValueError('Snapshot does not match provenance')
    document = json.loads(original)
    components = {c['bom-ref']:c for c in [document['metadata']['component'],*document['components']]}
    changed = []
    for match in evidence['matches']:
        if match['bom_ref'] != match['evaluated_drv_path']:
            raise ValueError('License evidence must match exact derivation identity')
        component = components.get(match['bom_ref'])
        if component is None:
            continue
        if component['name'] != match['name'] or component.get('version') != match['version']:
            raise ValueError('Component metadata differs from evidence')
        if component.get('licenses'):
            if component['licenses'] != match['licenses']:
                raise ValueError('Refusing to overwrite conflicting license metadata')
            continue
        component['licenses'] = match['licenses']
        component.setdefault('properties',[]).append({'name':'psi:license_evidence','value':'license-evidence.json; exact evaluated drvPath match'})
        changed.append(match['bom_ref'])
    if changed:
        path.write_text(json.dumps(document,indent=2)+'\n')
        provenance['license_enrichment'] = {
            'evidence_file':'license-evidence.json',
            'evidence_sha256':hashlib.sha256(evidence_path.read_bytes()).hexdigest(),
            'pre_enrichment_sha256':hashlib.sha256(original).hexdigest(),
            'enriched_components':changed,
            'scope':evidence['scope_note'],
            'dependency_graph_changed':False,
        }
        provenance['sbom_sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        provenance_path.write_text(json.dumps(provenance,indent=2)+'\n')
    print(f'{filename}: {len(changed)} license gaps filled')
