import contextlib,io,pathlib,shutil,subprocess,sys,tempfile,unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'shared'))
from rey_compiler import transpile,CompileError

SAMPLES={
 'arithmetic':'x = 4\ny = 3\nprint(x * y + 2)\nprint(2 * -3)\n',
 'loops':'total = 0\nfor i in range(2, 8, 2):\n    total += i\nprint(total)\nfor j in range(3, 0, -1):\n    print(j)\n',
 'function':'def twice(n: int) -> int:\n    return n * 2\nprint(twice(21))\n',
 'class':'class Engineer:\n    def __init__(self, name: str):\n        self.name = name\n    def introduce(self):\n        return "Hello, " + self.name\nrey = Engineer("Rey")\nprint(rey.introduce())\n',
 'list':'values = [2, 3, 4]\nvalues.append(5)\nprint(values[2])\nprint(len(values))\n',
 'comprehension':'squares = [n*n for n in range(5) if n > 1]\nprint(squares)\n',
 'condition':'n = 7\nif n > 5 and n < 10:\n    print("inside")\nelse:\n    print("outside")\n',
 'fstring':'name = "Rey"\nprint(f"Hello, {name}!")\n',
 'while':'i = 0\nwhile i < 3:\n    print(i)\n    i += 1\n',
 'negative_division':'print(-7 // 3)\nprint(-7 % 3)\nprint(7 % -3)\nprint(7 / 2)\nprint(2.0)\n',
 'truth':'value = 2\nif value:\n    print("number")\ntext = "hello"\nif text:\n    print("text")\nprint(not 0)\n',
}

class CompilerTests(unittest.TestCase):
    def test_actual_compiled_output(self):
        for name,source in SAMPLES.items():
            for target in ['cpp','java']:
                if target=='java' and not shutil.which('javac'):continue
                with self.subTest(name=name,target=target),tempfile.TemporaryDirectory() as directory:
                    root=pathlib.Path(directory);code=transpile(source,target);path=root/('Main.java' if target=='java' else 'main.cpp');path.write_text(code)
                    command=['javac',str(path)] if target=='java' else ['g++','-std=c++17',str(path),'-o',str(root/'program')]
                    compile=subprocess.run(command,capture_output=True,text=True,timeout=30);self.assertEqual(compile.returncode,0,compile.stderr+'\n'+code)
                    result=subprocess.run(['java','-cp',directory,'Main'] if target=='java' else [str(root/'program')],capture_output=True,text=True,timeout=5)
                    output=io.StringIO()
                    with contextlib.redirect_stdout(output):exec(source,{})
                    self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout,output.getvalue())
    def test_reject_instead_of_drop(self):
        for code in ['import socket','x = {"a": 1}','async def f():\n    pass','@unknown\ndef f():\n    pass','def f(x=1):\n    return x','print("x" * 3)','print(1 and 2)','print("x".replace("x", "y"))','if True:\n    x = 2\nprint(x)']:
            with self.subTest(code=code),self.assertRaises(CompileError):transpile(code)
    def test_python_passthrough_still_validates(self):
        self.assertEqual(transpile('print(42)','python'),'print(42)')
        with self.assertRaises(SyntaxError):transpile('def broken(:','python')
