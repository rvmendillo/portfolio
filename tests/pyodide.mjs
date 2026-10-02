import {loadPyodide} from 'pyodide';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const py=await loadPyodide();
for(const name of ['rey_runtime','rey_compiler'])py.FS.writeFile('/home/pyodide/'+name+'.py',await readFile('shared/'+name+'.py','utf8'));
py.runPython('import json, rey_runtime, rey_compiler');
const run=(code,files={},input='')=>{
  py.globals.set('request',JSON.stringify({code,files,input}));
  return JSON.parse(py.runPython('r=json.loads(request)\njson.dumps(rey_runtime.run(r["code"],r["files"],r["input"]))'));
};
const checks=[];
const first=run('from helper import square\nprint([square(n) for n in range(4)])\nprint(input())',{'helper.py':'def square(n):\n    return n*n'},'WASM');
assert.equal(first.exitCode,0);assert.equal(first.output,'[0, 1, 4, 9]\nWASM\n');checks.push('WASM Python: functions, imports, comprehensions and stdin');
assert.equal(run('print(1/0)').exitCode,1);checks.push('WASM Python exception status');
assert.equal(run('while True:\n    pass').exitCode,1);checks.push('WASM Python loop limit');
assert.match(py.runPython('rey_compiler.transpile("print(6*7)","java")'),/R.print/);checks.push('WASM AST compiler');
try{
  const output=await readFile('.test-output/model-generation.txt','utf8');
  const code=/```python\s*\n([\s\S]*?)```/.exec(output)?.[1];
  assert.ok(code,'Local model must produce Python code');
  const result=run(code);assert.equal(result.exitCode,0);assert.equal(result.output.trim(),'49');
  checks.push('Actual local-model generated square function executes and prints 49');
}catch(e){if(e.code!=='ENOENT')throw e;}
await mkdir('.test-output',{recursive:true});
await writeFile('.test-output/pyodide-results.json',JSON.stringify({engine:py.version,passed:checks},null,2));
console.log(checks.join('\n'));
