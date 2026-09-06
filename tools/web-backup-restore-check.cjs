// Drives the whole backup-and-restore path, which is the one where being wrong
// costs somebody their history rather than an afternoon.
//
//   node tools/web-backup-restore-check.cjs      (needs the web build on :8099)
//
// Two accounts talk, one backs up, the recovery key is copied off the screen,
// and a third browser context signs into the same account with nothing on it
// and restores. It passes when the message shows up in the chat list of a
// device that never had it.
//
// The coordinates are the fiddly part and the reason this is kept: the restore
// dialog's field sits above where it looks like it should, and typing into
// empty space submits an empty key, which the app answers with "that does not
// look like a recovery key" — a convincing failure that is entirely the
// script's fault.
const { chromium } = require('playwright');
const OUT = process.env.SP + '/backup';
const PASSWORD = 'correct-horse-battery';
const errors = [];
const tap = async (p, x, y, w = 1200) => { await p.mouse.click(x, y); await p.waitForTimeout(w); };
const text = async (page) => {
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await page.waitForTimeout(2500);
  return (await page.evaluate(() => document.body.innerText)).split('\n').filter(Boolean);
};

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const stamp = Date.now().toString().slice(-5);
  const a = `alt${stamp}`, b = `freund${stamp}`;

  const mk = async () => {
    const ctx = await browser.newContext({
      viewport: { width: 390, height: 844 },
      permissions: ['clipboard-read', 'clipboard-write'],
    });
    const page = await ctx.newPage();
    page.on('pageerror', (e) => errors.push(e.toString().slice(0, 120)));
    await page.goto('http://localhost:8099/index.html', { waitUntil: 'networkidle' });
    await page.waitForTimeout(18000);
    return page;
  };
  const signUp = async (page, u) => {
    await tap(page, 195, 646, 2500); await tap(page, 195, 646, 2500); await tap(page, 195, 646, 2500);
    await tap(page, 195, 268, 500); await page.keyboard.type(u);
    await tap(page, 195, 328, 500); await page.keyboard.type(PASSWORD);
    await tap(page, 195, 394, 7000);
  };

  const pb = await mk(); await signUp(pb, b);
  const pa = await mk(); await signUp(pa, a);

  await tap(pa, 366, 28, 2000);
  await tap(pa, 346, 800, 1800);
  await pa.keyboard.type(b);
  await tap(pa, 195, 798, 4000);
  await tap(pa, 195, 150, 4000);
  await tap(pa, 200, 817, 500);
  await pa.keyboard.type('WIEDERHERSTELLEN-6601');
  await tap(pa, 358, 816, 6000);
  await tap(pa, 28, 28, 2000); await tap(pa, 28, 28, 2000);

  await tap(pa, 351, 812, 3000);
  await tap(pa, 195, 446, 3500);                 // Backup
  await tap(pa, 195, 344, 9000);                 // Back up now
  await tap(pa, 195, 455, 3000);                 // Recovery key
  await tap(pa, 195, 646, 1500);                 // Copy
  const key = (await pa.evaluate(() => navigator.clipboard.readText())).trim();
  console.log('recovery key:', JSON.stringify(key));

  // A second device: the same account, nothing on it.
  const pc = await mk();
  await tap(pc, 195, 693, 3000);                 // Import from backup
  await pc.screenshot({ path: `${OUT}/R1-import-signin.png` });
  await tap(pc, 195, 268, 500); await pc.keyboard.type(a);
  await tap(pc, 195, 328, 500); await pc.keyboard.type(PASSWORD);
  await tap(pc, 195, 394, 9000);
  await pc.screenshot({ path: `${OUT}/R2-after-signin.png` });
  console.log('after signing in on the new device:', JSON.stringify((await text(pc)).slice(0, 10)));

  await tap(pc, 195, 504, 3000);                 // Restore from backup
  await pc.screenshot({ path: `${OUT}/R3-restore-dialog.png` });
  await tap(pc, 195, 361, 800);
  await pc.keyboard.type(key);
  await pc.screenshot({ path: `${OUT}/R4-key-entered.png` });
  await tap(pc, 195, 528, 12000);
  await pc.screenshot({ path: `${OUT}/R5-restored.png` });
  console.log('after the restore:', JSON.stringify((await text(pc)).slice(0, 10)));
  await tap(pc, 28, 28, 2000); await tap(pc, 28, 28, 2500);
  await pc.screenshot({ path: `${OUT}/R6-chats.png` });
  console.log('chat list:', JSON.stringify((await text(pc)).slice(0, 10)));

  await browser.close();
  console.log(errors.length ? 'PAGE ERRORS: ' + [...new Set(errors)].join(' | ') : 'no page errors');
  console.log('account', a, 'key', key);
})();
