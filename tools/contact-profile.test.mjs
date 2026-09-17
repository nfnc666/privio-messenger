import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('all contact-profile strings exist in each supported language and generated delegate', () => {
  const english = JSON.parse(read('app/lib/l10n/app_en.arb'));
  const keys = Object.keys(english).filter((key) => key.startsWith('contactProfile'));
  assert.equal(keys.length, 8);
  for (const locale of ['en', 'de', 'es', 'fr', 'it']) {
    const arb = JSON.parse(read(`app/lib/l10n/app_${locale}.arb`));
    const generated = read(`app/lib/l10n/app_localizations_${locale}.dart`);
    for (const key of keys) {
      assert.equal(typeof arb[key], 'string');
      assert.ok(arb[key].length > 0);
      assert.ok(generated.includes(`String get ${key} =>`));
      assert.ok(read('app/lib/l10n/app_localizations.dart').includes(`String get ${key};`));
    }
  }
});

test('profile navigation pushes over the mounted chat and uses sender IDs', () => {
  const source = read('app/lib/screens/chat_screen.dart');
  assert.match(source, /_openContactProfile\(String accountId\) => Navigator\.of\(context\)\.push\(/);
  assert.match(source, /onTap: widget\.isGroup \? _openGroupInfo/);
  assert.match(source, /message\.isMine \? state\.accountId : message\.senderAccountId/);
  assert.match(source, /returnToChat: !widget\.isGroup && accountId == widget\.accountId/);
});

test('profile data has no phone field and no username lookup', () => {
  const controller = read('app/lib/core/contact_profile_controller.dart');
  assert.doesNotMatch(controller, /json\[['"](?:phone|phoneNumber|telephone)/);
  assert.match(controller, /api\.lookupById\(accountId\)/);
  assert.match(controller, /profile\.id != accountId/);
  assert.match(controller, /api\.sessionGeneration == generation/);
});
