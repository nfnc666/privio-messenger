// Drives the path every launch takes once a screen lock is set: sign up, say
// something, turn the lock on, reload, type the passcode on the drawn keypad,
// and check the history came back.
//
//   node tools/web-unlock-check.cjs      (needs the web build on :8099)
//
// It prints which archive entries exist at each step, which is the part worth
// watching: a plain `archive.key` appearing next to the wrapped one means
// something read the archive while it was locked, decided there was no key, and
// wrote a new one over a history it could not read. That is how this was broken
// the first time, and the run is quick enough to keep doing.
const { chromium } = require('playwright');
const OUT = process.env.SP + '/unlock';
const PASSWORD = 'correct-horse-battery';
const errors = [];
const tap = async (p, x, y, w = 1200) => { await p.mouse.click(x, y); await p.waitForTimeout(w); };
const lines = async (page) => {
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(2500);
  return (await page.evaluate(() => document.body.innerText)).split('\n').filter(Boolean);
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const stamp = Date.now().toString().slice(-5);
  const a = `auf${stamp}`, b = `zu${stamp}`;
  const ctxA = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const pa = await ctxA.newPage();
  pa.on('pageerror', (e) => errors.push('A: ' + e));

  const mk = async (page) => {
    await page.goto('http://localhost:8099/index.html', { waitUntil: 'networkidle' });
    await page.waitForTimeout(18000);
  };
  const signUp = async (page, u) => {
    await tap(page, 195, 646, 2500); await tap(page, 195, 646, 2500); await tap(page, 195, 646, 2500);
    await tap(page, 195, 268, 500); await page.keyboard.type(u);
    await tap(page, 195, 328, 500); await page.keyboard.type(PASSWORD);
    await tap(page, 195, 394, 7000);
  };

  const ctxB = await browser.newContext({ viewport: { width: 390, height: 844 } });
  const pb = await ctxB.newPage();
  await mk(pb); await signUp(pb, b);

  await mk(pa); await signUp(pa, a);
  await tap(pa, 366, 28, 2000);
  await tap(pa, 346, 800, 1800);
  await pa.keyboard.type(b);
  await tap(pa, 195, 798, 4000);
  await tap(pa, 195, 150, 4000);
  await tap(pa, 200, 817, 500);
  await pa.keyboard.type('NACH-DEM-SPERREN-5501');
  await tap(pa, 358, 816, 6000);
  await tap(pa, 28, 28, 2000);
  await tap(pa, 28, 28, 2000);

  // Account -> Settings -> Privacy & Security -> Screen Lock -> 4 digits.
  await tap(pa, 351, 812, 3000);
  await tap(pa, 366, 28, 2500);
  await tap(pa, 195, 88, 2500);
  await pa.mouse.wheel(0, 400); await pa.waitForTimeout(1200);
  await tap(pa, 195, 585, 2500);
  await tap(pa, 195, 570, 600); await pa.keyboard.type('1234');
  await tap(pa, 195, 630, 600); await pa.keyboard.type('1234');
  await tap(pa, 195, 696, 4000);
  await pa.screenshot({ path: `${OUT}/U1-lock-on.png` });
  const probe = async (label) => {
    const out = await pa.evaluate(() => {
      const r = {};
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k.includes('archive') || k.includes('lock.pin')) r[k.split('privio.')[1]] = true;
      }
      return r;
    });
    console.log(label, JSON.stringify(Object.keys(out)));
  };
  await probe('after setting the lock: ');

  // The path every launch takes from now on.
  await pa.reload({ waitUntil: 'networkidle' });
  await pa.waitForTimeout(20000);
  await pa.screenshot({ path: `${OUT}/U2-locked.png` });
  await probe('after reload, still locked:');

  // The pad is drawn, not a text field: physical keystrokes go nowhere.
  const pad = { 1: [94, 420], 2: [195, 420], 3: [296, 420], 4: [94, 513] };
  const t0 = Date.now();
  for (const d of [1, 2, 3, 4]) {
    await pa.mouse.click(pad[d][0], pad[d][1]);
    await pa.waitForTimeout(200);
  }
  // Wait for the shell rather than a fixed sleep, so the number means something.
  let elapsed = null;
  for (let i = 0; i < 60; i++) {
    const text = await pa.evaluate(() => document.body.innerText);
    if (text.includes('Chats') || text.includes('NACH-DEM')) { elapsed = Date.now() - t0; break; }
    await pa.waitForTimeout(250);
  }
  await probe('right after unlocking:  ');
  await pa.waitForTimeout(8000);
  await probe('eight seconds later:    ');
  await pa.screenshot({ path: `${OUT}/U3-unlocked.png` });
  console.log('unlock took:', elapsed === null ? '(not measured)' : elapsed + 'ms');
  console.log('after unlock:', JSON.stringify((await lines(pa)).slice(0, 8)));
  const store = await pa.evaluate(() => {
    const out = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k.includes('archive') || k.includes('lock')) out[k] = (localStorage.getItem(k) ?? '').length;
    }
    return out;
  });
  console.log('archive entries after unlock:', JSON.stringify(store));

  await browser.close();
  console.log(errors.length ? 'PAGE ERRORS:\n' + errors.join('\n') : 'no page errors');
})();
