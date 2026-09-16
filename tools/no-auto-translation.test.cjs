const assert = require('node:assert/strict');
const { readFileSync, readdirSync } = require('node:fs');
const { join } = require('node:path');
const { test } = require('node:test');
const root = join(__dirname, '..');
const obsolete = /editChannelAutoTranslate|translationNotSetUpTitle|translationNotSetUpBody|_explainTranslation|TRANSLATION_URL/;

function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? files(path) : [path];
  });
}

test('content-translation placeholder and endpoint are absent from app and server source', () => {
  for (const directory of ['app/lib', 'server/src']) {
    for (const path of files(join(root, directory))) {
      if (!/\.(dart|arb|ts)$/.test(path)) continue;
      assert.equal(obsolete.test(readFileSync(path, 'utf8')), false, path);
    }
  }
});

test('all five interface languages and language picker remain available', () => {
  for (const language of ['en', 'de', 'es', 'fr', 'it']) {
    const messages = JSON.parse(readFileSync(join(root, `app/lib/l10n/app_${language}.arb`), 'utf8'));
    assert.equal(messages['@@locale'], language);
    assert.ok(messages.languageName);
    assert.ok(messages.languagePickerTitle);
    assert.ok(messages.editChannelAppearance);
    assert.ok(messages.editChannelDirectMessages);
  }
  const screen = readFileSync(join(root, 'app/lib/screens/settings_screen.dart'), 'utf8');
  assert.match(screen, /LanguageScreen/);
});

test('removal does not leave duplicate section dividers', () => {
  const screen = readFileSync(join(root, 'app/lib/screens/channel_edit_screen.dart'), 'utf8');
  assert.doesNotMatch(screen, /const _Hairline\(\),\s*const _Hairline\(\),/);
});
