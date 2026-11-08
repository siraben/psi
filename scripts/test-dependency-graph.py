import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('graph', Path(__file__).with_name('generate-dependency-graph.py'))
graph = importlib.util.module_from_spec(spec)
spec.loader.exec_module(graph)

class GraphTests(unittest.TestCase):
    def snapshot(self):
        return {'bomFormat':'CycloneDX', 'metadata':{'component':{'bom-ref':'root','name':'psi'}}, 'components':[{'bom-ref':'a','name':'library','version':'1'}, {'bom-ref':'b','name':'library','version':'2'}], 'dependencies':[{'ref':'root','dependsOn':['a','a']},{'ref':'a','dependsOn':['b']},{'ref':'b','dependsOn':['a']}]}
    def test_identity_cycles_and_exact_edges(self):
        result = graph.read_graph(self.snapshot())
        ids = {n['ref']:n['id'] for n in result['nodes']}
        self.assertEqual(len(ids),3)
        self.assertEqual({(e['source'],e['target']) for e in result['edges']}, {(ids['root'],ids['a']),(ids['a'],ids['b']),(ids['b'],ids['a'])})
    def test_runtime_edges_stay_solid_and_build_only_are_dashed(self):
        runtime = graph.read_graph(self.snapshot())
        document = self.snapshot()
        document['components'] += [{'bom-ref':'tool','name':'compiler'}, {'bom-ref':'deep','name':'bootstrap'}]
        document['dependencies'] += [{'ref':'tool','dependsOn':['deep']}]
        document['dependencies'][0]['dependsOn'].append('tool')
        mixed = graph.include_build_inputs(runtime, graph.read_graph(document))
        self.assertEqual({n['ref'] for n in mixed['nodes']}, {'root','a','b','tool'})
        self.assertEqual(sum(e['scope']=='runtime' for e in mixed['edges']),3)
        self.assertEqual(sum(e['scope']=='build' for e in mixed['edges']),1)
        self.assertEqual(mixed['build_count'],5)

    def test_unknown_reference_rejected(self):
        document = self.snapshot(); document['dependencies'][0]['dependsOn'].append('missing')
        with self.assertRaisesRegex(ValueError,'Unknown dependency target'): graph.read_graph(document)
    def test_conflicting_identity_rejected(self):
        document = self.snapshot(); document['components'].append({'bom-ref':'a','name':'other'})
        with self.assertRaisesRegex(ValueError,'Conflicting'): graph.read_graph(document)
    def test_order_independent(self):
        document = self.snapshot(); expected = graph.read_graph(document)
        document['components'].reverse(); document['dependencies'].reverse()
        self.assertEqual(graph.read_graph(document),expected)

if __name__ == '__main__': unittest.main()
