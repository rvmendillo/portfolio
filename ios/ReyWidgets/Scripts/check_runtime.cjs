// Execute the actual template scripts using a small DOM test double.
// This verifies JavaScript/data contracts; it does not test browser rendering or enforce CSP.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const base = path.resolve(__dirname, '../build/validation');
const fixtures = JSON.parse(fs.readFileSync(path.join(base, 'fixtures.json')));
const results = [];

for (const fixture of fixtures) {
  const page = fs.readFileSync(fixture.path, 'utf8');
  const nodes = [];
  for (const match of page.matchAll(/<([a-z][\w-]*)([^<>]*)>/gi)) {
    const attrs = {};
    for (const pair of match[2].matchAll(/([\w-]+)="([^"]*)"/g)) attrs[pair[1]] = pair[2];
    nodes.push({attrs,textContent:'',getAttribute(name){return this.attrs[name] ?? null;}});
  }
  const document = {
    readyCallbacks:[],
    addEventListener(name, fn){if(name==='DOMContentLoaded')this.readyCallbacks.push(fn);},
    querySelectorAll(selector){assert.equal(selector,'[data-bind]');return nodes.filter(n=>'data-bind' in n.attrs);},
    getElementById(id){return nodes.find(n=>n.attrs.id===id);},
  };
  const scope = {document,TextDecoder,Uint8Array,Promise,
    atob:value=>Buffer.from(value,'base64').toString('binary'),addEventListener(){}};
  scope.window = scope;
  vm.createContext(scope);
  const scripts = [...page.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m=>m[1]);
  assert.equal(scripts.length,2);
  for(const script of scripts)vm.runInContext(script,scope,{timeout:1000});
  vm.runInContext('document.readyCallbacks.forEach(fn=>fn())',scope,{timeout:1000});
  assert.equal(scope.__rwError,null);
  assert.equal(scope.widget.size,fixture.size);
  assert.equal(scope.widget.width,fixture.width);
  assert.equal(scope.widget.height,fixture.height);
  assert.equal(scope.widget.get('/missing','fallback'),'fallback');
  if(fixture.name==='api-canvas'){
    assert.equal(document.getElementById('temp').textContent,29);
    assert.equal(document.querySelectorAll('[data-bind]')[0].textContent,'33');
  }else{assert.equal(document.querySelectorAll('[data-bind]')[0].textContent,'Make something yours.');}
  vm.runInContext(`widget.data = {'a/b':{'~x':['日本',null]},'truth':false,'zero':0};`,scope);
  assert.equal(scope.widget.get('/a~1b/~0x/0'),'日本');
  assert.equal(scope.widget.get('/a~1b/~0x/1','empty'),'empty');
  assert.equal(scope.widget.get('/truth',true),false);
  assert.equal(scope.widget.get('/zero',1),0);
  assert.equal(scope.widget.get('/toString','missing'),'missing');
  for(const directive of ["connect-src 'none'","frame-src 'none'","form-action 'none'","base-uri 'none'"]){assert.ok(page.includes(directive));}
  results.push({template:fixture.name,size:fixture.size,status:'PASS'});
}
const harness = fs.readFileSync(path.resolve(__dirname,'../Docs/HTML-Preview.html'),'utf8');
for(const match of harness.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(match[1]);
fs.writeFileSync(path.join(base,'runtime-results.json'),JSON.stringify({environment:'Node.js with DOM test double; no browser rendering',results},null,2));
process.stdout.write('PASS: six actual runtime/template combinations; bindings, scripts, dimensions, Unicode, missing/null/false/zero values, and preview-harness syntax.\n');
