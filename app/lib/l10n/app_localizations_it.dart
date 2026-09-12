// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppTextIt extends AppText {
  AppTextIt([String locale = 'it']) : super(locale);

  @override
  String get languageName => 'Lingua';

  @override
  String get languagePickerTitle => 'Lingua';

  @override
  String get languagePickerNote =>
      'L\'interfaccia cambia subito. I messaggi, i nomi dei canali e tutto il resto scritto dalle persone restano nella lingua in cui sono stati scritti.';

  @override
  String get commonCancel => 'Annulla';

  @override
  String get commonDone => 'Fatto';

  @override
  String get commonSave => 'Salva';

  @override
  String get commonClose => 'Chiudi';

  @override
  String get commonDelete => 'Elimina';

  @override
  String get commonRemove => 'Rimuovi';

  @override
  String get commonRetry => 'Riprova';

  @override
  String get commonSearch => 'Cerca';

  @override
  String get commonEdit => 'Modifica';

  @override
  String get commonAdd => 'Aggiungi';

  @override
  String get commonBack => 'Indietro';

  @override
  String get commonNext => 'Avanti';

  @override
  String get commonSkip => 'Salta';

  @override
  String get commonContinue => 'Continua';

  @override
  String get commonYes => 'Sì';

  @override
  String get commonNo => 'No';

  @override
  String get commonOk => 'Va bene';

  @override
  String get commonCopy => 'Copia';

  @override
  String get commonCopied => 'Copiato.';

  @override
  String get commonShare => 'Condividi';

  @override
  String get commonLoading => 'Caricamento…';

  @override
  String get commonSomethingWentWrong => 'Qualcosa è andato storto.';

  @override
  String get commonNotNow => 'Non ora';

  @override
  String get commonOn => 'Attivo';

  @override
  String get commonOff => 'Disattivo';

  @override
  String get commonDefault => 'Predefinito';

  @override
  String get commonCustom => 'Personalizzato';

  @override
  String get commonUnavailable => 'Non disponibile';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsAccount => 'Account';

  @override
  String get settingsPrivacy => 'Privacy';

  @override
  String get settingsSecurity => 'Sicurezza';

  @override
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsNotifications => 'Notifiche';

  @override
  String get settingsStorage => 'Archiviazione';

  @override
  String get settingsAbout => 'Informazioni su PRIVIO';

  @override
  String get settingsSupport => 'Assistenza';

  @override
  String get settingsSignOut => 'Esci';

  @override
  String get disappearingTitle => 'Messaggi a tempo';

  @override
  String get disappearingExplainer =>
      'I nuovi messaggi vengono eliminati automaticamente dopo questo intervallo. Il conto alla rovescia parte quando il messaggio viene inviato.';

  @override
  String get disappearingCoversChat =>
      'Vale per testo, foto, file e messaggi vocali, e solo per questa chat. I messaggi già inviati non sono interessati, e quando cambia lo sapete entrambi.';

  @override
  String get disappearingCoversGroup =>
      'Vale per testo, foto, file e messaggi vocali, e solo per questo gruppo. I messaggi già inviati non sono interessati, quando cambia lo sanno tutti, e può cambiarlo solo un amministratore.';

  @override
  String get disappearingScreenshotCaveat =>
      'Non può annullare uno screenshot, una foto già salvata o qualcosa annotato altrove.';

  @override
  String get disappearingOff => 'Disattivo';

  @override
  String get disappearing30Seconds => '30 secondi';

  @override
  String get disappearing1Minute => '1 minuto';

  @override
  String get disappearing5Minutes => '5 minuti';

  @override
  String get disappearing1Hour => '1 ora';

  @override
  String get disappearing24Hours => '24 ore';

  @override
  String get disappearing7Days => '7 giorni';

  @override
  String get disappearingAdminOnly => 'Solo un amministratore può cambiarlo';

  @override
  String noticeTimerSetBy(String who, String duration) {
    return '$who ha impostato i messaggi a tempo su $duration';
  }

  @override
  String noticeTimerOffBy(String who) {
    return '$who ha disattivato i messaggi a tempo';
  }

  @override
  String get noticeYou => 'Tu';

  @override
  String get noticeThey => 'L\'altra persona';

  @override
  String get noticeSomeone => 'Qualcuno';

  @override
  String noticeMessageDeletedBy(String who) {
    return '$who ha eliminato un messaggio';
  }

  @override
  String noticeSafetyNumberChanged(String who) {
    return 'Il tuo numero di sicurezza con $who è cambiato';
  }

  @override
  String durationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secondi',
      one: '1 secondo',
    );
    return '$_temp0';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuti',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ore',
      one: '1 ora',
    );
    return '$_temp0';
  }

  @override
  String durationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '1 giorno',
    );
    return '$_temp0';
  }

  @override
  String durationWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count settimane',
      one: '1 settimana',
    );
    return '$_temp0';
  }

  @override
  String channelSubscribers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count iscritti',
      one: '1 iscritto',
    );
    return '$_temp0';
  }

  @override
  String channelMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membri',
      one: '1 membro',
    );
    return '$_temp0';
  }

  @override
  String get channelPublic => 'Pubblico';

  @override
  String get channelPrivate => 'Privato';

  @override
  String get channelAdministrators => 'Amministratori';

  @override
  String get channelSubscribersRow => 'Iscritti';

  @override
  String get channelSettings => 'Impostazioni del canale';

  @override
  String get channelShareLink => 'Condividi il link';

  @override
  String get channelDescription => 'Descrizione';

  @override
  String get channelMedia => 'Media';

  @override
  String get channelLinks => 'Link';

  @override
  String get channelNoMedia => 'Ancora nessuna immagine';

  @override
  String get channelNoLinks => 'Ancora nessun link';

  @override
  String get channelNoPosts => 'Ancora nessun post';

  @override
  String get channelActionLivestream => 'diretta';

  @override
  String get channelActionMute => 'silenzia';

  @override
  String get channelActionUnmute => 'riattiva';

  @override
  String get channelActionSearch => 'cerca';

  @override
  String get channelActionMore => 'altro';

  @override
  String get channelMuteTitle => 'Silenzia questo canale';

  @override
  String get channelMuteNote =>
      'Resta silenziato su tutti i dispositivi su cui hai effettuato l\'accesso: silenziarlo qui non significa «finché non prendo il portatile».';

  @override
  String get channelMuteForHour => 'Per 1 ora';

  @override
  String get channelMuteForEightHours => 'Per 8 ore';

  @override
  String get channelMuteForTwoDays => 'Per 2 giorni';

  @override
  String get channelMuteUntilOff => 'Finché non lo riattivo';

  @override
  String get channelCopyLink => 'Copia il link';

  @override
  String get channelQrCode => 'Codice QR';

  @override
  String get channelInviteSettings => 'Impostazioni degli inviti';

  @override
  String get channelStatistics => 'Statistiche';

  @override
  String get channelReport => 'Segnala il canale';

  @override
  String get channelLeave => 'Esci dal canale';

  @override
  String get channelLeaveTitle => 'Uscire da questo canale?';

  @override
  String get channelLeaveBody =>
      'Smetti di ricevere i suoi post. Il canale passa a una nuova chiave, quindi nulla di ciò che viene pubblicato dopo sarà leggibile per te.';

  @override
  String get channelStay => 'Resta';

  @override
  String get channelNoLinkToShare =>
      'Questo canale non ha nessun link da condividere.';

  @override
  String get channelInfo => 'Info del canale';

  @override
  String get adminsTitle => 'Amministratori';

  @override
  String get adminsSectionHeader => 'AMMINISTRATORI DEL CANALE';

  @override
  String get adminsAdd => 'Aggiungi amministratore';

  @override
  String get adminsSearch => 'Cerca amministratori';

  @override
  String get adminsRoleOwner => 'Proprietario';

  @override
  String get adminsRoleAdmin => 'Amministratore';

  @override
  String adminsPromotedBy(String who) {
    return 'nominato da $who';
  }

  @override
  String get adminsHelpOwner =>
      'Gli amministratori ti aiutano a gestire il tuo canale.';

  @override
  String get adminsHelpMember =>
      'Gli amministratori aiutano a gestire questo canale. Solo chi può nominare amministratori può modificare questo elenco.';

  @override
  String get adminsNobodyYet => 'Ancora nessuno.';

  @override
  String get adminsShowSenderName => 'Mostra il nome di chi pubblica';

  @override
  String get adminsShowSenderNameOn =>
      'I nuovi post portano il nome di chi li ha scritti';

  @override
  String get adminsShowSenderNameLocked =>
      'Può cambiarlo solo un amministratore che può modificare il canale';

  @override
  String get adminsShowSenderNameNote =>
      'Se è disattivo, tutto ciò che il canale pubblica è pubblicato dal canale: nessun nome di amministratore viene allegato e chi legge sente una sola voce.';

  @override
  String get adminsTransfer => 'Trasferisci la proprietà';

  @override
  String get adminsTransferNote =>
      'Chiede la tua password e non si può annullare';

  @override
  String get adminsEverybodyAlready =>
      'In questo canale sono già tutti amministratori.';

  @override
  String get adminsWhoShouldBe => 'Chi dovrebbe essere amministratore?';

  @override
  String get adminsDismiss => 'Revoca come amministratore';

  @override
  String get adminsAppoint => 'Nomina';

  @override
  String get adminsOwnerFixed =>
      'Il proprietario ha ogni permesso, e questo non è modificabile: né qui né sul server.';

  @override
  String get adminsOutranksYou =>
      'Ha permessi che tu non hai, quindi non puoi cambiare ciò che gli è consentito fare.';

  @override
  String get adminsOnlyWhatYouHold =>
      'Puoi concedere solo ciò che hai tu stesso. Quello che non hai è disattivato e non si può attivare.';

  @override
  String get adminsYouDoNotHold => 'Tu non hai questo permesso';

  @override
  String get adminsCouldNotChange => 'Non è stato possibile cambiarlo.';

  @override
  String get permissionEditChannel => 'Modificare il canale';

  @override
  String get permissionEditChannelDetail =>
      'Nome, immagine, descrizione e impostazioni';

  @override
  String get permissionPost => 'Pubblicare post';

  @override
  String get permissionPostDetail => 'E modificare o programmare i propri';

  @override
  String get permissionDeletePosts => 'Eliminare post';

  @override
  String get permissionDeletePostsDetail => 'Anche quelli di altre persone';

  @override
  String get permissionModerate => 'Moderare la discussione';

  @override
  String get permissionModerateDetail =>
      'Rimuovere commenti e silenziare persone';

  @override
  String get permissionManageMembers => 'Gestire gli iscritti';

  @override
  String get permissionManageMembersDetail =>
      'Aggiungere, rimuovere e silenziare';

  @override
  String get permissionManageInvites => 'Gestire gli inviti';

  @override
  String get permissionManageInvitesDetail =>
      'Il link, i suoi limiti e chi è in attesa';

  @override
  String get permissionManageLivestreams => 'Gestire le dirette';

  @override
  String get permissionManageLivestreamsDetail => 'Avviarle e terminarle';

  @override
  String get permissionAppointAdmins => 'Nominare amministratori';

  @override
  String get permissionAppointAdminsDetail =>
      'Affidare questa autorità a qualcun altro';

  @override
  String get subscribersTitle => 'Iscritti';

  @override
  String get subscribersAdd => 'Aggiungi iscritti';

  @override
  String get subscribersSearch => 'Cerca iscritti';

  @override
  String get subscribersAdminsOnlyNote =>
      'Solo gli amministratori del canale vedono questo elenco.';

  @override
  String get subscribersPartialNote =>
      'Questo non è l\'elenco completo. Solo gli amministratori del canale possono vedere chi è iscritto: quello che vedi qui sono le persone che lo gestiscono, e tu.';

  @override
  String get subscribersCompleteNote => 'Tutti in questo canale.';

  @override
  String get subscribersContactsSection => 'CONTATTI IN QUESTO CANALE';

  @override
  String get subscribersOthersSection => 'ALTRI ISCRITTI';

  @override
  String get subscribersOnlySection => 'ISCRITTI';

  @override
  String get subscribersNobodyFound => 'Nessuno trovato.';

  @override
  String get subscribersNoContacts => 'Ancora nessun contatto da aggiungere.';

  @override
  String get subscribersEverybodyHere => 'Tutti i tuoi contatti sono già qui.';

  @override
  String get subscribersAddedOne => 'Aggiunto.';

  @override
  String subscribersAddedMany(int count) {
    return 'Aggiunte $count persone.';
  }

  @override
  String get subscribersNobodyAdded =>
      'Non è stato possibile aggiungere nessuno';

  @override
  String subscribersAddedCount(int count) {
    return 'Aggiunti: $count';
  }

  @override
  String subscribersNeedInvite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count persone hanno impostato il proprio account',
      one: '1 persona ha impostato il proprio account',
    );
    return '$_temp0 in modo che solo i propri contatti possano aggiungerle. Mandale il link e lasciale decidere.';
  }

  @override
  String get subscribersCopyTheLink => 'Copia il link';

  @override
  String get subscribersOwnerCannotBeRemoved =>
      'Il proprietario non può essere rimosso.';

  @override
  String get subscribersSilenced => 'Silenziato';

  @override
  String get subscribersSilence => 'Silenzialo';

  @override
  String get subscribersSilenceDetail =>
      'Resta iscritto e non può più commentare';

  @override
  String get subscribersUnsilence => 'Fallo parlare di nuovo';

  @override
  String get subscribersUnsilenceDetail => 'Può commentare di nuovo';

  @override
  String get subscribersRemoveFromChannel => 'Rimuovi dal canale';

  @override
  String get subscribersRemoveDetail =>
      'Il canale passa a una nuova chiave, quindi non potrà leggere ciò che viene dopo';

  @override
  String get subscribersCouldNotDoThat => 'Non è stato possibile farlo.';

  @override
  String get presenceOnline => 'online';

  @override
  String presenceMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minuti',
      one: '1 minuto',
    );
    return 'visto $_temp0 fa';
  }

  @override
  String presenceHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ore',
      one: '1 ora',
    );
    return 'visto $_temp0 fa';
  }

  @override
  String presenceDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '1 giorno',
    );
    return 'visto $_temp0 fa';
  }

  @override
  String presenceOnDate(String date) {
    return 'visto il $date';
  }

  @override
  String get editChannelName => 'Nome del canale';

  @override
  String get editChannelDescriptionHint => 'Descrizione';

  @override
  String get editChannelChangePicture => 'Cambia immagine';

  @override
  String get editChannelChoosePicture => 'Scegli un\'immagine';

  @override
  String get editChannelRemovePicture => 'Rimuovila';

  @override
  String get editChannelPrivateNameNote =>
      'Questo canale è privato, quindi il suo nome è cifrato con la chiave del canale. Rinominarlo lo risigilla per ogni membro.';

  @override
  String get editChannelType => 'Tipo di canale';

  @override
  String get editChannelDiscussion => 'Discussione';

  @override
  String get editChannelReactions => 'Reazioni';

  @override
  String editChannelReactionsValue(int count) {
    return '$count emoji';
  }

  @override
  String get editChannelWelcome => 'Messaggio di benvenuto';

  @override
  String get editChannelAppearance => 'Aspetto';

  @override
  String get editChannelAutoTranslate => 'Traduzione automatica';

  @override
  String get editChannelDirectMessages => 'Messaggi diretti';

  @override
  String get editChannelNeedsName => 'Un canale ha bisogno di un nome.';

  @override
  String get editChannelDiscardTitle => 'Scartare le modifiche?';

  @override
  String get editChannelDiscardBody => 'Qui non è ancora stato salvato niente.';

  @override
  String get editChannelKeepEditing => 'Continua a modificare';

  @override
  String get editChannelDiscard => 'Scarta';

  @override
  String get editChannelCouldNotSave =>
      'Non è stato possibile salvare le modifiche.';

  @override
  String get editChannelCouldNotUsePicture =>
      'Non è stato possibile usare quell\'immagine.';

  @override
  String get editChannelPublicPictureTitle => 'Questa immagine sarà pubblica';

  @override
  String get editChannelPublicPictureBody =>
      'L\'immagine di un canale pubblico viene mostrata sulla sua pagina web e nelle anteprime dei link, quindi è archiviata senza cifratura, come il nome, il nome utente e la descrizione. I post restano cifrati end-to-end.';

  @override
  String get editChannelUseIt => 'Usala';

  @override
  String get editChannelSignatureNote =>
      'I post firmati mostrano il nome di chi li ha scritti. Se è disattivo, tutto ciò che il canale pubblica è pubblicato dal canale.';

  @override
  String get livestreamNotSetUpTitle => 'Le dirette non sono configurate';

  @override
  String get livestreamNotSetUpBody =>
      'Una diretta ha bisogno di un server multimediale: una persona invia il video e tutte le altre lo ricevono, cosa che non si può fare da dispositivo a dispositivo come in una chiamata.\n\nQuesto server PRIVIO non ne ha nessuno configurato, quindi non c\'è ancora niente a cui unirsi. Chi lo gestisce può configurarne uno.';

  @override
  String get livestreamYouAreLive => 'Sei in diretta';

  @override
  String get livestreamRunning => 'È in corso una diretta';

  @override
  String get livestreamPublisherBody =>
      'La stanza è aperta e il tuo dispositivo ha un token per trasmettere. PRIVIO non trasporta ancora il video vero e proprio — lo fa il server multimediale — quindi da questa schermata non viene inviato niente.\n\nTerminala quando hai finito.';

  @override
  String get livestreamViewerBody =>
      'È in corso una diretta e questo dispositivo ha un token per guardarla. PRIVIO non può ancora mostrare il video.';

  @override
  String get livestreamEndIt => 'Terminala';

  @override
  String get livestreamNobodyStreaming =>
      'Al momento non sta trasmettendo nessuno.';

  @override
  String get livestreamCouldNotStart =>
      'Non è stato possibile avviare la diretta.';

  @override
  String get translationNotSetUpTitle =>
      'La traduzione automatica non è configurata';

  @override
  String get translationNotSetUpBody =>
      'Tradurre un post significa inviare ciò che dice a un servizio di traduzione. Il server di PRIVIO non può farlo — conserva testo cifrato e nessuna chiave — quindi dovrebbe avvenire sul tuo dispositivo, e il testo ne uscirebbe in chiaro.\n\nÈ una decisione che deve abilitare chi gestisce questo server e che ogni lettore deve accettare, quindi resta disattivata finché non sono avvenute entrambe le cose. Nessun post è stato inviato da nessuna parte.';

  @override
  String get visibilityPublicTitle => 'Questo canale è pubblico';

  @override
  String get visibilityPrivateTitle => 'Questo canale è privato';

  @override
  String visibilityPublicBody(String handle) {
    return 'Chiunque può trovarlo per nome e leggere i suoi post. Il suo nome utente è @$handle.\n\nPRIVIO non può rendere privato un canale pubblico a posteriori: il suo nome e la sua descrizione sono stati leggibili, e disdire questo non è qualcosa che un\'app possa fare.';
  }

  @override
  String get visibilityPrivateBody =>
      'Non è elencato, non è ricercabile e si raggiunge solo tramite il suo link di invito. Il suo nome è cifrato con la chiave del canale.\n\nRenderlo pubblico pubblicherebbe quel nome, e questa non è una decisione che PRIVIO prende per te: crea invece un canale pubblico.';

  @override
  String get discussionBody =>
      'Con questa opzione attiva, ogni post ha un thread sotto di sé. I commenti sono sigillati con la stessa chiave del canale del post, quindi un dispositivo che non può leggere il post non può leggere il thread.\n\nDisattivarla più tardi nasconde i thread invece di eliminarli.';

  @override
  String get discussionTurnOn => 'Attiva';

  @override
  String get discussionTurnOff => 'Disattiva';

  @override
  String get welcomeShowToNew => 'Mostralo ai nuovi iscritti';

  @override
  String get welcomeHint => 'Mostrato una volta, all\'ingresso';

  @override
  String get welcomePrivateNote =>
      'Questo canale è privato, quindi il messaggio è cifrato con la chiave del canale, come il suo nome.';

  @override
  String get appearanceNote =>
      'Un insieme fisso invece di un selettore di colori: ogni combinazione qui è stata verificata per il contrasto, così un canale non può scegliere qualcosa che chi lo legge non riesce a leggere.';

  @override
  String get appearancePreviewPost => 'Un post in questo canale';

  @override
  String get appearancePreviewLink => 'e un link al suo interno';

  @override
  String get appearanceAccent => 'Colore d\'accento';

  @override
  String get appearanceBackground => 'Sfondo';

  @override
  String get appearanceUseDefault => 'Usa il predefinito';

  @override
  String get composerHint => 'Scrivi un messaggio…';

  @override
  String get composerAttach => 'Allega un file';

  @override
  String get composerTimerOff => 'I messaggi a tempo sono disattivati';

  @override
  String composerTimerOn(String badge) {
    return 'I messaggi scompaiono dopo $badge';
  }

  @override
  String get searchPostsHint => 'Cerca nei post che puoi leggere';

  @override
  String get searchThisChannel => 'Cerca in questo canale';

  @override
  String get searchClose => 'Chiudi la ricerca';

  @override
  String get searchNoResults => 'Nessun risultato';
}
