import {EditorView,keymap} from '@codemirror/view';
import {EditorState,Compartment} from '@codemirror/state';
import {basicSetup} from 'codemirror';
import {HighlightStyle,syntaxHighlighting} from '@codemirror/language';
import {tags} from '@lezer/highlight';
import {indentWithTab} from '@codemirror/commands';
import {python} from '@codemirror/lang-python';
import {javascript} from '@codemirror/lang-javascript';
import {java} from '@codemirror/lang-java';
import {cpp} from '@codemirror/lang-cpp';
import {yaml} from '@codemirror/lang-yaml';
import {createRunner,runCode,compilePython} from './runtime.js';
import {localAI,codeBlock,systemPrompt} from './local-ai.js';
export {runCode,compilePython,localAI};
const el=(tag,cls,text)=>{const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=text;return n};
const button=(label,fn,cls='dev-button')=>{const b=el('button',cls,label);b.type='button';b.addEventListener('click',fn);return b};
const mode=name=>name.endsWith('.py')?'Python':name.endsWith('.java')?'Java':/\.(cpp|h|hpp|cc)$/.test(name)?'C++':/\.ya?ml$/.test(name)?'YAML':/\.(js|mjs|ts)$/.test(name)?'JavaScript':'Text';
const extension=lang=>({'Python':python,'JavaScript':javascript,'Java':java,'C++':cpp,'YAML':yaml}[lang]||(()=>[]))();
const codeColors=syntaxHighlighting(HighlightStyle.define([
  {tag:tags.keyword,color:'#d6a7ff'},
  {tag:[tags.string,tags.regexp],color:'#a8e6b5'},
  {tag:[tags.number,tags.bool,tags.null],color:'#ffca91'},
  {tag:tags.comment,color:'#98adc4'},
  {tag:tags.function(tags.variableName),color:'#8dceff'},
  {tag:[tags.typeName,tags.className],color:'#8ee0d4'}
]));
function download(name,text){const a=document.createElement('a'),url=URL.createObjectURL(new Blob([text],{type:'text/plain'}));a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
const readSaved=(key,fallback)=>{try{const x=JSON.parse(localStorage.getItem(key));if(!x||typeof x!=='object'||Array.isArray(x))return fallback;return x}catch{return fallback}};
const validFilename=name=>/^[\w][\w. /-]{0,79}$/.test(name)&&!name.includes('..')&&!name.endsWith('/')&&!name.includes('//');
function aiPanel({context=()=>'',apply,knowledge=''}) {
  const root=el('section','dev-ai');root.setAttribute('aria-label','Local AI assistant');
  const top=el('div','dev-ai-top');const title=el('strong',null,'LOCAL AI');
  const status=el('p','dev-model-status');status.setAttribute('role','status');
  const load=button('Load model · 469 MB',async()=>{try{await localAI.load()}catch(e){status.textContent=e.message}});
  const importInput=el('input');importInput.type='file';importInput.accept='.gguf';importInput.hidden=true;
  const imports=button('Import GGUF',()=>importInput.click());
  importInput.onchange=async()=>{const file=importInput.files[0];importInput.value='';if(file)try{await localAI.load(file)}catch(e){status.textContent=e.message}};
  const unload=button('Unload',()=>localAI.unload().catch(e=>status.textContent=e.message));
  top.append(title,load,imports,unload,importInput);
  const help=el('p','dev-small','First load downloads the model. After caching, prompts and code stay on this device.');
  const messages=el('div','dev-messages');messages.setAttribute('aria-live','polite');
  const prompt=el('textarea','dev-prompt');prompt.placeholder='Ask about your code…';prompt.setAttribute('aria-label','Ask local AI');prompt.maxLength=5000;
  const actions=el('div','dev-ai-actions');
  const include=el('input');include.type='checkbox';include.checked=true;const includeLabel=el('label','dev-small');includeLabel.append(include,' Include current file');
  const send=button('Send',ask,'dev-button primary'),stop=button('Stop',()=>localAI.stop()),clear=button('New chat',()=>{if(localAI.busy)return;history=[];messages.replaceChildren();});
  actions.append(send,stop,clear);let history=[],owned=false,disposed=false;
  function refresh(){status.textContent=localAI.detail;root.dataset.state=localAI.state;load.disabled=localAI.state==='loading'||localAI.busy;send.disabled=localAI.state!=='ready'||localAI.busy;stop.disabled=!localAI.busy&&localAI.state!=='loading';imports.disabled=localAI.busy||localAI.state==='loading';unload.disabled=localAI.busy||localAI.state==='loading';}
  localAI.addEventListener('change',refresh);refresh();
  async function ask(){
    const query=prompt.value.trim();if(!query||localAI.busy)return;owned=true;
    const snapshot=include.checked?context():null;
    const user=el('p','dev-chat-user',query),answer=el('div','dev-chat-answer'),text=el('pre',null,'Reading your request…');answer.append(text);messages.append(user,answer);prompt.value='';
    const content=(snapshot?'Current file '+snapshot.name+':\n```'+mode(snapshot.name).toLowerCase()+'\n'+snapshot.code.slice(0,9000)+'\n```\n\n':'')+'User request: '+query;
    try {
      const result=await localAI.generate([{role:'system',content:systemPrompt+(knowledge?'\nPortfolio facts:\n'+knowledge:'')},...history.slice(-4),{role:'user',content}],value=>{if(!disposed){text.textContent=value;messages.scrollTop=messages.scrollHeight}});
      history.push({role:'user',content},{role:'assistant',content:result});
      const code=codeBlock(result);
      if(code&&apply&&snapshot&&!disposed){
        const review=el('details','dev-review'),summary=el('summary',null,'Review proposed replacement');
        const before=el('pre',null,snapshot.code),after=el('pre',null,code);
        review.append(summary,el('b',null,'Current file'),before,el('b',null,'Proposed file'),after,button('Apply replacement',()=>{try{apply(code,snapshot);review.remove()}catch(e){text.textContent+='\n\n'+e.message}}));answer.append(review);
      }
    }catch(e){if(!disposed)text.textContent=(text.textContent==='Reading your request…'?'':text.textContent+'\n\n')+(e.name==='AbortError'?'Stopped.':e.message);}
    finally{owned=false;refresh();}
  }
  prompt.addEventListener('keydown',e=>{if(e.key==='Enter'&&(e.ctrlKey||e.metaKey)){e.preventDefault();ask()}});
  root.append(top,status,help,messages,prompt);if(apply)root.append(includeLabel);root.append(actions);
  return {root,dispose(){disposed=true;if(owned)localAI.stop();localAI.removeEventListener('change',refresh)}};
}
export async function mountAssistant(win,knowledge) {const panel=aiPanel({knowledge});win.querySelector('.window-body').replaceChildren(panel.root);return panel.dispose;}
export async function mountIDE(win,{profile,samples,previewYAML,notify}) {
  const key='rey-ide-v2:'+encodeURIComponent(profile);
  let files=readSaved(key,{...samples,'hello.js':'const squares = [1, 2, 3].map(n => n * n);\nconsole.log(squares);'});
  files=Object.assign(Object.create(null),Object.fromEntries(Object.entries(files).filter(([name,value])=>validFilename(name)&&typeof value==='string'&&value.length<=200000).slice(0,100)));
  if(!Object.keys(files).length)files={...samples};
  let current=Object.keys(files)[0],running=false,closed=false;
  const states=new Map(),language=new Compartment(),runner=createRunner();
  const root=el('div','dev-workspace');const toolbar=el('div','dev-toolbar'),sidebar=el('aside','dev-files'),main=el('section','dev-main'),host=el('div','dev-editor');
  const filename=el('strong','dev-filename',current),saved=el('span','dev-small','Saved locally');
  const output=el('pre','dev-output','Ready.');output.setAttribute('aria-live','polite');output.setAttribute('aria-label','Program output');
  const stdin=el('textarea','dev-stdin');stdin.placeholder='Program input (one answer per line)';stdin.setAttribute('aria-label','Program input');
  const run=button('▶ Run',runProgram,'dev-button primary');run.setAttribute('aria-label','Run program');
  const stop=button('■ Stop',()=>runner.stop());stop.disabled=true;
  const select=el('select');select.setAttribute('aria-label','Language');for(const item of ['Python','JavaScript','Java','C++','YAML','Text'])select.append(new Option(item,item));select.value=mode(current);
  const editor=new EditorView({parent:host,state:newState(files[current],current)});
  function newState(text,name){return EditorState.create({doc:text,extensions:[basicSetup,codeColors,keymap.of([indentWithTab,{key:'Mod-Enter',run:()=>{runProgram();return true}},{key:'Mod-s',run:()=>{save();return true}}]),language.of(extension(mode(name))),EditorView.theme({'&':{height:'100%',fontSize:'14px',backgroundColor:'#081323',color:'#dce8f7'},'.cm-scroller':{overflow:'auto',fontFamily:'ui-monospace, SFMono-Regular, monospace'},'.cm-gutters':{backgroundColor:'#0b1829',color:'#8296b2',border:'none'},'.cm-activeLine':{backgroundColor:'#163354'},'.cm-activeLineGutter':{backgroundColor:'#163354'},'.cm-content':{caretColor:'#7fc5ff'}},{dark:true}),EditorView.updateListener.of(update=>{if(update.docChanged){files[current]=update.state.doc.toString();save()}})]});}
  function save(){files[current]=editor.state.doc.toString();try{localStorage.setItem(key,JSON.stringify(files));saved.textContent='Saved locally'}catch{saved.textContent='Storage full — export your project';}}
  function switchFile(name){if(!Object.hasOwn(files,name))return;save();states.set(current,editor.state);current=name;filename.textContent=current;editor.setState(states.get(name)||newState(files[name],name));select.value=mode(name);renderFiles();}
  function renderFiles(){sidebar.replaceChildren(el('b','dev-small','PROJECT'));for(const name of Object.keys(files).sort()){const b=button(name,()=>switchFile(name),'dev-file'+(name===current?' active':''));b.setAttribute('aria-label','Open '+name);sidebar.append(b)}}
  const naming=el('input','dev-new-name');naming.placeholder='new-file.py';naming.setAttribute('aria-label','New file name');naming.maxLength=80;
  const create=()=>{const name=naming.value.trim();if(!validFilename(name)){notify('Invalid filename','Use a relative filename such as lib/helpers.py.');return}if(Object.hasOwn(files,name)){switchFile(name);return}if(Object.keys(files).length>=100){notify('Project limit','Export or remove files before adding more.');return}files[name]='';switchFile(name);naming.value='';save()};
  naming.onkeydown=e=>{if(e.key==='Enter')create()};
  const importFile=el('input');importFile.type='file';importFile.accept='.json,.py,.js,.java,.cpp,.yml,.yaml,.txt';importFile.multiple=true;importFile.hidden=true;
  importFile.onchange=async()=>{try{
    const incoming=Object.create(null);
    for(const f of importFile.files){
      if(f.size>2000000)throw new Error('Import files smaller than 2 MB.');
      const text=await f.text();
      if(f.name.endsWith('.rey.json')){
        const project=JSON.parse(text);
        if(project.format!=='rey-project/v1'||!project.files||typeof project.files!=='object'||Array.isArray(project.files))throw new Error('Invalid Rey project');
        Object.assign(incoming,project.files);
      }else incoming[f.name]=text;
    }
    for(const [name,source]of Object.entries(incoming))if(!validFilename(name)||typeof source!=='string'||source.length>200000)throw new Error('Invalid project file');
    const merged=Object.assign(Object.create(null),files,incoming);
    if(Object.keys(merged).length>100||JSON.stringify(merged).length>2000000)throw new Error('Projects support up to 100 files and 2 MB of source.');
    files=merged;states.clear();editor.setState(newState(files[current],current));save();renderFiles();
  }catch(e){notify('Import failed',e.message)}finally{importFile.value=''}};
  toolbar.append(run,stop,select,button('Export file',()=>download(current,editor.state.doc.toString())),button('Export project',()=>{save();download('workspace.rey.json',JSON.stringify({format:'rey-project/v1',files},null,2))}),button('Import',()=>importFile.click()),importFile);
  const toggleAI=button('✦ AI',()=>root.classList.toggle('ai-hidden'));toolbar.append(toggleAI);
  const fileActions=el('div','dev-file-actions');fileActions.append(naming,button('+ File',create),button('Delete',()=>{if(Object.keys(files).length<=1){notify('Keep one file','Create another file before deleting this one.');return}if(!confirm('Delete '+current+'?'))return;const old=current;switchFile(Object.keys(files).find(x=>x!==old));delete files[old];states.delete(old);save();renderFiles()}));
  const editorTop=el('div','dev-editor-top');editorTop.append(filename,saved);main.append(editorTop,host,stdin,output);
  const panel=aiPanel({context:()=>({name:current,code:editor.state.doc.toString()}),apply:(code,snapshot)=>{if(current!==snapshot.name||editor.state.doc.toString()!==snapshot.code)throw new Error('The file changed. Ask for a new proposal to avoid overwriting your edits.');editor.dispatch({changes:{from:0,to:editor.state.doc.length,insert:code}});save();notify('Applied','Undo in the editor restores the previous version.')}});
  const explorer=el('div','dev-explorer');explorer.append(sidebar,fileActions);
  const body=el('div','dev-body');body.append(explorer,main,panel.root);root.append(toolbar,body);win.querySelector('.window-body').replaceChildren(root);renderFiles();
  select.onchange=()=>editor.dispatch({effects:language.reconfigure(extension(select.value))});
  async function runProgram(){if(running)return;save();running=true;run.disabled=true;stop.disabled=false;output.textContent='Running '+select.value+'…';try{if(select.value==='YAML'){previewYAML(editor.state.doc.toString());output.textContent='GUI preview opened.';}else{const result=await runner.run(editor.state.doc.toString(),select.value,files,stdin.value);if(!closed)output.textContent=(result.output||'(No output)')+'\n\nExit code: '+result.exitCode;}}catch(e){if(!closed)output.textContent=e.message}finally{running=false;run.disabled=false;stop.disabled=true;}}
  return ()=>{closed=true;save();runner.stop();editor.destroy();panel.dispose()};
}
