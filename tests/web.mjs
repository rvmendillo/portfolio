import {chromium} from 'playwright';
import {spawn} from 'node:child_process';
import {mkdir,writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
const server=spawn('python3',['-m','http.server','8765','--bind','127.0.0.1'],{stdio:'ignore'});
const base='http://127.0.0.1:8765';
let browser;
const results=[];
try{
  for(let i=0;i<50;i++){try{if((await fetch(base)).ok)break}catch{}await new Promise(r=>setTimeout(r,100));}
  browser=await chromium.launch({headless:true});
  const page=await browser.newPage({viewport:{width:1440,height:1000}});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(base);await page.locator('#bootSkip').click();
  async function check(name,fn){await fn();results.push(name);console.log('PASS',name)}
  const open=async id=>{await page.evaluate(id=>openApp(id),id);await page.locator(`.app-window[data-app="${id}"]`).waitFor();};
  const close=async id=>{await page.locator(`.app-window[data-app="${id}"] [data-action="close"]`).click();await page.locator(`.app-window[data-app="${id}"]`).waitFor({state:'detached'});};
  await check('All 13 desktop apps open and close',async()=>{for(const id of ['about','resume','projects','files','browser','terminal','ide','designer','transpiler','agent','store','settings','calculator']){await open(id);if(id==='ide')await page.locator('.cm-editor').waitFor();await close(id)}});
  await check('Calculator precedence and negative operands',async()=>{assert.equal(await page.evaluate(()=>safeArithmetic('2 * -3 + 8')),2);assert.equal(await page.evaluate(()=>safeArithmetic('-(2+3)*4')),-20)});
  await check('Native Python AST conversion is used by transpiler',async()=>{const result=await page.evaluate(()=>transpileSource('def twice(n: int) -> int:\n    return n * 2\nprint(twice(3))','python','cpp','show'));assert.match(result,/long long twice/);assert.doesNotMatch(result,/preserved object/)});
  await check('Real Python executes functions and loops in the IDE',async()=>{
    await open('ide');await page.locator('.cm-content').fill('def square(n):\n    return n*n\nprint([square(n) for n in range(4)])');
    await page.getByRole('button',{name:'Run program',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.dev-output')?.textContent.includes('Exit code: 0'),{},{timeout:120000});assert.match(await page.locator('.dev-output').innerText(),/\[0, 1, 4, 9\]/);
  });
  await check('Python exception produces a failed exit code',async()=>{await page.locator('.cm-content').fill('print(1/0)');await page.getByRole('button',{name:'Run program',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.dev-output')?.textContent.includes('Exit code: 1'));assert.match(await page.locator('.dev-output').innerText(),/ZeroDivisionError/)});
  await check('Create, switch, and persist workspace files',async()=>{
    await page.getByRole('textbox',{name:'New file name'}).fill('helpers.py');await page.getByRole('button',{name:'+ File',exact:true}).click();await page.locator('.cm-content').fill('def answer():\n    return 42');
    await page.getByRole('button',{name:'Open main.py',exact:true}).click();await page.locator('.cm-content').fill('from helpers import answer\nprint(answer())');await page.getByRole('button',{name:'Run program',exact:true}).click();await page.waitForFunction(()=>document.querySelector('.dev-output')?.textContent.includes('Exit code: 0'));assert.match(await page.locator('.dev-output').innerText(),/42/);
    await close('ide');await open('ide');assert.match(await page.locator('.cm-content').innerText(),/from helpers import answer/);
  });
  await check('JavaScript runs in isolated execution frame',async()=>{const result=await page.evaluate(()=>ReyDev.runCode('console.log([1,2,3].map(n=>n*n)); console.log(prompt(), prompt())','JavaScript',{},'first\nsecond'));assert.equal(result.exitCode,0);assert.equal(result.output,'[1,4,9]\nfirst second')});
  await check('Unsupported native language never reports simulated success',async()=>{const error=await page.evaluate(async()=>{try{await ReyDev.runCode('class Main {}','Java')}catch(e){return e.message}});assert.match(error,/compiler/)});
  await check('AI review applies only to the unchanged source snapshot',async()=>{
    await page.evaluate(()=>{ReyDev.localAI.state='ready';ReyDev.localAI.detail='UI fixture — inference tested separately';ReyDev.localAI.generate=async(_messages,onText)=>{const reply='```python\nprint("reviewed")\n```';onText(reply);return reply};ReyDev.localAI.dispatchEvent(new Event('change'))});
    await page.getByRole('textbox',{name:'Ask local AI'}).fill('Replace this file.');await page.getByRole('button',{name:'Send',exact:true}).click();await page.getByText('Review proposed replacement',{exact:true}).click();await page.getByRole('button',{name:'Apply replacement',exact:true}).click();assert.match(await page.locator('.cm-content').innerText(),/reviewed/);
    await page.getByRole('textbox',{name:'Ask local AI'}).fill('Propose another edit');await page.getByRole('button',{name:'Send',exact:true}).click();await page.getByText('Review proposed replacement',{exact:true}).click();await page.locator('.cm-content').fill('print("newer unsaved revision")');await page.getByRole('button',{name:'Apply replacement',exact:true}).click();assert.match(await page.locator('.cm-content').innerText(),/newer unsaved revision/);assert.match(await page.locator('.dev-messages').innerText(),/file changed/);
  });
  await close('ide');
  await check('Designer bindings run and packages install',async()=>{
    await open('designer');await page.locator('[data-designer-demo]').click();await page.locator('[data-designer-run]').click();
    const custom=page.locator('.custom-app-surface').last();await custom.locator('input').nth(0).fill('12');await custom.locator('input').nth(1).fill('8');await custom.locator('button').click();assert.equal(await custom.locator('output').innerText(),'20');
    await page.evaluate(()=>{const project=parseProjectYAML(TRANSPILE_SAMPLES.yaml);installPackage(project)});assert.ok(await page.evaluate(()=>getInstalledApps().length>0));
    await page.evaluate(()=>{for(const win of openWindows.values())closeWindow(win)});await page.waitForTimeout(400);
  });
  await check('Browser uses a sandboxed iframe for external URLs',async()=>{await open('browser');await page.locator('[data-browser-address]').fill('https://example.com');await page.locator('[data-browser-go]').click();const frame=page.locator('.browser-embed');assert.equal(await frame.getAttribute('src'),'https://example.com/');assert.match(await frame.getAttribute('sandbox'),/allow-scripts/);assert.doesNotMatch(await frame.getAttribute('sandbox'),/allow-top-navigation/);await close('browser')});
  await check('Window minimize, restore, maximize and phone-width drag',async()=>{
    await page.setViewportSize({width:430,height:932});await open('calculator');const win=page.locator('.app-window[data-app="calculator"]');
    const before=await win.boundingBox();const bar=await win.locator('.titlebar').boundingBox();await page.mouse.move(bar.x+65,bar.y+20);await page.mouse.down();await page.mouse.move(bar.x+90,bar.y+110,{steps:6});await page.mouse.up();const after=await win.boundingBox();assert.ok(after.y>before.y+20);
    await win.locator('[data-action="minimize"]').click();await page.locator('#runningApps button[data-app="calculator"]').click();assert.ok(!(await win.getAttribute('class')).includes('minimized'));
    await win.locator('[data-action="maximize"]').click();assert.match(await win.getAttribute('class'),/maximized/);
  });
  await mkdir('.test-output',{recursive:true});await page.screenshot({path:'.test-output/mobile.png'});
  await close('calculator');await page.setViewportSize({width:1440,height:1000});await open('ide');await page.screenshot({path:'.test-output/ide.png'});
  assert.deepEqual(errors,[],'Uncaught browser errors');
  await writeFile('.test-output/web-results.json',JSON.stringify({passed:results,uncaughtErrors:errors},null,2));
  console.log(`${results.length} browser checks passed.`);
}finally{await browser?.close();server.kill();}
