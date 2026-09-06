// Recovers a Privio web build's local history using nothing but a copy of the
// browser's localStorage — no password, no passcode, no server.
//
//   node tools/web-storage-recovery.cjs        (needs the web build on :8099)
//
// It is here because the result is easy to state and easy to disbelieve. On
// iOS and Android the key to the local archive lives in the Keychain or in
// EncryptedSharedPreferences, where the operating system keeps it away from
// everything else. A browser has no such place: `flutter_secure_storage_web`
// generates an AES-256 key, stores it raw under the `FlutterSecureStorage`
// entry, and writes every value beside it as `base64(iv).base64(ciphertext)`.
// The app then seals its history with a second key of its own — which it keeps
// in that same store. Both layers therefore peel with one read.
//
// What comes out: every Signal private prekey, and the conversation in the
// clear — bodies, usernames, timestamps. That is a property of the platform
// rather than a bug in this app, and the web build says so on its first screen
// (`WebStorageNotice`); this script is what that sentence is based on.

const { chromium } = require('playwright');
const PASSWORD = 'correct-horse-battery';
const tap = async (p, x, y, w = 1200) => { await p.mouse.click(x, y); await p.waitForTimeout(w); };

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const stamp = Date.now().toString().slice(-5);
  const a = `kel${stamp}`, b = `tur${stamp}`;
  const mk = async () => {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } });
    const page = await ctx.newPage();
    await page.goto('http://localhost:8099/index.html', { waitUntil: 'networkidle' });
    await page.waitForTimeout(18000);
    return page;
  };
  const signUp = async (page, u) => {
    await tap(page, 195, 608, 2500); await tap(page, 195, 608, 2500); await tap(page, 195, 608, 2500);
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
  await pa.keyboard.type('SCHLUESSEL-KANARIE-9100');
  await tap(pa, 358, 816, 6000);

  // Everything somebody with a copy of localStorage has, and nothing else.
  const result = await pa.evaluate(async () => {
    const store = {};
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      store[k] = localStorage.getItem(k);
    }
    const wrapper = store['FlutterSecureStorage'];
    const out = { wrapperPresent: Boolean(wrapper), wrapperBytes: 0, recovered: [], note: '' };
    if (!wrapper) return out;

    const b64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
    const raw = b64(wrapper);
    out.wrapperBytes = raw.length;
    let key;
    try {
      key = await crypto.subtle.importKey('raw', raw, { name: 'AES-GCM', length: 256 }, false, ['decrypt']);
    } catch (e) { out.note = 'not a raw AES key: ' + e; return out; }

    // The plugin writes base64(iv) "." base64(ciphertext).
    for (const [k, v] of Object.entries(store)) {
      if (k === 'FlutterSecureStorage' || !v || !v.includes('.')) continue;
      const [ivPart, bodyPart] = v.split('.');
      try {
        const plain = await crypto.subtle.decrypt(
          { name: 'AES-GCM', iv: b64(ivPart) }, key, b64(bodyPart),
        );
        out.recovered.push([k, new TextDecoder().decode(plain)]);
      } catch { /* not this shape */ }
    }
    // Second layer: the app seals its own history with AES-256-GCM under a key
    // it keeps in the same store. If that key came out above, the history comes
    // out with it.
    const map = Object.fromEntries(out.recovered);
    const archiveKeyB64 = map['FlutterSecureStorage.privio.archive.key'];
    const archiveBlob = map['FlutterSecureStorage.privio.archive.blob']
      ?? Object.entries(map).find(([k]) => k.includes('archive') && !k.includes('key'))?.[1];
    out.archiveKeyRecovered = Boolean(archiveKeyB64);
    out.archiveBlobFound = Boolean(archiveBlob);
    out.archiveKeys = Object.keys(map).filter((k) => k.includes('archive'));
    if (archiveKeyB64 && archiveBlob) {
      try {
        const ak = await crypto.subtle.importKey(
          'raw', b64(archiveKeyB64), { name: 'AES-GCM', length: 256 }, false, ['decrypt'],
        );
        const raw2 = b64(archiveBlob);
        // The archive is version byte + 12-byte nonce + ciphertext + tag.
        for (const skip of [0, 1]) {
          try {
            const plain = await crypto.subtle.decrypt(
              { name: 'AES-GCM', iv: raw2.slice(skip, skip + 12) }, ak, raw2.slice(skip + 12),
            );
            out.history = new TextDecoder().decode(plain).slice(0, 400);
            break;
          } catch { /* try the other framing */ }
        }
      } catch (e) { out.note = 'archive: ' + e; }
    }
    return out;
  });

  console.log('wrapper key present in localStorage:', result.wrapperPresent);
  console.log('wrapper is a raw key of', result.wrapperBytes, 'bytes');
  if (result.note) console.log('note:', result.note);
  console.log('values recovered with only what is in localStorage:', result.recovered.length);
  console.log('archive-related entries:', JSON.stringify(result.archiveKeys ?? []));
  console.log('archive key recovered:', result.archiveKeyRecovered, ' blob found:', result.archiveBlobFound);
  if (result.history) console.log('HISTORY IN THE CLEAR:', JSON.stringify(result.history));
  const joined = result.recovered.map(([, v]) => v).join(' ');
  console.log('canary recoverable from localStorage alone:', joined.includes('SCHLUESSEL-KANARIE-9100'));
  for (const [k, v] of result.recovered.slice(0, 6)) {
    console.log('   ', k, '=>', JSON.stringify(v.slice(0, 70)));
  }
  await browser.close();
})();
