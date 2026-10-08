# Privio — Leitlinie für jede Arbeit an diesem Repository

## Wofür Privio steht

**Maximaler Datenschutz und maximale Privatsphäre.** Das ist der Maßstab für
jede Entscheidung, vor Komfort und vor Funktionsumfang.

Das Ziel ist ein Messenger auf dem Sicherheitsniveau, das Behörden und Militär
für vertrauliche Kommunikation verlangen. Vorbild ist **Wickr Me**, nur mit mehr
Funktionen. „Militärisch“ ist dabei ein Anspruch an die Umsetzung, kein
Etikett: Er wird durch geprüfte Protokolle, möglichst wenig Metadaten und
ehrliche Aussagen erreicht. Ohne Nachweis steht er in keinem App-Text und in
keinem Marketing.

Daraus folgt bei jeder Funktion:

* **Der Server darf keinen Klartext privater Nachrichten sehen.** Gruppen- und
  Kanalinhalte werden auf dem Gerät versiegelt.
* **Keine eigene Kryptografie.** Nur etablierte, geprüfte Bibliotheken und
  Protokolle (Signal-Protokoll, libsodium und Ähnliches).
* **So wenig Metadaten wie möglich.** Wer eine neue Spalte, ein Log oder einen
  Zähler einführt, begründet ihn. `server/test/schema.test.ts` verweigert jede
  lesbare Spalte ohne Begründung, und das bleibt so.
* **Keine Pflicht zu Telefonnummer oder E-Mail.** Ein Konto ist ein
  Benutzername.
* **Ausnahmen sind sichtbar, nie still.** Bot-Chats sind derzeit Klartext auf
  dem Server; die App sagt das vor der ersten Nachricht und auf jeder
  Bot-Umfrage. Jede künftige Ausnahme wird genauso offen gekennzeichnet.
* **Löschen heißt löschen.** Kontolöschung und Duress-Wipe entfernen alles, was
  der Server über die Person hält.

## Bekannte Lücken auf dem Weg dorthin

Stand dieser Datei, Details in `docs/metadata-privacy-review.md`:

* **Kein Sealed Sender.** Der Server weiß, wer mit wem schreibt. Das ist die
  wichtigste offene Metadaten-Lücke.
* **Keine „Einmal ansehen“-Nachrichten.**
* **Bots sind nicht Ende-zu-Ende-verschlüsselt.** Ein E2E-Bot-SDK ist entworfen,
  aber nicht gebaut (`docs/bots.md`); erst danach können Bots in Kanälen posten.

## Feste Regeln

* Kein Deployment, keine Veröffentlichung, kein Upload, keine kostenpflichtigen
  Einstellungen ohne ausdrücklichen Auftrag. Der Nutzer drückt Deploy und Merge.
* Keine Zugangsdaten, Gerätetokens, Signierschlüssel oder Secrets in Code,
  Commits, Logs oder öffentlichen Artefakten. Bestehendes Signing beibehalten.
* Keine Tests deaktivieren und keine Sicherheitsprüfungen abschwächen.
* Keine Datenbank zurücksetzen, keine angewandte Migration umbenennen, keine
  produktiven Daten verändern.
* Keine eigenmächtige Lizenzumstellung.
* Berichte auf Deutsch, und klar getrennt: implementiert, automatisch getestet,
  kompiliert, auf echten Geräten bestätigt.

## Arbeitsweise

* App: `cd app && flutter analyze && flutter test` (Flutter liegt unter
  `/opt/flutter/bin`). Der Analyzer bricht schon bei `info` ab.
  Übersetzungen: `flutter gen-l10n`, danach muss `l10n-missing.json` `{}` sein.
  Neue Texte immer in allen fünf Sprachen (EN/DE/ES/FR/IT).
* Kein `dart format` auf bestehende Dateien: Der Formatierer hier formatiert
  ganze Dateien anders als das Repository.
* Server: `TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/privio_test
  npm --workspace server test`.
* Eine Regel gilt erst als getestet, wenn sie einmal absichtlich gebrochen wurde
  und der passende Test rot wurde.
* Beispiel- und Testdaten sind neutral (z. B. `PrivioNews`), keine Namen
  anderer Projekte.
