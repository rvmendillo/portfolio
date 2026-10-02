export function createRunner() {
  let worker, pending, timer, javascript;
  const stop = (reason='Execution stopped.') => {
    worker?.terminate(); worker=null; clearTimeout(timer);
    javascript?.abort(); javascript=null;
    if (pending) { pending.reject(new Error(reason)); pending=null; }
  };
  async function python(code, files={}, input='', action='run', target='java') {
    if (pending || javascript) throw new Error('A program is already running. Stop it first.');
    if (!worker) {
      worker=new Worker(new URL('assets/runtime/python-worker.js',document.baseURI),{type:'module'});
      worker.onmessage=({data})=>{
        if (!pending) return;
        if (data.status) { pending.onStatus?.(data.status); return; }
        clearTimeout(timer); const p=pending;pending=null;
        data.error?p.reject(new Error(data.error)):p.resolve(data.result);
      };
      worker.onerror=e=>stop('Python runtime failed: '+e.message);
    }
    return new Promise((resolve,reject)=>{
      pending={resolve,reject};
      timer=setTimeout(()=>stop('Execution timed out. The runtime was restarted.'),120000);
      worker.postMessage({code,files,input,action,target});
    });
  }
  async function run(code,language,files={},input='') {
    if (language==='Python') return python(code,files,input);
    if (language==='JavaScript') {
      if (pending || javascript) throw new Error('A program is already running. Stop it first.');
      const controller=new AbortController(); javascript=controller;
      try { return await runJavaScript(code,input,controller.signal); }
      finally { if(javascript===controller)javascript=null; }
    }
    throw new Error(`${language} needs its own compiler. Use Export to build this source with ${language==='Java'?'a JDK':'Clang or GCC'}. Python and JavaScript run here.`);
  }
  return {run,python,stop};
}
export async function runJavaScript(code,input='',signal) {
  return new Promise((resolve,reject)=>{
    if(signal?.aborted){reject(new Error('Execution stopped.'));return;}
    const frame=document.createElement('iframe');frame.hidden=true;frame.sandbox='allow-scripts';
    frame.src=new URL('assets/runtime/js-runner.html',document.baseURI);
    let finished=false;
    const finish=(result,error)=>{if(finished)return;finished=true;clearTimeout(timeout);signal?.removeEventListener('abort',abort);window.removeEventListener('message',receive);frame.remove();error?reject(new Error(error)):resolve(result);};
    const abort=()=>finish(null,'Execution stopped.');
    const receive=({source,data})=>{if(source!==frame.contentWindow)return;if(data.ready)frame.contentWindow.postMessage({code,input},'*');else if(data.result)finish(data.result);};
    window.addEventListener('message',receive);
    const timeout=setTimeout(()=>finish(null,'JavaScript exceeded the 10-second limit.'),10000);
    signal?.addEventListener('abort',abort,{once:true});
    document.body.append(frame);
  });
}
export const terminalRunner=createRunner();
export const runCode=(...args)=>terminalRunner.run(...args);
const compilerRunner=createRunner();
let compilation=Promise.resolve();
export const compilePython=(source,target)=>{
  const next=compilation.catch(()=>{}).then(()=>compilerRunner.python(source,{},'','compile',target));
  compilation=next;
  return next;
};
