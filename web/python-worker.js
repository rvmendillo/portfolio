import {loadPyodide} from './pyodide/pyodide.mjs';
let runtime;
async function getRuntime() {
  if (!runtime) {
    postMessage({status:'Loading Python…'});
    runtime=loadPyodide({indexURL:new URL('./pyodide/',import.meta.url).href}).then(async py=>{
      for(const name of ['rey_runtime','rey_compiler']) {
        const response=await fetch(new URL(name+'.py',import.meta.url));
        if(!response.ok)throw new Error('Cannot load '+name);
        py.FS.writeFile('/home/pyodide/'+name+'.py',await response.text());
      }
      py.runPython('import rey_runtime, rey_compiler, json');return py;
    }).catch(e=>{runtime=null;throw e;});
  }
  return runtime;
}
self.onmessage=async ({data})=>{
  try {
    const py=await getRuntime();
    py.globals.set('_request',JSON.stringify(data));
    const result=py.runPython(`\n_req=json.loads(_request)\nif _req['action']=='compile':\n    _result=rey_compiler.transpile(_req['code'],_req['target'])\nelse:\n    _result=rey_runtime.run(_req['code'],_req.get('files',{}),_req.get('input',''))\njson.dumps(_result)\n`);
    postMessage({result:JSON.parse(result)});
  } catch(e) {postMessage({error:String(e.message||e)});}
};
