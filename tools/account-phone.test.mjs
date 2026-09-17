import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('all new account phone strings are present in five languages and delegates', () => {
  const keys = Object.keys(JSON.parse(read('app/lib/l10n/app_en.arb'))).filter((k) => k.startsWith('accountPhone'));
  assert.equal(keys.length, 6);
  for (const locale of ['en', 'de', 'es', 'fr', 'it']) {
    const arb = JSON.parse(read(`app/lib/l10n/app_${locale}.arb`));
    const dart = read(`app/lib/l10n/app_localizations_${locale}.dart`);
    for (const key of keys) {
      assert.ok(arb[key]?.length);
      assert.ok(dart.includes(`String get ${key} =>`));
    }
  }
});

test('annotation route does not invoke SMS or modify verified mappings', () => {
  const route = read('server/src/routes/account_phone.ts');
  assert.doesNotMatch(route, /(?:INSERT INTO|UPDATE|DELETE FROM) phone_links/i);
  assert.doesNotMatch(route, /SmsSender|generateCode|discoveryHash|hashesFor|phone_verifications/);
  assert.match(route, /verified: false, usedForDiscovery: false/);
  assert.match(route, /auth\(request\)/);
  assert.doesNotMatch(read('server/src/routes/phone.ts'), /account_phone_notes/);
});

test('account note schema has no number uniqueness or discovery index', () => {
  const schema = read('server/migrations/033_unverified_account_phone.sql');
  assert.match(schema, /account_id uuid PRIMARY KEY REFERENCES accounts\(id\) ON DELETE CASCADE/);
  assert.doesNotMatch(schema, /CREATE (?:UNIQUE )?INDEX|phone_number[^\n]*UNIQUE/);
});
