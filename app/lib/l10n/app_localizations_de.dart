// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppTextDe extends AppText {
  AppTextDe([String locale = 'de']) : super(locale);

  @override
  String get languageName => 'Sprache';

  @override
  String get languagePickerTitle => 'Sprache';

  @override
  String get languagePickerNote =>
      'Die Oberfläche wechselt sofort. Nachrichten, Channel-Namen und alles andere, was Menschen geschrieben haben, bleibt in der Sprache, in der es geschrieben wurde.';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonDone => 'Fertig';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonRemove => 'Entfernen';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonSearch => 'Suchen';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonNext => 'Weiter';

  @override
  String get commonSkip => 'Überspringen';

  @override
  String get commonContinue => 'Fortfahren';

  @override
  String get commonYes => 'Ja';

  @override
  String get commonNo => 'Nein';

  @override
  String get commonOk => 'Alles klar';

  @override
  String get commonCopy => 'Kopieren';

  @override
  String get commonCopied => 'Kopiert.';

  @override
  String get commonShare => 'Teilen';

  @override
  String get commonLoading => 'Wird geladen …';

  @override
  String get commonSomethingWentWrong => 'Etwas ist schiefgelaufen.';

  @override
  String get commonNotNow => 'Jetzt nicht';

  @override
  String get commonOn => 'An';

  @override
  String get commonOff => 'Aus';

  @override
  String get commonDefault => 'Standard';

  @override
  String get commonCustom => 'Eigene';

  @override
  String get commonUnavailable => 'Nicht verfügbar';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsAppearance => 'Darstellung';

  @override
  String get settingsNotifications => 'Benachrichtigungen';

  @override
  String get disappearingTitle => 'Selbstlöschende Nachrichten';

  @override
  String get disappearingExplainer =>
      'Neue Nachrichten werden nach dieser Zeit automatisch gelöscht. Der Timer beginnt beim Senden.';

  @override
  String get disappearingCoversChat =>
      'Das gilt für Texte, Fotos, Dateien und Sprachnachrichten und nur für diesen Chat. Bereits gesendete Nachrichten bleiben unberührt, und ihr werdet beide informiert, wenn sich etwas ändert.';

  @override
  String get disappearingCoversGroup =>
      'Das gilt für Texte, Fotos, Dateien und Sprachnachrichten und nur für diese Gruppe. Bereits gesendete Nachrichten bleiben unberührt, alle werden bei einer Änderung informiert, und ändern kann es nur ein Admin.';

  @override
  String get disappearingScreenshotCaveat =>
      'Ein Screenshot, ein bereits gespeichertes Foto oder etwas anderswo Notiertes lässt sich damit nicht zurücknehmen.';

  @override
  String get disappearingOff => 'Aus';

  @override
  String get disappearing30Seconds => '30 Sekunden';

  @override
  String get disappearing1Minute => '1 Minute';

  @override
  String get disappearing5Minutes => '5 Minuten';

  @override
  String get disappearing1Hour => '1 Stunde';

  @override
  String get disappearing24Hours => '24 Stunden';

  @override
  String get disappearing7Days => '7 Tage';

  @override
  String get disappearingAdminOnly => 'Das kann nur ein Admin ändern';

  @override
  String noticeTimerSetBy(String who, String duration) {
    return '$who hat selbstlöschende Nachrichten auf $duration gesetzt';
  }

  @override
  String noticeTimerOffBy(String who) {
    return '$who hat selbstlöschende Nachrichten ausgeschaltet';
  }

  @override
  String get noticeYou => 'Du';

  @override
  String get noticeThey => 'Die Gegenseite';

  @override
  String get noticeSomeone => 'Jemand';

  @override
  String noticeMessageDeletedBy(String who) {
    return '$who hat eine Nachricht gelöscht';
  }

  @override
  String noticeSafetyNumberChanged(String who) {
    return 'Deine Sicherheitsnummer mit $who hat sich geändert';
  }

  @override
  String noticeUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nachrichten',
      one: 'Eine Nachricht',
    );
    return '$_temp0 konnte nicht gelesen werden. Sie war mit einem Schlüssel versiegelt, den dieses Gerät nicht mehr hat.';
  }

  @override
  String noticeUnreadableFrom(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nachrichten',
      one: 'Eine Nachricht',
    );
    return '$_temp0 von $who konnte nicht gelesen werden. Sie war mit einem Schlüssel versiegelt, den dieses Gerät nicht mehr hat.';
  }

  @override
  String durationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sekunden',
      one: '1 Sekunde',
    );
    return '$_temp0';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stunden',
      one: '1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String durationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tage',
      one: '1 Tag',
    );
    return '$_temp0';
  }

  @override
  String durationWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wochen',
      one: '1 Woche',
    );
    return '$_temp0';
  }

  @override
  String channelSubscribers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abonnenten',
      one: '1 Abonnent',
    );
    return '$_temp0';
  }

  @override
  String channelMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '1 Mitglied',
    );
    return '$_temp0';
  }

  @override
  String get channelPublic => 'Öffentlich';

  @override
  String get channelPrivate => 'Privat';

  @override
  String get channelAdministrators => 'Administratoren';

  @override
  String get channelSubscribersRow => 'Abonnenten';

  @override
  String get channelSettings => 'Kanaleinstellungen';

  @override
  String get channelShareLink => 'Link teilen';

  @override
  String get channelDescription => 'Beschreibung';

  @override
  String get channelMedia => 'Medien';

  @override
  String get channelLinks => 'Links';

  @override
  String get channelNoMedia => 'Noch keine Bilder';

  @override
  String get channelNoLinks => 'Noch keine Links';

  @override
  String get channelNoPosts => 'Noch keine Beiträge';

  @override
  String get channelActionLivestream => 'Livestream';

  @override
  String get channelActionMute => 'stumm';

  @override
  String get channelActionUnmute => 'laut';

  @override
  String get channelActionSearch => 'suchen';

  @override
  String get channelActionMore => 'mehr';

  @override
  String get channelMuteTitle => 'Diesen Channel stummschalten';

  @override
  String get channelMuteNote =>
      'Er bleibt auf jedem Gerät stumm, auf dem du angemeldet bist — hier stumm zu schalten heißt nicht „bis ich den Laptop aufklappe“.';

  @override
  String get channelMuteForHour => 'Für 1 Stunde';

  @override
  String get channelMuteForEightHours => 'Für 8 Stunden';

  @override
  String get channelMuteForTwoDays => 'Für 2 Tage';

  @override
  String get channelMuteUntilOff => 'Bis ich es wieder einschalte';

  @override
  String get channelCopyLink => 'Link kopieren';

  @override
  String get channelQrCode => 'QR-Code';

  @override
  String get channelInviteSettings => 'Einladungseinstellungen';

  @override
  String get channelStatistics => 'Statistiken';

  @override
  String get channelReport => 'Channel melden';

  @override
  String get channelLeave => 'Channel verlassen';

  @override
  String get channelLeaveTitle => 'Diesen Channel verlassen?';

  @override
  String get channelLeaveBody =>
      'Du bekommst seine Beiträge nicht mehr. Der Channel wechselt auf einen neuen Schlüssel, sodass du nichts lesen kannst, was danach veröffentlicht wird.';

  @override
  String get channelStay => 'Bleiben';

  @override
  String get channelNoLinkToShare =>
      'Dieser Channel hat keinen Link zum Teilen.';

  @override
  String get channelInfo => 'Channel-Info';

  @override
  String get adminsTitle => 'Admins';

  @override
  String get adminsSectionHeader => 'KANALADMINISTRATOREN';

  @override
  String get adminsAdd => 'Admin hinzufügen';

  @override
  String get adminsSearch => 'Admins suchen';

  @override
  String get adminsRoleOwner => 'Inhaber';

  @override
  String get adminsRoleAdmin => 'Admin';

  @override
  String adminsPromotedBy(String who) {
    return 'befördert von $who';
  }

  @override
  String get adminsHelpOwner =>
      'Administratoren helfen dir, deinen Kanal zu verwalten.';

  @override
  String get adminsHelpMember =>
      'Administratoren helfen bei der Verwaltung dieses Kanals. Diese Liste ändern kann nur, wer Admins ernennen darf.';

  @override
  String get adminsNobodyYet => 'Noch niemand.';

  @override
  String get adminsShowSenderName => 'Absendername zeigen';

  @override
  String get adminsShowSenderNameOn =>
      'Neue Beiträge tragen den Namen dessen, der sie geschrieben hat';

  @override
  String get adminsShowSenderNameLocked =>
      'Das kann nur ein Admin ändern, der den Kanal bearbeiten darf';

  @override
  String get adminsShowSenderNameNote =>
      'Ist es aus, veröffentlicht der Kanal alles unter seinem eigenen Namen — kein Admin-Name hängt daran, und Lesende sehen eine Stimme.';

  @override
  String get adminsTransfer => 'Eigentum übertragen';

  @override
  String get adminsTransferNote =>
      'Fragt nach deinem Passwort und lässt sich nicht rückgängig machen';

  @override
  String get adminsEverybodyAlready =>
      'Alle in diesem Kanal sind bereits Admin.';

  @override
  String get adminsWhoShouldBe => 'Wer soll Admin werden?';

  @override
  String get adminsDismiss => 'Als Admin absetzen';

  @override
  String get adminsAppoint => 'Ernennen';

  @override
  String get adminsOwnerFixed =>
      'Der Inhaber hat jede Berechtigung, und das lässt sich nicht ändern — weder hier noch auf dem Server.';

  @override
  String get adminsOutranksYou =>
      'Diese Person hat Berechtigungen, die du nicht hast. Deshalb kannst du nicht ändern, was sie darf.';

  @override
  String get adminsOnlyWhatYouHold =>
      'Du kannst nur weitergeben, was du selbst hast. Alles Übrige ist aus und lässt sich nicht einschalten.';

  @override
  String get adminsYouDoNotHold => 'Diese Berechtigung hast du selbst nicht';

  @override
  String get adminsCouldNotChange => 'Das ließ sich nicht ändern.';

  @override
  String get permissionEditChannel => 'Kanal bearbeiten';

  @override
  String get permissionEditChannelDetail =>
      'Name, Bild, Beschreibung und Einstellungen';

  @override
  String get permissionPost => 'Beiträge veröffentlichen';

  @override
  String get permissionPostDetail => 'Und eigene bearbeiten oder planen';

  @override
  String get permissionDeletePosts => 'Beiträge löschen';

  @override
  String get permissionDeletePostsDetail => 'Auch die von anderen';

  @override
  String get permissionModerate => 'Diskussion moderieren';

  @override
  String get permissionModerateDetail =>
      'Kommentare entfernen und Personen stummschalten';

  @override
  String get permissionManageMembers => 'Abonnenten verwalten';

  @override
  String get permissionManageMembersDetail =>
      'Hinzufügen, entfernen und stummschalten';

  @override
  String get permissionManageInvites => 'Einladungen verwalten';

  @override
  String get permissionManageInvitesDetail =>
      'Den Link, seine Grenzen und wer wartet';

  @override
  String get permissionManageLivestreams => 'Livestreams verwalten';

  @override
  String get permissionManageLivestreamsDetail => 'Starten und beenden';

  @override
  String get permissionAppointAdmins => 'Admins ernennen';

  @override
  String get permissionAppointAdminsDetail =>
      'Diese Befugnis an jemand anderen weitergeben';

  @override
  String get subscribersTitle => 'Abonnenten';

  @override
  String get subscribersAdd => 'Abonnenten hinzufügen';

  @override
  String get subscribersSearch => 'Abonnenten suchen';

  @override
  String get subscribersAdminsOnlyNote =>
      'Nur Kanaladministratoren sehen diese Liste.';

  @override
  String get subscribersPartialNote =>
      'Das ist nicht die ganze Liste. Wer abonniert hat, sehen nur Kanaladministratoren — hier stehen die Leute, die den Kanal führen, und du.';

  @override
  String get subscribersCompleteNote => 'Alle in diesem Kanal.';

  @override
  String get subscribersContactsSection => 'KONTAKTE IN DIESEM KANAL';

  @override
  String get subscribersOthersSection => 'ANDERE ABONNENTEN';

  @override
  String get subscribersOnlySection => 'ABONNENTEN';

  @override
  String get subscribersNobodyFound => 'Niemanden gefunden.';

  @override
  String get subscribersNoContacts => 'Noch keine Kontakte zum Hinzufügen.';

  @override
  String get subscribersEverybodyHere =>
      'Alle aus deinen Kontakten sind schon hier.';

  @override
  String get subscribersAddedOne => 'Hinzugefügt.';

  @override
  String subscribersAddedMany(int count) {
    return '$count Personen hinzugefügt.';
  }

  @override
  String get subscribersNobodyAdded => 'Niemand konnte hinzugefügt werden';

  @override
  String subscribersAddedCount(int count) {
    return '$count hinzugefügt';
  }

  @override
  String subscribersNeedInvite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Personen haben',
      one: '1 Person hat',
    );
    return '$_temp0 eingestellt, dass nur eigene Kontakte sie zu etwas hinzufügen dürfen. Schick ihnen stattdessen den Link und lass sie entscheiden.';
  }

  @override
  String get subscribersCopyTheLink => 'Den Link kopieren';

  @override
  String get subscribersOwnerCannotBeRemoved =>
      'Der Inhaber kann nicht entfernt werden.';

  @override
  String get subscribersSilenced => 'Stummgeschaltet';

  @override
  String get subscribersSilence => 'Stummschalten';

  @override
  String get subscribersSilenceDetail =>
      'Bleibt abonniert und kann nicht mehr kommentieren';

  @override
  String get subscribersUnsilence => 'Wieder sprechen lassen';

  @override
  String get subscribersUnsilenceDetail => 'Kann wieder kommentieren';

  @override
  String get subscribersRemoveFromChannel => 'Aus dem Kanal entfernen';

  @override
  String get subscribersRemoveDetail =>
      'Der Kanal wechselt auf einen neuen Schlüssel, sodass nichts Folgendes mehr lesbar ist';

  @override
  String get subscribersCouldNotDoThat => 'Das ging nicht.';

  @override
  String get presenceOnline => 'online';

  @override
  String presenceMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minuten',
      one: '1 Minute',
    );
    return 'zuletzt online vor $_temp0';
  }

  @override
  String presenceHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stunden',
      one: '1 Stunde',
    );
    return 'zuletzt online vor $_temp0';
  }

  @override
  String presenceDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tagen',
      one: '1 Tag',
    );
    return 'zuletzt online vor $_temp0';
  }

  @override
  String presenceOnDate(String date) {
    return 'zuletzt online am $date';
  }

  @override
  String get editChannelName => 'Kanalname';

  @override
  String get editChannelDescriptionHint => 'Beschreibung';

  @override
  String get editChannelChangePicture => 'Bild ändern';

  @override
  String get editChannelChoosePicture => 'Bild auswählen';

  @override
  String get editChannelRemovePicture => 'Entfernen';

  @override
  String get editChannelPrivateNameNote =>
      'Dieser Kanal ist privat, sein Name also mit dem Kanalschlüssel verschlüsselt. Beim Umbenennen wird das für jedes Mitglied neu versiegelt.';

  @override
  String get editChannelType => 'Kanalart';

  @override
  String get editChannelDiscussion => 'Diskussion';

  @override
  String get editChannelReactions => 'Reaktionen';

  @override
  String editChannelReactionsValue(int count) {
    return '$count Emojis';
  }

  @override
  String get editChannelWelcome => 'Willkommensnachricht';

  @override
  String get editChannelAppearance => 'Darstellung';

  @override
  String get editChannelAutoTranslate => 'Auto-Übersetzung';

  @override
  String get editChannelDirectMessages => 'Direktnachrichten';

  @override
  String get editChannelNeedsName => 'Ein Kanal braucht einen Namen.';

  @override
  String get editChannelDiscardTitle => 'Änderungen verwerfen?';

  @override
  String get editChannelDiscardBody => 'Hier ist noch nichts gespeichert.';

  @override
  String get editChannelKeepEditing => 'Weiter bearbeiten';

  @override
  String get editChannelDiscard => 'Verwerfen';

  @override
  String get editChannelCouldNotSave =>
      'Diese Änderungen ließen sich nicht speichern.';

  @override
  String get editChannelCouldNotUsePicture =>
      'Dieses Bild ließ sich nicht verwenden.';

  @override
  String get editChannelPublicPictureTitle => 'Dieses Bild wird öffentlich';

  @override
  String get editChannelPublicPictureBody =>
      'Das Bild eines öffentlichen Kanals erscheint auf seiner Webseite und in Linkvorschauen und wird deshalb unverschlüsselt gespeichert — genau wie Name, Benutzername und Beschreibung. Beiträge bleiben Ende-zu-Ende-verschlüsselt.';

  @override
  String get editChannelUseIt => 'Verwenden';

  @override
  String get editChannelSignatureNote =>
      'Signierte Beiträge zeigen den Namen dessen, der sie geschrieben hat. Ist es aus, veröffentlicht der Kanal alles unter seinem eigenen Namen.';

  @override
  String get livestreamNotSetUpTitle => 'Livestreams sind nicht eingerichtet';

  @override
  String get livestreamNotSetUpBody =>
      'Ein Livestream braucht einen Medienserver: Eine Person sendet Video, alle anderen empfangen es — das geht nicht von Gerät zu Gerät wie bei einem Anruf.\n\nAuf diesem Privio-Server ist keiner konfiguriert, es gibt also nichts beizutreten. Wer ihn betreibt, kann einen einrichten.';

  @override
  String get livestreamYouAreLive => 'Du bist live';

  @override
  String get livestreamRunning => 'Ein Stream läuft';

  @override
  String get livestreamPublisherBody =>
      'Der Raum ist offen und dein Gerät hat ein Token, um darin zu senden. Privio überträgt das Video noch nicht selbst — das macht der Medienserver —, von diesem Bildschirm geht also nichts raus.\n\nBeende es, wenn du fertig bist.';

  @override
  String get livestreamViewerBody =>
      'Ein Stream läuft, und dieses Gerät hat ein Token, um ihn anzusehen. Privio kann das Video noch nicht darstellen.';

  @override
  String get livestreamEndIt => 'Beenden';

  @override
  String get livestreamNobodyStreaming => 'Gerade streamt niemand.';

  @override
  String get livestreamCouldNotStart => 'Der Stream ließ sich nicht starten.';

  @override
  String get translationNotSetUpTitle =>
      'Auto-Übersetzung ist nicht eingerichtet';

  @override
  String get translationNotSetUpBody =>
      'Einen Beitrag zu übersetzen heißt, seinen Inhalt an einen Übersetzungsdienst zu schicken. Der Server von Privio kann das nicht — er hält Chiffrat und keinen Schlüssel —, es müsste also auf deinem Gerät geschehen, und der Text würde es im Klartext verlassen.\n\nDas ist eine Entscheidung, die der Betreiber freischalten und jede lesende Person zulassen muss. Bis beides geschehen ist, bleibt es aus. Es wurde kein Beitrag irgendwohin gesendet.';

  @override
  String get visibilityPublicTitle => 'Dieser Kanal ist öffentlich';

  @override
  String get visibilityPrivateTitle => 'Dieser Kanal ist privat';

  @override
  String visibilityPublicBody(String handle) {
    return 'Jede und jeder kann ihn über den Namen finden und seine Beiträge lesen. Sein Benutzername ist @$handle.\n\nPrivio kann einen öffentlichen Kanal nicht nachträglich privat machen: Name und Beschreibung waren lesbar, und das kann keine App ungeschehen machen.';
  }

  @override
  String get visibilityPrivateBody =>
      'Er ist nicht gelistet, nicht durchsuchbar und nur über seinen Einladungslink erreichbar. Sein Name ist mit dem Kanalschlüssel verschlüsselt.\n\nIhn öffentlich zu machen würde diesen Namen veröffentlichen — diese Entscheidung trifft Privio nicht für dich. Leg stattdessen einen öffentlichen Kanal an.';

  @override
  String get discussionBody =>
      'Ist das an, bekommt jeder Beitrag einen Thread darunter. Kommentare werden mit demselben Kanalschlüssel versiegelt wie der Beitrag: Ein Gerät, das den Beitrag nicht lesen kann, kann auch den Thread nicht lesen.\n\nSpäter ausschalten blendet die Threads aus, statt sie zu löschen.';

  @override
  String get discussionTurnOn => 'Einschalten';

  @override
  String get discussionTurnOff => 'Ausschalten';

  @override
  String get welcomeShowToNew => 'Neuen Abonnenten zeigen';

  @override
  String get welcomeHint => 'Einmal beim Beitritt gezeigt';

  @override
  String get welcomePrivateNote =>
      'Dieser Kanal ist privat, die Nachricht ist also wie sein Name mit dem Kanalschlüssel verschlüsselt.';

  @override
  String get appearanceNote =>
      'Eine feste Auswahl statt eines Farbwählers: Jede Kombination hier wurde auf Kontrast geprüft, damit ein Kanal nichts wählen kann, was seine Lesenden nicht lesen können.';

  @override
  String get appearancePreviewPost => 'Ein Beitrag in diesem Kanal';

  @override
  String get appearancePreviewLink => 'und ein Link darin';

  @override
  String get appearanceAccent => 'Akzent';

  @override
  String get appearanceBackground => 'Hintergrund';

  @override
  String get appearanceUseDefault => 'Standard verwenden';

  @override
  String get composerHint => 'Nachricht schreiben …';

  @override
  String get composerAttach => 'Datei anhängen';

  @override
  String get composerTimerOff => 'Selbstlöschende Nachrichten sind aus';

  @override
  String composerTimerOn(String badge) {
    return 'Nachrichten verschwinden nach $badge';
  }

  @override
  String get searchPostsHint => 'Lesbare Beiträge durchsuchen';

  @override
  String get searchThisChannel => 'Diesen Kanal durchsuchen';

  @override
  String get searchClose => 'Suche schließen';

  @override
  String get searchNoResults => 'Nichts gefunden';

  @override
  String get settingsPrivacy => 'Privatsphäre & Sicherheit';

  @override
  String get settingsStorage => 'Daten und Speicher';

  @override
  String get settingsAbout => 'Über Privio';

  @override
  String get settingsDevices => 'Geräte';

  @override
  String get settingsBackup => 'Sicherung';

  @override
  String get settingsDisguise => 'Tarnmodus';

  @override
  String get settingsLicense => 'Privio-Lizenz';

  @override
  String get settingsLicenseNotActive => 'Nicht aktiv';

  @override
  String get appearanceTextSize => 'Schriftgröße';

  @override
  String get appearanceTextSizeNote =>
      'Das ist Privios eigene Einstellung und sie gilt überall in der App. Sie überschreibt nicht die Größe, die dein Telefon für alles andere eingestellt hat — die gilt weiterhin darunter.';

  @override
  String get appearanceDarkOnly =>
      'Privio ist ausschließlich dunkel. Das Design ist dafür gebaut, echtes Schwarz kostet auf den OLED-Displays der meisten Telefone nichts, und ein helles Design, das nur halb existiert, ist keinen Schalter wert, der etwas anderes behauptet.';

  @override
  String get textSizeSmall => 'Klein';

  @override
  String get textSizeMedium => 'Mittel';

  @override
  String get textSizeLarge => 'Groß';

  @override
  String get textSizeLarger => 'Größer';

  @override
  String get notificationsPushNote =>
      'Eine Push-Nachricht trägt keinen Inhalt — nur ein Wecksignal. Die Nachricht wird auf diesem Gerät geholt und entschlüsselt, niemand dazwischen sieht also, wer dir geschrieben hat, auch nicht der Betreiber des Dienstes, der geweckt hat.';

  @override
  String get notificationsPhoneNote =>
      'Ton, Vibration, das Licht und ob auf dem Sperrbildschirm etwas erscheint, gehören zu den Einstellungen deines Telefons für Privio, nicht auf diesen Bildschirm. Hier standen einmal fünf Schalter, die nichts einstellten; sie sind weg, statt so auszusehen, als funktionierten sie.';

  @override
  String get notificationsDelivery => 'Zustellung';

  @override
  String notificationsDistributorFound(String app) {
    return 'Eine Verteiler-App auf diesem Telefon hält eine Verbindung für alle Apps, die sie nutzen, und leitet ein inhaltsloses Signal weiter. $app braucht dafür keinen Google-Dienst, und du kannst den Verteiler selbst betreiben.';
  }

  @override
  String get notificationsNoDistributor =>
      'Kein Verteiler gefunden. Installiere einen — zum Beispiel ntfy — um geweckt zu werden, während Privio geschlossen ist. Ohne einen kommen Nachrichten an, während die App offen ist.';

  @override
  String get privacyWhoCanSee => 'Wer sehen darf';

  @override
  String get privacyLastSeen => 'Zuletzt online';

  @override
  String get privacyLastSeenEveryone => 'Alle';

  @override
  String get privacyLastSeenContacts => 'Meine Kontakte';

  @override
  String get privacyLastSeenNobody => 'Niemand';

  @override
  String get privacyMessaging => 'Nachrichten';

  @override
  String get privacyReadReceipts => 'Lesebestätigungen';

  @override
  String get privacyTypingIndicators => 'Tippanzeige';

  @override
  String get privacyDisappearing => 'Selbstlöschende Nachrichten';

  @override
  String get privacyPerChat => 'Pro Chat';

  @override
  String get privacyAccess => 'Zugang';

  @override
  String get privacyScreenLock => 'Bildschirmsperre';

  @override
  String get privacyPin => 'PIN';

  @override
  String get privacyTwoFactor => 'Zwei-Faktor-Authentifizierung';

  @override
  String get privacyDuressCode => 'Notfallcode';

  @override
  String get privacySet => 'Gesetzt';

  @override
  String get privacyBlockedUsers => 'Blockierte Nutzer';

  @override
  String get privacyMutualNote =>
      'Lesebestätigungen und Tippanzeige gelten gegenseitig: Wenn du sie ausschaltest, siehst du auch die der anderen nicht mehr.';

  @override
  String get storageOnThisDevice => 'Auf diesem Gerät';

  @override
  String get storageHistory => 'Chatverlauf';

  @override
  String get storageInIt => 'Darin';

  @override
  String storageChatsAndMessages(int chats, int messages) {
    String _temp0 = intl.Intl.pluralLogic(
      chats,
      locale: localeName,
      other: '$chats Chats',
      one: '1 Chat',
    );
    String _temp1 = intl.Intl.pluralLogic(
      messages,
      locale: localeName,
      other: '$messages Nachrichten',
      one: '1 Nachricht',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get storageKeys => 'Schlüssel und Sitzungen';

  @override
  String get storageKeystoreNote =>
      'Beides liegt im Schlüsselspeicher der Plattform — der Keychain unter iOS, Keystore-gestützter Speicher unter Android — und der Verlauf wird vorher mit AES-256-GCM versiegelt. Keines davon ist für eine andere App lesbar, und keines für jemanden, der das Telefon in der Hand hält, ohne es zu entsperren.';

  @override
  String get storageNotKept => 'Nicht aufbewahrt';

  @override
  String get storageFilesOpened => 'Geöffnete Dateien';

  @override
  String get storageMemoryOnly => 'Nur im Arbeitsspeicher';

  @override
  String get storageVoiceRecordings => 'Sprachaufnahmen';

  @override
  String get storageShredded => 'Beim Senden vernichtet';

  @override
  String get storageEphemeralNote =>
      'Ein Foto oder eine Datei, die du öffnest, wird in den Arbeitsspeicher entschlüsselt und verschwindet, wenn die App schließt; nichts schreibt sie auf die Festplatte. Eine Sprachnachricht wird in eine temporäre Datei aufgenommen, weil das Mikrofon irgendwohin schreiben muss, und diese Datei wird sofort nach Ende der Aufnahme mit Zufallsbytes überschrieben und gelöscht — eine gelöschte Datei auf Flash-Speicher ist keine verschwundene Datei.';

  @override
  String get storageDelete => 'Löschen';

  @override
  String get storageDeleteHistory => 'Verlauf auf diesem Gerät löschen';

  @override
  String get storageDeleteNote =>
      'Das ist die einzige Löschung, die hier passiert. Was der Server hält — eine Sicherung, ein Anhang innerhalb seiner dreißig Tage — steht auf dem Sicherungsbildschirm, und was die Person hat, der du geschrieben hast, gehört ihr.';

  @override
  String get storageConfirmTitle => 'Den Verlauf auf diesem Gerät löschen?';

  @override
  String get storageConfirmBody =>
      'Jede Nachricht auf diesem Telefon verschwindet, in jedem Chat. Dein Konto, deine Schlüssel und deine Unterhaltungen bleiben: Man kann dir weiterhin schreiben, und was du danach sendest, kommt weiterhin an.\n\nEs erreicht nicht die Kopie der anderen und keine Sicherung, die schon auf dem Server liegt. Lösche die auf dem Sicherungsbildschirm, wenn sie auch weg soll.';

  @override
  String get storageDeleteIt => 'Löschen';

  @override
  String get storageDeleted => 'Der Verlauf auf diesem Gerät ist weg.';

  @override
  String get devicesThisDevice => 'Dieses Gerät';

  @override
  String get devicesOthers => 'Andere Geräte';

  @override
  String get devicesOthersTapToSignOut =>
      'Andere Geräte — zum Abmelden antippen';

  @override
  String get devicesNone => 'Keine';

  @override
  String get devicesOnlyThisOne => 'Nur dieses';

  @override
  String get devicesSignedIn => 'Angemeldet';

  @override
  String get devicesActiveNow => 'Gerade aktiv';

  @override
  String devicesActiveMinutes(int count) {
    return 'Vor $count Min. aktiv';
  }

  @override
  String devicesActiveHours(int count) {
    return 'Vor $count Std. aktiv';
  }

  @override
  String get devicesActiveYesterday => 'Gestern aktiv';

  @override
  String devicesActiveDays(int count) {
    return 'Vor $count Tagen aktiv';
  }

  @override
  String get devicesSignOutNote =>
      'Ein Gerät abzumelden widerruft seine Sitzung und löscht alles, was noch für es in der Warteschlange liegt. Es kommt nur zurück, indem es sich neu anmeldet — als neues Gerät, mit neuen Schlüsseln.';

  @override
  String devicesRevokeTitle(String name) {
    return '$name abmelden?';
  }

  @override
  String get devicesRevokeBody =>
      'Seine Sitzung wird widerrufen und alles, was noch für es in der Warteschlange liegt, gelöscht. Was es bereits entschlüsselt hat, bleibt auf diesem Gerät — von hier aus ist das nicht erreichbar. Es kommt nur durch eine erneute Anmeldung zurück.';

  @override
  String get devicesSignItOut => 'Abmelden';

  @override
  String devicesSignedOut(String name) {
    return '$name ist abgemeldet.';
  }

  @override
  String devicesLicenseCovers(int limit) {
    return 'Deine Lizenz deckt $limit Geräte ab.';
  }

  @override
  String devicesLicenseCoversUsed(int limit, int used) {
    return 'Deine Lizenz deckt $limit Geräte ab. $used in Benutzung.';
  }

  @override
  String get aboutTagline =>
      'Mit Privatsphäre im Sinn gebaut.\nKein Tracking. Keine Werbung. Nur du.';

  @override
  String get aboutWebsite => 'Webseite';

  @override
  String get aboutSupport => 'Support';

  @override
  String get aboutAddress => 'Adresse';

  @override
  String get aboutOpenSource => 'Quelloffen';

  @override
  String get aboutEdition => 'Edition';

  @override
  String aboutFreeSoftware(String name) {
    return '$name · freie Software';
  }

  @override
  String get aboutLicense => 'Lizenz';

  @override
  String get aboutSourceCode => 'Quellcode';

  @override
  String get aboutCopyLink => 'Link kopieren';

  @override
  String get aboutSourceLink => 'Quell-Link';

  @override
  String get aboutThirdParty => 'Lizenzen Dritter';

  @override
  String aboutCopied(String what) {
    return '$what kopiert.';
  }

  @override
  String get aboutFreeBuildNote =>
      'Dieser Build enthält keinen proprietären Code und lässt sich aus dem Quellcode oben reproduzieren. Nichts davon muss man glauben — bau ihn selbst und vergleiche.';

  @override
  String get aboutStoreBuildNote =>
      'Dieser Build stammt aus einem App-Store und bindet dessen Dienste ein. Der Libre-Build, im Quellcode oben, enthält keinen davon.';

  @override
  String get blockedUnblock => 'Entsperren';

  @override
  String blockedUnblockTitle(String name) {
    return '$name entsperren?';
  }

  @override
  String get blockedUnblockBody =>
      'Diese Person kann dir wieder Nachrichten schicken.';

  @override
  String get blockedInvisibleNote =>
      'Blockieren ist unsichtbar: Ihre Nachrichten werden verworfen und sie erfahren nichts, eine Blockade lässt sich also nicht nutzen, um herauszufinden, dass man blockiert wurde.';

  @override
  String get blockedNobody => 'Niemand ist blockiert';

  @override
  String get blockedEmptyNote =>
      'Blockiere jemanden aus dem Chat heraus, dann taucht die Person hier auf.';
}
