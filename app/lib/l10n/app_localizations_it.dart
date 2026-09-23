// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppTextIt extends AppText {
  AppTextIt([String locale = 'it']) : super(locale);

  @override
  String get accountPhoneNote =>
      'Informazione facoltativa. Il tuo numero di telefono non viene verificato né utilizzato per trovare automaticamente i contatti.';

  @override
  String get accountPhoneUnverified =>
      'Non verificato — non è una prova d’identità';

  @override
  String get accountPhoneVerifiedSeparate =>
      'Un numero verificato separatamente resta invariato. Gestiscilo in Impostazioni → Privacy → Numero di telefono e contatti.';

  @override
  String get accountPhoneSaveError =>
      'Impossibile caricare o salvare il numero. Riprova.';

  @override
  String get accountPhoneSaved => 'Salvato';

  @override
  String get accountPhoneSessionEnded =>
      'La sessione del tuo account è cambiata. Riapri questa impostazione dal tuo account.';

  @override
  String get contactProfileTitle => 'Profilo del contatto';

  @override
  String get contactProfileMessage => 'Scrivi un messaggio';

  @override
  String get contactProfileRemove => 'Rimuovi contatto';

  @override
  String get contactProfileMissing =>
      'Questo account non esiste più o non è disponibile.';

  @override
  String get contactProfileError =>
      'Impossibile caricare o aggiornare il profilo. Riprova.';

  @override
  String get contactProfileSessionEnded =>
      'Questa sessione è terminata. Riapri il profilo dal tuo account.';

  @override
  String get contactProfileBlockNote =>
      'Non riceverai più messaggi da questa persona. La cronologia resta su questo dispositivo.';

  @override
  String get contactProfileYou => 'Tu';

  @override
  String get proxyTitle => 'Proxy SOCKS5';

  @override
  String get proxyEnable => 'Usa proxy';

  @override
  String get proxyHost => 'Server (nome o IP)';

  @override
  String get proxyPort => 'Porta';

  @override
  String get proxyUsername => 'Nome utente (facoltativo)';

  @override
  String get proxyPassword => 'Password (facoltativa)';

  @override
  String get proxyScope =>
      'Per questo dispositivo: accesso, messaggi, file e backup. Le chiamate sono disattivate con il proxy. Nessun ripiego diretto. Salva le modifiche.';

  @override
  String get proxyPrivacy =>
      'Le notifiche di sistema e i link aperti nel browser non usano questo proxy. SOCKS5 non cifra le credenziali del proxy; usa una rete e un proxy affidabili. Il proxy vede il tuo IP e la destinazione; HTTPS resta cifrato. I proxy MTProto di Telegram non sono supportati.';

  @override
  String get proxyTest => 'Verifica connessione';

  @override
  String get proxySave => 'Salva';

  @override
  String get proxyRemove => 'Rimuovi proxy e connettiti direttamente';

  @override
  String get proxyInvalid =>
      'Inserisci un server valido e una porta (1–65535). Compila utente e password oppure lascia entrambi vuoti.';

  @override
  String get proxyTestSuccess =>
      'Privio è raggiungibile tramite questo proxy. Le impostazioni non sono ancora salvate.';

  @override
  String get proxySaved => 'Impostazioni di rete salvate.';

  @override
  String get proxyFailed =>
      'Operazione non riuscita. Controlla proxy, credenziali e connessione e termina le chiamate. Nessun ripiego diretto automatico.';

  @override
  String get proxyCallsBlocked =>
      'Le chiamate non sono disponibili con il proxy attivo.';

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
  String get settingsAppearance => 'Aspetto';

  @override
  String get settingsNotifications => 'Notifiche';

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
  String noticeUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messaggi',
      one: 'Un messaggio',
    );
    return '$_temp0 non è stato possibile leggerlo. Era sigillato con una chiave che questo dispositivo non ha più.';
  }

  @override
  String noticeUnreadableFrom(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messaggi',
      one: 'Un messaggio',
    );
    return '$_temp0 da $who non è stato possibile leggerlo. Era sigillato con una chiave che questo dispositivo non ha più.';
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
  String get composerAttach => 'Allega';

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

  @override
  String get settingsPrivacy => 'Privacy e sicurezza';

  @override
  String get settingsStorage => 'Dati e archiviazione';

  @override
  String get settingsAbout => 'Informazioni su Privio';

  @override
  String get settingsDevices => 'Dispositivi';

  @override
  String get settingsBackup => 'Backup';

  @override
  String get settingsDisguise => 'Modalità travestimento';

  @override
  String get settingsLicense => 'Licenza Privio';

  @override
  String get settingsLicenseNotActive => 'Non attiva';

  @override
  String get appearanceTextSize => 'Dimensione del testo';

  @override
  String get appearanceTextSizeNote =>
      'Questa è l\'impostazione di Privio e vale in tutta l\'app. Non sostituisce la dimensione impostata sul telefono per tutto il resto: quella continua a valere sotto.';

  @override
  String get appearanceDarkOnly =>
      'Privio è solo scuro. Il design è fatto per questo, il nero pieno non costa nulla sui pannelli OLED della maggior parte dei telefoni, e un tema chiaro che esiste solo a metà non merita un interruttore che finga il contrario.';

  @override
  String get textSizeSmall => 'Piccolo';

  @override
  String get textSizeMedium => 'Medio';

  @override
  String get textSizeLarge => 'Grande';

  @override
  String get textSizeLarger => 'Più grande';

  @override
  String get notificationsPushNote =>
      'Una notifica push non porta contenuti, solo un segnale di risveglio. Il messaggio viene scaricato e decifrato su questo dispositivo, quindi nessuno nel mezzo vede chi ti ha scritto, nemmeno chi gestisce il servizio che lo ha svegliato.';

  @override
  String get notificationsPhoneNote =>
      'Suono, vibrazione, la spia luminosa e se qualcosa compare sulla schermata di blocco appartengono alle impostazioni del telefono per Privio, non a questa schermata.';

  @override
  String get notificationsDelivery => 'Recapito';

  @override
  String notificationsDistributorFound(String app) {
    return 'Un\'app distributore su questo telefono tiene una sola connessione per tutte le app che la usano e inoltra un segnale senza contenuto. $app non ha bisogno di alcun servizio Google per questo, e puoi gestire il distributore tu stesso.';
  }

  @override
  String get notificationsNoDistributor =>
      'Nessun distributore trovato. Installane uno — ntfy, per esempio — per essere svegliato mentre Privio è chiuso. Senza, i messaggi arrivano mentre l\'app è aperta.';

  @override
  String get privacyWhoCanSee => 'Chi può vedere';

  @override
  String get privacyLastSeen => 'Ultimo accesso';

  @override
  String get privacyLastSeenEveryone => 'Tutti';

  @override
  String get privacyLastSeenContacts => 'I miei contatti';

  @override
  String get privacyLastSeenNobody => 'Nessuno';

  @override
  String get privacyMessaging => 'Messaggi';

  @override
  String get privacyReadReceipts => 'Conferme di lettura';

  @override
  String get privacyTypingIndicators => 'Indicatori di scrittura';

  @override
  String get privacyDisappearing => 'Messaggi a tempo';

  @override
  String get privacyPerChat => 'Per chat';

  @override
  String get privacyAccess => 'Accesso';

  @override
  String get privacyScreenLock => 'Blocco schermo';

  @override
  String get privacyPin => 'PIN';

  @override
  String get privacyTwoFactor => 'Autenticazione a due fattori';

  @override
  String get privacyDuressCode => 'Codice di emergenza';

  @override
  String get privacyScreenShield => 'Protezione dello schermo';

  @override
  String get privacyScreenShieldAndroid =>
      'Blocca screenshot e registrazioni dello schermo dell\'app.';

  @override
  String get privacyScreenShieldIos =>
      'Nasconde i contenuti sensibili quando viene rilevata una registrazione o una condivisione dello schermo. Su iOS gli screenshot non possono essere impediti in modo affidabile.';

  @override
  String get privacyScreenShieldUnavailable =>
      'Questo dispositivo non può proteggere lo schermo.';

  @override
  String get privacyScreenShieldScope =>
      'Protegge soltanto il tuo dispositivo. Non impedisce ad altri di registrare il proprio schermo, né una foto scattata con un\'altra fotocamera.';

  @override
  String get privacyScreenShieldCovering =>
      'È in corso una registrazione dello schermo. Privio resta nascosto finché non termina.';

  @override
  String get privacySet => 'Impostato';

  @override
  String get privacyBlockedUsers => 'Utenti bloccati';

  @override
  String get privacyMutualNote =>
      'Le conferme di lettura e gli indicatori di scrittura sono reciproci: se li disattivi, non vedrai più nemmeno quelli degli altri.';

  @override
  String get storageOnThisDevice => 'Su questo dispositivo';

  @override
  String get storageHistory => 'Cronologia delle conversazioni';

  @override
  String get storageInIt => 'Contenuto';

  @override
  String storageChatsAndMessages(int chats, int messages) {
    String _temp0 = intl.Intl.pluralLogic(
      chats,
      locale: localeName,
      other: '$chats chat',
      one: '1 chat',
    );
    String _temp1 = intl.Intl.pluralLogic(
      messages,
      locale: localeName,
      other: '$messages messaggi',
      one: '1 messaggio',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get storageKeys => 'Chiavi e sessioni';

  @override
  String get storageKeystoreNote =>
      'Entrambi stanno nel portachiavi della piattaforma — il Portachiavi su iOS, l\'archiviazione basata su Keystore su Android — e la cronologia viene sigillata con AES-256-GCM prima di arrivarci. Nessuno dei due è leggibile da un\'altra app, né da chi ha in mano il telefono senza sbloccarlo.';

  @override
  String get storageNotKept => 'Non conservato';

  @override
  String get storageFilesOpened => 'File che hai aperto';

  @override
  String get storageMemoryOnly => 'Solo in memoria';

  @override
  String get storageVoiceRecordings => 'Registrazioni vocali';

  @override
  String get storageShredded => 'Distrutte all\'invio';

  @override
  String get storageEphemeralNote =>
      'Una foto o un file che apri viene decifrato in memoria e sparisce alla chiusura dell\'app; nulla lo scrive su disco. Un messaggio vocale viene registrato in un file temporaneo, perché il microfono deve pur scrivere da qualche parte, e quel file viene sovrascritto con byte casuali ed eliminato appena la registrazione finisce: un file eliminato su memoria flash non è un file sparito.';

  @override
  String get storageDelete => 'Elimina';

  @override
  String get storageDeleteHistory =>
      'Elimina la cronologia su questo dispositivo';

  @override
  String get storageDeleteNote =>
      'Questa è l\'unica eliminazione che avviene qui. Quello che tiene il server — un backup, un allegato ancora entro i suoi trenta giorni — è nella schermata Backup, e quello che ha la persona a cui hai scritto è suo.';

  @override
  String get storageConfirmTitle =>
      'Eliminare la cronologia su questo dispositivo?';

  @override
  String get storageConfirmBody =>
      'Ogni messaggio su questo telefono sparisce, in ogni chat. Il tuo account, le tue chiavi e le tue conversazioni restano: ti si può ancora scrivere, e quello che invii dopo arriva ancora.\n\nNon raggiunge la loro copia, né un backup già sul server. Elimina quello dalla schermata Backup se vuoi che sparisca anche lui.';

  @override
  String get storageDeleteIt => 'Eliminala';

  @override
  String get storageDeleted => 'La cronologia su questo dispositivo è sparita.';

  @override
  String get devicesThisDevice => 'Questo dispositivo';

  @override
  String get devicesOthers => 'Altri dispositivi';

  @override
  String get devicesOthersTapToSignOut =>
      'Altri dispositivi — tocca per disconnettere';

  @override
  String get devicesNone => 'Nessuno';

  @override
  String get devicesOnlyThisOne => 'Solo questo';

  @override
  String get devicesSignedIn => 'Connesso';

  @override
  String get devicesActiveNow => 'Attivo ora';

  @override
  String devicesActiveMinutes(int count) {
    return 'Attivo $count min fa';
  }

  @override
  String devicesActiveHours(int count) {
    return 'Attivo $count h fa';
  }

  @override
  String get devicesActiveYesterday => 'Attivo ieri';

  @override
  String devicesActiveDays(int count) {
    return 'Attivo $count giorni fa';
  }

  @override
  String get devicesSignOutNote =>
      'Disconnettere un dispositivo revoca la sua sessione ed elimina tutto ciò che è ancora in coda per lui. Può tornare solo accedendo di nuovo — come nuovo dispositivo, con nuove chiavi.';

  @override
  String devicesRevokeTitle(String name) {
    return 'Disconnettere $name?';
  }

  @override
  String get devicesRevokeBody =>
      'La sua sessione viene revocata e tutto ciò che è ancora in coda per lui viene eliminato. Quello che ha già decifrato resta su quel dispositivo: da qui non è raggiungibile. Può tornare solo accedendo di nuovo.';

  @override
  String get devicesSignItOut => 'Disconnettilo';

  @override
  String devicesSignedOut(String name) {
    return '$name è stato disconnesso.';
  }

  @override
  String devicesLicenseCovers(int limit) {
    return 'La tua licenza copre $limit dispositivi.';
  }

  @override
  String devicesLicenseCoversUsed(int limit, int used) {
    return 'La tua licenza copre $limit dispositivi. $used in uso.';
  }

  @override
  String get aboutTagline =>
      'Costruito pensando alla privacy.\nNessun tracciamento. Nessuna pubblicità. Solo tu.';

  @override
  String get aboutWebsite => 'Sito web';

  @override
  String get aboutSupport => 'Assistenza';

  @override
  String get aboutAddress => 'Indirizzo';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutEdition => 'Edizione';

  @override
  String aboutFreeSoftware(String name) {
    return '$name · software libero';
  }

  @override
  String get aboutLicense => 'Licenza';

  @override
  String get aboutSourceCode => 'Codice sorgente';

  @override
  String get aboutCopyLink => 'Copia il link';

  @override
  String get aboutSourceLink => 'Link al sorgente';

  @override
  String get aboutThirdParty => 'Licenze di terze parti';

  @override
  String aboutCopied(String what) {
    return '$what copiato.';
  }

  @override
  String get aboutFreeBuildNote =>
      'Questa build non contiene codice proprietario e può essere riprodotta dal sorgente qui sopra. Niente qui va preso sulla fiducia: compilala tu stesso e confronta.';

  @override
  String get aboutStoreBuildNote =>
      'Questa build viene da uno store di app e collega i suoi servizi. La build Libre, al sorgente qui sopra, non ne contiene nessuno.';

  @override
  String get blockedUnblock => 'Sblocca';

  @override
  String blockedUnblockTitle(String name) {
    return 'Sbloccare $name?';
  }

  @override
  String get blockedUnblockBody => 'Potrà inviarti di nuovo messaggi.';

  @override
  String get blockedInvisibleNote =>
      'Il blocco è invisibile: i loro messaggi vengono scartati e non viene detto loro nulla, quindi un blocco non può servire a scoprire di essere stati bloccati.';

  @override
  String get blockedNobody => 'Nessuno è bloccato';

  @override
  String get blockedEmptyNote =>
      'Blocca qualcuno dalla sua chat e comparirà qui.';

  @override
  String get chatsSectionChats => 'Chat';

  @override
  String get chatsSectionMessages => 'Messaggi';

  @override
  String get chatsYouPrefix => 'Tu: ';

  @override
  String get chatsNoSearchResults =>
      'Qui non corrisponde nulla. È stato interrogato solo questo dispositivo: il server tiene messaggi che non può leggere, quindi non avrebbe potuto rispondere.';

  @override
  String get chatsFilterAll => 'Tutte';

  @override
  String get chatsJoin => 'Partecipa';

  @override
  String get chatsFilterUnread => 'Non letti';

  @override
  String get chatsFilterGroups => 'Gruppi';

  @override
  String get chatsPin => 'Fissa in alto';

  @override
  String get chatsUnpin => 'Rimuovi dai fissati';

  @override
  String get chatsPinNote =>
      'Solo su questo dispositivo. Non viene inviato nulla.';

  @override
  String get chatsGroupFallbackName => 'Gruppo';

  @override
  String get chatsNewGroupTooltip => 'Nuovo gruppo';

  @override
  String get chatsNewChatTooltip => 'Nuova chat';

  @override
  String get chatsEmptyTitle => 'Ancora nessuna chat';

  @override
  String get chatsEmptyBody =>
      'Aggiungi qualcuno con il suo nome utente esatto per iniziare a parlare.';

  @override
  String get chatsAddContact => 'Aggiungi un contatto';

  @override
  String get commonGotIt => 'Ho capito';

  @override
  String get commonPause => 'Pausa';

  @override
  String get commonPlay => 'Riproduci';

  @override
  String get commonOpen => 'Apri';

  @override
  String get commonReply => 'Rispondi';

  @override
  String get commonFile => 'File';

  @override
  String get scrubRemoved => 'Metadati rimossi';

  @override
  String get scrubNothingToRemove => 'Niente da rimuovere';

  @override
  String get scrubCouldNotClean => 'Non è stato possibile ripulirlo';

  @override
  String get scrubRemovedBody =>
      'Questo è stato tolto prima che il file venisse cifrato e inviato. Chi lo riceve non lo ottiene mai.';

  @override
  String get scrubNothingBody =>
      'Questo file non conteneva metadati identificativi fin dall\'inizio.';

  @override
  String scrubNoCleanerBody(String type) {
    return 'Privio non ha ancora un pulitore per $type, quindi il file è stato inviato così com\'è. Resta cifrato end-to-end, ma tutti i metadati al suo interno raggiungono chi lo riceve.';
  }

  @override
  String get webStorageShort =>
      'In un browser, la cronologia di questo dispositivo è privata quanto lo è questo profilo del browser. I messaggi in transito sono cifrati in ogni caso.';

  @override
  String get webStorageLong =>
      'Stai usando Privio in un browser. I messaggi restano cifrati end-to-end in transito, ma un browser non ha un portachiavi, quindi la cronologia tenuta su questo dispositivo è privata quanto lo è questo profilo del browser. Chiunque possa leggerlo — un computer condiviso, un\'estensione, una copia del profilo — può leggere le tue chat. Le app per telefono non hanno questo problema.';

  @override
  String get voiceCouldNotOpen =>
      'Non è stato possibile aprire questa registrazione.';

  @override
  String get voiceCannotPlay =>
      'Questo dispositivo non può riprodurre quella registrazione.';

  @override
  String get voiceMicUnavailable =>
      'Il microfono non è disponibile in questo momento.';

  @override
  String get voiceCouldNotSave =>
      'Non è stato possibile salvare quella registrazione.';

  @override
  String get voiceSlideToCancel => 'Scorri per annullare';

  @override
  String get voiceResume => 'Riprendi';

  @override
  String get voiceStop => 'Ferma';

  @override
  String get voiceDeleteRecording => 'Elimina la registrazione';

  @override
  String get voiceListenBack => 'Riascolta';

  @override
  String get bubbleYouDeleted => 'Hai eliminato questo messaggio';

  @override
  String get bubbleMessageDeleted => 'Questo messaggio è stato eliminato';

  @override
  String get bubbleCouldNotOpen => 'Non è stato possibile aprire';

  @override
  String get bubbleEncryptedNotice =>
      'I messaggi e le chiamate sono cifrati end-to-end. Nessuno fuori da questa chat può leggerli o ascoltarli, nemmeno Privio.';

  @override
  String get linkNotWebAddress => 'Quel link non è un indirizzo web.';

  @override
  String get linkNothingCanOpen =>
      'Niente su questo dispositivo è riuscito ad aprire quel link.';

  @override
  String get linkOpenTitle => 'Aprire questo link?';

  @override
  String get linkOpenBody =>
      'Si apre nel tuo browser, fuori da Privio. Il sito vede la tua connessione come qualsiasi sito che visiti.';

  @override
  String timerBadgeDays(int count) {
    return '$count g';
  }

  @override
  String timerBadgeHours(int count) {
    return '$count h';
  }

  @override
  String timerBadgeMinutes(int count) {
    return '$count min';
  }

  @override
  String timerBadgeSeconds(int count) {
    return '$count s';
  }

  @override
  String get chatSafetyNumberChanged => 'Numero di sicurezza cambiato';

  @override
  String get chatEncrypted => 'Cifrato end-to-end';

  @override
  String get chatEncryptedVerified => 'Cifrato end-to-end · verificato';

  @override
  String get chatEncryptedNumberChanged =>
      'Cifrato end-to-end · numero cambiato';

  @override
  String get chatWaitingGroupKey => 'In attesa della chiave del gruppo';

  @override
  String chatMembersEncrypted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membri',
      one: '1 membro',
    );
    return '$_temp0 · cifrato';
  }

  @override
  String get chatRetrySendTitle => 'Riprova';

  @override
  String get chatRetryFailed => 'Non è partito. Invialo ora.';

  @override
  String get chatRetryQueued => 'In attesa di rete. Prova comunque ora.';

  @override
  String get chatCopyText => 'Copia il testo';

  @override
  String get chatDeleteForMe => 'Elimina per me';

  @override
  String get chatDeleteForMeNote =>
      'Sparisce da questo dispositivo. Gli altri lo conservano.';

  @override
  String get chatDeleteForEveryone => 'Elimina per tutti';

  @override
  String get chatDeleteForEveryoneNote =>
      'Chiede alla loro app di dimenticarlo. Non può riprendersi ciò che è già stato letto, catturato in uno screenshot o ripristinato da un backup.';

  @override
  String get chatPickerNoResponse => 'Il selettore di file non ha risposto.';

  @override
  String chatPickerFailed(String reason) {
    return 'Non è stato possibile aprire il selettore di file: $reason';
  }

  @override
  String chatCouldNotReadFile(String name) {
    return 'Non è stato possibile leggere $name.';
  }

  @override
  String chatBlockTitle(String name) {
    return 'Bloccare $name?';
  }

  @override
  String get chatBlockBody =>
      'I loro messaggi smettono di arrivare. Non gliene viene detto nulla, e per loro sembra che niente sia cambiato. Puoi toglierlo in Privacy e sicurezza.';

  @override
  String get chatBlock => 'Blocca';

  @override
  String chatBlocked(String name) {
    return '$name è bloccato.';
  }

  @override
  String get chatCouldNotBlock => 'Non è stato possibile bloccarlo.';

  @override
  String get chatMicrophoneDenied =>
      'Privio non può registrare senza accesso al microfono. Puoi concederlo nelle impostazioni del dispositivo.';

  @override
  String get chatNoGroupLink =>
      'Ancora nessun link per questo gruppo: tira per aggiornare.';

  @override
  String get chatInviteLink => 'Link di invito';

  @override
  String get chatInviteLinkNote =>
      'Condividilo ovunque: non porta nessuna chiave. Chi lo apre entra nel gruppo, e la chiave del suo nome arriva cifrata sul suo dispositivo.';

  @override
  String get chatTyping => 'sta scrivendo…';

  @override
  String get chatVideoCall => 'Videochiamata';

  @override
  String get chatVoiceCall => 'Chiamata vocale';

  @override
  String get chatMore => 'Altro';

  @override
  String get chatGroupInfo => 'Info del gruppo';

  @override
  String get chatSafetyNumber => 'Numero di sicurezza';

  @override
  String get chatActivate => 'Attiva';

  @override
  String get chatSend => 'Invia';

  @override
  String get chatHoldToRecord =>
      'Tieni premuto il microfono per registrare un messaggio vocale.';

  @override
  String get chatReplyingToYourself => 'Stai rispondendo a te stesso';

  @override
  String chatReplyingTo(String name) {
    return 'Stai rispondendo a $name';
  }

  @override
  String get chatReplying => 'Stai rispondendo';

  @override
  String get chatCancelReply => 'Annulla la risposta';

  @override
  String get contactsTitle => 'Contatti';

  @override
  String get contactsSearch => 'Cerca contatti';

  @override
  String contactsLastSeen(String username, String when) {
    return '@$username · ultimo accesso $when';
  }

  @override
  String get contactsSeenJustNow => 'proprio ora';

  @override
  String contactsSeenMinutes(int count) {
    return '$count min fa';
  }

  @override
  String contactsSeenAtTime(String time) {
    return 'alle $time';
  }

  @override
  String contactsSeenDays(int count) {
    return '$count g fa';
  }

  @override
  String get contactsCouldNotAdd =>
      'Non è stato possibile aggiungere quell\'utente';

  @override
  String get contactsAddTitle => 'Aggiungi contatto';

  @override
  String get contactsAddNote =>
      'Inserisci il loro nome utente Privio esatto. Dalla tua rubrica non viene caricato niente, e nessuno può trovarti scorrendo un elenco.';

  @override
  String get contactsUsernameHint => 'nome utente';

  @override
  String get contactsEmptyTitle => 'Ancora nessun contatto';

  @override
  String get contactsEmptyBody =>
      'Aggiungi qualcuno con il suo nome utente esatto, o condividi il tuo link di invito dalla scheda Account.';

  @override
  String get groupCouldNotCreate => 'Non è stato possibile creare il gruppo';

  @override
  String get groupNewTitle => 'Nuovo gruppo';

  @override
  String get groupCreate => 'Crea';

  @override
  String get groupName => 'Nome del gruppo';

  @override
  String get groupNameEncryptedNote =>
      'Il nome è cifrato. Privio conserva un gruppo che non può nominare.';

  @override
  String get groupChooseMembers => 'Scegli i membri';

  @override
  String groupSelectedCount(int count) {
    return '$count selezionati';
  }

  @override
  String get groupAddContactsFirst =>
      'Aggiungi prima qualche contatto: un gruppo ha bisogno di persone.';

  @override
  String get groupInfoCouldNotRead =>
      'Non è stato possibile leggere chi è in questo gruppo.';

  @override
  String get groupAdminOnly => 'Solo un amministratore può cambiarlo';

  @override
  String get groupRename => 'Rinomina il gruppo';

  @override
  String get groupRenameAction => 'Rinomina';

  @override
  String get groupRenamed =>
      'Rinominato. Tutti gli altri aprono il nuovo nome con la chiave che hanno già.';

  @override
  String get groupCouldNotRename =>
      'Non è stato possibile rinominare il gruppo.';

  @override
  String groupRemoveTitle(String name) {
    return 'Rimuovere $name?';
  }

  @override
  String get groupRemoveBody =>
      'Da ora in poi non ricevono più ciò che viene inviato. Quello che hanno già ricevuto resta sul loro dispositivo: da qui non è raggiungibile.';

  @override
  String get groupCouldNotRemove => 'Non è stato possibile rimuoverlo.';

  @override
  String get groupLeaveTitle => 'Uscire da questo gruppo?';

  @override
  String get groupLeaveBody =>
      'Smetti di ricevere ciò che viene inviato lì, e la conversazione sparisce da questo dispositivo con tutto quello che contiene. Non viene detto a nessuno; gli altri ti vedono sparire dall\'elenco dei membri.';

  @override
  String get groupLeave => 'Esci';

  @override
  String get groupLeaveRow => 'Esci dal gruppo';

  @override
  String get groupDeleteTitle => 'Eliminare questo gruppo?';

  @override
  String get groupDeleteBody =>
      'Sparisce per tutti: nessuno può più inviare lì. Quello che è già stato consegnato resta sui dispositivi che lo hanno ricevuto, cioè ogni messaggio che qualcuno ha letto.';

  @override
  String get groupDeleteRow => 'Elimina il gruppo per tutti';

  @override
  String get groupYouSuffix => 'Tu';

  @override
  String get groupAdminSuffix => 'Amministratore';

  @override
  String get navChats => 'Chat';

  @override
  String get navChannels => 'Canali';

  @override
  String get navCalls => 'Chiamate';

  @override
  String get navContacts => 'Contatti';

  @override
  String get navAccount => 'Account';

  @override
  String get splashTagline => 'Messaggistica sicura';

  @override
  String get splashPromise => 'Cifrato. Privato. Tuo.';

  @override
  String get splashInitialising => 'Preparazione dell\'ambiente sicuro';

  @override
  String accountPickerFailed(String reason) {
    return 'Non è stato possibile aprire il selettore: $reason';
  }

  @override
  String accountCouldNotReadFile(String name, String reason) {
    return 'Non è stato possibile leggere $name: $reason';
  }

  @override
  String get accountCouldNotSetPicture =>
      'Non è stato possibile impostare l\'immagine';

  @override
  String get accountTapToAddPicture => 'Tocca per aggiungere un\'immagine';

  @override
  String get accountPictureEncrypted =>
      'Cifrata: solo i tuoi contatti possono vederla';

  @override
  String get accountUsername => 'Nome utente';

  @override
  String get accountStatus => 'Stato';

  @override
  String get accountStatusDefault => 'Ciao! Sto usando Privio.';

  @override
  String get accountStatusNone => 'Non impostato';

  @override
  String get accountStatusTitle => 'Stato';

  @override
  String get accountStatusHint => 'Che cosa stai facendo?';

  @override
  String get accountStatusEmoji => 'Emoji';

  @override
  String get accountStatusEmojiNone => 'Nessuna';

  @override
  String get accountStatusClearsAfter => 'Scompare dopo';

  @override
  String get accountStatusNeverClears => 'Mai';

  @override
  String get accountStatus30Minutes => '30 minuti';

  @override
  String get accountStatus1Hour => '1 ora';

  @override
  String get accountStatus4Hours => '4 ore';

  @override
  String get accountStatusToday => 'Oggi';

  @override
  String get accountStatus1Week => '1 settimana';

  @override
  String accountStatusUntil(String time) {
    return 'Fino alle $time';
  }

  @override
  String get accountStatusCouldNotSave =>
      'Il tuo stato non è stato salvato. Quello che hai scritto è ancora qui: riprova.';

  @override
  String get accountStatusSaving => 'Salvataggio…';

  @override
  String get accountStatusExplainer =>
      'Chi può vedere il tuo stato legge questo. Non è cifrato come i tuoi messaggi e non è il tuo stato online.';

  @override
  String get privacyProfileStatus => 'Stato';

  @override
  String get privacyProfileStatusEveryone => 'Tutti';

  @override
  String get privacyProfileStatusContacts => 'I miei contatti';

  @override
  String get privacyProfileStatusNobody => 'Nessuno';

  @override
  String get accountId => 'ID account';

  @override
  String get accountInviteRow => 'Link di invito / codice QR';

  @override
  String get accountLogOut => 'Esci';

  @override
  String get accountLogOutQuestion => 'Uscire?';

  @override
  String get accountLogOutBody =>
      'I tuoi messaggi restano cifrati su questo dispositivo finché non li elimini. Per rientrare ti servirà la password.';

  @override
  String get accountDelete => 'Elimina l\'account';

  @override
  String get accountDeleteTitle => 'Eliminare questo account?';

  @override
  String get accountDeleteBody =>
      'I tuoi dispositivi, le tue chiavi, i messaggi ancora in attesa di consegna, i tuoi contatti, i gruppi a cui appartieni e il tuo backup vengono tutti eliminati sul server. Tutto quello che c\'è su questo telefono se ne va con loro.\n\nNon raggiunge quello che altri hanno già ricevuto, e il tuo nome utente torna libero per qualcun altro.\n\nNon c\'è modo di annullare né di recuperare: né con la chiave di recupero, né scrivendo a qualcuno.';

  @override
  String get accountYourPassword => 'La tua password';

  @override
  String get accountDeleteIt => 'Eliminalo';

  @override
  String get inviteTitle => 'Invita';

  @override
  String get inviteTabLink => 'Link di invito';

  @override
  String get inviteTabQr => 'Codice QR';

  @override
  String get inviteYourLink => 'Il tuo link di invito';

  @override
  String get inviteCopied => 'Link di invito copiato';

  @override
  String get inviteCopyLink => 'Copia il link';

  @override
  String get inviteCopyInviteLink => 'Copia il link di invito';

  @override
  String get inviteNote =>
      'Condividi questo link per invitare altre persone su Privio. Rivela il tuo nome utente e nient\'altro.';

  @override
  String inviteScanToConnect(String username) {
    return 'Scansiona per collegarti con @$username';
  }

  @override
  String get callsClearHistory => 'Svuota la cronologia delle chiamate';

  @override
  String get callsClearTitle => 'Svuotare la cronologia delle chiamate?';

  @override
  String get callsClearBody =>
      'Questo elenco sta solo su questo dispositivo: svuotarlo lo toglie da qui e da nessun altro posto, perché non è mai stato altrove.';

  @override
  String get callsClear => 'Svuota';

  @override
  String get callsNeverLeavesNote =>
      'Questo elenco non lascia mai il dispositivo. Il server instrada la creazione di una chiamata come instrada un messaggio — sigillata e per lui illeggibile — quindi non conserva alcuna traccia di chi ha chiamato chi.';

  @override
  String callsCallSomeone(String name) {
    return 'Chiama $name';
  }

  @override
  String get callsDeclined => 'Rifiutata';

  @override
  String get callsNotTaken => 'Non accettata';

  @override
  String get callsBusy => 'Occupato';

  @override
  String get callsCouldNotConnect => 'Connessione non riuscita';

  @override
  String get callsMissed => 'Persa';

  @override
  String get callsNoAnswer => 'Nessuna risposta';

  @override
  String get callsEmptyTitle => 'Ancora nessuna chiamata';

  @override
  String get callsEmptyBody =>
      'Avviane una da una chat. La chiamata viene stabilita sulla sessione Signal che quella chat già usa, quindi gli indirizzi che i vostri due dispositivi si scambiano per trovarsi sono sigillati l\'uno per l\'altro e non per il server.';

  @override
  String get callCalling => 'Sto chiamando…';

  @override
  String get callIncomingVideo => 'Videochiamata in arrivo';

  @override
  String get callIncoming => 'Chiamata in arrivo';

  @override
  String get callConnecting => 'Connessione…';

  @override
  String get callEnded => 'Chiamata terminata';

  @override
  String get callDecline => 'Rifiuta';

  @override
  String get callAccept => 'Accetta';

  @override
  String get callMute => 'Muto';

  @override
  String get callUnmute => 'Riattiva';

  @override
  String get callCamera => 'Fotocamera';

  @override
  String get callCameraOff => 'Fotocamera spenta';

  @override
  String get callEnd => 'Chiudi';

  @override
  String get callSpeaker => 'Altoparlante';

  @override
  String get welcomePromiseEncrypted => 'Cifrato end-to-end';

  @override
  String get welcomePromiseNoPhone => 'Nessun numero di telefono richiesto';

  @override
  String get welcomePromiseControl => 'Il controllo è tuo';

  @override
  String get welcomePromiseByDesign => 'Privacy fin dalla progettazione';

  @override
  String get welcomeTo => 'Ti diamo il benvenuto su';

  @override
  String get welcomeGetStarted => 'Inizia';

  @override
  String get welcomeHaveAccount => 'Ho già un account';

  @override
  String get welcomeImportBackup => 'Importa da un backup';

  @override
  String get authCreateTitle => 'Crea il tuo account';

  @override
  String get authWelcomeBack => 'Bentornato';

  @override
  String get authCreateNote =>
      'Scegli un nome utente. Nessun numero di telefono, nessuna email: niente che colleghi questo account a qualcos\'altro.';

  @override
  String get authSignInNote => 'Accedi con il tuo nome utente e la password.';

  @override
  String get authUsernameRule =>
      'Da 3 a 32 caratteri: a-z, 0-9, punto o trattino basso';

  @override
  String get authPasswordRule => 'Almeno 10 caratteri: questa protegge tutto';

  @override
  String get authPasswordRequired => 'Inserisci la tua password';

  @override
  String get authTotpHint => 'codice a due fattori';

  @override
  String get authCreateAccount => 'Crea account';

  @override
  String get authSignIn => 'Accedi';

  @override
  String get authCreateNew => 'Crea un nuovo account';

  @override
  String get authPasswordOnlyWay =>
      'La tua password è l\'unico modo per entrare in questo account. Privio non può reimpostarla, perché Privio non può leggere nulla di ciò che aprirebbe.';

  @override
  String get pinEnterPassphrase => 'Inserisci la tua passphrase';

  @override
  String get pinEnterPasscode => 'Inserisci il tuo codice';

  @override
  String get pinPassphrase => 'Passphrase';

  @override
  String get pinWrong => 'Non è quello.';

  @override
  String get pinUnlock => 'Sblocca';

  @override
  String get activationTitle => 'Attiva Privio';

  @override
  String get activationSignedInNote =>
      'Il tuo account è pronto. Questo server chiede una chiave di licenza prima di inoltrare i tuoi messaggi.';

  @override
  String get activationNewNote =>
      'Questo server chiede una chiave di licenza prima di inoltrare i messaggi. Inserisci la tua ora e verrà attivata non appena il tuo account esisterà.';

  @override
  String get activationActivate => 'Attiva';

  @override
  String get activationNoKeyYet => 'Non ho ancora una chiave';

  @override
  String get activationWithoutKeyNote =>
      'Senza chiave puoi creare un account, accedere e leggere quello che arriva, ma non inviare. Puoi inserirla più tardi in Impostazioni › Licenza Privio.';

  @override
  String activationFreeSoftwareNote(String name, String license) {
    return '$name è software libero sotto $license. La chiave non sblocca l\'app: ce l\'hai già tutta e puoi compilarla tu. Paga il servizio ospitato che inoltra i tuoi messaggi.';
  }

  @override
  String get backupCouldNotReach =>
      'Non è stato possibile raggiungere Privio per controllare il backup.';

  @override
  String get backupDone => 'Backup fatto. Privio non può leggerlo.';

  @override
  String get backupUploadFailed => 'Non è stato possibile caricare il backup.';

  @override
  String get backupBadKey => 'Questa non sembra una chiave di recupero.';

  @override
  String backupRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversazioni ripristinate.',
      one: '1 conversazione ripristinata.',
    );
    return '$_temp0';
  }

  @override
  String get backupKeyDidNotOpen =>
      'Quella chiave non ha aperto il backup, o non ce n\'è nessuno da aprire.';

  @override
  String get backupLast => 'Ultimo backup';

  @override
  String get backupOnServer => 'Sul server';

  @override
  String get backupNothingYet => 'Ancora niente';

  @override
  String get backupAlways => 'Sempre';

  @override
  String get backupNow => 'Fai il backup ora';

  @override
  String get backupAutomatic => 'Backup automatico';

  @override
  String get backupIntervalDaily => 'Ogni giorno';

  @override
  String get backupIntervalWeekly => 'Ogni settimana';

  @override
  String get backupRecoveryKey => 'Chiave di recupero';

  @override
  String get backupRestoreRow => 'Ripristina da un backup';

  @override
  String get backupSealedNote =>
      'I backup vengono sigillati su questo dispositivo con la tua chiave di recupero. Privio non può aprirli né reimpostare la chiave: se la perdi, il backup è perso. Annotala in un posto sicuro.\n\nUn backup contiene le tue conversazioni, non le tue chiavi: ripristinarlo su un nuovo dispositivo ti restituisce la cronologia, e quel dispositivo crea la propria identità per quello che verrà dopo.';

  @override
  String get backupNever => 'Mai';

  @override
  String backupToday(String time) {
    return 'Oggi, $time';
  }

  @override
  String get backupWriteItDown =>
      'Annota questo. È l\'unica cosa che apre i tuoi backup, e nessuno — nemmeno Privio — può ricrearlo per te.';

  @override
  String get backupRestoreReplacesNote =>
      'Questo sostituisce quello che c\'è su questo dispositivo con ciò che è nel backup.';

  @override
  String get backupRestore => 'Ripristina';

  @override
  String get twoFactorOnToast =>
      'L\'autenticazione a due fattori è attiva. Conserva al sicuro il recupero della tua app di autenticazione.';

  @override
  String get twoFactorOffToast =>
      'L\'autenticazione a due fattori è disattivata.';

  @override
  String get twoFactorTurnOffTitle =>
      'Disattiva l\'autenticazione a due fattori';

  @override
  String get twoFactorTurnOff => 'Disattiva';

  @override
  String get twoFactorTurnOn => 'Attiva';

  @override
  String get twoFactorServerNote =>
      'Il codice viene verificato al login, sul server. Protegge l\'account in sé: chi scopre la tua password non può comunque registrare un nuovo dispositivo. Non è ciò che cifra i tuoi messaggi: quella è la chiave su questo dispositivo, e nessun codice può sostituirla.';

  @override
  String get twoFactorOffBody =>
      'Con l\'autenticazione a due fattori, l\'accesso richiede un codice a sei cifre dalla tua app di autenticazione oltre alla password.';

  @override
  String get twoFactorSetUp => 'Configurala';

  @override
  String get twoFactorScanThis => 'Scansiona questo';

  @override
  String get twoFactorScanNote =>
      'Aggiungilo alla tua app di autenticazione, poi digita il codice che mostra. L\'autenticazione a due fattori non è attiva finché quel codice non è stato verificato.';

  @override
  String get twoFactorTypeKey => 'Oppure digita questa chiave';

  @override
  String get twoFactorKeyCopied => 'Chiave copiata.';

  @override
  String get twoFactorOnBody =>
      'L\'accesso chiede un codice dalla tua app di autenticazione.';

  @override
  String get passcodeFourDigits => '4 cifre';

  @override
  String get passcodeSixDigits => '6 cifre';

  @override
  String get passcodeFourDigitsNote =>
      'Diecimila combinazioni. Veloce, e sufficiente contro chi raccoglie il telefono.';

  @override
  String get passcodeSixDigitsNote =>
      'Un milione di combinazioni, e resta un tastierino.';

  @override
  String get passcodePhraseNote =>
      'Lettere, e cifre o simboli se li vuoi. L\'unica delle tre che regge contro chi ha il telefono e tempo.';

  @override
  String get passcodeNeedsFourDigits => 'Quattro cifre.';

  @override
  String get passcodeNeedsSixDigits => 'Sei cifre.';

  @override
  String passcodePhraseTooShort(int count) {
    return 'Almeno $count caratteri.';
  }

  @override
  String get passcodePhraseNeedsLetter =>
      'Una passphrase ha bisogno di almeno una lettera. Cifre e simboli sono i benvenuti accanto.';

  @override
  String get lockEntriesDiffer => 'Le due voci non coincidono.';

  @override
  String get lockOnToast =>
      'Blocco dell\'app attivo. Privio lo chiede quando torna.';

  @override
  String get lockOffToast => 'Blocco dell\'app disattivato.';

  @override
  String get lockTurnOffTitle => 'Disattivare il blocco dell\'app?';

  @override
  String get lockTurnOffBody =>
      'Chiunque tenga in mano un telefono sbloccato arriva ai tuoi messaggi. Un codice di emergenza impostato per la schermata di blocco viene tolto con esso.';

  @override
  String get lockTurnOffRow => 'Disattiva il blocco dell\'app';

  @override
  String get lockWhatItIsNote =>
      'Un codice su questo dispositivo, richiesto ogni volta che Privio torna in primo piano. Non è la password del tuo account e non lascia mai il telefono: protegge la cronologia già cifrata su di esso.';

  @override
  String get lockNoBiometricsNote =>
      'Non c\'è l\'opzione volto o impronta. Sono le uniche credenziali che qualcuno può usare tenendoti il telefono davanti alla faccia, o premendoci il tuo dito mentre dormi — e in diversi luoghi un tribunale può ordinarle dove non può ordinare un codice.';

  @override
  String get lockChangePasscode => 'Cambia il codice';

  @override
  String get lockChoosePasscode => 'Scegli un codice';

  @override
  String get lockAgain => 'Di nuovo';

  @override
  String get lockChangeIt => 'Cambialo';

  @override
  String get lockTurnItOn => 'Attivalo';

  @override
  String get lockForgettingNote =>
      'Dimenticarlo significa accedere di nuovo, che per il server è un nuovo dispositivo: quello che è già stato consegnato qui è perso se non è in un backup. Non c\'è reimpostazione, perché una reimpostazione che chiunque potrebbe chiedere non sarebbe un blocco.';

  @override
  String get duressNoLockNote =>
      'Nella schermata di blocco non fa ancora nulla, perché su questo dispositivo non c\'è un blocco dell\'app. Attivane uno in Blocco schermo, e un codice di emergenza della stessa forma di quel blocco funzionerà anche lì — ed è lì che viene preso un telefono già connesso.';

  @override
  String duressShapeNote(String kind) {
    return 'Questo dispositivo si sblocca con $kind. Un codice di emergenza della stessa forma può essere digitato nella schermata di blocco, dove distrugge invece di sbloccare. Qualsiasi altra forma funziona solo all\'accesso.';
  }

  @override
  String get duressMatchesLock =>
      'Questo corrisponde al blocco di questo dispositivo, quindi funziona sia nella schermata di blocco sia all\'accesso.';

  @override
  String duressDoesNotMatchLock(String kind) {
    return 'Questo non corrisponde al blocco di questo dispositivo ($kind), quindi funziona solo all\'accesso: la schermata di blocco non ha dove digitarlo.';
  }

  @override
  String get duressAtLeastFour => 'Usa almeno quattro caratteri.';

  @override
  String get duressCodesDiffer => 'I due codici non coincidono.';

  @override
  String get duressSameAsUnlock =>
      'Quello è il codice che sblocca questo dispositivo. Un codice di emergenza deve essere diverso: la schermata di blocco lo controlla per primo, quindi se fossero uguali ogni sblocco distruggerebbe l\'account — senza dirlo.';

  @override
  String get duressSetBoth =>
      'Codice di emergenza impostato. Distrugge l\'account all\'accesso e nella schermata di blocco.';

  @override
  String get duressSetSignInOnly =>
      'Codice di emergenza impostato. Digitarlo all\'accesso distrugge l\'account.';

  @override
  String get duressRemoved => 'Codice di emergenza rimosso.';

  @override
  String get duressRemoveTitle => 'Rimuovi il codice di emergenza';

  @override
  String get duressWarning =>
      'Digitare questo codice invece della password all\'accesso distrugge l\'account: ogni dispositivo, ogni messaggio in attesa, i tuoi contatti, i tuoi gruppi, il tuo backup. Non c\'è modo di annullare né una conferma: è proprio questo il punto.';

  @override
  String get duressIsSet => 'È impostato un codice di emergenza';

  @override
  String get duressCannotShow =>
      'Privio non può mostrartelo: è conservato come si conserva una password. Impostarne uno nuovo qui sotto lo sostituisce.';

  @override
  String get duressRemoveIt => 'Rimuovilo';

  @override
  String get duressReplaceIt => 'Sostituiscilo';

  @override
  String get duressSetOne => 'Imposta un codice di emergenza';

  @override
  String get duressAccountPassword => 'La password del tuo account Privio';

  @override
  String get duressLooksLikePin =>
      'È più corta di una password di account. Questo campo vuole la password che hai scelto creando l\'account, non il PIN che sblocca l\'app.';

  @override
  String get duressCodeField => 'Codice di emergenza';

  @override
  String get duressCodeAgain => 'Ripeti il codice di emergenza';

  @override
  String get duressReplaceCode => 'Sostituisci il codice';

  @override
  String get duressSetCode => 'Imposta il codice';

  @override
  String get duressWhatItDoesNotDo =>
      'Quello che non fa: il nome dell\'account resta occupato, quindi nessuno può rivendicarlo dopo, e non raggiunge un altro dispositivo già connesso altrove. Chi guarda vede il tentativo rifiutato esattamente come una password o un PIN sbagliati.';

  @override
  String get disguiseIntro =>
      'Un Privio bloccato si apre come una calcolatrice funzionante invece che come schermata di blocco. Qualsiasi calcolo il cui risultato sia il tuo codice apre Privio quando premi =, quindi il codice stesso non deve mai comparire sullo schermo. Ogni altro calcolo è solo un calcolo.';

  @override
  String get disguiseOpenTo => 'Apri come';

  @override
  String get disguiseLockScreen => 'La schermata di blocco';

  @override
  String disguiseCalculatorNamed(String name) {
    return 'Calcolatrice $name';
  }

  @override
  String get disguisePickNote =>
      'Scegli quella che il tuo telefono ha già. Una calcolatrice che non somiglia a quella solita è proprio la cosa che si nota.';

  @override
  String get disguiseSeeIt => 'Guardala';

  @override
  String disguiseErrorSuffix(String reason) {
    return '$reason La schermata di blocco è cambiata comunque; la schermata iniziale no.';
  }

  @override
  String get disguiseNoLock =>
      'Su questo dispositivo non c\'è ancora un blocco schermo, quindi non c\'è nessun codice da digitare in una calcolatrice.';

  @override
  String get disguisePhraseLock =>
      'Il tuo blocco schermo è una passphrase. Una calcolatrice ha dieci tasti e nessuna lettera, quindi non c\'è modo di digitarla. Passa il blocco a 4 o 6 cifre per usare un travestimento.';

  @override
  String get disguiseOnHomeScreen => 'Sulla schermata iniziale';

  @override
  String get disguiseWhatItDoesNotDo => 'Quello che non fa';

  @override
  String get disguiseNotADefence =>
      'Non è una difesa contro chi tiene il telefono a lungo. L\'app resta installata, e la sua dimensione, i suoi file e il suo traffico di rete sono lì da trovare per chi guarda davvero. Dove funziona bene è il caso ordinario: uno schermo intravisto, o un telefono passato sbloccato.';

  @override
  String get disguiseHomeScreenChanges =>
      'Sulla schermata iniziale e nel cassetto delle app, Privio diventa un\'icona di calcolatrice chiamata «Calcolatrice». Il tuo launcher può metterci qualche secondo a ridisegnarsi, e un\'icona che hai fissato tu alla schermata iniziale potrebbe dover essere rifissata. Disattivare il travestimento la rimette a posto.\n\nL\'elenco app di Android — Impostazioni, info app, il nome mostrato quando Privio chiede un permesso — dice ancora Privio. Quel nome viene fissato in fase di compilazione e nessuna app può cambiarlo mentre gira.';

  @override
  String get disguiseIconUnchanged =>
      'Su questo dispositivo l\'icona e il nome non cambiano, solo ciò su cui l\'app si apre. Chi passa in rassegna la schermata iniziale trova ancora Privio dal nome.';

  @override
  String get disguiseClosePreview => 'Chiudi l\'anteprima';

  @override
  String get licenseActivatedToast =>
      'Attivata. Questa licenza appartiene ora al tuo account.';

  @override
  String get licenseNotCheckedTitle => 'Non ancora verificata';

  @override
  String get licenseNotCheckedBody =>
      'Privio non ha ancora potuto chiedere al server di questo account. Rimetti l\'app online e riapri questa schermata.';

  @override
  String get licenseNotNeededTitle => 'Qui non serve una licenza';

  @override
  String get licenseNotNeededBody =>
      'Questo server non ne richiede una. Le licenze riguardano il servizio Privio ospitato: una licenza per un\'infrastruttura che gestisci già non significherebbe nulla.';

  @override
  String get licenseStoreTitle => 'Gestita dallo store';

  @override
  String licenseStoreBody(String store) {
    return 'Questa build è stata pagata tramite lo store da cui proviene, quindi non c\'è nessuna chiave da inserire. Se non è attiva, ripristina il tuo acquisto in $store.';
  }

  @override
  String get licenseOnePurchaseNote =>
      'Un acquisto, una chiave, un account, per sempre. Una chiave riscattata è legata all\'account che l\'ha riscattata e non può essere spostata né riutilizzata.';

  @override
  String get licenseEnterTitle => 'Inserisci la tua chiave di licenza';

  @override
  String get licenseEnterBody =>
      'Compra una chiave su getprivio.com/license, poi digitala qui. Finché non è attivata, questo account può accedere e leggere quello che è già arrivato, ma non inviare.';

  @override
  String get licenseActivated => 'Attivata';

  @override
  String licenseRedeemedOn(String date) {
    return 'Riscattata il $date.';
  }

  @override
  String get licenseFromAppStore => 'Acquistata tramite l\'App Store.';

  @override
  String get licenseFromPlay => 'Acquistata tramite Google Play.';

  @override
  String get licenseFromKey =>
      'Attivata con una chiave di licenza. Accesso a vita, nessun rinnovo.';

  @override
  String get safetyTrustedToast =>
      'La nuova chiave è considerata attendibile. Confronta di nuovo il numero prima di fidartene.';

  @override
  String get safetyMatches => 'Corrisponde a uno dei numeri qui sotto.';

  @override
  String get safetyNoMatch => 'Non corrisponde a nessuno dei numeri qui sotto.';

  @override
  String safetyNothingYet(String name) {
    return 'Non c\'è ancora niente da confrontare. Un numero esiste una volta che tu e $name vi siete scambiati un messaggio, perché solo allora questo dispositivo ha fissato una loro chiave.';
  }

  @override
  String safetyReadThese(String name) {
    return 'Leggi queste cifre a $name, in chiamata o di persona. Se vede le stesse, nessuno si è messo in mezzo. Se no, smetti di usare questa chat per qualsiasi cosa che non diresti in pubblico.';
  }

  @override
  String get safetyMarkNotVerified => 'Segna come non verificato';

  @override
  String get safetyMarkVerified => 'Segna come verificato';

  @override
  String safetyMarkNote(String name) {
    return 'Segnarlo come verificato registra esattamente le chiavi sullo schermo. Se una di esse cambia, o se un nuovo dispositivo si aggiunge a $name, il contrassegno torna da solo a «cambiato»: è un registro di ciò che hai controllato, non una promessa su ciò che verrà.';
  }

  @override
  String get safetyVerified => 'Verificato';

  @override
  String get safetyChangedSince => 'Cambiato da quando hai controllato';

  @override
  String get safetyNotVerified => 'Non verificato';

  @override
  String safetyTheirDevice(int index) {
    return 'Il loro dispositivo $index';
  }

  @override
  String get safetyCompareTitle => 'Confronta un numero che ti hanno mandato';

  @override
  String get safetyCompare => 'Confronta';

  @override
  String get safetyKeyNotYours => 'La chiave sul server non è quella che avevi';

  @override
  String get safetyRefusedUntilDecide =>
      'I messaggi verso questa chat vengono rifiutati finché non decidi. Reinstallare Privio, o accedere su un nuovo dispositivo, lo fa legittimamente ed è il motivo consueto. Lo fa anche un server che ti passa una chiave sua, che da qui sembra esattamente uguale: per questo vale la pena riconfrontare il numero qui sotto dopo.';

  @override
  String get safetyTrustNewKey => 'Fidati della nuova chiave';

  @override
  String get safetyKeyChangedArrived =>
      'La loro chiave è cambiata, ed è arrivato un messaggio con essa';

  @override
  String get safetyKeyChangedBody =>
      'La nuova chiave è già in uso: un messaggio che ne porta una non può essere respinto senza dare a chiunque il modo di zittire una chat. Reinstallare fa questo. Lo fa anche qualcuno che si mette in mezzo. Il numero qui sotto è la differenza, e vale qualcosa solo se confrontato ad alta voce.';

  @override
  String get channelsCouldNotOpenLink =>
      'Non è stato possibile aprire quel link';

  @override
  String get channelsJoinWithLink => 'Entra con un link';

  @override
  String get channelsNewChannel => 'Nuovo canale';

  @override
  String get channelsTabFollowing => 'Seguiti';

  @override
  String get channelsTabDiscover => 'Scopri';

  @override
  String get channelsSearchMine => 'Cerca nei tuoi canali';

  @override
  String get channelsSearchPublic => 'Cerca canali pubblici';

  @override
  String get channelsEmptyTitle => 'Ancora nessun canale';

  @override
  String get channelsEmptyBody =>
      'Creane uno, o trova un canale pubblico in Scopri.';

  @override
  String get channelsNothingFound => 'Nessun risultato';

  @override
  String get channelsDiscoverEmptyBody =>
      'Cerca canali pubblici per nome, nome utente o descrizione. I canali privati non compaiono mai qui.';

  @override
  String channelsHandleAndMembers(String handle, String members) {
    return '@$handle  ·  $members';
  }

  @override
  String get channelsJoinTitle => 'Entra in un canale';

  @override
  String get channelsJoinNote =>
      'Incolla un link di canale. Ti mostra il canale; entrare è un pulsante lì. Entrare non ti consegna nemmeno la chiave: un membro che ce l\'ha la manda cifrata al tuo dispositivo subito dopo.';

  @override
  String get categoryNews => 'Notizie';

  @override
  String get categoryTechnology => 'Tecnologia';

  @override
  String get categoryCommunity => 'Comunità';

  @override
  String get categoryEducation => 'Istruzione';

  @override
  String get categoryCulture => 'Cultura';

  @override
  String newChannelPictureUnreadable(String name) {
    return 'Privio non è riuscito a leggere $name. Prova con un\'altra immagine.';
  }

  @override
  String get newChannelCouldNotCreate =>
      'Non è stato possibile creare il canale';

  @override
  String get newChannelWithoutPicture =>
      'Il canale è stato creato senza l\'immagine.';

  @override
  String get newChannelCreate => 'Crea';

  @override
  String get newChannelPublicPictureNote =>
      'L\'immagine di un canale pubblico compare sulla sua pagina web e nelle anteprime dei link, quindi è archiviata senza cifratura, come il suo nome, il nome utente e la descrizione.';

  @override
  String get newChannelHandle => 'Nome utente';

  @override
  String get newChannelHandleRule =>
      'Da 3 a 32 caratteri: a-z, 0-9, trattino basso o punto';

  @override
  String get newChannelCategory => 'Categoria';

  @override
  String get newChannelRestrictSaving => 'Limita il salvataggio';

  @override
  String get newChannelRestrictNote =>
      'Chiede alle app di chi legge di non salvare né inoltrare i post. Una richiesta, non una garanzia: chi può leggere un post può fotografarlo.';

  @override
  String get newChannelPrivateBody =>
      'Raggiungibile solo con un link di invito. Il nome viene caricato cifrato, quindi il server conserva un canale che non può nominare.';

  @override
  String get newChannelPublicBody =>
      'Elencato e ricercabile. Il nome, il nome utente e la descrizione sono pubblici per definizione; i post restano cifrati end-to-end.';

  @override
  String get membersCouldNotLift => 'Non è stato possibile revocarlo.';

  @override
  String get membersCouldNotChange =>
      'Non è stato possibile modificare quel membro';

  @override
  String get membersTitle => 'Membri';

  @override
  String get membersWhoRuns => 'Chi gestisce questo canale';

  @override
  String get membersSilencedCanRead =>
      'Può leggere, non può pubblicare né reagire';

  @override
  String get membersAllowAgain => 'Consenti di nuovo';

  @override
  String get membersRoleAndPermissions => 'Ruolo e permessi';

  @override
  String get membersOwnerEverything => 'Proprietario · tutto';

  @override
  String get membersSubscriberReadOnly => 'Iscritto · sola lettura';

  @override
  String get membersGrantPost => 'pubblicare';

  @override
  String get membersGrantEdit => 'modificare';

  @override
  String get membersGrantDeletePosts => 'eliminare post';

  @override
  String get membersGrantManageMembers => 'gestire i membri';

  @override
  String get membersGrantDeleteChannel => 'eliminare il canale';

  @override
  String membersRoleLine(String role, String granted) {
    return '$role · $granted';
  }

  @override
  String get membersSubscriber => 'Iscritto';

  @override
  String get membersTogglePost => 'Pubblicare';

  @override
  String get membersToggleEditChannel => 'Modificare il canale';

  @override
  String get membersToggleDeletePosts => 'Eliminare i post';

  @override
  String get membersToggleManageMembers => 'Gestire i membri';

  @override
  String get membersToggleDeleteChannel => 'Eliminare il canale';

  @override
  String get membersGreyedOutNote =>
      'I permessi in grigio sono quelli che tu non hai. Nessuno può concedere più di quanto ha.';

  @override
  String get membersSubscriberNote =>
      'Un iscritto legge il canale e nient\'altro.';

  @override
  String get membersRemoveFromChannel => 'Rimuovi dal canale';

  @override
  String get membersStoppedFromPosting => 'Impedito di pubblicare';

  @override
  String get membersAudienceNote =>
      'Sono elencate solo le persone che gestiscono questo canale. Chi lo legge non viene mostrato agli altri lettori, te compreso.';

  @override
  String get channelPicture => 'Immagine';

  @override
  String get channelLinkCopied => 'Link copiato.';

  @override
  String get adminsMakeSomebodyFirst => 'Prima rendi qualcuno amministratore.';

  @override
  String get subscribersCouldNotAddAnybody =>
      'Non è stato possibile aggiungere nessuno.';

  @override
  String subscribersAddCount(int count) {
    return 'Aggiungi $count';
  }

  @override
  String get threadCouldNotPost =>
      'Non è stato possibile pubblicare quel commento.';

  @override
  String get threadCouldNotRemove =>
      'Non è stato possibile rimuovere quel commento.';

  @override
  String threadStopTitle(String name) {
    return 'Impedire a $name di pubblicare?';
  }

  @override
  String get threadStopBody =>
      'Resta nel canale e può continuare a leggerlo. Non può commentare né reagire finché non lo annulli.\n\nRimuoverla dal canale è l\'altra cosa, più pesante: quella ruota la chiave e si porta via anche la lettura.';

  @override
  String get threadStopThem => 'Fermalo';

  @override
  String get threadStopThemPosting => 'Impediscigli di pubblicare';

  @override
  String get threadCouldNotDoThat => 'Non è stato possibile farlo.';

  @override
  String get threadTitle => 'Commenti';

  @override
  String get threadUnknown => 'Sconosciuto';

  @override
  String get threadEncryptedNoKey =>
      'Cifrato: questo dispositivo non ne ha la chiave.';

  @override
  String get threadCommentHint => 'Commenta';

  @override
  String get threadNoKeyForChannel => 'Nessuna chiave per questo canale';

  @override
  String get threadDeletedAccount => 'Account eliminato';

  @override
  String get threadEncryptedNoKeyHere =>
      'Cifrato: su questo dispositivo non c\'è una chiave per questo.';

  @override
  String get threadEmptyTitle => 'Ancora nessun commento';

  @override
  String get threadEmptyBody =>
      'I commenti sono cifrati con la chiave del canale, come i post. Il server li conserva e non può leggerli.';

  @override
  String threadStoppedToast(String name) {
    return '$name può ancora leggere il canale, ma non pubblicarci.';
  }

  @override
  String get threadThem => 'Quella persona';

  @override
  String get threadThemObject => 'quella persona';

  @override
  String get feedCouldNotAskForKey =>
      'Non è stato possibile chiedere la chiave.';

  @override
  String get feedKeyArrived =>
      'La chiave è arrivata. Puoi pubblicare di nuovo.';

  @override
  String get feedAskedAgain =>
      'Richiesta di nuovo. La chiave la consegna un altro membro, quindi arriva quando uno di loro è online.';

  @override
  String get feedCouldNotJoin => 'Non è stato possibile entrare';

  @override
  String get feedPickFutureTime => 'Scegli un orario che non sia già passato.';

  @override
  String get feedCouldNotPublishPoll =>
      'Non è stato possibile pubblicare quel sondaggio.';

  @override
  String feedScheduledFor(String when) {
    return 'Programmato per $when. Fino ad allora è sotto «Programmati».';
  }

  @override
  String get feedCouldNotPublish => 'Non è stato possibile pubblicare';

  @override
  String get feedCouldNotChangeLink =>
      'Non è stato possibile cambiare il link.';

  @override
  String get feedOldLinkDead =>
      'Il vecchio link è morto. Chi ce l\'ha avrà bisogno di quello nuovo.';

  @override
  String get feedSaved => 'Salvato.';

  @override
  String get feedCouldNotChangeReactions =>
      'Non è stato possibile cambiare le reazioni.';

  @override
  String get feedCouldNotChangePost =>
      'Non è stato possibile modificare il post.';

  @override
  String get feedPublished => 'Pubblicato.';

  @override
  String get feedCouldNotPublishIt => 'Non è stato possibile pubblicarlo.';

  @override
  String get feedCouldNotChangeThat => 'Non è stato possibile cambiarlo.';

  @override
  String get feedCommentsOn => 'Ora chi legge può commentare i post.';

  @override
  String get feedCommentsOff =>
      'I commenti sono disattivati. I thread esistenti sono nascosti, non eliminati.';

  @override
  String get feedCouldNotReadNumbers =>
      'Non è stato possibile leggere i numeri.';

  @override
  String get feedNobodyToHandTo =>
      'In questo canale non c\'è nessun altro a cui passarlo.';

  @override
  String feedOwnsNow(String name) {
    return 'Ora $name è proprietario di questo canale. Tu ci sei come amministratore.';
  }

  @override
  String get feedCouldNotHandOn => 'Non è stato possibile cedere il canale.';

  @override
  String get feedReported => 'Segnalato. Grazie.';

  @override
  String get feedCouldNotSendThat => 'Non è stato possibile inviarlo.';

  @override
  String get feedRemovePicture => 'Rimuovi l\'immagine';

  @override
  String get feedPictureRemoved => 'Immagine rimossa.';

  @override
  String get feedCouldNotRemovePicture =>
      'Non è stato possibile rimuovere l\'immagine.';

  @override
  String get feedCouldNotSetPicture =>
      'Non è stato possibile impostare l\'immagine.';

  @override
  String get feedPictureUpdated => 'Immagine del canale aggiornata.';

  @override
  String get feedDeleteChannelTitle => 'Eliminare il canale?';

  @override
  String get feedDeleteChannelBody =>
      'Il canale e ogni post al suo interno vengono rimossi per tutti. Niente annulla questo.';

  @override
  String get feedCouldNotDeleteChannel =>
      'Non è stato possibile eliminare il canale';

  @override
  String get feedCouldNotLeaveChannel =>
      'Non è stato possibile uscire dal canale';

  @override
  String get feedScheduled => 'Programmati';

  @override
  String get feedRequestsToJoin => 'Richieste di ingresso';

  @override
  String get feedChannelPicture => 'Immagine del canale';

  @override
  String get feedAddPicture => 'Aggiungi un\'immagine';

  @override
  String get feedTurnCommentsOff => 'Disattiva i commenti';

  @override
  String get feedTurnCommentsOn => 'Attiva i commenti';

  @override
  String get feedHandChannelOn => 'Cedi questo canale';

  @override
  String get feedDeleteChannel => 'Elimina il canale';

  @override
  String get dayToday => 'Oggi';

  @override
  String get dayYesterday => 'Ieri';

  @override
  String get feedNoSearchResultsBody =>
      'La ricerca gira su questo dispositivo, sui post che ha già caricato e che è riuscito ad aprire. Il server non può cercarli: li tiene sigillati.';

  @override
  String get feedEdited => '· modificato';

  @override
  String feedCommentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commenti',
      one: '1 commento',
      zero: 'Commenta',
    );
    return '$_temp0';
  }

  @override
  String get feedUnpin => 'Rimuovi dai fissati';

  @override
  String get feedPin => 'Fissa';

  @override
  String get feedRemoveFile => 'Rimuovi il file';

  @override
  String get feedAttach => 'Allega un\'immagine o un file';

  @override
  String get feedPublishLater => 'Pubblica più tardi';

  @override
  String get feedAskQuestion => 'Fai una domanda';

  @override
  String get feedWritePost => 'Scrivi un post';

  @override
  String get feedEditPost => 'Modifica il post';

  @override
  String get feedPost => 'Post';

  @override
  String get feedEditUnseenNote =>
      'Non l\'ha ancora visto nessuno, quindi non verrà contrassegnato come modificato.';

  @override
  String get feedEditSeenNote =>
      'Il post verrà contrassegnato come modificato. Il suo file, se ne ha uno, resta com\'è.';

  @override
  String get feedWaiting => 'In attesa';

  @override
  String get feedEncryptedNoKeyHere =>
      'Cifrato: nessuna chiave su questo dispositivo.';

  @override
  String get feedDiscard => 'Scarta';

  @override
  String get feedPublishNow => 'Pubblica ora';

  @override
  String get feedNothingWaiting => 'Niente in attesa';

  @override
  String get feedNothingWaitingBody =>
      'I post che programmi aspettano qui finché non arriva il loro momento. Nessun altro può vederli, né sapere che esistono.';

  @override
  String feedTodayAt(String time) {
    return 'oggi alle $time';
  }

  @override
  String feedTomorrowAt(String time) {
    return 'domani alle $time';
  }

  @override
  String feedDateAt(String date, String time) {
    return '$date alle $time';
  }

  @override
  String get feedReactionsNote =>
      'Quello che chi legge può mettere sotto un post. Le reazioni già presenti su un post restano, anche se togli l\'emoji da questa lista.';

  @override
  String feedChosenOfLimit(int chosen, int limit) {
    return '$chosen di $limit';
  }

  @override
  String get feedPollNoKey =>
      'Un sondaggio di cui questo dispositivo non ha la chiave.';

  @override
  String feedPollPickUpTo(int count) {
    return 'Scegline fino a $count';
  }

  @override
  String get feedPollPickOne => 'Scegline una';

  @override
  String feedPollCloses(String when) {
    return 'chiude $when';
  }

  @override
  String feedPollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votanti',
      one: '1 votante',
    );
    return '$_temp0';
  }

  @override
  String get feedPollClearAnswer => 'Cancella la mia risposta';

  @override
  String get feedPollAnswer => 'Rispondi';

  @override
  String get feedPollQuestion => 'Domanda';

  @override
  String feedPollAnswerN(int index) {
    return 'Risposta $index';
  }

  @override
  String get feedPollAddAnswer => 'Aggiungi una risposta';

  @override
  String get feedPollSeveral => 'Più risposte';

  @override
  String get feedPollNote =>
      'La domanda e le risposte sono cifrate con la chiave del canale, come un post. Il server conta i voti senza mai sapere cosa dicano.';

  @override
  String get feedPollAsk => 'Chiedi';

  @override
  String get feedCouldNotOpenFile => 'Non è stato possibile aprire quel file.';

  @override
  String get feedOpened => 'Aperto';

  @override
  String get statsPosts => 'Post';

  @override
  String get statsWaitingToPublish => 'In attesa di pubblicazione';

  @override
  String get statsPeopleWhoVoted => 'Persone che hanno votato';

  @override
  String get statsWaitingToJoin => 'In attesa di entrare';

  @override
  String get statsNoViewCountNote =>
      'Non c\'è un conteggio delle visualizzazioni, ed è una decisione, non una lacuna. Contare chi ha letto un post — senza contare nessuno due volte — significa tenere una riga per ogni lettore di ogni post, cioè un registro di ciò che ciascuno ha letto. Tutto quello sopra è contato da qualcosa che qualcuno ha scelto di fare.';

  @override
  String get feedPollClosed => 'chiuso';

  @override
  String get inviteNever => 'Mai';

  @override
  String inviteExpires(String when) {
    return 'scade $when';
  }

  @override
  String requestsAsked(String when) {
    return 'Richiesto $when';
  }

  @override
  String get inviteAskMeFirst => 'Chiedimi prima';

  @override
  String get inviteAskMeFirstNote =>
      'Chi segue il link aspetta la tua approvazione invece di entrare e basta. Non hanno nessuna chiave finché non li fai entrare.';

  @override
  String get inviteExpiresLabel => 'Scade';

  @override
  String get invitePickATime => 'Scegli un orario';

  @override
  String get inviteHowMany => 'Quanti possono entrarci';

  @override
  String get inviteNoLimit => 'Nessun limite';

  @override
  String inviteJoinedSoFar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sono entrate con questo link finora.',
      one: '1 persona è entrata con questo link finora.',
    );
    return '$_temp0 Aprirlo e andarsene non conta.';
  }

  @override
  String get inviteReplaceLink => 'Sostituisci il link';

  @override
  String get inviteReplaceNote =>
      'Sostituirlo è il modo di revocare un link: quello vecchio smette di funzionare subito, ovunque. Non resta nessun link mezzo funzionante.';

  @override
  String get inviteReplaceTitle => 'Sostituire il link?';

  @override
  String get inviteReplaceBody =>
      'Il link che hai condiviso smette di funzionare subito: nei messaggi, sui volantini, ovunque sia stato incollato. Nessuno che ce l\'abbia può entrare.\n\nChi è già nel canale resta dentro. Non c\'è modo di riportare indietro il vecchio link.';

  @override
  String get inviteReplaceIt => 'Sostituiscilo';

  @override
  String get inviteExpired => 'Questo link è scaduto: nessuno può entrarci.';

  @override
  String get inviteUsedUp => 'Questo link è esaurito.';

  @override
  String get inviteNeedsApproval => 'Entrare richiede la tua approvazione';

  @override
  String get inviteOpenJoin => 'Chi ce l\'ha entra subito';

  @override
  String inviteUsedOf(int used, int max) {
    return '$used di $max usati';
  }

  @override
  String get inviteShareNote =>
      'Condividilo ovunque: non porta nessuna chiave. Chi lo apre entra nel canale, e la chiave per leggerlo gliela manda dopo sul dispositivo, cifrata, qualcuno che ce l\'ha già.';

  @override
  String get requestsNobodyWaiting => 'Nessuno in attesa';

  @override
  String get requestsNobodyWaitingBody =>
      'Chi segue il link di invito compare qui finché il link è impostato per chiedertelo prima.';

  @override
  String get requestsNo => 'No';

  @override
  String get requestsLetIn => 'Fai entrare';

  @override
  String get feedSettings => 'Impostazioni';

  @override
  String feedKeyRotating(int epoch) {
    return 'Qualcuno ha lasciato questo canale, quindi sta cambiando la chiave (versione $epoch). I post precedenti restano leggibili. Quelli nuovi si aprono quando la nuova chiave arriva su questo dispositivo.';
  }

  @override
  String get feedWaitingForKey =>
      'In attesa della chiave. Te la manda su questo dispositivo, cifrata, qualcuno che è già nel canale: il server non la tiene mai.';

  @override
  String get feedJoinNote =>
      'Entrare ti porta i post. La chiave che li apre te la manda dopo un membro sul dispositivo, mai il server.';

  @override
  String get feedJoinChannel => 'Entra nel canale';

  @override
  String get feedNoPostsYet => 'Ancora nessun post';

  @override
  String get feedPickNewOwnerNote =>
      'Solo qualcuno che è già nel canale. Cederlo a uno sconosciuto lo metterebbe a capo di una chiave che non ha.';

  @override
  String feedTransferTitle(String name) {
    return 'Dare il canale a $name?';
  }

  @override
  String get feedTransferBody =>
      'Diventerà suo. Tu resti come amministratore con tutto quello che hai adesso tranne il diritto di eliminare il canale — e può rimuoverti dopo.\n\nNon puoi annullarlo da solo. Per questo chiede la tua password invece di fidarsi di un telefono sbloccato.';

  @override
  String get feedYourPrivioPassword => 'La tua password Privio';

  @override
  String get feedHandItOn => 'Cedilo';

  @override
  String get feedReportTitle => 'Segnala questo canale';

  @override
  String get feedReportPublicNote =>
      'La segnalazione porta questo canale e il motivo che scegli. Chi gestisce il server può vedere nome e descrizione di un canale pubblico, perché è così che lo si cerca, ma non i suoi post, che sono cifrati.';

  @override
  String get feedReportPrivateNote =>
      'La segnalazione porta questo canale e il motivo che scegli, e nient\'altro. Il suo nome e i suoi post sono cifrati, quindi chi gestisce il server non può leggerli. Questo è il limite onesto di cosa fa segnalare un canale privato.';

  @override
  String get feedReportNoMessageNote =>
      'Non c\'è un campo messaggio di proposito: sarebbe l\'unico posto in Privio dove qualcuno incollerebbe la cosa cifrata che sta segnalando in un campo che il server può leggere.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportAbuse => 'Abuso o molestie';

  @override
  String get reportIllegal => 'Contenuti illegali';

  @override
  String get reportImpersonation => 'Si spaccia per qualcun altro';

  @override
  String get reportOther => 'Qualcos\'altro';

  @override
  String get feedReactionLimit => 'Reazioni';

  @override
  String get failureUnreachable => 'Impossibile raggiungere Privio.';

  @override
  String get failureUnreachableCheckConnection =>
      'Impossibile raggiungere Privio. Controlla la connessione.';

  @override
  String get failureUnreachableTryAgain =>
      'Impossibile raggiungere Privio. Controlla la connessione e riprova.';

  @override
  String get failureCouldNotSave =>
      'Impossibile salvare. Controlla la connessione.';

  @override
  String get failureChangeNotSaved =>
      'Impossibile raggiungere Privio. La modifica non è stata salvata.';

  @override
  String get failureRateLimited => 'Troppe richieste. Attendi un momento.';

  @override
  String get failureTooManyAttempts =>
      'Troppi tentativi. Attendi qualche minuto.';

  @override
  String get failureLicenseRequired =>
      'Attiva la tua licenza per inviare messaggi.';

  @override
  String get failureIdentityChanged =>
      'Il numero di sicurezza è cambiato. Non è stato inviato nulla: controllalo prima.';

  @override
  String get failureCouldNotSendMessage => 'Impossibile inviare il messaggio';

  @override
  String get failureCouldNotSendFile => 'Impossibile inviare il file';

  @override
  String get failureCouldNotReadMessage => 'Impossibile leggere un messaggio';

  @override
  String failureMessagesUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Non è stato possibile leggere $count messaggi',
      one: 'Non è stato possibile leggere un messaggio',
    );
    return '$_temp0';
  }

  @override
  String get failureCouldNotOpenFile => 'Impossibile aprire questo file.';

  @override
  String get failureNotAnImage =>
      'Questo file non è un\'immagine che Privio può usare.';

  @override
  String get failureCouldNotSetPicture => 'Impossibile impostare l\'immagine';

  @override
  String get failureDeletedHereOnly =>
      'Eliminato qui. La richiesta di eliminarlo dall\'altra parte non è partita.';

  @override
  String get failureCouldNotCreateGroup => 'Impossibile creare il gruppo';

  @override
  String get failureNotAGroupLink =>
      'Questo non sembra un link a un gruppo Privio.';

  @override
  String get failureGroupNotFound =>
      'Questo gruppo non esiste oppure il link è sbagliato.';

  @override
  String get failureGroupKeyMissing =>
      'Questo dispositivo non ha ancora la chiave del gruppo.';

  @override
  String get failureNotAChannelLink =>
      'Questo non sembra un link a un canale Privio.';

  @override
  String get failureHandleTaken => 'Questo identificativo è già in uso.';

  @override
  String get failureChannelNotFound =>
      'Questo canale non esiste oppure il link è sbagliato.';

  @override
  String get failureNotAMember => 'Non fai parte di questo canale.';

  @override
  String get failureInsufficientPermission =>
      'Non hai l\'autorizzazione per farlo.';

  @override
  String get failureCannotChangeOwnRole => 'Non puoi modificare il tuo ruolo.';

  @override
  String get failureOwnerIsFixed =>
      'Il proprietario del canale non può essere cambiato né rimosso.';

  @override
  String get failureTargetOutranksYou =>
      'Questo membro ha autorizzazioni che tu non hai.';

  @override
  String get failureCannotGrantWhatYouLack =>
      'Non puoi concedere un\'autorizzazione che tu stesso non hai.';

  @override
  String get failureOwnerCannotLeave =>
      'Trasferisci il canale oppure eliminalo.';

  @override
  String get failureUsernameTaken => 'Questo nome utente è già in uso.';

  @override
  String get failureInvalidCredentials =>
      'Nome utente o password non corretti.';

  @override
  String get failureTotpRequired => 'Inserisci il tuo codice a due fattori.';

  @override
  String get failureInvalidTwoFactorCode =>
      'Questo codice a due fattori non è corretto.';

  @override
  String get failureTooManyDevices =>
      'Questo account ha già il numero massimo di dispositivi.';

  @override
  String failureCheckUsernameAndPassword(String detail) {
    return 'Controlla nome utente e password: $detail';
  }

  @override
  String get failureInvalidTotp =>
      'Questo codice non è corretto. Controlla l\'ora del telefono e riprova.';

  @override
  String get failureTotpAlreadyEnabled =>
      'L\'autenticazione a due fattori è già attiva per questo account.';

  @override
  String get failureTotpNotSetUp =>
      'Ricomincia la configurazione: il segreto non c\'è più.';

  @override
  String get failureInvalidPassword => 'Questa password non è corretta.';

  @override
  String get failureDuressMatchesPassword =>
      'Il codice di emergenza deve essere diverso dalla tua password, altrimenti un accesso normale distruggerebbe l\'account.';

  @override
  String get failureDeviceNotFound => 'Questo dispositivo è già disconnesso.';

  @override
  String get failureCouldNotLiftBlock => 'Impossibile rimuovere questo blocco.';

  @override
  String failureLicenseKeyIncomplete(String format) {
    return 'Questa chiave è incompleta. Ha la forma $format.';
  }

  @override
  String get failureNotALicenseKey =>
      'Questa non sembra una chiave di licenza Privio.';

  @override
  String get failureLicenseNotFound =>
      'Nessuna licenza corrisponde a questa chiave. Controllala e riprova.';

  @override
  String get failureLicenseAlreadyRedeemed =>
      'Questa chiave è già stata usata da un altro account. Una chiave può essere riscattata una sola volta.';

  @override
  String get failureLicenseRevoked =>
      'Questa licenza è stata revocata. Contatta l\'assistenza se l\'hai pagata.';

  @override
  String get failureAccountAlreadyLicensed =>
      'Questo account ha già una licenza, quindi la chiave inserita non è stata usata.';

  @override
  String get failureNoPlayServices =>
      'Questo telefono non ha i servizi Google Play, quindi Privio non può essere riattivato mentre è chiuso. I messaggi arrivano quando Privio è aperto.';

  @override
  String get failureNoApnsToken =>
      'iOS non ha rilasciato un token push per Privio, quindi non può essere riattivato mentre è chiuso. I messaggi arrivano quando Privio è aperto.';

  @override
  String get failureNoPushService =>
      'Nessun servizio push ha risposto. I messaggi arrivano quando Privio è aperto.';

  @override
  String get failureNoDistributor =>
      'Nessun distributore UnifiedPush ha risposto. Installane uno, per esempio ntfy, e riprova.';

  @override
  String get failureDistributorUnreachable =>
      'Privio non riesce a raggiungere quel distributore. Deve essere un indirizzo https sulla rete pubblica.';

  @override
  String get failureChannelKeyAwaitingGeneration =>
      'Questo canale sta cambiando chiave dopo che un membro se n\'è andato. Potrai pubblicare di nuovo quando qualcuno che gestisce il canale aprirà Privio.';

  @override
  String get failureChannelKeyPending =>
      'In attesa che la nuova chiave del canale arrivi su questo dispositivo. Il tuo post non è perso: riprova tra un momento.';

  @override
  String get failureUnexpected =>
      'Qualcosa non ha funzionato come previsto. Riprova.';

  @override
  String get failureCallDevicesUnavailable =>
      'Privio non è riuscito ad aprire la fotocamera o il microfono.';

  @override
  String get failureCallMicrophoneUnavailable =>
      'Privio non è riuscito ad aprire il microfono.';

  @override
  String get failureCallNotOpen => 'La chiamata non era aperta.';

  @override
  String get deepLinkChannelGone =>
      'Questo link non porta più a nessun canale. Chiedine uno nuovo a chi te l\'ha mandato.';

  @override
  String get chatsPreviewDeleted => 'Messaggio eliminato';

  @override
  String get chatsPreviewPhoto => 'Foto';

  @override
  String get chatsPreviewVideo => 'Video';

  @override
  String get chatsPreviewVoice => 'Messaggio vocale';

  @override
  String get chatsPreviewFile => 'File';

  @override
  String get notificationsPermissionDenied =>
      'Le notifiche sono disattivate per Privio nelle impostazioni di sistema. I messaggi continuano ad arrivare mentre Privio è aperto, ma non ne verrai avvisato e una chiamata non squillerà.';

  @override
  String get notificationsPermissionNotAsked =>
      'Privio non ha ancora il permesso di inviarti notifiche.';

  @override
  String get failureCallMediaNotEncrypted =>
      'La chiamata è stata interrotta: l\'altra parte ha richiesto una connessione che Privio non può cifrare. Privio non ripiega mai su una chiamata non cifrata.';

  @override
  String get failureCallFarEndNotBound =>
      'La chiamata è stata interrotta: nella negoziazione non era dimostrato chi fosse dall\'altra parte. Privio non collega una chiamata che non può legare a una chiave.';

  @override
  String get failureCallCertificateChanged =>
      'La chiamata è stata interrotta: l\'altro capo è cambiato a metà negoziazione. Una chiamata ha un solo altro capo, questa ne aveva due.';

  @override
  String failureCallIdentityChanged(String who) {
    return 'La chiamata è stata interrotta: il numero di sicurezza di $who non è quello che Privio aveva. Confrontalo con questa persona per un\'altra via prima di richiamare.';
  }

  @override
  String get failureCallWrongParty =>
      'La chiamata è stata interrotta: è arrivato un messaggio al riguardo da qualcuno che non ne fa parte.';

  @override
  String failureCallNotVerified(String who) {
    return 'La chiamata è stata interrotta: accetti solo chiamate da persone di cui hai confermato il numero di sicurezza, e quello di $who non è confermato su questo dispositivo.';
  }

  @override
  String get callEncrypted => 'Crittografato end-to-end';

  @override
  String get callEncryptedVerified => 'Crittografato end-to-end · verificato';

  @override
  String get securityVerifiedCallsOnly =>
      'Solo chiamate da contatti verificati';

  @override
  String get securityVerifiedCallsOnlyBody =>
      'Ogni chiamata è comunque crittografata end-to-end. Con questa opzione attiva, Privio rifiuta inoltre una chiamata finché non hai confrontato il numero di sicurezza con quella persona e non l\'hai confermato: una chiave che questo dispositivo ha semplicemente incontrato per prima non basta. Le chiamate di chiunque altro terminano con una spiegazione, da entrambe le parti.';

  @override
  String get privacyCalls => 'Chiamate';

  @override
  String get appearanceAccentColour => 'Colore d\'accento';

  @override
  String get appearanceAccentNote =>
      'Questo cambia l\'aspetto di Privio su questo dispositivo, per questo account. Nessuno a cui scrivi lo vede, e i tuoi altri account mantengono il proprio. Il rosso, per eliminare e riagganciare, resta rosso qualunque accento tu scelga.';

  @override
  String get accentGreen => 'Verde';

  @override
  String get accentBlue => 'Blu';

  @override
  String get accentTeal => 'Turchese';

  @override
  String get accentPurple => 'Viola';

  @override
  String get accentPink => 'Rosa';

  @override
  String get accentRed => 'Rosso';

  @override
  String get accentOrange => 'Arancione';

  @override
  String get accentYellow => 'Giallo';

  @override
  String get accentPrivioDefault => 'Predefinito di Privio';

  @override
  String get appearanceAccentReset => 'Ripristina il valore predefinito';

  @override
  String get appearanceAccentPreview => 'Anteprima';

  @override
  String get appearancePreviewSend => 'Invia';

  @override
  String get appearancePreviewSetting => 'Conferme di lettura';

  @override
  String get appearancePreviewMessage =>
      'Ecco come appariranno i tuoi messaggi.';

  @override
  String accentSelected(String colour) {
    return '$colour, selezionato';
  }

  @override
  String get appearanceAppIcon => 'Icona dell\'app';

  @override
  String get appearanceAppIconNote =>
      'Questa è l\'icona sulla tua schermata iniziale e appartiene a questo telefono, non al tuo account: accedere come qualcun altro non la cambia. Resta come l\'hai impostata anche se in seguito scegli un altro colore d\'accento.';

  @override
  String get appearanceAppIconMatchAccent => 'Usa il colore d\'accento attuale';

  @override
  String get appearanceAppIconReset => 'Ripristina l\'icona originale';

  @override
  String get appearanceAppIconSlow =>
      'La schermata iniziale può impiegare qualche secondo per ridisegnarsi. Quell\'attesa è del launcher, non di Privio.';

  @override
  String get appearanceAppIconUnavailable =>
      'Questo dispositivo non può cambiare l\'icona dell\'app, quindi Privio non lo propone.';

  @override
  String get appearanceAppIconOriginal => 'Originale';

  @override
  String get failureAppIconUnsupported =>
      'Non è stato possibile cambiare l\'icona dell\'app: questo dispositivo non lo consente.';

  @override
  String get failureAppIconHiddenByDisguise =>
      'Finché il travestimento è attivo, la schermata iniziale mostra la calcolatrice, quindi il colore dell\'icona non è stato cambiato. Disattiva prima il travestimento.';

  @override
  String appIconSelected(String colour) {
    return 'Icona in $colour, selezionata';
  }

  @override
  String appIconChoose(String colour) {
    return 'Icona in $colour';
  }

  @override
  String get failureStickerNotAnImage =>
      'Questo file non è un’immagine PNG né WebP.';

  @override
  String get failureStickerAnimated =>
      'Gli sticker animati non sono ancora supportati. Usa un PNG o un WebP fermo.';

  @override
  String failureStickerTooLarge(int limit) {
    return 'Uno sticker deve essere più piccolo di $limit KB.';
  }

  @override
  String failureStickerTooWide(int limit) {
    return 'Uno sticker può essere al massimo di $limit×$limit pixel.';
  }

  @override
  String failureStickerTooSmall(int limit) {
    return 'Uno sticker deve essere almeno di $limit×$limit pixel.';
  }

  @override
  String get failureStickerPackFull =>
      'Questo pacchetto è pieno. Rimuovi qualcosa per fare spazio.';

  @override
  String get failureStickerTooManyPacks =>
      'Hai tanti pacchetti quanti Privio ne gestisce. Eliminane uno per crearne un altro.';

  @override
  String get failureStickerPackNotFound => 'Questo pacchetto non esiste più.';

  @override
  String get failureStickerLinkDead =>
      'Questo link non apre più nulla: è stato ritirato oppure il pacchetto è stato eliminato.';

  @override
  String get settingsStickers => 'Sticker ed emoji';

  @override
  String get stickersTitle => 'Sticker ed emoji';

  @override
  String get stickersMyPacks => 'I miei pacchetti';

  @override
  String get stickersInstalled => 'Aggiunti';

  @override
  String get stickersEmptyTitle => 'Ancora nessun pacchetto';

  @override
  String get stickersEmptyBody =>
      'Crea un pacchetto con immagini tue, oppure apri un link che ti hanno mandato.';

  @override
  String get stickersNewPack => 'Nuovo pacchetto';

  @override
  String get stickersNewStickerPack => 'Pacchetto di sticker';

  @override
  String get stickersNewEmojiPack => 'Pacchetto di emoji';

  @override
  String get stickersNameLabel => 'Nome';

  @override
  String get stickersNameHint => 'Come si chiama questo pacchetto';

  @override
  String get stickersCreate => 'Crea';

  @override
  String get stickersRename => 'Rinomina';

  @override
  String get stickersDelete => 'Elimina il pacchetto';

  @override
  String stickersDeleteConfirm(String title) {
    return 'Eliminare «$title»?';
  }

  @override
  String get stickersDeleteExplain =>
      'Il link smette di funzionare e il pacchetto sparisce dal selettore. Gli sticker già inviati restano visibili in quelle conversazioni.';

  @override
  String get stickersRemovePack => 'Rimuovi dai miei pacchetti';

  @override
  String get stickersAddPack => 'Aggiungi il pacchetto';

  @override
  String get stickersAlreadyAdded => 'È già nei tuoi pacchetti';

  @override
  String get stickersShare => 'Condividi questo pacchetto';

  @override
  String get stickersSharedOn => 'Chi ha il link può aggiungerlo';

  @override
  String get stickersSharedOff => 'Privato. Lo vedi solo tu.';

  @override
  String get stickersShareExplain =>
      'Un pacchetto è privato finché non lo condividi. Le immagini degli sticker non sono cifrate: un link è pensato per persone che non hanno nessuna tua chiave, quindi chi ha il link — e anche questo server — può vederle. Ritirare il link impedisce nuove aggiunte; non lo toglie a chi lo ha già.';

  @override
  String get stickersCopyLink => 'Copia il link';

  @override
  String get stickersLinkCopied => 'Link copiato';

  @override
  String get stickersWithdrawLink => 'Ritira il link';

  @override
  String get stickersNewLinkNote =>
      'Condividere di nuovo crea un link nuovo e annulla il precedente.';

  @override
  String get stickersAddItem => 'Aggiungi un’immagine';

  @override
  String get stickersItemEmoji => 'Emoji per questo';

  @override
  String get stickersItemEmojiWhy =>
      'Che cosa rappresenta: quello che mostra al suo posto un’app senza questo pacchetto, e come lo ritrovi dopo.';

  @override
  String get stickersEmptyPack => 'Questo pacchetto è ancora vuoto.';

  @override
  String stickersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count immagini',
      one: '1 immagine',
      zero: 'Vuoto',
    );
    return '$_temp0';
  }

  @override
  String get stickersRemoveItem => 'Rimuovi';

  @override
  String get stickersReorderHint => 'Tieni premuto e trascina per riordinare.';

  @override
  String get stickersCropTitle => 'Ritaglia';

  @override
  String get stickersCropHint =>
      'Trascina e pizzica per scegliere il quadrato. La trasparenza viene mantenuta.';

  @override
  String get stickersUse => 'Usa';

  @override
  String get stickersPreviewTitle => 'Pacchetto di sticker';

  @override
  String get stickersOpenLinkTitle => 'Apri un link di pacchetto';

  @override
  String get stickersOpenLinkHint =>
      'Incolla il link o il codice che ti hanno mandato.';

  @override
  String get stickersOpen => 'Apri';

  @override
  String get stickersKindSticker => 'Sticker';

  @override
  String get stickersKindEmoji => 'Emoji personalizzate';

  @override
  String get stickersPickFailed =>
      'Non è stato possibile aprire questa immagine.';

  @override
  String get notificationsIphoneNote =>
      'Puoi gestire le notifiche di Privio nelle impostazioni di iPhone.';

  @override
  String get notificationsOpenIphoneSettings => 'Apri impostazioni di iPhone';

  @override
  String get notificationsSettingsFailed =>
      'Impossibile aprire le impostazioni. Apri l’app Impostazioni e seleziona Privio.';

  @override
  String get pickerEmoji => 'Emoji';

  @override
  String get pickerStickers => 'Sticker';

  @override
  String get pickerMine => 'I miei';

  @override
  String get pickerFavourites => 'Preferiti';

  @override
  String get pickerRecent => 'Usati di recente';

  @override
  String get pickerNoStickers => 'Ancora nessun pacchetto di sticker.';

  @override
  String get pickerNoCustomEmoji => 'Ancora nessuna emoji personalizzata.';

  @override
  String get pickerManagePacks => 'Gestisci i pacchetti';

  @override
  String get pickerAddFavourite => 'Aggiungi ai preferiti';

  @override
  String get pickerRemoveFavourite => 'Togli dai preferiti';

  @override
  String get pickerOpenPack => 'Apri il pacchetto';

  @override
  String stickerFromPack(String title) {
    return 'Sticker da «$title»';
  }

  @override
  String get stickerPackGone => 'Questo pacchetto non è disponibile per te.';

  @override
  String get chatSticker => 'Sticker';

  @override
  String get pickerOpenTooltip => 'Sticker ed emoji';

  @override
  String get failurePhoneInvalid =>
      'Questo non è un numero di telefono che PRIVIO può usare. Indica il prefisso del paese, ad esempio +39.';

  @override
  String get failurePhoneSmsUnavailable =>
      'Questo server non può ancora inviare SMS, quindi qui non è possibile verificare un numero. Puoi continuare a usare PRIVIO senza.';

  @override
  String get failurePhoneDiscoveryUnavailable =>
      'Su questo server la ricerca dei contatti è disattivata.';

  @override
  String get failurePhoneWrongCode => 'Questo codice non è corretto.';

  @override
  String get failurePhoneCodeExpired =>
      'Questo codice è scaduto. Richiedine uno nuovo.';

  @override
  String get failurePhoneTooManyAttempts =>
      'Troppi codici sbagliati. Richiedine uno nuovo.';

  @override
  String get failurePhoneTooManySends =>
      'PRIVIO ha inviato questo codice tutte le volte che lo fa. Riprova più tardi.';

  @override
  String get failurePhoneResendTooSoon =>
      'Aspetta un momento prima di richiedere un altro codice.';

  @override
  String get failurePhoneNoVerification => 'Richiedi prima un codice.';

  @override
  String get failurePhoneUnchanged =>
      'Questo numero è già verificato su questo account.';

  @override
  String get failurePhoneNotLinked =>
      'Su questo account non c’è nessun numero verificato.';

  @override
  String get failurePhoneLookupBudgetSpent =>
      'Oggi PRIVIO ha confrontato per questo account tutti i numeri che confronta. Riprova domani.';

  @override
  String get failureContactsPermissionDenied =>
      'PRIVIO non ha accesso ai tuoi contatti. Puoi comunque aggiungere persone con il loro PRIVIO ID o un link di invito.';

  @override
  String get channelVerifiedTooltip => 'Canale ufficiale PRIVIO';

  @override
  String get phoneFieldLabel => 'Numero di telefono (facoltativo)';

  @override
  String get phoneFieldHint => 'Numero di telefono (facoltativo)';

  @override
  String get phoneFieldExplain =>
      'Collega il tuo numero di telefono così i contatti possono trovarti. Puoi usare PRIVIO anche senza numero di telefono.';

  @override
  String get phoneCountryCode => 'Prefisso del paese';

  @override
  String get phoneVerifyTitle => 'Conferma il numero';

  @override
  String phoneVerifySent(String hint) {
    return 'Abbiamo inviato un codice al $hint.';
  }

  @override
  String get phoneVerifyCode => 'Codice a sei cifre';

  @override
  String get phoneVerifyConfirm => 'Conferma';

  @override
  String get phoneVerifyResend => 'Invia un nuovo codice';

  @override
  String get phoneVerifySkip => 'Continua senza numero';

  @override
  String phoneVerifyStub(String code) {
    return 'Server di sviluppo: non è stato inviato alcun SMS. Il codice è $code.';
  }

  @override
  String get privacyPhoneSection => 'Numero di telefono e contatti';

  @override
  String get phoneAdd => 'Aggiungi un numero di telefono';

  @override
  String get phoneChange => 'Cambia numero';

  @override
  String get phoneRemove => 'Rimuovi il numero';

  @override
  String get phoneRemoveExplain =>
      'Vengono eliminati sia il numero sia il collegamento che il server conserva per trovarti. Le tue chat restano intatte.';

  @override
  String get phoneDiscoverable => 'Farmi trovare tramite il mio numero';

  @override
  String get phoneDiscoverableExplain =>
      'Disattivato finché non lo attivi. Quando è attivo, chi ha il tuo numero in rubrica vede il tuo account PRIVIO.';

  @override
  String get phoneContactSync => 'Sincronizza i contatti del dispositivo';

  @override
  String get phoneContactSyncExplain =>
      'Disattivato finché non lo attivi. PRIVIO legge i numeri di telefono dei tuoi contatti, trasforma ciascuno in un valore illeggibile su questo dispositivo e chiede al server quali appartengono a un account PRIVIO. I nomi, le note e la rubrica stessa non vengono mai inviati né conservati sul server.';

  @override
  String get phoneSyncNow => 'Confronta i contatti adesso';

  @override
  String phoneSyncFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count persone trovate.',
      one: '1 persona trovata.',
      zero:
          'Nessuno dei tuoi contatti è su PRIVIO, oppure nessuno ha attivato la ricerca.',
    );
    return '$_temp0';
  }

  @override
  String get phoneImportedRemove => 'Rimuovi i contatti importati';

  @override
  String get phoneImportedRemoveExplain =>
      'Rimuove solo le persone aggiunte dal confronto. Le tue chat con loro restano.';

  @override
  String get phoneNotLinkedYet => 'Nessun numero collegato';

  @override
  String get settingsBots => 'Bot';

  @override
  String get botsTitle => 'I miei bot';

  @override
  String get botsEmptyTitle => 'Ancora nessun bot';

  @override
  String get botsEmptyBody =>
      'Un bot è un account che gestisci tramite un’API HTTP. Creane uno e @botcreator ti guiderà.';

  @override
  String get botsCreate => 'Crea un bot';

  @override
  String get botsNameLabel => 'Nome';

  @override
  String get botsUsernameLabel => 'Nome utente';

  @override
  String get botsDescriptionLabel => 'Descrizione';

  @override
  String get botsCommandsLabel => 'Comandi';

  @override
  String get botsCommandsHint => 'Uno per riga: comando — che cosa fa';

  @override
  String get botsDisable => 'Spegni questo bot';

  @override
  String get botsDisabled => 'Spento';

  @override
  String get botsDelete => 'Elimina il bot';

  @override
  String botsDeleteConfirm(String username) {
    return 'Eliminare @$username?';
  }

  @override
  String get botsToken => 'Token API';

  @override
  String get botsTokenNew => 'Crea un nuovo token';

  @override
  String get botsTokenRevoke => 'Revoca i token';

  @override
  String get botsTokenOnce =>
      'Questo token viene mostrato solo questa volta. È conservato come digest e non può essere riletto. Un nuovo token sostituisce quello precedente.';

  @override
  String get botsTokenCopy => 'Copia il token';

  @override
  String get botsTokenCopied => 'Token copiato';

  @override
  String get botsTokenDone => 'L’ho salvato';

  @override
  String get botsBadge => 'BOT';

  @override
  String get botsNotEncrypted =>
      'Una conversazione con un bot non è cifrata end-to-end. Chi gestisce il bot può leggere quello che gli mandi, e anche questo server. Le tue altre chat, i gruppi e i canali restano invariati.';

  @override
  String get botsUnderstood => 'Ho capito';

  @override
  String get botcreatorTitle => 'Bot Creator';

  @override
  String get botcreatorHint => 'Scrivi un comando oppure /help';

  @override
  String get composerCamera => 'Fotocamera';

  @override
  String get attachPhotos => 'Scegli foto';

  @override
  String get attachFile => 'Invia un file';

  @override
  String get photoTitle => 'Foto';

  @override
  String get photoPreviewOne => 'Invia foto';

  @override
  String photoPreviewMany(int count) {
    return 'Invia $count foto';
  }

  @override
  String get photoRetake => 'Scatta di nuovo';

  @override
  String get photoCaptionHint => 'Aggiungi una didascalia';

  @override
  String get photoNoCamera =>
      'Su questo dispositivo non c\'è una fotocamera che Privio possa aprire.';

  @override
  String get photoCameraRefused => 'Privio non può usare la fotocamera';

  @override
  String get photoLibraryRefused => 'Privio non può aprire le tue foto';

  @override
  String get photoAllowInSettings =>
      'Il sistema lo chiede una volta sola. Puoi consentirlo nella pagina di Privio nelle impostazioni di sistema.';

  @override
  String get photoOpenSettings => 'Apri le impostazioni';

  @override
  String get photoSettingsFailed =>
      'Non è stato possibile aprire le impostazioni. Aprile tu e consentilo a Privio.';

  @override
  String photoFailed(String detail) {
    return 'Non è stato possibile aprire la fotocamera: $detail';
  }

  @override
  String get photoNoneReadable =>
      'Privio non è riuscito a leggere nessuna di quelle immagini.';

  @override
  String photoSomeLeftOut(int count) {
    return '$count delle immagini non si sono potute leggere e sono state escluse.';
  }

  @override
  String get photoStateSending => 'Invio in corso';

  @override
  String get photoStateQueued => 'In attesa di una rete';

  @override
  String get photoStateSent => 'Inviata';

  @override
  String get photoStateFailed =>
      'Non inviata. Tieni premuto il messaggio per riprovare.';

  @override
  String get privacySecurityActivity => 'Attività di sicurezza';

  @override
  String get securityActivityTitle => 'Attività di sicurezza';

  @override
  String get securityActivityEmpty =>
      'Su questo dispositivo non è stato ancora registrato nulla.';

  @override
  String get securityActivityNote =>
      'Questo elenco resta solo su questo telefono, cifrato con la stessa chiave dei tuoi messaggi. I server di Privio non tengono alcun registro di attività, il che significa anche che un evento visto da un altro dei tuoi dispositivi compare lì e non qui.';

  @override
  String get securityActivityNothingSensitive =>
      'Qui non vengono registrati contenuti dei messaggi, indirizzi o posizione.';

  @override
  String get securityEventADevice => 'un dispositivo';

  @override
  String get securityEventAContact => 'un contatto';

  @override
  String securityEventDeviceAdded(String name) {
    return 'Nuovo dispositivo collegato: $name';
  }

  @override
  String securityEventDeviceRemoved(String name) {
    return 'Dispositivo disconnesso: $name';
  }

  @override
  String get securityEventPasswordChanged => 'Password cambiata';

  @override
  String get securityEventTwoFactorOn =>
      'Autenticazione a due fattori attivata';

  @override
  String get securityEventTwoFactorOff =>
      'Autenticazione a due fattori disattivata';

  @override
  String get securityEventBackupRestored =>
      'Backup ripristinato su questo dispositivo';

  @override
  String get securityEventPhoneLinked => 'Numero di telefono collegato';

  @override
  String get securityEventPhoneRemoved => 'Numero di telefono rimosso';

  @override
  String get securityEventProxyOn => 'Connessione tramite il proxy SOCKS5';

  @override
  String get securityEventProxyOff => 'Proxy disattivato — connessione diretta';

  @override
  String securityEventKeyChanged(String name) {
    return 'Il codice di sicurezza di $name è cambiato';
  }

  @override
  String securityEventContactVerified(String name) {
    return '$name verificato';
  }

  @override
  String securityEventVerificationCleared(String name) {
    return 'Verifica di $name ritirata';
  }

  @override
  String get securityEventScreenLock => 'Blocco schermo modificato';

  @override
  String get securityEventDuressCode => 'Codice di emergenza modificato';

  @override
  String get safetyScanTheirs => 'Fotografa il suo codice';

  @override
  String get safetyScanNothingFound =>
      'In quella foto non è stato trovato nessun codice. Tieni il telefono ben frontale e riprova.';

  @override
  String get safetyScanNoCamera =>
      'Privio non può aprire la fotocamera. Confrontate invece le cifre.';

  @override
  String get safetyScanFailed =>
      'Non è stato possibile aprire la fotocamera. Confrontate invece le cifre.';

  @override
  String get privacyIdentity => 'Identità dei contatti';

  @override
  String get privacyBlockOnKeyChange =>
      'Sospendi le chat dopo un cambio di chiave';

  @override
  String get privacyBlockOnKeyChangeNote =>
      'Se il codice di sicurezza di un contatto cambia, sospendi la chat finché non hai confrontato quello nuovo. L’invio viene comunque rifiutato con una chiave cambiata.';

  @override
  String chatHeldByKeyChange(String name) {
    return 'Il codice di sicurezza di $name è cambiato. Questa chat è sospesa finché non confronti quello nuovo.';
  }

  @override
  String get chatHeldCompareNow => 'Confrontalo ora';

  @override
  String get privacyDashboardRow => 'Pannello privacy';

  @override
  String get privacyDashboardTitle => 'Pannello privacy';

  @override
  String get privacyDashboardContent => 'Cosa è cifrato';

  @override
  String get privacyDashboardMessages => 'Messaggi';

  @override
  String get privacyDashboardCalls => 'Chiamate';

  @override
  String get privacyDashboardEndToEnd => 'End-to-end';

  @override
  String get privacyDashboardBotsExcepted =>
      'Le conversazioni con i bot sono l’eccezione: non sono cifrate end-to-end';

  @override
  String get privacyDashboardVerifiedCallsOnly =>
      'Solo da contatti che hai verificato';

  @override
  String get privacyDashboardAnyCaller => 'Da chiunque possa scriverti';

  @override
  String get privacyDashboardAccount => 'Questo account';

  @override
  String get privacyDashboardDevices => 'Dispositivi collegati';

  @override
  String get privacyDashboardBackup => 'Backup';

  @override
  String get privacyDashboardBackupSealed => 'Sigillato';

  @override
  String get privacyDashboardNoBackup => 'Nessuno sul server';

  @override
  String get privacyDashboardLocalOnly =>
      'Creato su questo dispositivo, lo conservi tu';

  @override
  String get privacyDashboardFinding => 'Farsi trovare';

  @override
  String get privacyDashboardPhone => 'Numero di telefono';

  @override
  String get privacyDashboardLinked => 'Collegato';

  @override
  String get privacyDashboardNotLinked => 'Non collegato';

  @override
  String get privacyDashboardDiscovery => 'Trovabile dal mio numero';

  @override
  String get privacyDashboardContactSync => 'Sincronizzazione dei contatti';

  @override
  String get privacyDashboardIdentityAndRouting => 'Identità e connessione';

  @override
  String get privacyDashboardVerifiedContacts => 'Contatti verificati';

  @override
  String get privacyDashboardVerifiedNote =>
      'Contati rispetto alle chiavi in uso adesso: una chiave cambiata esce dal conto';

  @override
  String get privacyDashboardProxyDirect => 'Diretta';

  @override
  String get privacyDashboardProxySocks => 'SOCKS5';

  @override
  String get privacyDashboardMetadataNote =>
      'Il contenuto è cifrato; che un messaggio sia partito da te verso qualcuno, e quando, non lo è. Il server di Privio lo vede perché deve consegnarlo.';

  @override
  String get privacyOverview => 'Panoramica';

  @override
  String get profileContactAdded => 'Aggiunto ai contatti';

  @override
  String get profileCouldNotAddContact =>
      'Impossibile aggiungere questo contatto';

  @override
  String get contactMatchNow => 'Confronta i contatti ora';

  @override
  String get contactMatchRunning => 'Confronto in corso…';

  @override
  String get contactMatchNobody =>
      'Nessuno della tua rubrica è ancora su Privio, oppure non ha attivato la reperibilità tramite numero.';

  @override
  String contactMatchFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contatti su Privio',
      one: '1 contatto su Privio',
    );
    return '$_temp0';
  }

  @override
  String get contactMatchNote =>
      'La tua rubrica è rimasta su questo dispositivo. Ogni numero è stato trasformato qui in un hash con chiave e sono stati confrontati solo gli hash; non è stato caricato né conservato nulla.';

  @override
  String get contactMatchUnsupported =>
      'Questa versione non può leggere la rubrica. Puoi comunque aggiungere qualcuno tramite ID Privio, link d’invito o codice QR.';

  @override
  String get savedTitle => 'Salvati';

  @override
  String get savedEmptyPreview => 'Le tue note e i tuoi file privati';

  @override
  String get savedAccountRow => 'Salvati';

  @override
  String get savedChatSubtitle => 'Lo vedi solo tu';

  @override
  String get savedEmptyTitle => 'Non hai ancora salvato nulla';

  @override
  String get savedEmptyBody =>
      'Note, immagini, file e messaggi vocali solo per te. Nessun altro li vede, nemmeno il server di Privio, che conserva soltanto ciò che i tuoi dispositivi hanno sigillato.';

  @override
  String get savedComposerHint => 'Scrivi una nota…';

  @override
  String get savedSaveAction => 'Salva nei Salvati';

  @override
  String get savedSaved => 'Salvato';

  @override
  String get savedWaitingToSync =>
      'Salvato qui: in attesa degli altri tuoi dispositivi';

  @override
  String get savedDisappearingRefused =>
      'Questo messaggio scompare, quindi non può essere salvato. Conservarne una copia annullerebbe ciò che è stato promesso a chi lo ha inviato.';

  @override
  String get savedNothingToSave =>
      'In questo messaggio non c’è nulla da salvare.';

  @override
  String get savedCouldNotSave => 'Impossibile salvare';

  @override
  String get savedPin => 'Fissa';

  @override
  String get savedUnpin => 'Togli';

  @override
  String get savedPinnedSection => 'Fissati';

  @override
  String get savedDeleteOne => 'Elimina questa voce';

  @override
  String savedDeleteMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Elimina $count voci',
      one: 'Elimina 1 voce',
    );
    return '$_temp0';
  }

  @override
  String get savedDeleteBody =>
      'Viene rimossa da questo dispositivo e dagli altri tuoi dispositivi. Non è reversibile.';

  @override
  String savedSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count selezionate',
      one: '1 selezionata',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchHint => 'Cerca fra note, didascalie e nomi di file';

  @override
  String get savedSearchNothing => 'Nessuna corrispondenza';

  @override
  String get savedMediaRow => 'Media e file';

  @override
  String get savedMediaEmpty => 'Nessuna immagine o file salvato';

  @override
  String get savedInfoTitle => 'Informazioni su Salvati';

  @override
  String get savedKeptForever => 'Resta finché non lo elimini';

  @override
  String get savedNoTimerNote =>
      'Il timer dei messaggi che scompaiono delle tue chat non vale qui. Salvati conserva ciò che ci metti finché non lo rimuovi.';

  @override
  String get failureDisplayNameNotSaved =>
      'Il tuo nome visualizzato non è stato salvato. Quello che hai scritto è ancora nel campo.';

  @override
  String get failureDisplayNameTooLong => 'Questo nome supera i 50 caratteri.';

  @override
  String get authDisplayNameHint => 'nome visualizzato (facoltativo)';

  @override
  String get authDisplayNamePurpose =>
      'È il nome che vedono gli altri. Puoi cambiarlo quando vuoi.';

  @override
  String get authUsernamePermanent =>
      'Il tuo nome utente non potrà essere cambiato in seguito. È così che gli altri ti trovano.';

  @override
  String get authUsernameChecking => 'Controllo in corso…';

  @override
  String authUsernameFree(String name) {
    return '@$name è libero';
  }

  @override
  String authUsernameTakenHint(String name) {
    return '@$name è già preso';
  }

  @override
  String get profileEditTitle => 'Modifica profilo';

  @override
  String get profileEditDisplayName => 'Nome visualizzato';

  @override
  String get profileEditDisplayNameHint => 'il nome che vedono gli altri';

  @override
  String profileEditEmptyNote(String name) {
    return 'Lascia vuoto per essere mostrato come @$name.';
  }

  @override
  String get profileEditUsernameNote =>
      'Il tuo nome utente è stato scelto alla registrazione e resta invariato.';

  @override
  String get profileEditSaved => 'Nome visualizzato salvato';

  @override
  String get profileEditCopyUsername => 'Copia nome utente';

  @override
  String get profileEditUsernameCopied => 'Nome utente copiato';

  @override
  String profileEditRemaining(int count) {
    return 'Restano $count caratteri';
  }

  @override
  String get accountEditProfile => 'Modifica profilo';

  @override
  String get accountNoDisplayName => 'Nessun nome visualizzato';

  @override
  String get disappearing15Minutes => '15 minuti';

  @override
  String get disappearing6Hours => '6 ore';

  @override
  String get disappearing12Hours => '12 ore';

  @override
  String get disappearingStartsOnSend =>
      'I nuovi messaggi vengono eliminati automaticamente dopo questo tempo. Il timer parte all’invio.';

  @override
  String get disappearingUseDefault => 'Usa l’impostazione generale';

  @override
  String disappearingDefaultIs(String value) {
    return 'Al momento $value';
  }

  @override
  String disappearingEffective(String value) {
    return 'Qui vale: $value';
  }

  @override
  String get disappearingFollowsDefault => 'Segue la tua impostazione generale';

  @override
  String get disappearingSettingsTitle => 'Messaggi a tempo';

  @override
  String get disappearingSettingsRow => 'Messaggi a tempo';

  @override
  String get disappearingSettingsIntro =>
      'Le nuove chat partono così. Una chat che imposti tu mantiene la propria risposta.';

  @override
  String get disappearingDefaultSection => 'Impostazione generale';

  @override
  String get disappearingApplyToExisting => 'Applica alle chat esistenti';

  @override
  String disappearingApplyPreviewTitle(String value) {
    return 'Applicare $value alle chat esistenti?';
  }

  @override
  String disappearingApplyFollowing(int count) {
    return '$count chat seguono la tua impostazione generale e cambieranno.';
  }

  @override
  String disappearingApplyExceptions(int count) {
    return '$count chat hanno un’impostazione propria. Restano invariate se non le includi.';
  }

  @override
  String get disappearingApplyIncludeExceptions =>
      'Cambia anche le chat con impostazione propria';

  @override
  String get disappearingApplyConfirm => 'Applica';

  @override
  String disappearingApplied(int count) {
    return '$count chat modificate';
  }

  @override
  String disappearingSkippedGroups(int count) {
    return '$count gruppi saltati: non sei amministratore.';
  }

  @override
  String get disappearingExceptionsRow => 'Gestisci le eccezioni';

  @override
  String get disappearingExceptionsTitle => 'Chat con impostazione propria';

  @override
  String get disappearingExceptionsEmpty =>
      'Nessuna chat differisce dalla tua impostazione generale.';

  @override
  String get disappearingResetToDefault => 'Usa l’impostazione generale';

  @override
  String get disappearingResetAll => 'Riporta tutto all’impostazione generale';

  @override
  String get disappearingCappedNotice =>
      'Un timer superiore a 24 ore è stato ridotto a 24 ore. I messaggi già inviati mantengono il tempo originale.';

  @override
  String get noticeTimerCapped =>
      'I messaggi a tempo sono stati impostati su 24 ore, il massimo di questa app.';
}
