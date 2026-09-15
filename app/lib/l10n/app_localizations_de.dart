// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppTextDe extends AppText {
  @override
  String get proxyTitle => "SOCKS5-Proxy";
  @override
  String get proxyEnable => "Proxy verwenden";
  @override
  String get proxyHost => "Server (Hostname oder IP)";
  @override
  String get proxyPort => "Port";
  @override
  String get proxyUsername => "Benutzername (optional)";
  @override
  String get proxyPassword => "Passwort (optional)";
  @override
  String get proxyScope => "Gilt für dieses Gerät: Anmeldung, Nachrichten, Medien und Sicherungen. Anrufe sind bei aktivem Proxy gesperrt. Kein automatischer Direktzugriff. Änderungen mit Speichern übernehmen.";
  @override
  String get proxyPrivacy => "System-Push und im Browser geöffnete Links nutzen diesen Proxy nicht. SOCKS5 verschlüsselt die Proxy-Zugangsdaten nicht; verwende ein vertrauenswürdiges Netz und einen vertrauenswürdigen Proxy. Der Proxy sieht deine IP und das Verbindungsziel; HTTPS bleibt verschlüsselt. Telegram-MTProto-Proxys werden nicht unterstützt.";
  @override
  String get proxyTest => "Verbindung testen";
  @override
  String get proxySave => "Speichern";
  @override
  String get proxyRemove => "Proxy entfernen und direkt verbinden";
  @override
  String get proxyInvalid => "Gültigen Server und Port (1–65535) eingeben. Benutzername und Passwort gemeinsam ausfüllen oder beide leer lassen.";
  @override
  String get proxyTestSuccess => "Privio ist über diesen Proxy erreichbar. Die Einstellungen sind noch nicht gespeichert.";
  @override
  String get proxySaved => "Netzwerkeinstellungen gespeichert.";
  @override
  String get proxyFailed => "Aktion fehlgeschlagen. Proxy, Zugangsdaten und Verbindung prüfen und laufende Anrufe beenden. Kein automatischer Direktzugriff.";
  @override
  String get proxyCallsBlocked => "Anrufe sind bei aktivem Proxy nicht verfügbar.";
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
      'Ton, Vibration, das Licht und ob auf dem Sperrbildschirm etwas erscheint, gehören zu den Einstellungen deines Telefons für Privio, nicht auf diesen Bildschirm.';

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
  String get privacyScreenShield => 'Bildschirmschutz';

  @override
  String get privacyScreenShieldAndroid =>
      'Blockiert Screenshots und Bildschirmaufnahmen der App.';

  @override
  String get privacyScreenShieldIos =>
      'Verbirgt sensible Inhalte bei erkennbarer Bildschirmaufnahme oder Bildschirmübertragung. Screenshots können auf iOS nicht zuverlässig verhindert werden.';

  @override
  String get privacyScreenShieldUnavailable =>
      'Dieses Gerät kann den Bildschirm nicht schützen.';

  @override
  String get privacyScreenShieldScope =>
      'Das schützt nur dein eigenes Gerät. Es verhindert keine Aufnahmen auf den Geräten anderer Teilnehmer und kein Foto mit einer externen Kamera.';

  @override
  String get privacyScreenShieldCovering =>
      'Eine Bildschirmaufnahme läuft. Privio ist verborgen, bis sie endet.';

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

  @override
  String get chatsSectionChats => 'Chats';

  @override
  String get chatsSectionMessages => 'Nachrichten';

  @override
  String get chatsYouPrefix => 'Du: ';

  @override
  String get chatsNoSearchResults =>
      'Hier passt nichts. Gefragt wurde nur dieses Gerät — der Server hält Nachrichten, die er nicht lesen kann, er hätte also gar nicht antworten können.';

  @override
  String get chatsFilterAll => 'Alle';

  @override
  String get chatsJoin => 'Beitreten';

  @override
  String get chatsFilterUnread => 'Ungelesen';

  @override
  String get chatsFilterGroups => 'Gruppen';

  @override
  String get chatsPin => 'Oben anheften';

  @override
  String get chatsUnpin => 'Lösen';

  @override
  String get chatsPinNote => 'Nur auf diesem Gerät. Es wird nichts gesendet.';

  @override
  String get chatsGroupFallbackName => 'Gruppe';

  @override
  String get chatsNewGroupTooltip => 'Neue Gruppe';

  @override
  String get chatsNewChatTooltip => 'Neuer Chat';

  @override
  String get chatsEmptyTitle => 'Noch keine Chats';

  @override
  String get chatsEmptyBody =>
      'Füge jemanden über den genauen Benutzernamen hinzu, um loszulegen.';

  @override
  String get chatsAddContact => 'Kontakt hinzufügen';

  @override
  String get commonGotIt => 'Verstanden';

  @override
  String get commonPause => 'Pause';

  @override
  String get commonPlay => 'Abspielen';

  @override
  String get commonOpen => 'Öffnen';

  @override
  String get commonReply => 'Antworten';

  @override
  String get commonFile => 'Datei';

  @override
  String get scrubRemoved => 'Metadaten entfernt';

  @override
  String get scrubNothingToRemove => 'Nichts zu entfernen';

  @override
  String get scrubCouldNotClean => 'Konnte nicht bereinigt werden';

  @override
  String get scrubRemovedBody =>
      'Das wurde entfernt, bevor die Datei verschlüsselt und gesendet wurde. Die empfangende Person bekommt es nie.';

  @override
  String get scrubNothingBody =>
      'Diese Datei enthielt von vornherein keine identifizierenden Metadaten.';

  @override
  String scrubNoCleanerBody(String type) {
    return 'Privio hat noch keinen Reiniger für $type, die Datei wurde also unverändert gesendet. Sie ist weiterhin Ende-zu-Ende verschlüsselt, aber alle Metadaten darin erreichen die empfangende Person.';
  }

  @override
  String get webStorageShort =>
      'Im Browser ist der Verlauf dieses Geräts nur so privat wie dieses Browserprofil. Nachrichten unterwegs sind so oder so verschlüsselt.';

  @override
  String get webStorageLong =>
      'Du benutzt Privio in einem Browser. Nachrichten sind unterwegs weiterhin Ende-zu-Ende verschlüsselt — aber ein Browser hat keinen Schlüsselspeicher, der auf diesem Gerät gehaltene Verlauf ist also nur so privat wie dieses Browserprofil. Wer es lesen kann — ein gemeinsam genutzter Computer, eine Erweiterung, eine Kopie des Profils — kann deine Chats lesen. Die Telefon-Apps haben dieses Problem nicht.';

  @override
  String get voiceCouldNotOpen => 'Diese Aufnahme ließ sich nicht öffnen.';

  @override
  String get voiceCannotPlay =>
      'Dieses Gerät kann diese Aufnahme nicht abspielen.';

  @override
  String get voiceMicUnavailable => 'Das Mikrofon ist gerade nicht verfügbar.';

  @override
  String get voiceCouldNotSave =>
      'Diese Aufnahme konnte nicht gespeichert werden.';

  @override
  String get voiceSlideToCancel => 'Zum Abbrechen wischen';

  @override
  String get voiceResume => 'Fortsetzen';

  @override
  String get voiceStop => 'Stopp';

  @override
  String get voiceDeleteRecording => 'Aufnahme löschen';

  @override
  String get voiceListenBack => 'Anhören';

  @override
  String get bubbleYouDeleted => 'Du hast diese Nachricht gelöscht';

  @override
  String get bubbleMessageDeleted => 'Diese Nachricht wurde gelöscht';

  @override
  String get bubbleCouldNotOpen => 'Konnte nicht geöffnet werden';

  @override
  String get bubbleEncryptedNotice =>
      'Nachrichten und Anrufe sind Ende-zu-Ende verschlüsselt. Niemand außerhalb dieses Chats kann sie lesen oder mithören, auch Privio nicht.';

  @override
  String get linkNotWebAddress => 'Dieser Link ist keine Webadresse.';

  @override
  String get linkNothingCanOpen =>
      'Auf diesem Gerät konnte nichts diesen Link öffnen.';

  @override
  String get linkOpenTitle => 'Diesen Link öffnen?';

  @override
  String get linkOpenBody =>
      'Das öffnet sich in deinem Browser, außerhalb von Privio. Die Seite sieht deine Verbindung so, wie es jede besuchte Seite tut.';

  @override
  String timerBadgeDays(int count) {
    return '$count T';
  }

  @override
  String timerBadgeHours(int count) {
    return '$count Std';
  }

  @override
  String timerBadgeMinutes(int count) {
    return '$count Min';
  }

  @override
  String timerBadgeSeconds(int count) {
    return '$count Sek';
  }

  @override
  String get chatSafetyNumberChanged => 'Sicherheitsnummer geändert';

  @override
  String get chatEncrypted => 'Ende-zu-Ende verschlüsselt';

  @override
  String get chatEncryptedVerified => 'Ende-zu-Ende verschlüsselt · bestätigt';

  @override
  String get chatEncryptedNumberChanged =>
      'Ende-zu-Ende verschlüsselt · Nummer geändert';

  @override
  String get chatWaitingGroupKey => 'Warte auf den Gruppenschlüssel';

  @override
  String chatMembersEncrypted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Mitglieder',
      one: '1 Mitglied',
    );
    return '$_temp0 · verschlüsselt';
  }

  @override
  String get chatRetrySendTitle => 'Erneut versuchen';

  @override
  String get chatRetryFailed => 'Sie ging nicht raus. Jetzt senden.';

  @override
  String get chatRetryQueued =>
      'Wartet auf ein Netz. Trotzdem jetzt versuchen.';

  @override
  String get chatCopyText => 'Text kopieren';

  @override
  String get chatDeleteForMe => 'Für mich löschen';

  @override
  String get chatDeleteForMeNote =>
      'Weg von diesem Gerät. Andere Geräte behalten sie.';

  @override
  String get chatDeleteForEveryone => 'Für alle löschen';

  @override
  String get chatDeleteForEveryoneNote =>
      'Bittet ihre App, sie zu vergessen. Es kann nicht zurückholen, was schon gelesen, abfotografiert oder aus einer Sicherung wiederhergestellt wurde.';

  @override
  String get chatPickerNoResponse => 'Die Dateiauswahl hat nicht geantwortet.';

  @override
  String chatPickerFailed(String reason) {
    return 'Die Dateiauswahl ließ sich nicht öffnen: $reason';
  }

  @override
  String chatCouldNotReadFile(String name) {
    return '$name ließ sich nicht lesen.';
  }

  @override
  String chatBlockTitle(String name) {
    return '$name blockieren?';
  }

  @override
  String get chatBlockBody =>
      'Ihre Nachrichten kommen nicht mehr an. Sie erfahren nichts davon, und für sie sieht es aus, als hätte sich nichts geändert. Du kannst es unter Privatsphäre & Sicherheit aufheben.';

  @override
  String get chatBlock => 'Blockieren';

  @override
  String chatBlocked(String name) {
    return '$name ist blockiert.';
  }

  @override
  String get chatCouldNotBlock => 'Blockieren war nicht möglich.';

  @override
  String get chatMicrophoneDenied =>
      'Privio kann ohne Mikrofonzugriff nicht aufnehmen. Du kannst ihn in den Geräteeinstellungen erteilen.';

  @override
  String get chatNoGroupLink =>
      'Noch kein Link für diese Gruppe — zum Aktualisieren ziehen.';

  @override
  String get chatInviteLink => 'Einladungslink';

  @override
  String get chatInviteLinkNote =>
      'Teile ihn überall — er trägt keinen Schlüssel. Wer ihn öffnet, tritt der Gruppe bei, und der Schlüssel zu ihrem Namen erreicht das Gerät verschlüsselt.';

  @override
  String get chatTyping => 'tippt …';

  @override
  String get chatVideoCall => 'Videoanruf';

  @override
  String get chatVoiceCall => 'Sprachanruf';

  @override
  String get chatMore => 'Mehr';

  @override
  String get chatGroupInfo => 'Gruppeninfo';

  @override
  String get chatSafetyNumber => 'Sicherheitsnummer';

  @override
  String get chatActivate => 'Aktivieren';

  @override
  String get chatSend => 'Senden';

  @override
  String get chatHoldToRecord =>
      'Halte das Mikrofon gedrückt, um eine Sprachnachricht aufzunehmen.';

  @override
  String get chatReplyingToYourself => 'Antwort auf dich selbst';

  @override
  String chatReplyingTo(String name) {
    return 'Antwort an $name';
  }

  @override
  String get chatReplying => 'Antwort';

  @override
  String get chatCancelReply => 'Antwort verwerfen';

  @override
  String get contactsTitle => 'Kontakte';

  @override
  String get contactsSearch => 'Kontakte durchsuchen';

  @override
  String contactsLastSeen(String username, String when) {
    return '@$username · zuletzt online $when';
  }

  @override
  String get contactsSeenJustNow => 'gerade eben';

  @override
  String contactsSeenMinutes(int count) {
    return 'vor $count Min.';
  }

  @override
  String contactsSeenAtTime(String time) {
    return 'um $time';
  }

  @override
  String contactsSeenDays(int count) {
    return 'vor $count T.';
  }

  @override
  String get contactsCouldNotAdd => 'Diese Person ließ sich nicht hinzufügen';

  @override
  String get contactsAddTitle => 'Kontakt hinzufügen';

  @override
  String get contactsAddNote =>
      'Gib den genauen Privio-Benutzernamen ein. Aus deinem Adressbuch wird nichts hochgeladen, und niemand kann dich durch Stöbern finden.';

  @override
  String get contactsUsernameHint => 'Benutzername';

  @override
  String get contactsEmptyTitle => 'Noch keine Kontakte';

  @override
  String get contactsEmptyBody =>
      'Füge jemanden über den genauen Benutzernamen hinzu oder teile deinen Einladungslink aus dem Konto-Tab.';

  @override
  String get groupCouldNotCreate => 'Die Gruppe ließ sich nicht erstellen';

  @override
  String get groupNewTitle => 'Neue Gruppe';

  @override
  String get groupCreate => 'Erstellen';

  @override
  String get groupName => 'Gruppenname';

  @override
  String get groupNameEncryptedNote =>
      'Der Name ist verschlüsselt. Privio speichert eine Gruppe, die es nicht benennen kann.';

  @override
  String get groupChooseMembers => 'Mitglieder wählen';

  @override
  String groupSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get groupAddContactsFirst =>
      'Füge erst Kontakte hinzu — eine Gruppe braucht Leute darin.';

  @override
  String get groupInfoCouldNotRead =>
      'Wer in dieser Gruppe ist, ließ sich nicht lesen.';

  @override
  String get groupAdminOnly => 'Nur ein Admin kann das ändern';

  @override
  String get groupRename => 'Gruppe umbenennen';

  @override
  String get groupRenameAction => 'Umbenennen';

  @override
  String get groupRenamed =>
      'Umbenannt. Alle anderen öffnen den neuen Namen mit dem Schlüssel, den sie schon haben.';

  @override
  String get groupCouldNotRename => 'Die Gruppe ließ sich nicht umbenennen.';

  @override
  String groupRemoveTitle(String name) {
    return '$name entfernen?';
  }

  @override
  String get groupRemoveBody =>
      'Sie bekommen ab jetzt nichts mehr, was gesendet wird. Was sie schon bekommen haben, bleibt auf ihrem Gerät — von hier aus ist das nicht erreichbar.';

  @override
  String get groupCouldNotRemove => 'Entfernen war nicht möglich.';

  @override
  String get groupLeaveTitle => 'Diese Gruppe verlassen?';

  @override
  String get groupLeaveBody =>
      'Du bekommst nichts mehr, was dorthin gesendet wird, und die Unterhaltung verschwindet mit allem darin von diesem Gerät. Niemand wird benachrichtigt; die anderen sehen dich aus der Mitgliederliste verschwinden.';

  @override
  String get groupLeave => 'Verlassen';

  @override
  String get groupLeaveRow => 'Gruppe verlassen';

  @override
  String get groupDeleteTitle => 'Diese Gruppe löschen?';

  @override
  String get groupDeleteBody =>
      'Sie verschwindet für alle: Niemand kann mehr dorthin senden. Was schon zugestellt wurde, bleibt auf den Geräten, die es empfangen haben — also jede Nachricht, die jemand gelesen hat.';

  @override
  String get groupDeleteRow => 'Gruppe für alle löschen';

  @override
  String get groupYouSuffix => 'Du';

  @override
  String get groupAdminSuffix => 'Admin';

  @override
  String get navChats => 'Chats';

  @override
  String get navChannels => 'Kanäle';

  @override
  String get navCalls => 'Anrufe';

  @override
  String get navContacts => 'Kontakte';

  @override
  String get navAccount => 'Konto';

  @override
  String get splashTagline => 'Sicherer Messenger';

  @override
  String get splashPromise => 'Verschlüsselt. Privat. Deins.';

  @override
  String get splashInitialising => 'Sichere Umgebung wird vorbereitet';

  @override
  String accountPickerFailed(String reason) {
    return 'Die Auswahl ließ sich nicht öffnen: $reason';
  }

  @override
  String accountCouldNotReadFile(String name, String reason) {
    return '$name ließ sich nicht lesen: $reason';
  }

  @override
  String get accountCouldNotSetPicture => 'Das Bild ließ sich nicht setzen';

  @override
  String get accountTapToAddPicture => 'Antippen, um ein Bild hinzuzufügen';

  @override
  String get accountPictureEncrypted =>
      'Verschlüsselt — nur deine Kontakte sehen es';

  @override
  String get accountUsername => 'Benutzername';

  @override
  String get accountStatus => 'Status';

  @override
  String get accountStatusDefault => 'Hallo! Ich benutze Privio.';

  @override
  String get accountStatusNone => 'Nicht gesetzt';

  @override
  String get accountStatusTitle => 'Status';

  @override
  String get accountStatusHint => 'Was machst du gerade?';

  @override
  String get accountStatusEmoji => 'Emoji';

  @override
  String get accountStatusEmojiNone => 'Keins';

  @override
  String get accountStatusClearsAfter => 'Verschwindet nach';

  @override
  String get accountStatusNeverClears => 'Nie';

  @override
  String get accountStatus30Minutes => '30 Minuten';

  @override
  String get accountStatus1Hour => '1 Stunde';

  @override
  String get accountStatus4Hours => '4 Stunden';

  @override
  String get accountStatusToday => 'Heute';

  @override
  String get accountStatus1Week => '1 Woche';

  @override
  String accountStatusUntil(String time) {
    return 'Bis $time';
  }

  @override
  String get accountStatusCouldNotSave =>
      'Dein Status wurde nicht gespeichert. Was du geschrieben hast, steht noch da — versuche es erneut.';

  @override
  String get accountStatusSaving => 'Wird gespeichert…';

  @override
  String get accountStatusExplainer =>
      'Wer deinen Status sehen darf, liest das hier. Er ist nicht so verschlüsselt wie deine Nachrichten, und er ist nicht deine Online-Anzeige.';

  @override
  String get privacyProfileStatus => 'Status';

  @override
  String get privacyProfileStatusEveryone => 'Alle';

  @override
  String get privacyProfileStatusContacts => 'Meine Kontakte';

  @override
  String get privacyProfileStatusNobody => 'Niemand';

  @override
  String get accountId => 'Konto-ID';

  @override
  String get accountInviteRow => 'Einladungslink / QR-Code';

  @override
  String get accountLogOut => 'Abmelden';

  @override
  String get accountLogOutQuestion => 'Abmelden?';

  @override
  String get accountLogOutBody =>
      'Deine Nachrichten bleiben auf diesem Gerät verschlüsselt, bis du sie löschst. Zum erneuten Anmelden brauchst du dein Passwort.';

  @override
  String get accountDelete => 'Konto löschen';

  @override
  String get accountDeleteTitle => 'Dieses Konto löschen?';

  @override
  String get accountDeleteBody =>
      'Deine Geräte, deine Schlüssel, die noch auf Zustellung wartenden Nachrichten, deine Kontakte, deine Gruppenmitgliedschaften und deine Sicherung werden alle auf dem Server gelöscht. Alles auf diesem Telefon geht mit.\n\nEs erreicht nicht, was andere schon empfangen haben, und dein Benutzername wird frei für jemand anderen.\n\nEs gibt kein Zurück und keine Wiederherstellung — nicht mit dem Wiederherstellungsschlüssel, nicht durch Anschreiben irgendeiner Stelle.';

  @override
  String get accountYourPassword => 'Dein Passwort';

  @override
  String get accountDeleteIt => 'Löschen';

  @override
  String get inviteTitle => 'Einladen';

  @override
  String get inviteTabLink => 'Einladungslink';

  @override
  String get inviteTabQr => 'QR-Code';

  @override
  String get inviteYourLink => 'Dein Einladungslink';

  @override
  String get inviteCopied => 'Einladungslink kopiert';

  @override
  String get inviteCopyLink => 'Link kopieren';

  @override
  String get inviteCopyInviteLink => 'Einladungslink kopieren';

  @override
  String get inviteNote =>
      'Teile diesen Link, um andere zu Privio einzuladen. Er verrät deinen Benutzernamen und sonst nichts.';

  @override
  String inviteScanToConnect(String username) {
    return 'Scannen, um sich mit @$username zu verbinden';
  }

  @override
  String get callsClearHistory => 'Anrufliste leeren';

  @override
  String get callsClearTitle => 'Anrufliste leeren?';

  @override
  String get callsClearBody =>
      'Diese Liste liegt nur auf diesem Gerät — sie zu leeren entfernt sie von hier und von sonst nirgends, weil sie nie woanders war.';

  @override
  String get callsClear => 'Leeren';

  @override
  String get callsNeverLeavesNote =>
      'Diese Liste verlässt das Gerät nie. Der Server leitet den Aufbau eines Anrufs weiter wie eine Nachricht — versiegelt und für ihn unlesbar — er hält also keine Aufzeichnung darüber, wer wen angerufen hat.';

  @override
  String callsCallSomeone(String name) {
    return '$name anrufen';
  }

  @override
  String get callsDeclined => 'Abgelehnt';

  @override
  String get callsNotTaken => 'Nicht angenommen';

  @override
  String get callsBusy => 'Besetzt';

  @override
  String get callsCouldNotConnect => 'Verbindung nicht möglich';

  @override
  String get callsMissed => 'Verpasst';

  @override
  String get callsNoAnswer => 'Keine Antwort';

  @override
  String get callsEmptyTitle => 'Noch keine Anrufe';

  @override
  String get callsEmptyBody =>
      'Starte einen aus einem Chat heraus. Der Anruf wird über die Signal-Sitzung aufgebaut, die dieser Chat ohnehin nutzt, die Adressen, die eure beiden Geräte zum Finden austauschen, sind also füreinander versiegelt und nicht für den Server.';

  @override
  String get callCalling => 'Ruft an …';

  @override
  String get callIncomingVideo => 'Eingehender Videoanruf';

  @override
  String get callIncoming => 'Eingehender Anruf';

  @override
  String get callConnecting => 'Verbinde …';

  @override
  String get callEnded => 'Anruf beendet';

  @override
  String get callDecline => 'Ablehnen';

  @override
  String get callAccept => 'Annehmen';

  @override
  String get callMute => 'Stumm';

  @override
  String get callUnmute => 'Ton an';

  @override
  String get callCamera => 'Kamera';

  @override
  String get callCameraOff => 'Kamera aus';

  @override
  String get callEnd => 'Beenden';

  @override
  String get callSpeaker => 'Lautsprecher';

  @override
  String get welcomePromiseEncrypted => 'Ende-zu-Ende verschlüsselt';

  @override
  String get welcomePromiseNoPhone => 'Keine Telefonnummer nötig';

  @override
  String get welcomePromiseControl => 'Du hast die Kontrolle';

  @override
  String get welcomePromiseByDesign => 'Datenschutz von Grund auf';

  @override
  String get welcomeTo => 'Willkommen bei';

  @override
  String get welcomeGetStarted => 'Loslegen';

  @override
  String get welcomeHaveAccount => 'Ich habe schon ein Konto';

  @override
  String get welcomeImportBackup => 'Aus Sicherung importieren';

  @override
  String get authCreateTitle => 'Konto erstellen';

  @override
  String get authWelcomeBack => 'Willkommen zurück';

  @override
  String get authCreateNote =>
      'Wähle einen Benutzernamen. Keine Telefonnummer, keine E-Mail — nichts, was dieses Konto mit etwas anderem verbindet.';

  @override
  String get authSignInNote => 'Melde dich mit Benutzername und Passwort an.';

  @override
  String get authUsernameRule =>
      '3–32 Zeichen: a–z, 0–9, Punkt oder Unterstrich';

  @override
  String get authPasswordRule => 'Mindestens 10 Zeichen — dieses schützt alles';

  @override
  String get authPasswordRequired => 'Gib dein Passwort ein';

  @override
  String get authTotpHint => 'Zwei-Faktor-Code';

  @override
  String get authCreateAccount => 'Konto erstellen';

  @override
  String get authSignIn => 'Anmelden';

  @override
  String get authCreateNew => 'Neues Konto erstellen';

  @override
  String get authPasswordOnlyWay =>
      'Dein Passwort ist der einzige Weg in dieses Konto. Privio kann es nicht zurücksetzen, weil Privio nichts lesen kann, was es aufschließen würde.';

  @override
  String get pinEnterPassphrase => 'Passphrase eingeben';

  @override
  String get pinEnterPasscode => 'Code eingeben';

  @override
  String get pinPassphrase => 'Passphrase';

  @override
  String get pinWrong => 'Das ist es nicht.';

  @override
  String get pinUnlock => 'Entsperren';

  @override
  String get activationTitle => 'Privio aktivieren';

  @override
  String get activationSignedInNote =>
      'Dein Konto ist bereit. Dieser Server verlangt einen Lizenzschlüssel, bevor er deine Nachrichten weiterleitet.';

  @override
  String get activationNewNote =>
      'Dieser Server verlangt einen Lizenzschlüssel, bevor er Nachrichten weiterleitet. Gib deinen jetzt ein, dann wird er aktiviert, sobald dein Konto existiert.';

  @override
  String get activationActivate => 'Aktivieren';

  @override
  String get activationNoKeyYet => 'Ich habe noch keinen Schlüssel';

  @override
  String get activationWithoutKeyNote =>
      'Ohne Schlüssel kannst du ein Konto anlegen, dich anmelden und Eingehendes lesen, aber nicht senden. Du kannst ihn später unter Einstellungen › Privio-Lizenz eingeben.';

  @override
  String activationFreeSoftwareNote(String name, String license) {
    return '$name ist freie Software unter $license. Der Schlüssel schaltet die App nicht frei — du hast sie bereits vollständig und kannst sie selbst bauen. Er bezahlt den gehosteten Dienst, der deine Nachrichten weiterleitet.';
  }

  @override
  String get backupCouldNotReach =>
      'Privio war nicht erreichbar, um die Sicherung zu prüfen.';

  @override
  String get backupDone => 'Gesichert. Privio kann sie nicht lesen.';

  @override
  String get backupUploadFailed =>
      'Die Sicherung konnte nicht hochgeladen werden.';

  @override
  String get backupBadKey =>
      'Das sieht nicht nach einem Wiederherstellungsschlüssel aus.';

  @override
  String backupRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Unterhaltungen wiederhergestellt.',
      one: '1 Unterhaltung wiederhergestellt.',
    );
    return '$_temp0';
  }

  @override
  String get backupKeyDidNotOpen =>
      'Dieser Schlüssel hat die Sicherung nicht geöffnet, oder es gibt keine zu öffnen.';

  @override
  String get backupLast => 'Letzte Sicherung';

  @override
  String get backupOnServer => 'Auf dem Server';

  @override
  String get backupNothingYet => 'Noch nichts';

  @override
  String get backupAlways => 'Immer';

  @override
  String get backupNow => 'Jetzt sichern';

  @override
  String get backupAutomatic => 'Automatische Sicherung';

  @override
  String get backupIntervalDaily => 'Täglich';

  @override
  String get backupIntervalWeekly => 'Wöchentlich';

  @override
  String get backupRecoveryKey => 'Wiederherstellungsschlüssel';

  @override
  String get backupRestoreRow => 'Aus Sicherung wiederherstellen';

  @override
  String get backupSealedNote =>
      'Sicherungen werden auf diesem Gerät mit deinem Wiederherstellungsschlüssel versiegelt. Privio kann sie nicht öffnen und den Schlüssel nicht zurücksetzen — wenn du ihn verlierst, ist die Sicherung weg. Schreib ihn an einem sicheren Ort auf.\n\nEine Sicherung enthält deine Unterhaltungen, nicht deine Schlüssel: Wiederherstellen auf einem neuen Gerät gibt dir deinen Verlauf, und dieses Gerät richtet für alles Weitere seine eigene Identität ein.';

  @override
  String get backupNever => 'Nie';

  @override
  String backupToday(String time) {
    return 'Heute, $time';
  }

  @override
  String get backupWriteItDown =>
      'Schreib das auf. Es ist das Einzige, was deine Sicherungen öffnet, und niemand — auch Privio nicht — kann es dir noch einmal erzeugen.';

  @override
  String get backupRestoreReplacesNote =>
      'Das ersetzt alles auf diesem Gerät durch das, was in der Sicherung steht.';

  @override
  String get backupRestore => 'Wiederherstellen';

  @override
  String get twoFactorOnToast =>
      'Zwei-Faktor ist an. Bewahre die Wiederherstellung deiner Authenticator-App sicher auf.';

  @override
  String get twoFactorOffToast => 'Zwei-Faktor ist aus.';

  @override
  String get twoFactorTurnOffTitle => 'Zwei-Faktor ausschalten';

  @override
  String get twoFactorTurnOff => 'Ausschalten';

  @override
  String get twoFactorTurnOn => 'Einschalten';

  @override
  String get twoFactorServerNote =>
      'Der Code wird beim Anmelden auf dem Server geprüft. Er schützt das Konto selbst — wer dein Passwort erfährt, kann trotzdem kein neues Gerät anmelden. Er verschlüsselt nicht deine Nachrichten: Das tut der Schlüssel auf diesem Gerät, und kein Code kann ihn ersetzen.';

  @override
  String get twoFactorOffBody =>
      'Mit Zwei-Faktor braucht das Anmelden zusätzlich zum Passwort einen sechsstelligen Code aus deiner Authenticator-App.';

  @override
  String get twoFactorSetUp => 'Einrichten';

  @override
  String get twoFactorScanThis => 'Das hier scannen';

  @override
  String get twoFactorScanNote =>
      'Füge es deiner Authenticator-App hinzu und tippe dann den angezeigten Code ein. Zwei-Faktor ist erst an, wenn dieser Code geprüft wurde.';

  @override
  String get twoFactorTypeKey => 'Oder diesen Schlüssel eintippen';

  @override
  String get twoFactorKeyCopied => 'Schlüssel kopiert.';

  @override
  String get twoFactorOnBody =>
      'Beim Anmelden wird ein Code aus deiner Authenticator-App verlangt.';

  @override
  String get passcodeFourDigits => '4 Ziffern';

  @override
  String get passcodeSixDigits => '6 Ziffern';

  @override
  String get passcodeFourDigitsNote =>
      'Zehntausend Kombinationen. Schnell, und genug gegen jemanden, der das Telefon aufhebt.';

  @override
  String get passcodeSixDigitsNote =>
      'Eine Million Kombinationen, und immer noch ein Ziffernblock.';

  @override
  String get passcodePhraseNote =>
      'Buchstaben, dazu Ziffern oder Zeichen, wenn du magst. Als einzige der drei hält sie jemandem stand, der das Telefon und Zeit hat.';

  @override
  String get passcodeNeedsFourDigits => 'Vier Ziffern.';

  @override
  String get passcodeNeedsSixDigits => 'Sechs Ziffern.';

  @override
  String passcodePhraseTooShort(int count) {
    return 'Mindestens $count Zeichen.';
  }

  @override
  String get passcodePhraseNeedsLetter =>
      'Eine Passphrase braucht mindestens einen Buchstaben. Ziffern und Zeichen sind daneben willkommen.';

  @override
  String get lockEntriesDiffer => 'Die beiden Eingaben sind nicht gleich.';

  @override
  String get lockOnToast =>
      'App-Sperre an. Privio fragt danach, wenn es zurückkommt.';

  @override
  String get lockOffToast => 'App-Sperre aus.';

  @override
  String get lockTurnOffTitle => 'App-Sperre ausschalten?';

  @override
  String get lockTurnOffBody =>
      'Wer ein entsperrtes Telefon in der Hand hält, kommt an deine Nachrichten. Ein für den Sperrbildschirm gesetzter Notfallcode wird mit entfernt.';

  @override
  String get lockTurnOffRow => 'App-Sperre ausschalten';

  @override
  String get lockWhatItIsNote =>
      'Ein Code auf diesem Gerät, der abgefragt wird, sobald Privio wieder in den Vordergrund kommt. Er ist nicht dein Kontopasswort und verlässt das Telefon nie — er schützt den darauf bereits verschlüsselten Verlauf.';

  @override
  String get lockNoBiometricsNote =>
      'Es gibt keine Gesichts- oder Fingerabdruckoption. Das sind die einzigen Merkmale, für die jemand dir ein Telefon vors Gesicht halten oder deinen Finger im Schlaf darauflegen kann — und an mehreren Orten kann ein Gericht sie anordnen, wo es einen Code nicht anordnen kann.';

  @override
  String get lockChangePasscode => 'Code ändern';

  @override
  String get lockChoosePasscode => 'Code wählen';

  @override
  String get lockAgain => 'Noch einmal';

  @override
  String get lockChangeIt => 'Ändern';

  @override
  String get lockTurnItOn => 'Einschalten';

  @override
  String get lockForgettingNote =>
      'Ihn zu vergessen bedeutet, sich neu anzumelden, was für den Server ein neues Gerät ist: Was hier schon zugestellt wurde, ist weg, wenn es nicht in einer Sicherung liegt. Es gibt kein Zurücksetzen, denn ein Zurücksetzen, das jeder verlangen könnte, wäre keine Sperre.';

  @override
  String get duressNoLockNote =>
      'Am Sperrbildschirm bewirkt er noch nichts, weil es auf diesem Gerät keine App-Sperre gibt. Schalte eine unter Bildschirmsperre ein, dann wirkt ein Notfallcode in der Form dieser Sperre auch dort — und genau dort wird ein bereits angemeldetes Telefon weggenommen.';

  @override
  String duressShapeNote(String kind) {
    return 'Dieses Gerät entsperrt mit $kind. Ein Notfallcode derselben Form kann am Sperrbildschirm eingegeben werden, wo er zerstört statt zu entsperren. Jede andere Form wirkt nur bei der Anmeldung.';
  }

  @override
  String get duressMatchesLock =>
      'Dieser passt zur Sperre auf diesem Gerät, er wirkt also am Sperrbildschirm wie bei der Anmeldung.';

  @override
  String duressDoesNotMatchLock(String kind) {
    return 'Dieser passt nicht zur Sperre auf diesem Gerät ($kind), er wirkt also nur bei der Anmeldung — am Sperrbildschirm gibt es kein Feld dafür.';
  }

  @override
  String get duressAtLeastFour => 'Verwende mindestens vier Zeichen.';

  @override
  String get duressCodesDiffer => 'Die beiden Codes sind nicht gleich.';

  @override
  String get duressSameAsUnlock =>
      'Das ist der Code, der dieses Gerät entsperrt. Ein Notfallcode muss anders sein: Der Sperrbildschirm prüft ihn zuerst, wären beide gleich, würde jedes Entsperren das Konto zerstören — ohne es zu sagen.';

  @override
  String get duressSetBoth =>
      'Notfallcode gesetzt. Er zerstört das Konto bei der Anmeldung und am Sperrbildschirm.';

  @override
  String get duressSetSignInOnly =>
      'Notfallcode gesetzt. Ihn bei der Anmeldung einzugeben zerstört das Konto.';

  @override
  String get duressRemoved => 'Notfallcode entfernt.';

  @override
  String get duressRemoveTitle => 'Notfallcode entfernen';

  @override
  String get duressWarning =>
      'Diesen Code statt deines Passworts bei der Anmeldung einzugeben zerstört das Konto: jedes Gerät, jede noch wartende Nachricht, deine Kontakte, deine Gruppenmitgliedschaften, deine Sicherung. Es gibt kein Zurück und keine Bestätigung — das ist der Sinn.';

  @override
  String get duressIsSet => 'Ein Notfallcode ist gesetzt';

  @override
  String get duressCannotShow =>
      'Privio kann ihn dir nicht zeigen — er ist gespeichert wie ein Passwort. Einen neuen unten zu setzen ersetzt ihn.';

  @override
  String get duressRemoveIt => 'Entfernen';

  @override
  String get duressReplaceIt => 'Ersetzen';

  @override
  String get duressSetOne => 'Notfallcode setzen';

  @override
  String get duressAccountPassword => 'Dein Privio-Kontopasswort';

  @override
  String get duressLooksLikePin =>
      'Das ist kürzer als ein Kontopasswort. Dieses Feld will das Passwort, das du bei der Kontoerstellung gewählt hast — nicht die PIN, die die App entsperrt.';

  @override
  String get duressCodeField => 'Notfallcode';

  @override
  String get duressCodeAgain => 'Notfallcode wiederholen';

  @override
  String get duressReplaceCode => 'Code ersetzen';

  @override
  String get duressSetCode => 'Code setzen';

  @override
  String get duressWhatItDoesNotDo =>
      'Was er nicht tut: Der Kontoname bleibt vergeben, niemand kann ihn danach beanspruchen, und er erreicht kein anderes Gerät, das anderswo schon angemeldet ist. Wer zusieht, sieht den Versuch genauso abgelehnt wie ein falsch getipptes Passwort oder eine falsche PIN.';

  @override
  String get disguiseIntro =>
      'Ein gesperrtes Privio öffnet sich als funktionierender Taschenrechner statt als Sperrbildschirm. Jede Rechnung, die deinen Code ergibt, öffnet Privio, wenn du = drückst — der Code selbst muss also nie auf dem Bildschirm erscheinen. Jede andere Rechnung ist einfach eine Rechnung.';

  @override
  String get disguiseOpenTo => 'Öffnen als';

  @override
  String get disguiseLockScreen => 'Den Sperrbildschirm';

  @override
  String disguiseCalculatorNamed(String name) {
    return 'Taschenrechner ($name)';
  }

  @override
  String get disguisePickNote =>
      'Wähle die, die dein Telefon ohnehin mitbringt. Ein Taschenrechner, der nicht wie der übliche aussieht, ist genau das, was jemandem auffällt.';

  @override
  String get disguiseSeeIt => 'Ansehen';

  @override
  String disguiseErrorSuffix(String reason) {
    return '$reason Der Sperrbildschirm hat sich trotzdem geändert; der Startbildschirm nicht.';
  }

  @override
  String get disguiseNoLock =>
      'Auf diesem Gerät gibt es noch keine Bildschirmsperre, es gibt also keinen Code, den man in einen Taschenrechner tippen könnte.';

  @override
  String get disguisePhraseLock =>
      'Deine Bildschirmsperre ist eine Passphrase. Ein Taschenrechner hat zehn Tasten und keine Buchstaben, sie lässt sich also nicht eingeben. Stelle die Sperre auf 4 oder 6 Ziffern um, damit eine Tarnung möglich ist.';

  @override
  String get disguiseOnHomeScreen => 'Auf dem Startbildschirm';

  @override
  String get disguiseWhatItDoesNotDo => 'Was das nicht leistet';

  @override
  String get disguiseNotADefence =>
      'Es ist kein Schutz gegen jemanden, der das Telefon länger hat. Die App ist weiterhin installiert, und ihre Größe, ihre Dateien und ihr Netzwerkverkehr sind für jeden auffindbar, der richtig hinsieht. Gut ist sie im Alltagsfall — ein flüchtiger Blick auf den Bildschirm oder ein entsperrt weitergereichtes Telefon.';

  @override
  String get disguiseHomeScreenChanges =>
      'Auf dem Startbildschirm und in der App-Übersicht wird Privio zu einem Taschenrechner-Symbol namens „Rechner\". Dein Launcher braucht vielleicht ein paar Sekunden zum Neuzeichnen, und ein von dir selbst angeheftetes Symbol muss eventuell neu angeheftet werden. Die Tarnung auszuschalten setzt es zurück.\n\nAndroids eigene App-Liste — Einstellungen, App-Info, der Name bei einer Berechtigungsanfrage — sagt weiterhin Privio. Dieser Name wird beim Bauen der App festgelegt, und keine App kann ihn zur Laufzeit ändern.';

  @override
  String get disguiseIconUnchanged =>
      'Auf diesem Gerät ändern sich Symbol und Name nicht — nur das, worauf die App sich öffnet. Wer den Startbildschirm durchgeht, findet Privio weiterhin am Namen.';

  @override
  String get disguiseClosePreview => 'Vorschau schließen';

  @override
  String get licenseActivatedToast =>
      'Aktiviert. Diese Lizenz gehört jetzt zu deinem Konto.';

  @override
  String get licenseNotCheckedTitle => 'Noch nicht geprüft';

  @override
  String get licenseNotCheckedBody =>
      'Privio konnte den Server zu diesem Konto noch nicht fragen. Bring die App wieder online und öffne diesen Bildschirm erneut.';

  @override
  String get licenseNotNeededTitle => 'Hier ist keine Lizenz nötig';

  @override
  String get licenseNotNeededBody =>
      'Dieser Server verlangt keine. Lizenzen sind für den gehosteten Privio-Dienst da — eine Lizenz für Infrastruktur, die du selbst betreibst, würde nichts bedeuten.';

  @override
  String get licenseStoreTitle => 'Über den Store geregelt';

  @override
  String licenseStoreBody(String store) {
    return 'Dieser Build wurde über den App-Store bezahlt, aus dem er stammt, es gibt also keinen Schlüssel einzugeben. Wenn er nicht aktiv ist, stelle deinen Kauf in $store wieder her.';
  }

  @override
  String get licenseOnePurchaseNote =>
      'Ein Kauf, ein Schlüssel, ein Konto, für immer. Ein eingelöster Schlüssel ist an das einlösende Konto gebunden und kann nicht verschoben oder erneut benutzt werden.';

  @override
  String get licenseEnterTitle => 'Lizenzschlüssel eingeben';

  @override
  String get licenseEnterBody =>
      'Kauf einen Schlüssel auf getprivio.com/license und tippe ihn hier ein. Bis er aktiviert ist, kann sich dieses Konto anmelden und Eingegangenes lesen, aber nicht senden.';

  @override
  String get licenseActivated => 'Aktiviert';

  @override
  String licenseRedeemedOn(String date) {
    return 'Eingelöst am $date.';
  }

  @override
  String get licenseFromAppStore => 'Über den App Store gekauft.';

  @override
  String get licenseFromPlay => 'Über Google Play gekauft.';

  @override
  String get licenseFromKey =>
      'Mit einem Lizenzschlüssel aktiviert. Lebenslanger Zugang, keine Verlängerungen.';

  @override
  String get safetyTrustedToast =>
      'Der neue Schlüssel gilt als vertrauenswürdig. Vergleiche die Nummer noch einmal, bevor du dich darauf verlässt.';

  @override
  String get safetyMatches => 'Das stimmt mit einer der Nummern unten überein.';

  @override
  String get safetyNoMatch =>
      'Das stimmt mit keiner der Nummern unten überein.';

  @override
  String safetyNothingYet(String name) {
    return 'Es gibt noch nichts zu vergleichen. Eine Nummer entsteht, sobald du und $name eine Nachricht ausgetauscht habt, denn erst dann hat dieses Gerät einen Schlüssel von ihnen festgehalten.';
  }

  @override
  String safetyReadThese(String name) {
    return 'Lies $name diese Ziffern vor — am Telefon oder persönlich. Sieht die andere Seite dieselben, sitzt niemand dazwischen. Wenn nicht, benutze diesen Chat für nichts, was du nicht auch öffentlich sagen würdest.';
  }

  @override
  String get safetyMarkNotVerified => 'Als nicht bestätigt markieren';

  @override
  String get safetyMarkVerified => 'Als bestätigt markieren';

  @override
  String safetyMarkNote(String name) {
    return 'Als bestätigt zu markieren hält genau die Schlüssel fest, die auf dem Bildschirm stehen. Ändert sich einer davon oder kommt bei $name ein neues Gerät dazu, springt die Markierung von selbst auf „geändert\" — sie ist eine Aufzeichnung dessen, was du geprüft hast, kein Versprechen über das, was danach kommt.';
  }

  @override
  String get safetyVerified => 'Bestätigt';

  @override
  String get safetyChangedSince => 'Seit deiner Prüfung geändert';

  @override
  String get safetyNotVerified => 'Nicht bestätigt';

  @override
  String safetyTheirDevice(int index) {
    return 'Ihr Gerät $index';
  }

  @override
  String get safetyCompareTitle =>
      'Eine Nummer vergleichen, die man dir geschickt hat';

  @override
  String get safetyCompare => 'Vergleichen';

  @override
  String get safetyKeyNotYours =>
      'Der Schlüssel auf dem Server ist nicht der, den du hattest';

  @override
  String get safetyRefusedUntilDecide =>
      'Nachrichten in diesen Chat werden abgelehnt, bis du entscheidest. Privio neu zu installieren oder sich auf einem neuen Gerät anzumelden löst das legitim aus und ist der übliche Grund. Ein Server, der dir einen eigenen Schlüssel unterschiebt, ebenfalls — und von hier aus sieht das genau gleich aus, weshalb es sich lohnt, die Nummer unten danach noch einmal zu vergleichen.';

  @override
  String get safetyTrustNewKey => 'Dem neuen Schlüssel vertrauen';

  @override
  String get safetyKeyChangedArrived =>
      'Ihr Schlüssel hat sich geändert, und damit kam eine Nachricht';

  @override
  String get safetyKeyChangedBody =>
      'Der neue Schlüssel ist bereits im Einsatz — eine Nachricht, die einen mitbringt, lässt sich nicht abweisen, ohne jedem einen Weg zu geben, einen Chat stillzulegen. Eine Neuinstallation löst das aus. Jemand, der sich dazwischenschiebt, auch. Die Nummer unten ist der Unterschied, und sie ist nur etwas wert, wenn sie laut verglichen wird.';

  @override
  String get channelsCouldNotOpenLink => 'Dieser Link ließ sich nicht öffnen';

  @override
  String get channelsJoinWithLink => 'Mit einem Link beitreten';

  @override
  String get channelsNewChannel => 'Neuer Kanal';

  @override
  String get channelsTabFollowing => 'Abonniert';

  @override
  String get channelsTabDiscover => 'Entdecken';

  @override
  String get channelsSearchMine => 'Deine Kanäle durchsuchen';

  @override
  String get channelsSearchPublic => 'Öffentliche Kanäle durchsuchen';

  @override
  String get channelsEmptyTitle => 'Noch keine Kanäle';

  @override
  String get channelsEmptyBody =>
      'Erstelle einen oder finde unter Entdecken einen öffentlichen Kanal.';

  @override
  String get channelsNothingFound => 'Nichts gefunden';

  @override
  String get channelsDiscoverEmptyBody =>
      'Durchsuche öffentliche Kanäle nach Name, Handle oder Beschreibung. Private Kanäle tauchen hier nie auf.';

  @override
  String channelsHandleAndMembers(String handle, String members) {
    return '@$handle  ·  $members';
  }

  @override
  String get channelsJoinTitle => 'Kanal beitreten';

  @override
  String get channelsJoinNote =>
      'Füge einen Kanal-Link ein. Er zeigt dir den Kanal; der Beitritt ist ein Knopf dort. Auch der Beitritt gibt dir nicht den Schlüssel — ein Mitglied, das ihn hat, schickt ihn gleich danach verschlüsselt an dein Gerät.';

  @override
  String get categoryNews => 'Nachrichten';

  @override
  String get categoryTechnology => 'Technik';

  @override
  String get categoryCommunity => 'Gemeinschaft';

  @override
  String get categoryEducation => 'Bildung';

  @override
  String get categoryCulture => 'Kultur';

  @override
  String newChannelPictureUnreadable(String name) {
    return 'Privio konnte $name nicht lesen. Probier ein anderes Bild.';
  }

  @override
  String get newChannelCouldNotCreate => 'Der Kanal ließ sich nicht erstellen';

  @override
  String get newChannelWithoutPicture =>
      'Der Kanal wurde ohne das Bild erstellt.';

  @override
  String get newChannelCreate => 'Erstellen';

  @override
  String get newChannelPublicPictureNote =>
      'Das Bild eines öffentlichen Kanals erscheint auf seiner Webseite und in Linkvorschauen, es wird also unverschlüsselt gespeichert — genau wie Name, Handle und Beschreibung.';

  @override
  String get newChannelHandle => 'Handle';

  @override
  String get newChannelHandleRule =>
      '3–32 Zeichen: a–z, 0–9, Unterstrich oder Punkt';

  @override
  String get newChannelCategory => 'Kategorie';

  @override
  String get newChannelRestrictSaving => 'Speichern einschränken';

  @override
  String get newChannelRestrictNote =>
      'Bittet die Apps der Lesenden, Beiträge nicht zu speichern oder weiterzuleiten. Eine Bitte, keine Garantie — wer einen Beitrag lesen kann, kann ihn abfotografieren.';

  @override
  String get newChannelPrivateBody =>
      'Nur über einen Einladungslink erreichbar. Der Name wird verschlüsselt hochgeladen, der Server speichert also einen Kanal, den er nicht benennen kann.';

  @override
  String get newChannelPublicBody =>
      'Gelistet und durchsuchbar. Name, Handle und Beschreibung sind per Definition öffentlich; die Beiträge bleiben Ende-zu-Ende verschlüsselt.';

  @override
  String get membersCouldNotLift => 'Das ließ sich nicht aufheben.';

  @override
  String get membersCouldNotChange => 'Dieses Mitglied ließ sich nicht ändern';

  @override
  String get membersTitle => 'Mitglieder';

  @override
  String get membersWhoRuns => 'Wer diesen Kanal führt';

  @override
  String get membersSilencedCanRead =>
      'Kann lesen, nicht posten oder reagieren';

  @override
  String get membersAllowAgain => 'Wieder erlauben';

  @override
  String get membersRoleAndPermissions => 'Rolle und Rechte';

  @override
  String get membersOwnerEverything => 'Eigentümer · alles';

  @override
  String get membersSubscriberReadOnly => 'Abonnent · nur lesen';

  @override
  String get membersGrantPost => 'posten';

  @override
  String get membersGrantEdit => 'bearbeiten';

  @override
  String get membersGrantDeletePosts => 'Beiträge löschen';

  @override
  String get membersGrantManageMembers => 'Mitglieder verwalten';

  @override
  String get membersGrantDeleteChannel => 'Kanal löschen';

  @override
  String membersRoleLine(String role, String granted) {
    return '$role · $granted';
  }

  @override
  String get membersSubscriber => 'Abonnent';

  @override
  String get membersTogglePost => 'Posten';

  @override
  String get membersToggleEditChannel => 'Kanal bearbeiten';

  @override
  String get membersToggleDeletePosts => 'Beiträge löschen';

  @override
  String get membersToggleManageMembers => 'Mitglieder verwalten';

  @override
  String get membersToggleDeleteChannel => 'Kanal löschen';

  @override
  String get membersGreyedOutNote =>
      'Ausgegraute Rechte sind welche, die du selbst nicht hast. Niemand kann mehr vergeben, als er hat.';

  @override
  String get membersSubscriberNote =>
      'Ein Abonnent liest den Kanal und sonst nichts.';

  @override
  String get membersRemoveFromChannel => 'Aus dem Kanal entfernen';

  @override
  String get membersStoppedFromPosting => 'Vom Posten ausgeschlossen';

  @override
  String get membersAudienceNote =>
      'Aufgeführt sind nur die Personen, die diesen Kanal führen. Wer ihn liest, wird anderen Lesenden nicht gezeigt — dir eingeschlossen.';

  @override
  String get channelPicture => 'Bild';

  @override
  String get channelLinkCopied => 'Link kopiert.';

  @override
  String get adminsMakeSomebodyFirst => 'Mach zuerst jemanden zum Admin.';

  @override
  String get subscribersCouldNotAddAnybody =>
      'Es ließ sich niemand hinzufügen.';

  @override
  String subscribersAddCount(int count) {
    return '$count hinzufügen';
  }

  @override
  String get threadCouldNotPost => 'Dieser Kommentar ließ sich nicht senden.';

  @override
  String get threadCouldNotRemove =>
      'Dieser Kommentar ließ sich nicht entfernen.';

  @override
  String threadStopTitle(String name) {
    return '$name am Posten hindern?';
  }

  @override
  String get threadStopBody =>
      'Die Person bleibt im Kanal und kann weiterlesen. Kommentieren oder reagieren kann sie nicht, bis du das zurücknimmst.\n\nSie aus dem Kanal zu entfernen ist die andere, schwerere Sache: Das wechselt den Schlüssel und nimmt ihr das Lesen mit.';

  @override
  String get threadStopThem => 'Stoppen';

  @override
  String get threadStopThemPosting => 'Am Posten hindern';

  @override
  String get threadCouldNotDoThat => 'Das war nicht möglich.';

  @override
  String get threadTitle => 'Kommentare';

  @override
  String get threadUnknown => 'Unbekannt';

  @override
  String get threadEncryptedNoKey =>
      'Verschlüsselt — dieses Gerät hat keinen Schlüssel dafür.';

  @override
  String get threadCommentHint => 'Kommentieren';

  @override
  String get threadNoKeyForChannel => 'Kein Schlüssel für diesen Kanal';

  @override
  String get threadDeletedAccount => 'Gelöschtes Konto';

  @override
  String get threadEncryptedNoKeyHere =>
      'Verschlüsselt — auf diesem Gerät kein Schlüssel dafür.';

  @override
  String get threadEmptyTitle => 'Noch keine Kommentare';

  @override
  String get threadEmptyBody =>
      'Kommentare sind wie die Beiträge mit dem Kanalschlüssel verschlüsselt. Der Server speichert sie und kann sie nicht lesen.';

  @override
  String threadStoppedToast(String name) {
    return '$name kann den Kanal weiter lesen, aber nicht darin posten.';
  }

  @override
  String get threadThem => 'Die Person';

  @override
  String get threadThemObject => 'diese Person';

  @override
  String get feedCouldNotAskForKey =>
      'Der Schlüssel ließ sich nicht anfordern.';

  @override
  String get feedKeyArrived => 'Der Schlüssel ist da. Du kannst wieder posten.';

  @override
  String get feedAskedAgain =>
      'Erneut angefragt. Den Schlüssel liefert ein anderes Mitglied, er kommt also an, sobald eines davon online ist.';

  @override
  String get feedCouldNotJoin => 'Beitritt nicht möglich';

  @override
  String get feedPickFutureTime =>
      'Wähle einen Zeitpunkt, der noch nicht vorbei ist.';

  @override
  String get feedCouldNotPublishPoll =>
      'Diese Umfrage ließ sich nicht veröffentlichen.';

  @override
  String feedScheduledFor(String when) {
    return 'Geplant für $when. Bis dahin steht es unter „Geplant\".';
  }

  @override
  String get feedCouldNotPublish => 'Veröffentlichen nicht möglich';

  @override
  String get feedCouldNotChangeLink => 'Der Link ließ sich nicht ändern.';

  @override
  String get feedOldLinkDead =>
      'Der alte Link ist tot. Wer ihn hat, braucht den neuen.';

  @override
  String get feedSaved => 'Gespeichert.';

  @override
  String get feedCouldNotChangeReactions =>
      'Die Reaktionen ließen sich nicht ändern.';

  @override
  String get feedCouldNotChangePost => 'Der Beitrag ließ sich nicht ändern.';

  @override
  String get feedPublished => 'Veröffentlicht.';

  @override
  String get feedCouldNotPublishIt => 'Es ließ sich nicht veröffentlichen.';

  @override
  String get feedCouldNotChangeThat => 'Das ließ sich nicht ändern.';

  @override
  String get feedCommentsOn => 'Lesende können Beiträge jetzt kommentieren.';

  @override
  String get feedCommentsOff =>
      'Kommentare sind aus. Vorhandene Threads sind ausgeblendet, nicht gelöscht.';

  @override
  String get feedCouldNotReadNumbers => 'Die Zahlen ließen sich nicht lesen.';

  @override
  String get feedNobodyToHandTo =>
      'In diesem Kanal ist niemand sonst, dem man ihn übergeben könnte.';

  @override
  String feedOwnsNow(String name) {
    return '$name besitzt diesen Kanal jetzt. Du bist darin Admin.';
  }

  @override
  String get feedCouldNotHandOn => 'Der Kanal ließ sich nicht übergeben.';

  @override
  String get feedReported => 'Gemeldet. Danke.';

  @override
  String get feedCouldNotSendThat => 'Das ließ sich nicht senden.';

  @override
  String get feedRemovePicture => 'Bild entfernen';

  @override
  String get feedPictureRemoved => 'Bild entfernt.';

  @override
  String get feedCouldNotRemovePicture => 'Das Bild ließ sich nicht entfernen.';

  @override
  String get feedCouldNotSetPicture => 'Das Bild ließ sich nicht setzen.';

  @override
  String get feedPictureUpdated => 'Kanalbild aktualisiert.';

  @override
  String get feedDeleteChannelTitle => 'Kanal löschen?';

  @override
  String get feedDeleteChannelBody =>
      'Der Kanal und jeder Beitrag darin werden für alle entfernt. Das macht nichts rückgängig.';

  @override
  String get feedCouldNotDeleteChannel => 'Der Kanal ließ sich nicht löschen';

  @override
  String get feedCouldNotLeaveChannel => 'Der Kanal ließ sich nicht verlassen';

  @override
  String get feedScheduled => 'Geplant';

  @override
  String get feedRequestsToJoin => 'Beitrittsanfragen';

  @override
  String get feedChannelPicture => 'Kanalbild';

  @override
  String get feedAddPicture => 'Bild hinzufügen';

  @override
  String get feedTurnCommentsOff => 'Kommentare ausschalten';

  @override
  String get feedTurnCommentsOn => 'Kommentare einschalten';

  @override
  String get feedHandChannelOn => 'Diesen Kanal übergeben';

  @override
  String get feedDeleteChannel => 'Kanal löschen';

  @override
  String get dayToday => 'Heute';

  @override
  String get dayYesterday => 'Gestern';

  @override
  String get feedNoSearchResultsBody =>
      'Die Suche läuft auf diesem Gerät, über die Beiträge, die es bereits geladen und öffnen konnte. Der Server kann sie nicht durchsuchen: Er hält sie versiegelt.';

  @override
  String get feedEdited => '· bearbeitet';

  @override
  String feedCommentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kommentare',
      one: '1 Kommentar',
      zero: 'Kommentieren',
    );
    return '$_temp0';
  }

  @override
  String get feedUnpin => 'Lösen';

  @override
  String get feedPin => 'Anheften';

  @override
  String get feedRemoveFile => 'Datei entfernen';

  @override
  String get feedAttach => 'Bild oder Datei anhängen';

  @override
  String get feedPublishLater => 'Später veröffentlichen';

  @override
  String get feedAskQuestion => 'Eine Frage stellen';

  @override
  String get feedWritePost => 'Beitrag schreiben';

  @override
  String get feedEditPost => 'Beitrag bearbeiten';

  @override
  String get feedPost => 'Beitrag';

  @override
  String get feedEditUnseenNote =>
      'Das hat noch niemand gesehen, es wird also nicht als bearbeitet markiert.';

  @override
  String get feedEditSeenNote =>
      'Der Beitrag wird als bearbeitet markiert. Seine Datei, falls vorhanden, bleibt wie sie ist.';

  @override
  String get feedWaiting => 'Wartet';

  @override
  String get feedEncryptedNoKeyHere =>
      'Verschlüsselt — kein Schlüssel auf diesem Gerät.';

  @override
  String get feedDiscard => 'Verwerfen';

  @override
  String get feedPublishNow => 'Jetzt veröffentlichen';

  @override
  String get feedNothingWaiting => 'Nichts in der Warteschlange';

  @override
  String get feedNothingWaitingBody =>
      'Beiträge, die du planst, warten hier, bis ihre Zeit kommt. Niemand sonst kann sie sehen oder wissen, dass es sie gibt.';

  @override
  String feedTodayAt(String time) {
    return 'heute um $time';
  }

  @override
  String feedTomorrowAt(String time) {
    return 'morgen um $time';
  }

  @override
  String feedDateAt(String date, String time) {
    return '$date um $time';
  }

  @override
  String get feedReactionsNote =>
      'Was Lesende unter einen Beitrag setzen können. Reaktionen, die schon an einem Beitrag hängen, bleiben, auch wenn du das Emoji von dieser Liste nimmst.';

  @override
  String feedChosenOfLimit(int chosen, int limit) {
    return '$chosen von $limit';
  }

  @override
  String get feedPollNoKey =>
      'Eine Umfrage, für die dieses Gerät keinen Schlüssel hat.';

  @override
  String feedPollPickUpTo(int count) {
    return 'Bis zu $count auswählen';
  }

  @override
  String get feedPollPickOne => 'Eines auswählen';

  @override
  String feedPollCloses(String when) {
    return 'schließt $when';
  }

  @override
  String feedPollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Stimmen',
      one: '1 Stimme',
    );
    return '$_temp0';
  }

  @override
  String get feedPollClearAnswer => 'Meine Antwort zurücknehmen';

  @override
  String get feedPollAnswer => 'Antworten';

  @override
  String get feedPollQuestion => 'Frage';

  @override
  String feedPollAnswerN(int index) {
    return 'Antwort $index';
  }

  @override
  String get feedPollAddAnswer => 'Antwort hinzufügen';

  @override
  String get feedPollSeveral => 'Mehrere Antworten';

  @override
  String get feedPollNote =>
      'Frage und Antworten sind wie ein Beitrag mit dem Kanalschlüssel verschlüsselt. Der Server zählt die Stimmen, ohne je zu erfahren, was in einer davon steht.';

  @override
  String get feedPollAsk => 'Fragen';

  @override
  String get feedCouldNotOpenFile => 'Diese Datei ließ sich nicht öffnen.';

  @override
  String get feedOpened => 'Geöffnet';

  @override
  String get statsPosts => 'Beiträge';

  @override
  String get statsWaitingToPublish => 'Wartet auf Veröffentlichung';

  @override
  String get statsPeopleWhoVoted => 'Personen, die abgestimmt haben';

  @override
  String get statsWaitingToJoin => 'Wartet auf Beitritt';

  @override
  String get statsNoViewCountNote =>
      'Es gibt keine Aufrufzahl, und das ist eine Entscheidung, keine Lücke. Zu zählen, wer einen Beitrag gelesen hat — ohne jemanden doppelt zu zählen — heißt, eine Zeile für jede lesende Person und jeden Beitrag zu führen, und das ist eine Aufzeichnung dessen, was jede Person gelesen hat. Alles oben wird aus etwas gezählt, das jemand aktiv getan hat.';

  @override
  String get feedPollClosed => 'geschlossen';

  @override
  String get inviteNever => 'Nie';

  @override
  String inviteExpires(String when) {
    return 'läuft $when ab';
  }

  @override
  String requestsAsked(String when) {
    return 'Gefragt $when';
  }

  @override
  String get inviteAskMeFirst => 'Erst mich fragen';

  @override
  String get inviteAskMeFirstNote =>
      'Wer dem Link folgt, wartet auf deine Zustimmung, statt einfach hereinzuspazieren. Bis du sie hereinlässt, haben sie keinen Schlüssel.';

  @override
  String get inviteExpiresLabel => 'Läuft ab';

  @override
  String get invitePickATime => 'Zeitpunkt wählen';

  @override
  String get inviteHowMany => 'Wie viele damit beitreten können';

  @override
  String get inviteNoLimit => 'Kein Limit';

  @override
  String inviteJoinedSoFar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sind bisher über diesen Link beigetreten.',
      one: '1 Person ist bisher über diesen Link beigetreten.',
    );
    return '$_temp0 Ihn zu öffnen und wieder wegzugehen zählt nicht.';
  }

  @override
  String get inviteReplaceLink => 'Link ersetzen';

  @override
  String get inviteReplaceNote =>
      'Ersetzen ist die Art, einen Link zu widerrufen: Der alte funktioniert sofort überall nicht mehr. Es bleibt kein halb funktionierender Link zurück.';

  @override
  String get inviteReplaceTitle => 'Link ersetzen?';

  @override
  String get inviteReplaceBody =>
      'Der Link, den du geteilt hast, funktioniert sofort nicht mehr — in Nachrichten, auf Plakaten, überall, wo er eingefügt wurde. Niemand, der ihn hat, kann damit beitreten.\n\nWer schon im Kanal ist, bleibt drin. Der alte Link lässt sich nicht zurückholen.';

  @override
  String get inviteReplaceIt => 'Ersetzen';

  @override
  String get inviteExpired =>
      'Dieser Link ist abgelaufen — damit kann niemand beitreten.';

  @override
  String get inviteUsedUp => 'Dieser Link ist aufgebraucht.';

  @override
  String get inviteNeedsApproval => 'Beitritt braucht deine Zustimmung';

  @override
  String get inviteOpenJoin => 'Wer ihn hat, tritt sofort bei';

  @override
  String inviteUsedOf(int used, int max) {
    return '$used von $max genutzt';
  }

  @override
  String get inviteShareNote =>
      'Teile ihn überall — er trägt keinen Schlüssel. Wer ihn öffnet, tritt dem Kanal bei, und den Schlüssel zum Lesen schickt danach jemand, der ihn schon hat, verschlüsselt an das Gerät.';

  @override
  String get requestsNobodyWaiting => 'Niemand wartet';

  @override
  String get requestsNobodyWaitingBody =>
      'Wer dem Einladungslink folgt, erscheint hier, solange der Link auf „erst mich fragen\" steht.';

  @override
  String get requestsNo => 'Nein';

  @override
  String get requestsLetIn => 'Einlassen';

  @override
  String get feedSettings => 'Einstellungen';

  @override
  String feedKeyRotating(int epoch) {
    return 'Jemand hat diesen Kanal verlassen, deshalb wechselt er seinen Schlüssel (Version $epoch). Beiträge von vorher bleiben lesbar. Neue öffnen sich, sobald der neue Schlüssel dieses Gerät erreicht.';
  }

  @override
  String get feedWaitingForKey =>
      'Warte auf den Schlüssel. Ihn schickt jemand aus dem Kanal verschlüsselt an dieses Gerät — der Server hält ihn nie.';

  @override
  String get feedJoinNote =>
      'Beitreten bringt dir die Beiträge. Den Schlüssel, der sie öffnet, schickt danach ein Mitglied an dein Gerät, nie der Server.';

  @override
  String get feedJoinChannel => 'Kanal beitreten';

  @override
  String get feedNoPostsYet => 'Noch keine Beiträge';

  @override
  String get feedPickNewOwnerNote =>
      'Nur jemand, der schon im Kanal ist. Ihn einer fremden Person zu übergeben, würde sie über einen Schlüssel bestimmen lassen, den sie nicht hat.';

  @override
  String feedTransferTitle(String name) {
    return 'Den Kanal an $name geben?';
  }

  @override
  String get feedTransferBody =>
      'Die Person wird Eigentümer. Du bleibst als Admin mit allem, was du jetzt hast, außer dem Recht, den Kanal zu löschen — und sie kann dich danach entfernen.\n\nDu kannst das nicht selbst rückgängig machen. Deshalb fragt es nach deinem Passwort, statt einem entsperrten Telefon zu vertrauen.';

  @override
  String get feedYourPrivioPassword => 'Dein Privio-Passwort';

  @override
  String get feedHandItOn => 'Übergeben';

  @override
  String get feedReportTitle => 'Diesen Kanal melden';

  @override
  String get feedReportPublicNote =>
      'Die Meldung trägt diesen Kanal und den Grund, den du wählst. Wer den Server betreibt, sieht bei einem öffentlichen Kanal Name und Beschreibung, weil man danach sucht — aber nicht seine Beiträge, die sind verschlüsselt.';

  @override
  String get feedReportPrivateNote =>
      'Die Meldung trägt diesen Kanal und den Grund, den du wählst, und sonst nichts. Sein Name und seine Beiträge sind verschlüsselt, wer den Server betreibt, kann sie also nicht lesen. Das ist die ehrliche Grenze dessen, was das Melden eines privaten Kanals bewirkt.';

  @override
  String get feedReportNoMessageNote =>
      'Es gibt absichtlich kein Nachrichtenfeld: Es wäre die eine Stelle in Privio, an der jemand das verschlüsselte Ding, das er meldet, in ein Feld einfügt, das der Server lesen kann.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportAbuse => 'Missbrauch oder Belästigung';

  @override
  String get reportIllegal => 'Illegale Inhalte';

  @override
  String get reportImpersonation => 'Gibt sich als jemand anderes aus';

  @override
  String get reportOther => 'Etwas anderes';

  @override
  String get feedReactionLimit => 'Reaktionen';

  @override
  String get failureUnreachable => 'Privio ist nicht erreichbar.';

  @override
  String get failureUnreachableCheckConnection =>
      'Privio ist nicht erreichbar. Prüfe deine Verbindung.';

  @override
  String get failureUnreachableTryAgain =>
      'Privio ist nicht erreichbar. Prüfe deine Verbindung und versuche es erneut.';

  @override
  String get failureCouldNotSave =>
      'Das konnte nicht gespeichert werden. Prüfe deine Verbindung.';

  @override
  String get failureChangeNotSaved =>
      'Privio ist nicht erreichbar. Die Änderung wurde nicht gespeichert.';

  @override
  String get failureRateLimited => 'Zu viele Anfragen. Warte einen Moment.';

  @override
  String get failureTooManyAttempts =>
      'Zu viele Versuche. Warte ein paar Minuten.';

  @override
  String get failureLicenseRequired =>
      'Aktiviere deine Lizenz, um Nachrichten zu senden.';

  @override
  String get failureIdentityChanged =>
      'Die Sicherheitsnummer hat sich geändert. Es wurde nichts gesendet — prüfe sie zuerst.';

  @override
  String get failureCouldNotSendMessage =>
      'Nachricht konnte nicht gesendet werden';

  @override
  String get failureCouldNotSendFile => 'Datei konnte nicht gesendet werden';

  @override
  String get failureCouldNotReadMessage =>
      'Eine Nachricht konnte nicht gelesen werden';

  @override
  String failureMessagesUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Nachrichten konnten nicht gelesen werden',
      one: 'Eine Nachricht konnte nicht gelesen werden',
    );
    return '$_temp0';
  }

  @override
  String get failureCouldNotOpenFile =>
      'Diese Datei konnte nicht geöffnet werden.';

  @override
  String get failureNotAnImage =>
      'Diese Datei ist kein Bild, das Privio verwenden kann.';

  @override
  String get failureCouldNotSetPicture =>
      'Das Bild konnte nicht gesetzt werden';

  @override
  String get failureDeletedHereOnly =>
      'Hier gelöscht. Die Anfrage, sie dort zu löschen, ging nicht raus.';

  @override
  String get failureCouldNotCreateGroup =>
      'Die Gruppe konnte nicht erstellt werden';

  @override
  String get failureNotAGroupLink =>
      'Das sieht nicht nach einem Privio-Gruppenlink aus.';

  @override
  String get failureGroupNotFound =>
      'Diese Gruppe gibt es nicht, oder der Link ist falsch.';

  @override
  String get failureGroupKeyMissing =>
      'Dieses Gerät hat den Gruppenschlüssel noch nicht.';

  @override
  String get failureNotAChannelLink =>
      'Das sieht nicht nach einem Privio-Channel-Link aus.';

  @override
  String get failureHandleTaken => 'Dieser Handle ist bereits vergeben.';

  @override
  String get failureChannelNotFound =>
      'Diesen Channel gibt es nicht, oder der Link ist falsch.';

  @override
  String get failureNotAMember => 'Du bist nicht in diesem Channel.';

  @override
  String get failureInsufficientPermission =>
      'Dafür fehlt dir die Berechtigung.';

  @override
  String get failureCannotChangeOwnRole =>
      'Du kannst deine eigene Rolle nicht ändern.';

  @override
  String get failureOwnerIsFixed =>
      'Der Inhaber des Channels kann nicht geändert oder entfernt werden.';

  @override
  String get failureTargetOutranksYou =>
      'Dieses Mitglied hat Rechte, die du nicht hast.';

  @override
  String get failureCannotGrantWhatYouLack =>
      'Du kannst kein Recht vergeben, das du selbst nicht hast.';

  @override
  String get failureOwnerCannotLeave =>
      'Übertrage den Channel oder lösche ihn stattdessen.';

  @override
  String get failureUsernameTaken =>
      'Dieser Benutzername ist bereits vergeben.';

  @override
  String get failureInvalidCredentials =>
      'Benutzername oder Passwort ist falsch.';

  @override
  String get failureTotpRequired => 'Gib deinen Zwei-Faktor-Code ein.';

  @override
  String get failureInvalidTwoFactorCode =>
      'Dieser Zwei-Faktor-Code stimmt nicht.';

  @override
  String get failureTooManyDevices =>
      'Dieses Konto hat bereits die maximale Anzahl an Geräten.';

  @override
  String failureCheckUsernameAndPassword(String detail) {
    return 'Prüfe Benutzernamen und Passwort: $detail';
  }

  @override
  String get failureInvalidTotp =>
      'Dieser Code stimmt nicht. Prüfe die Uhrzeit deines Telefons und versuche es erneut.';

  @override
  String get failureTotpAlreadyEnabled =>
      'Zwei-Faktor ist für dieses Konto bereits aktiv.';

  @override
  String get failureTotpNotSetUp =>
      'Starte die Einrichtung neu — das Geheimnis ist weg.';

  @override
  String get failureInvalidPassword => 'Dieses Passwort stimmt nicht.';

  @override
  String get failureDuressMatchesPassword =>
      'Der Notfallcode muss sich von deinem Passwort unterscheiden, sonst würde eine normale Anmeldung das Konto zerstören.';

  @override
  String get failureDeviceNotFound => 'Dieses Gerät ist bereits abgemeldet.';

  @override
  String get failureCouldNotLiftBlock =>
      'Diese Blockierung konnte nicht aufgehoben werden.';

  @override
  String failureLicenseKeyIncomplete(String format) {
    return 'Dieser Schlüssel ist unvollständig. Er sieht aus wie $format.';
  }

  @override
  String get failureNotALicenseKey =>
      'Das sieht nicht nach einem Privio-Lizenzschlüssel aus.';

  @override
  String get failureLicenseNotFound =>
      'Zu diesem Schlüssel gibt es keine Lizenz. Prüfe ihn und versuche es erneut.';

  @override
  String get failureLicenseAlreadyRedeemed =>
      'Dieser Schlüssel wurde bereits von einem anderen Konto eingelöst. Ein Schlüssel lässt sich nur einmal einlösen.';

  @override
  String get failureLicenseRevoked =>
      'Diese Lizenz wurde widerrufen. Wende dich an den Support, wenn du dafür bezahlt hast.';

  @override
  String get failureAccountAlreadyLicensed =>
      'Dieses Konto hat bereits eine Lizenz, der eingegebene Schlüssel wurde daher nicht eingelöst.';

  @override
  String get failureNoPlayServices =>
      'Dieses Telefon hat keine Google-Play-Dienste, daher kann Privio im geschlossenen Zustand nicht geweckt werden. Nachrichten kommen an, solange Privio geöffnet ist.';

  @override
  String get failureNoApnsToken =>
      'iOS hat kein Push-Token für Privio ausgestellt, daher kann Privio im geschlossenen Zustand nicht geweckt werden. Nachrichten kommen an, solange Privio geöffnet ist.';

  @override
  String get failureNoPushService =>
      'Kein Push-Dienst hat geantwortet. Nachrichten kommen an, solange Privio geöffnet ist.';

  @override
  String get failureNoDistributor =>
      'Kein UnifiedPush-Distributor hat geantwortet. Installiere einen — zum Beispiel ntfy — und versuche es erneut.';

  @override
  String get failureDistributorUnreachable =>
      'Privio kann diesen Distributor nicht erreichen. Es muss eine https-Adresse im öffentlichen Internet sein.';

  @override
  String get failureChannelKeyAwaitingGeneration =>
      'Dieser Channel wechselt seinen Schlüssel, nachdem ein Mitglied gegangen ist. Du kannst wieder posten, sobald jemand, der den Channel verwaltet, Privio öffnet.';

  @override
  String get failureChannelKeyPending =>
      'Warte darauf, dass der neue Channel-Schlüssel dieses Gerät erreicht. Dein Beitrag ist nicht verloren — versuche es gleich noch einmal.';

  @override
  String get failureUnexpected =>
      'Etwas hat nicht wie erwartet funktioniert. Versuche es erneut.';

  @override
  String get failureCallDevicesUnavailable =>
      'Privio konnte die Kamera oder das Mikrofon nicht öffnen.';

  @override
  String get failureCallMicrophoneUnavailable =>
      'Privio konnte das Mikrofon nicht öffnen.';

  @override
  String get failureCallNotOpen => 'Der Anruf war nicht offen.';

  @override
  String get deepLinkChannelGone =>
      'Dieser Link führt zu keinem Channel mehr. Bitte die Person, die ihn geschickt hat, um einen neuen.';

  @override
  String get chatsPreviewDeleted => 'Nachricht gelöscht';

  @override
  String get chatsPreviewPhoto => 'Foto';

  @override
  String get chatsPreviewVideo => 'Video';

  @override
  String get chatsPreviewVoice => 'Sprachnachricht';

  @override
  String get chatsPreviewFile => 'Datei';

  @override
  String get notificationsPermissionDenied =>
      'Benachrichtigungen sind für Privio in deinen Systemeinstellungen ausgeschaltet. Nachrichten kommen weiterhin an, solange Privio geöffnet ist — du wirst aber nicht darüber informiert, und ein Anruf klingelt nicht.';

  @override
  String get notificationsPermissionNotAsked =>
      'Privio darf dich noch nicht benachrichtigen.';

  @override
  String get failureCallMediaNotEncrypted =>
      'Der Anruf wurde beendet: Die Gegenseite hat eine Verbindung angefordert, die Privio nicht verschlüsseln kann. Privio weicht nie auf einen unverschlüsselten Anruf aus.';

  @override
  String get failureCallFarEndNotBound =>
      'Der Anruf wurde beendet: In der Aushandlung war nicht belegt, wer am anderen Ende ist. Privio verbindet keinen Anruf, den es nicht an einen Schlüssel binden kann.';

  @override
  String get failureCallCertificateChanged =>
      'Der Anruf wurde beendet: Die Gegenstelle hat mitten in der Aushandlung gewechselt. Ein Anruf hat eine Gegenstelle, dieser hatte zwei.';

  @override
  String failureCallIdentityChanged(String who) {
    return 'Der Anruf wurde beendet: Die Sicherheitsnummer von $who ist nicht die, die Privio hatte. Vergleiche sie über einen anderen Weg mit dieser Person, bevor du erneut anrufst.';
  }

  @override
  String get failureCallWrongParty =>
      'Der Anruf wurde beendet: Eine Nachricht dazu kam von jemandem, der nicht daran beteiligt ist.';

  @override
  String failureCallNotVerified(String who) {
    return 'Der Anruf wurde beendet: Du nimmst nur Anrufe von Personen an, deren Sicherheitsnummer du bestätigt hast — die von $who ist auf diesem Gerät nicht bestätigt.';
  }

  @override
  String get callEncrypted => 'Ende-zu-Ende-verschlüsselt';

  @override
  String get callEncryptedVerified =>
      'Ende-zu-Ende-verschlüsselt · verifiziert';

  @override
  String get securityVerifiedCallsOnly =>
      'Nur Anrufe von verifizierten Kontakten';

  @override
  String get securityVerifiedCallsOnlyBody =>
      'Jeder Anruf ist ohnehin Ende-zu-Ende-verschlüsselt. Mit dieser Einstellung lehnt Privio einen Anruf zusätzlich ab, solange du die Sicherheitsnummer mit der Person nicht verglichen und bestätigt hast — ein Schlüssel, den dieses Gerät nur als ersten gesehen hat, reicht dann nicht. Anrufe von allen anderen enden mit einer Erklärung, auf beiden Seiten.';

  @override
  String get privacyCalls => 'Anrufe';

  @override
  String get appearanceAccentColour => 'Akzentfarbe';

  @override
  String get appearanceAccentNote =>
      'Das ändert, wie Privio auf diesem Gerät aussieht, für dieses Konto. Niemand, dem du schreibst, sieht es, und deine anderen Konten behalten ihre eigene Farbe. Rot für Löschen und Auflegen bleibt Rot, welchen Akzent du auch wählst.';

  @override
  String get accentGreen => 'Grün';

  @override
  String get accentBlue => 'Blau';

  @override
  String get accentTeal => 'Türkis';

  @override
  String get accentPurple => 'Violett';

  @override
  String get accentPink => 'Pink';

  @override
  String get accentRed => 'Rot';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentYellow => 'Gelb';

  @override
  String get accentPrivioDefault => 'PRIVIO-Standard';

  @override
  String get appearanceAccentReset => 'Auf Standard zurücksetzen';

  @override
  String get appearanceAccentPreview => 'Vorschau';

  @override
  String get appearancePreviewSend => 'Senden';

  @override
  String get appearancePreviewSetting => 'Lesebestätigungen';

  @override
  String get appearancePreviewMessage =>
      'So werden deine eigenen Nachrichten aussehen.';

  @override
  String accentSelected(String colour) {
    return '$colour, ausgewählt';
  }

  @override
  String get appearanceAppIcon => 'App-Icon';

  @override
  String get appearanceAppIconNote =>
      'Das ist das Symbol auf deinem Startbildschirm. Es gehört zu diesem Telefon und nicht zu deinem Konto: Wenn du dich als jemand anderes anmeldest, ändert es sich nicht. Es bleibt so, wie du es eingestellt hast, auch wenn du später eine andere Akzentfarbe wählst.';

  @override
  String get appearanceAppIconMatchAccent => 'Aktuelle Akzentfarbe übernehmen';

  @override
  String get appearanceAppIconReset => 'Standard wiederherstellen';

  @override
  String get appearanceAppIconSlow =>
      'Der Startbildschirm braucht manchmal ein paar Sekunden, bis er sich neu zeichnet. Diese Wartezeit gehört zum Launcher, nicht zu Privio.';

  @override
  String get appearanceAppIconUnavailable =>
      'Dieses Gerät kann das App-Symbol nicht ändern, deshalb bietet Privio es nicht an.';

  @override
  String get appearanceAppIconOriginal => 'Original';

  @override
  String get failureAppIconUnsupported =>
      'Das App-Symbol konnte nicht geändert werden: Dieses Gerät bietet das nicht an.';

  @override
  String get failureAppIconHiddenByDisguise =>
      'Solange die Tarnung an ist, zeigt der Startbildschirm den Taschenrechner — die Icon-Farbe wurde deshalb nicht geändert. Schalte die Tarnung zuerst aus.';

  @override
  String appIconSelected(String colour) {
    return 'Symbol in $colour, ausgewählt';
  }

  @override
  String appIconChoose(String colour) {
    return 'Symbol in $colour';
  }

  @override
  String get failureStickerNotAnImage =>
      'Diese Datei ist kein PNG- und kein WebP-Bild.';

  @override
  String get failureStickerAnimated =>
      'Animierte Sticker werden noch nicht unterstützt. Nimm ein unbewegtes PNG oder WebP.';

  @override
  String failureStickerTooLarge(int limit) {
    return 'Ein Sticker muss kleiner als $limit KB sein.';
  }

  @override
  String failureStickerTooWide(int limit) {
    return 'Ein Sticker darf höchstens $limit×$limit Pixel groß sein.';
  }

  @override
  String failureStickerTooSmall(int limit) {
    return 'Ein Sticker muss mindestens $limit×$limit Pixel groß sein.';
  }

  @override
  String get failureStickerPackFull =>
      'Dieses Paket ist voll. Entferne etwas, um Platz zu schaffen.';

  @override
  String get failureStickerTooManyPacks =>
      'Du hast so viele Pakete, wie Privio verwaltet. Lösche eines, um ein neues anzulegen.';

  @override
  String get failureStickerPackNotFound => 'Dieses Paket gibt es nicht mehr.';

  @override
  String get failureStickerLinkDead =>
      'Dieser Link öffnet nichts mehr: Er wurde zurückgezogen oder das Paket wurde gelöscht.';

  @override
  String get settingsStickers => 'Sticker & Emoji';

  @override
  String get stickersTitle => 'Sticker & Emoji';

  @override
  String get stickersMyPacks => 'Meine Pakete';

  @override
  String get stickersInstalled => 'Hinzugefügt';

  @override
  String get stickersEmptyTitle => 'Noch keine Pakete';

  @override
  String get stickersEmptyBody =>
      'Leg ein Paket aus eigenen Bildern an oder öffne einen Link, den dir jemand geschickt hat.';

  @override
  String get stickersNewPack => 'Neues Paket';

  @override
  String get stickersNewStickerPack => 'Sticker-Paket';

  @override
  String get stickersNewEmojiPack => 'Emoji-Paket';

  @override
  String get stickersNameLabel => 'Name';

  @override
  String get stickersNameHint => 'Wie dieses Paket heißt';

  @override
  String get stickersCreate => 'Anlegen';

  @override
  String get stickersRename => 'Umbenennen';

  @override
  String get stickersDelete => 'Paket löschen';

  @override
  String stickersDeleteConfirm(String title) {
    return '„$title\" löschen?';
  }

  @override
  String get stickersDeleteExplain =>
      'Der Link funktioniert dann nicht mehr und das Paket verschwindet aus deiner Auswahl. Bereits gesendete Sticker daraus bleiben in den Unterhaltungen sichtbar.';

  @override
  String get stickersRemovePack => 'Aus meinen Paketen entfernen';

  @override
  String get stickersAddPack => 'Paket hinzufügen';

  @override
  String get stickersAlreadyAdded => 'Schon in deinen Paketen';

  @override
  String get stickersShare => 'Dieses Paket teilen';

  @override
  String get stickersSharedOn => 'Wer den Link hat, kann es hinzufügen';

  @override
  String get stickersSharedOff => 'Privat. Nur du siehst es.';

  @override
  String get stickersShareExplain =>
      'Ein Paket ist privat, bis du es teilst. Sticker-Bilder sind nicht verschlüsselt: Ein Link ist für Leute gedacht, die keinen deiner Schlüssel haben — wer den Link hat und auch dieser Server können sie also sehen. Wenn du den Link zurückziehst, kann niemand Neues das Paket mehr hinzufügen; bei denen, die es schon haben, bleibt es.';

  @override
  String get stickersCopyLink => 'Link kopieren';

  @override
  String get stickersLinkCopied => 'Link kopiert';

  @override
  String get stickersWithdrawLink => 'Link zurückziehen';

  @override
  String get stickersNewLinkNote =>
      'Erneut teilen erzeugt einen neuen Link und macht den alten ungültig.';

  @override
  String get stickersAddItem => 'Bild hinzufügen';

  @override
  String get stickersItemEmoji => 'Emoji dafür';

  @override
  String get stickersItemEmojiWhy =>
      'Wofür er steht: Was eine App ohne dieses Paket stattdessen zeigt — und woran du ihn später wiederfindest.';

  @override
  String get stickersEmptyPack => 'In diesem Paket ist noch nichts.';

  @override
  String stickersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bilder',
      one: '1 Bild',
      zero: 'Leer',
    );
    return '$_temp0';
  }

  @override
  String get stickersRemoveItem => 'Entfernen';

  @override
  String get stickersReorderHint =>
      'Halten und ziehen, um die Reihenfolge zu ändern.';

  @override
  String get stickersCropTitle => 'Zuschneiden';

  @override
  String get stickersCropHint =>
      'Ziehen und zoomen, um das Quadrat zu wählen. Transparenz bleibt erhalten.';

  @override
  String get stickersUse => 'Übernehmen';

  @override
  String get stickersPreviewTitle => 'Sticker-Paket';

  @override
  String get stickersOpenLinkTitle => 'Paket-Link öffnen';

  @override
  String get stickersOpenLinkHint =>
      'Füge den Link oder den Code ein, den dir jemand geschickt hat.';

  @override
  String get stickersOpen => 'Öffnen';

  @override
  String get stickersKindSticker => 'Sticker';

  @override
  String get stickersKindEmoji => 'Eigene Emojis';

  @override
  String get stickersPickFailed => 'Dieses Bild ließ sich nicht öffnen.';

  @override
  String get notificationsIphoneNote =>
      'Du kannst Benachrichtigungen für Privio in den iPhone-Einstellungen verwalten.';

  @override
  String get notificationsOpenIphoneSettings => 'iPhone-Einstellungen öffnen';

  @override
  String get notificationsSettingsFailed =>
      'Die Einstellungen konnten nicht geöffnet werden. Öffne die Einstellungen-App und wähle Privio.';

  @override
  String get pickerEmoji => 'Emoji';

  @override
  String get pickerStickers => 'Sticker';

  @override
  String get pickerMine => 'Meine';

  @override
  String get pickerFavourites => 'Favoriten';

  @override
  String get pickerRecent => 'Zuletzt benutzt';

  @override
  String get pickerNoStickers => 'Noch keine Sticker-Pakete.';

  @override
  String get pickerNoCustomEmoji => 'Noch keine eigenen Emojis.';

  @override
  String get pickerManagePacks => 'Pakete verwalten';

  @override
  String get pickerAddFavourite => 'Zu Favoriten hinzufügen';

  @override
  String get pickerRemoveFavourite => 'Aus Favoriten entfernen';

  @override
  String get pickerOpenPack => 'Paket öffnen';

  @override
  String stickerFromPack(String title) {
    return 'Sticker aus „$title\"';
  }

  @override
  String get stickerPackGone => 'Dieses Paket ist für dich nicht verfügbar.';

  @override
  String get chatSticker => 'Sticker';

  @override
  String get pickerOpenTooltip => 'Sticker und Emoji';

  @override
  String get failurePhoneInvalid =>
      'Das ist keine Telefonnummer, die PRIVIO verwenden kann. Gib die Ländervorwahl an, zum Beispiel +49.';

  @override
  String get failurePhoneSmsUnavailable =>
      'Dieser Server kann noch keine SMS senden, eine Nummer lässt sich hier also nicht bestätigen. Du kannst PRIVIO weiterhin ohne Nummer nutzen.';

  @override
  String get failurePhoneDiscoveryUnavailable =>
      'Auf diesem Server ist die Kontaktfindung ausgeschaltet.';

  @override
  String get failurePhoneWrongCode => 'Dieser Code stimmt nicht.';

  @override
  String get failurePhoneCodeExpired =>
      'Dieser Code ist abgelaufen. Fordere einen neuen an.';

  @override
  String get failurePhoneTooManyAttempts =>
      'Zu viele falsche Codes. Fordere einen neuen an.';

  @override
  String get failurePhoneTooManySends =>
      'PRIVIO hat diesen Code so oft gesendet, wie es das tut. Versuch es später noch einmal.';

  @override
  String get failurePhoneResendTooSoon =>
      'Warte einen Moment, bevor du einen neuen Code anforderst.';

  @override
  String get failurePhoneNoVerification => 'Fordere zuerst einen Code an.';

  @override
  String get failurePhoneUnchanged =>
      'Diese Nummer ist für dieses Konto bereits bestätigt.';

  @override
  String get failurePhoneNotLinked =>
      'Für dieses Konto ist keine Nummer bestätigt.';

  @override
  String get failurePhoneLookupBudgetSpent =>
      'PRIVIO hat heute für dieses Konto so viele Nummern abgeglichen, wie es das tut. Versuch es morgen wieder.';

  @override
  String get failureContactsPermissionDenied =>
      'PRIVIO hat keinen Zugriff auf deine Kontakte. Du kannst Leute weiterhin über ihre PRIVIO-ID oder einen Einladungslink hinzufügen.';

  @override
  String get channelVerifiedTooltip => 'Offizieller PRIVIO-Kanal';
}
