import pathlib,sys,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'shared'))
from rey_runtime import run

class RuntimeTests(unittest.TestCase):
    def test_native_stop_callback(self):
        result=run('while True:\n    pass',cancelled=lambda:True)
        self.assertEqual(result['exitCode'],1)
        self.assertIn('Execution stopped.',result['output'])
    def test_functions_classes_imports_input(self):
        r=run('from helper import square\nclass C:\n    def values(self):\n        return [square(n) for n in range(4)]\nprint(C().values())\nprint(input())',{'helper.py':'def square(n):\n    return n*n'},'Rey\n')
        self.assertEqual(r['exitCode'],0,r);self.assertEqual(r['output'],'[0, 1, 4, 9]\nRey\n')
    def test_errors(self):
        for code in ['raise ValueError("failure")','def broken(:','print(missing)']:
            self.assertEqual(run(code)['exitCode'],1)
    def test_bounded_loop_and_output(self):
        self.assertEqual(run('while True:\n    pass',timeout=.05)['exitCode'],1)
        self.assertEqual(run('print("x"*70000)')['exitCode'],1)
    def test_module_does_not_leak_between_runs(self):
        self.assertEqual(run('import h\nprint(h.x)',{'h.py':'x=1'})['output'],'1\n')
        self.assertEqual(run('import h\nprint(h.x)',{'h.py':'x=2'})['output'],'2\n')
    def test_exit_codes(self):self.assertEqual(run('raise SystemExit(7)')['exitCode'],7)
    def test_path_traversal(self):self.assertEqual(run('print(1)',{'../outside.py':'oops'})['exitCode'],1)
