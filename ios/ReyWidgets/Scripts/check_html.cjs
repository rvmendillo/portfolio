// Desktop Chromium checks of the actual app runtime fixtures, not iOS WebKit validation.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

(async () => {
  const base = path.resolve(__dirname, '../build/validation');
  const fixtures = JSON.parse(fs.readFileSync(path.join(base, 'fixtures.json')));
  const browser = await chromium.launch({headless:true, args:['--no-sandbox']});
  const results = [];
  try {
    for (const fixture of fixtures) {
      const page = await browser.newPage({viewport:{width:fixture.width,height:fixture.height},deviceScaleFactor:2});
      const errors = []; page.on('pageerror', e => errors.push(e.message));
      await page.goto('file://' + fixture.path);
      await page.evaluate(async()=>{await document.fonts.ready;await widget.ready;});
      assert.deepEqual(errors, []);
      assert.equal(await page.evaluate(()=>window.__rwError), null);
      assert.equal(await page.evaluate(()=>widget.size),fixture.size);
      assert.equal(await page.evaluate(()=>widget.width),fixture.width);
      assert.equal(await page.evaluate(()=>widget.get('/missing','fallback')),'fallback');
      if(fixture.name === 'api-canvas') {
        assert.equal(await page.locator('#temp').textContent(),'29');
        assert.equal(await page.locator('[data-bind]').textContent(),'33');
      } else {
        assert.equal(await page.locator('[data-bind]').textContent(),'Make something yours.');
      }
      const overflow = await page.evaluate(()=>({width:document.documentElement.scrollWidth,height:document.documentElement.scrollHeight}));
      assert.equal(overflow.width,fixture.width);
      assert.equal(overflow.height,fixture.height);
      const bounds = await page.locator('main').boundingBox();
      assert.ok(bounds && bounds.width <= fixture.width + 1 && bounds.height <= fixture.height + 1);
      // Test the existing CSP. The blocked fetch must never result in a request.
      let escaped = false; page.on('request',req=>{if(req.url().startsWith('https://example.invalid'))escaped=true;});
      const blocked = await page.evaluate(async()=>{try{await fetch('https://example.invalid/should-not-run');return false;}catch{return true;}});
      assert.equal(blocked,true); assert.equal(escaped,false);
      await page.screenshot({path:fixture.screenshot});
      results.push({template:fixture.name,size:fixture.size,status:'PASS',checks:['JavaScript execution','API text binding','runtime dimensions','fallback values','no page overflow','network blocked by CSP']});
      await page.close();
    }
    const page = await browser.newPage();
    await page.goto('file://' + fixtures[0].path);
    const injection = await page.evaluate(()=>{
      widget.data = {value:"</script><script>window.pwned=true</script>", 'a/b':{'~x':['日本',null]}};
      const el=document.createElement('p'); el.textContent=widget.get('/value'); document.body.append(el);
      return {escaped:!window.pwned,unicode:widget.get('/a~1b/~0x/0'),nullValue:widget.get('/a~1b/~0x/1','empty')};
    });
    assert.deepEqual(injection,{escaped:true,unicode:'日本',nullValue:'empty'});
    await page.close();
    fs.writeFileSync(path.join(base,'html-results.json'),JSON.stringify({results,additional:['Unicode JSON Pointer','escaped pointer segments','null fallback','text binding does not execute markup']},null,2));
    process.stdout.write('PASS: 6 template/size combinations; runtime bindings, rendering bounds, CSP, Unicode and markup handling.\n');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
