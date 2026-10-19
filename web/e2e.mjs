// node e2e.mjs <patcher.html> <input.chd|bin> <pal|pale|ntsc|ntsce> <chd|bin> <out.zip>
// Needs Playwright; set PLAYWRIGHT_MODULE if it isn't resolvable as 'playwright'.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const [,, html, input, variant, fmt, out] = process.argv;
const b = await chromium.launch(); const p = await (await b.newContext({ acceptDownloads: true })).newPage();
p.on('console', m => console.log('console:', m.text())); p.on('pageerror', e => console.log('pageerror', e.message));
await p.goto('file://' + (await import('path')).resolve(html));
await p.setInputFiles('#file', input);
await p.waitForSelector('#go:not([disabled])');
const vb = variant.replace(/e$/, ''); await p.check('#v-' + vb); await p.setChecked('#skip', variant.endsWith('e')); await p.check('#f-' + fmt);
const t0 = Date.now(); await p.click('#go');
await p.waitForFunction(() => !document.getElementById('result').hidden || !document.getElementById('err').hidden, null, { timeout: 600000 });
console.log('took', Date.now() - t0, await p.textContent('#status'), await p.textContent('#err'), await p.textContent('#kv'));
if (!(await p.isHidden('#result'))) { const [d] = await Promise.all([p.waitForEvent('download'), p.click('#save')]); await d.saveAs(out); console.log('saved', d.suggestedFilename()); }
await p.screenshot({ path: 'shot_' + fmt + '.png', fullPage: true });
await b.close();
