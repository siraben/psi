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
