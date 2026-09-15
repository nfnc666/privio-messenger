// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppTextFr extends AppText {
  AppTextFr([String locale = 'fr']) : super(locale);

  @override
  String get languageName => 'Langue';

  @override
  String get languagePickerTitle => 'Langue';

  @override
  String get languagePickerNote =>
      'L\'interface change immédiatement. Les messages, les noms de canaux et tout ce que les gens ont écrit restent dans la langue dans laquelle ils ont été écrits.';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDone => 'Terminé';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonRemove => 'Retirer';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonSearch => 'Rechercher';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get commonBack => 'Retour';

  @override
  String get commonNext => 'Suivant';

  @override
  String get commonSkip => 'Passer';

  @override
  String get commonContinue => 'Continuer';

  @override
  String get commonYes => 'Oui';

  @override
  String get commonNo => 'Non';

  @override
  String get commonOk => 'D\'accord';

  @override
  String get commonCopy => 'Copier';

  @override
  String get commonCopied => 'Copié.';

  @override
  String get commonShare => 'Partager';

  @override
  String get commonLoading => 'Chargement…';

  @override
  String get commonSomethingWentWrong => 'Quelque chose s\'est mal passé.';

  @override
  String get commonNotNow => 'Pas maintenant';

  @override
  String get commonOn => 'Activé';

  @override
  String get commonOff => 'Désactivé';

  @override
  String get commonDefault => 'Par défaut';

  @override
  String get commonCustom => 'Personnalisé';

  @override
  String get commonUnavailable => 'Indisponible';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get disappearingTitle => 'Messages éphémères';

  @override
  String get disappearingExplainer =>
      'Les nouveaux messages sont supprimés automatiquement au bout de ce délai. Le compte à rebours démarre à l\'envoi du message.';

  @override
  String get disappearingCoversChat =>
      'Cela couvre le texte, les photos, les fichiers et les messages vocaux, et ne s\'applique qu\'à cette discussion. Les messages déjà envoyés ne sont pas concernés, et vous êtes tous les deux prévenus en cas de changement.';

  @override
  String get disappearingCoversGroup =>
      'Cela couvre le texte, les photos, les fichiers et les messages vocaux, et ne s\'applique qu\'à ce groupe. Les messages déjà envoyés ne sont pas concernés, tout le monde est prévenu en cas de changement, et seul un administrateur peut le modifier.';

  @override
  String get disappearingScreenshotCaveat =>
      'Cela ne peut pas annuler une capture d\'écran, une photo déjà enregistrée ou quoi que ce soit noté ailleurs.';

  @override
  String get disappearingOff => 'Désactivé';

  @override
  String get disappearing30Seconds => '30 secondes';

  @override
  String get disappearing1Minute => '1 minute';

  @override
  String get disappearing5Minutes => '5 minutes';

  @override
  String get disappearing1Hour => '1 heure';

  @override
  String get disappearing24Hours => '24 heures';

  @override
  String get disappearing7Days => '7 jours';

  @override
  String get disappearingAdminOnly =>
      'Seul un administrateur peut modifier ceci';

  @override
  String noticeTimerSetBy(String who, String duration) {
    return '$who a réglé les messages éphémères sur $duration';
  }

  @override
  String noticeTimerOffBy(String who) {
    return '$who a désactivé les messages éphémères';
  }

  @override
  String get noticeYou => 'Vous';

  @override
  String get noticeThey => 'Votre correspondant';

  @override
  String get noticeSomeone => 'Quelqu\'un';

  @override
  String noticeMessageDeletedBy(String who) {
    return '$who a supprimé un message';
  }

  @override
  String noticeSafetyNumberChanged(String who) {
    return 'Votre numéro de sécurité avec $who a changé';
  }

  @override
  String noticeUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: 'Un message',
    );
    return '$_temp0 n\'a pas pu être lu. Il était scellé avec une clé que cet appareil ne possède plus.';
  }

  @override
  String noticeUnreadableFrom(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: 'Un message',
    );
    return '$_temp0 de $who n\'a pas pu être lu. Il était scellé avec une clé que cet appareil ne possède plus.';
  }

  @override
  String durationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count secondes',
      one: '1 seconde',
    );
    return '$_temp0';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heures',
      one: '1 heure',
    );
    return '$_temp0';
  }

  @override
  String durationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return '$_temp0';
  }

  @override
  String durationWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count semaines',
      one: '1 semaine',
    );
    return '$_temp0';
  }

  @override
  String channelSubscribers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abonnés',
      one: '1 abonné',
    );
    return '$_temp0';
  }

  @override
  String channelMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '1 membre',
    );
    return '$_temp0';
  }

  @override
  String get channelPublic => 'Public';

  @override
  String get channelPrivate => 'Privé';

  @override
  String get channelAdministrators => 'Administrateurs';

  @override
  String get channelSubscribersRow => 'Abonnés';

  @override
  String get channelSettings => 'Réglages du canal';

  @override
  String get channelShareLink => 'Partager le lien';

  @override
  String get channelDescription => 'Description';

  @override
  String get channelMedia => 'Médias';

  @override
  String get channelLinks => 'Liens';

  @override
  String get channelNoMedia => 'Pas encore d\'images';

  @override
  String get channelNoLinks => 'Pas encore de liens';

  @override
  String get channelNoPosts => 'Pas encore de publications';

  @override
  String get channelActionLivestream => 'direct';

  @override
  String get channelActionMute => 'muet';

  @override
  String get channelActionUnmute => 'réactiver';

  @override
  String get channelActionSearch => 'rechercher';

  @override
  String get channelActionMore => 'plus';

  @override
  String get channelMuteTitle => 'Mettre ce canal en sourdine';

  @override
  String get channelMuteNote =>
      'Il reste en sourdine sur tous les appareils où vous êtes connecté : le mettre en sourdine ici, ce n\'est pas « jusqu\'à ce que je reprenne mon ordinateur ».';

  @override
  String get channelMuteForHour => 'Pendant 1 heure';

  @override
  String get channelMuteForEightHours => 'Pendant 8 heures';

  @override
  String get channelMuteForTwoDays => 'Pendant 2 jours';

  @override
  String get channelMuteUntilOff => 'Jusqu\'à ce que je le réactive';

  @override
  String get channelCopyLink => 'Copier le lien';

  @override
  String get channelQrCode => 'Code QR';

  @override
  String get channelInviteSettings => 'Réglages d\'invitation';

  @override
  String get channelStatistics => 'Statistiques';

  @override
  String get channelReport => 'Signaler le canal';

  @override
  String get channelLeave => 'Quitter le canal';

  @override
  String get channelLeaveTitle => 'Quitter ce canal ?';

  @override
  String get channelLeaveBody =>
      'Vous ne recevez plus ses publications. Le canal passe à une nouvelle clé : rien de ce qui sera publié ensuite ne vous sera lisible.';

  @override
  String get channelStay => 'Rester';

  @override
  String get channelNoLinkToShare => 'Ce canal n\'a aucun lien à partager.';

  @override
  String get channelInfo => 'Infos du canal';

  @override
  String get adminsTitle => 'Administrateurs';

  @override
  String get adminsSectionHeader => 'ADMINISTRATEURS DU CANAL';

  @override
  String get adminsAdd => 'Ajouter un administrateur';

  @override
  String get adminsSearch => 'Rechercher des administrateurs';

  @override
  String get adminsRoleOwner => 'Propriétaire';

  @override
  String get adminsRoleAdmin => 'Administrateur';

  @override
  String adminsPromotedBy(String who) {
    return 'nommé par $who';
  }

  @override
  String get adminsHelpOwner =>
      'Les administrateurs vous aident à gérer votre canal.';

  @override
  String get adminsHelpMember =>
      'Les administrateurs aident à gérer ce canal. Seule une personne autorisée à nommer des administrateurs peut modifier cette liste.';

  @override
  String get adminsNobodyYet => 'Personne pour l\'instant.';

  @override
  String get adminsShowSenderName => 'Afficher le nom de l\'auteur';

  @override
  String get adminsShowSenderNameOn =>
      'Les nouvelles publications portent le nom de la personne qui les a écrites';

  @override
  String get adminsShowSenderNameLocked =>
      'Seul un administrateur autorisé à modifier le canal peut changer ceci';

  @override
  String get adminsShowSenderNameNote =>
      'Désactivé, tout ce que le canal publie est publié par le canal : aucun nom d\'administrateur n\'est joint, et les lecteurs entendent une seule voix.';

  @override
  String get adminsTransfer => 'Transférer la propriété';

  @override
  String get adminsTransferNote =>
      'Demande votre mot de passe et ne peut pas être annulé';

  @override
  String get adminsEverybodyAlready =>
      'Tout le monde dans ce canal est déjà administrateur.';

  @override
  String get adminsWhoShouldBe => 'Qui doit devenir administrateur ?';

  @override
  String get adminsDismiss => 'Révoquer comme administrateur';

  @override
  String get adminsAppoint => 'Nommer';

  @override
  String get adminsOwnerFixed =>
      'Le propriétaire détient toutes les autorisations, et cela n\'est pas modifiable — ni ici, ni sur le serveur.';

  @override
  String get adminsOutranksYou =>
      'Cette personne détient des autorisations que vous n\'avez pas : vous ne pouvez donc pas modifier ce qu\'elle a le droit de faire.';

  @override
  String get adminsOnlyWhatYouHold =>
      'Vous ne pouvez accorder que ce que vous détenez vous-même. Ce que vous n\'avez pas est désactivé et ne peut pas être activé.';

  @override
  String get adminsYouDoNotHold => 'Vous ne détenez pas cette autorisation';

  @override
  String get adminsCouldNotChange => 'Impossible de modifier cela.';

  @override
  String get permissionEditChannel => 'Modifier le canal';

  @override
  String get permissionEditChannelDetail =>
      'Nom, image, description et réglages';

  @override
  String get permissionPost => 'Publier';

  @override
  String get permissionPostDetail =>
      'Et modifier ou programmer ses propres publications';

  @override
  String get permissionDeletePosts => 'Supprimer des publications';

  @override
  String get permissionDeletePostsDetail => 'Y compris celles des autres';

  @override
  String get permissionModerate => 'Modérer la discussion';

  @override
  String get permissionModerateDetail =>
      'Retirer des commentaires et réduire des personnes au silence';

  @override
  String get permissionManageMembers => 'Gérer les abonnés';

  @override
  String get permissionManageMembersDetail =>
      'Ajouter, retirer et réduire au silence';

  @override
  String get permissionManageInvites => 'Gérer les invitations';

  @override
  String get permissionManageInvitesDetail =>
      'Le lien, ses limites et qui est en attente';

  @override
  String get permissionManageLivestreams => 'Gérer les directs';

  @override
  String get permissionManageLivestreamsDetail => 'Les lancer et les terminer';

  @override
  String get permissionAppointAdmins => 'Nommer des administrateurs';

  @override
  String get permissionAppointAdminsDetail =>
      'Confier cette autorité à quelqu\'un d\'autre';

  @override
  String get subscribersTitle => 'Abonnés';

  @override
  String get subscribersAdd => 'Ajouter des abonnés';

  @override
  String get subscribersSearch => 'Rechercher des abonnés';

  @override
  String get subscribersAdminsOnlyNote =>
      'Seuls les administrateurs du canal voient cette liste.';

  @override
  String get subscribersPartialNote =>
      'Ce n\'est pas la liste complète. Seuls les administrateurs du canal peuvent voir qui est abonné : ce que vous voyez ici, ce sont les personnes qui le gèrent, et vous.';

  @override
  String get subscribersCompleteNote => 'Tout le monde dans ce canal.';

  @override
  String get subscribersContactsSection => 'CONTACTS DANS CE CANAL';

  @override
  String get subscribersOthersSection => 'AUTRES ABONNÉS';

  @override
  String get subscribersOnlySection => 'ABONNÉS';

  @override
  String get subscribersNobodyFound => 'Aucune personne trouvée.';

  @override
  String get subscribersNoContacts => 'Pas encore de contacts à ajouter.';

  @override
  String get subscribersEverybodyHere => 'Tous vos contacts sont déjà là.';

  @override
  String get subscribersAddedOne => 'Ajouté.';

  @override
  String subscribersAddedMany(int count) {
    return '$count personnes ajoutées.';
  }

  @override
  String get subscribersNobodyAdded => 'Personne n\'a pu être ajouté';

  @override
  String subscribersAddedCount(int count) {
    return '$count ajoutés';
  }

  @override
  String subscribersNeedInvite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes ont réglé leur compte',
      one: '1 personne a réglé son compte',
    );
    return '$_temp0 de sorte que seuls leurs propres contacts peuvent les ajouter. Envoyez-leur plutôt le lien et laissez-les décider.';
  }

  @override
  String get subscribersCopyTheLink => 'Copier le lien';

  @override
  String get subscribersOwnerCannotBeRemoved =>
      'Le propriétaire ne peut pas être retiré.';

  @override
  String get subscribersSilenced => 'Réduit au silence';

  @override
  String get subscribersSilence => 'Réduire au silence';

  @override
  String get subscribersSilenceDetail =>
      'La personne reste abonnée et ne peut plus commenter';

  @override
  String get subscribersUnsilence => 'Lui rendre la parole';

  @override
  String get subscribersUnsilenceDetail => 'Elle peut de nouveau commenter';

  @override
  String get subscribersRemoveFromChannel => 'Retirer du canal';

  @override
  String get subscribersRemoveDetail =>
      'Le canal passe à une nouvelle clé : la personne ne pourra pas lire la suite';

  @override
  String get subscribersCouldNotDoThat => 'Impossible de faire cela.';

  @override
  String get presenceOnline => 'en ligne';

  @override
  String presenceMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return 'vu il y a $_temp0';
  }

  @override
  String presenceHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count heures',
      one: '1 heure',
    );
    return 'vu il y a $_temp0';
  }

  @override
  String presenceDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count jours',
      one: '1 jour',
    );
    return 'vu il y a $_temp0';
  }

  @override
  String presenceOnDate(String date) {
    return 'vu le $date';
  }

  @override
  String get editChannelName => 'Nom du canal';

  @override
  String get editChannelDescriptionHint => 'Description';

  @override
  String get editChannelChangePicture => 'Changer l\'image';

  @override
  String get editChannelChoosePicture => 'Choisir une image';

  @override
  String get editChannelRemovePicture => 'La retirer';

  @override
  String get editChannelPrivateNameNote =>
      'Ce canal est privé : son nom est donc chiffré avec la clé du canal. Le renommer rescelle ce nom pour chaque membre.';

  @override
  String get editChannelType => 'Type de canal';

  @override
  String get editChannelDiscussion => 'Discussion';

  @override
  String get editChannelReactions => 'Réactions';

  @override
  String editChannelReactionsValue(int count) {
    return '$count émojis';
  }

  @override
  String get editChannelWelcome => 'Message de bienvenue';

  @override
  String get editChannelAppearance => 'Apparence';

  @override
  String get editChannelAutoTranslate => 'Traduction automatique';

  @override
  String get editChannelDirectMessages => 'Messages directs';

  @override
  String get editChannelNeedsName => 'Un canal a besoin d\'un nom.';

  @override
  String get editChannelDiscardTitle => 'Abandonner vos modifications ?';

  @override
  String get editChannelDiscardBody => 'Rien ici n\'a encore été enregistré.';

  @override
  String get editChannelKeepEditing => 'Continuer à modifier';

  @override
  String get editChannelDiscard => 'Abandonner';

  @override
  String get editChannelCouldNotSave =>
      'Impossible d\'enregistrer ces modifications.';

  @override
  String get editChannelCouldNotUsePicture =>
      'Impossible d\'utiliser cette image.';

  @override
  String get editChannelPublicPictureTitle => 'Cette image sera publique';

  @override
  String get editChannelPublicPictureBody =>
      'L\'image d\'un canal public est affichée sur sa page web et dans les aperçus de lien : elle est donc stockée sans chiffrement, comme son nom, son identifiant et sa description. Les publications restent chiffrées de bout en bout.';

  @override
  String get editChannelUseIt => 'L\'utiliser';

  @override
  String get editChannelSignatureNote =>
      'Les publications signées affichent le nom de la personne qui les a écrites. Désactivé, tout ce que le canal publie est publié par le canal.';

  @override
  String get livestreamNotSetUpTitle => 'Les directs ne sont pas configurés';

  @override
  String get livestreamNotSetUpBody =>
      'Un direct a besoin d\'un serveur média : une personne envoie la vidéo et toutes les autres la reçoivent, ce qui ne peut pas se faire d\'appareil à appareil comme pour un appel.\n\nCe serveur PRIVIO n\'en a aucun de configuré : il n\'y a donc encore rien à rejoindre. La personne qui l\'administre peut en mettre un en place.';

  @override
  String get livestreamYouAreLive => 'Vous êtes en direct';

  @override
  String get livestreamRunning => 'Un direct est en cours';

  @override
  String get livestreamPublisherBody =>
      'La salle est ouverte et votre appareil dispose d\'un jeton pour y diffuser. PRIVIO ne transporte pas encore la vidéo elle-même — c\'est le serveur média qui le fait — donc rien n\'est envoyé depuis cet écran.\n\nTerminez-le quand vous avez fini.';

  @override
  String get livestreamViewerBody =>
      'Un direct est en cours et cet appareil dispose d\'un jeton pour le regarder. PRIVIO ne peut pas encore afficher la vidéo.';

  @override
  String get livestreamEndIt => 'Y mettre fin';

  @override
  String get livestreamNobodyStreaming => 'Personne ne diffuse en ce moment.';

  @override
  String get livestreamCouldNotStart => 'Impossible de démarrer le direct.';

  @override
  String get translationNotSetUpTitle =>
      'La traduction automatique n\'est pas configurée';

  @override
  String get translationNotSetUpBody =>
      'Traduire une publication revient à envoyer son contenu à un service de traduction. Le serveur PRIVIO ne peut pas le faire — il ne détient que du texte chiffré et aucune clé — cela devrait donc se passer sur votre appareil, et le texte en sortirait en clair.\n\nC\'est une décision que la personne qui administre ce serveur doit activer et que chaque lecteur doit accepter : c\'est donc désactivé tant que les deux n\'ont pas eu lieu. Aucune publication n\'a été envoyée où que ce soit.';

  @override
  String get visibilityPublicTitle => 'Ce canal est public';

  @override
  String get visibilityPrivateTitle => 'Ce canal est privé';

  @override
  String visibilityPublicBody(String handle) {
    return 'N\'importe qui peut le trouver par son nom et lire ses publications. Son identifiant est @$handle.\n\nPRIVIO ne peut pas rendre privé un canal public après coup : son nom et sa description ont été lisibles, et une application ne peut pas défaire cela.';
  }

  @override
  String get visibilityPrivateBody =>
      'Il n\'est pas répertorié, pas trouvable par la recherche, et accessible uniquement par son lien d\'invitation. Son nom est chiffré avec la clé du canal.\n\nLe rendre public publierait ce nom, et ce n\'est pas une décision que PRIVIO prend à votre place — créez plutôt un canal public.';

  @override
  String get discussionBody =>
      'Avec ceci activé, chaque publication reçoit un fil en dessous. Les commentaires sont scellés avec la même clé de canal que la publication : un appareil qui ne peut pas lire la publication ne peut pas lire le fil.\n\nLe désactiver plus tard masque les fils au lieu de les supprimer.';

  @override
  String get discussionTurnOn => 'Activer';

  @override
  String get discussionTurnOff => 'Désactiver';

  @override
  String get welcomeShowToNew => 'L\'afficher aux nouveaux abonnés';

  @override
  String get welcomeHint => 'Affiché une fois, à l\'arrivée';

  @override
  String get welcomePrivateNote =>
      'Ce canal est privé : le message est donc chiffré avec la clé du canal, comme son nom.';

  @override
  String get appearanceNote =>
      'Un ensemble fixe plutôt qu\'un sélecteur de couleurs : chaque paire ici a été vérifiée en contraste, pour qu\'un canal ne puisse pas choisir quelque chose que ses lecteurs ne pourraient pas lire.';

  @override
  String get appearancePreviewPost => 'Une publication dans ce canal';

  @override
  String get appearancePreviewLink => 'et un lien dedans';

  @override
  String get appearanceAccent => 'Couleur d\'accentuation';

  @override
  String get appearanceBackground => 'Arrière-plan';

  @override
  String get appearanceUseDefault => 'Utiliser la valeur par défaut';

  @override
  String get composerHint => 'Écrivez un message…';

  @override
  String get composerAttach => 'Joindre un fichier';

  @override
  String get composerTimerOff => 'Les messages éphémères sont désactivés';

  @override
  String composerTimerOn(String badge) {
    return 'Les messages disparaissent après $badge';
  }

  @override
  String get searchPostsHint =>
      'Rechercher dans les publications que vous pouvez lire';

  @override
  String get searchThisChannel => 'Rechercher dans ce canal';

  @override
  String get searchClose => 'Fermer la recherche';

  @override
  String get searchNoResults => 'Aucun résultat';

  @override
  String get settingsPrivacy => 'Confidentialité et sécurité';

  @override
  String get settingsStorage => 'Données et stockage';

  @override
  String get settingsAbout => 'À propos de Privio';

  @override
  String get settingsDevices => 'Appareils';

  @override
  String get settingsBackup => 'Sauvegarde';

  @override
  String get settingsDisguise => 'Mode camouflage';

  @override
  String get settingsLicense => 'Licence Privio';

  @override
  String get settingsLicenseNotActive => 'Non active';

  @override
  String get appearanceTextSize => 'Taille du texte';

  @override
  String get appearanceTextSizeNote =>
      'C\'est le réglage propre à Privio et il s\'applique partout dans l\'application. Il ne remplace pas la taille que votre téléphone utilise pour tout le reste — celle-ci s\'applique toujours en dessous.';

  @override
  String get appearanceDarkOnly =>
      'Privio est uniquement sombre. Le design est fait pour cela, le vrai noir ne coûte rien sur les dalles OLED de la plupart des téléphones, et un thème clair qui n\'existe qu\'à moitié ne mérite pas un interrupteur qui prétend le contraire.';

  @override
  String get textSizeSmall => 'Petite';

  @override
  String get textSizeMedium => 'Moyenne';

  @override
  String get textSizeLarge => 'Grande';

  @override
  String get textSizeLarger => 'Très grande';

  @override
  String get notificationsPushNote =>
      'Une notification push ne transporte aucun contenu — seulement un réveil. Le message est récupéré et déchiffré sur cet appareil, donc personne au milieu ne voit qui vous a écrit, pas même celui qui exploite le service qui l\'a réveillé.';

  @override
  String get notificationsPhoneNote =>
      'Le son, la vibration, la lumière et ce qui s\'affiche sur l\'écran verrouillé relèvent des réglages de votre téléphone pour Privio, pas de cet écran. Il y avait ici cinq interrupteurs qui ne réglaient rien ; ils ont été retirés plutôt que laissés à faire semblant.';

  @override
  String get notificationsDelivery => 'Distribution';

  @override
  String notificationsDistributorFound(String app) {
    return 'Une application de distribution sur ce téléphone garde une connexion pour toutes les applications qui l\'utilisent et transmet un signal sans contenu. $app n\'a besoin d\'aucun service Google pour cela, et vous pouvez héberger le distributeur vous-même.';
  }

  @override
  String get notificationsNoDistributor =>
      'Aucun distributeur trouvé. Installez-en un — ntfy, par exemple — pour être réveillé pendant que Privio est fermé. Sans cela, les messages arrivent quand l\'application est ouverte.';

  @override
  String get privacyWhoCanSee => 'Qui peut voir';

  @override
  String get privacyLastSeen => 'Vu pour la dernière fois';

  @override
  String get privacyLastSeenEveryone => 'Tout le monde';

  @override
  String get privacyLastSeenContacts => 'Mes contacts';

  @override
  String get privacyLastSeenNobody => 'Personne';

  @override
  String get privacyMessaging => 'Messagerie';

  @override
  String get privacyReadReceipts => 'Accusés de lecture';

  @override
  String get privacyTypingIndicators => 'Indicateurs de saisie';

  @override
  String get privacyDisappearing => 'Messages éphémères';

  @override
  String get privacyPerChat => 'Par discussion';

  @override
  String get privacyAccess => 'Accès';

  @override
  String get privacyScreenLock => 'Verrouillage de l\'écran';

  @override
  String get privacyPin => 'Code';

  @override
  String get privacyTwoFactor => 'Authentification à deux facteurs';

  @override
  String get privacyDuressCode => 'Code de contrainte';

  @override
  String get privacyScreenShield => 'Protection de l\'écran';

  @override
  String get privacyScreenShieldAndroid =>
      'Bloque les captures et les enregistrements d\'écran de l\'application.';

  @override
  String get privacyScreenShieldIos =>
      'Masque le contenu sensible lorsqu\'un enregistrement ou un partage d\'écran est détecté. Sur iOS, les captures d\'écran ne peuvent pas être empêchées de manière fiable.';

  @override
  String get privacyScreenShieldUnavailable =>
      'Cet appareil ne peut pas protéger l\'écran.';

  @override
  String get privacyScreenShieldScope =>
      'Cela ne protège que votre propre appareil. Cela n\'empêche pas les autres d\'enregistrer leur écran, ni une photo prise avec un autre appareil.';

  @override
  String get privacyScreenShieldCovering =>
      'Un enregistrement d\'écran est en cours. Privio reste masqué jusqu\'à la fin.';

  @override
  String get privacySet => 'Défini';

  @override
  String get privacyBlockedUsers => 'Utilisateurs bloqués';

  @override
  String get privacyMutualNote =>
      'Les accusés de lecture et les indicateurs de saisie sont réciproques : les désactiver vous empêche aussi de voir ceux des autres.';

  @override
  String get storageOnThisDevice => 'Sur cet appareil';

  @override
  String get storageHistory => 'Historique des discussions';

  @override
  String get storageInIt => 'Contenu';

  @override
  String storageChatsAndMessages(int chats, int messages) {
    String _temp0 = intl.Intl.pluralLogic(
      chats,
      locale: localeName,
      other: '$chats discussions',
      one: '1 discussion',
    );
    String _temp1 = intl.Intl.pluralLogic(
      messages,
      locale: localeName,
      other: '$messages messages',
      one: '1 message',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get storageKeys => 'Clés et sessions';

  @override
  String get storageKeystoreNote =>
      'Les deux se trouvent dans le magasin de clés de la plateforme — le Trousseau sur iOS, un stockage adossé au Keystore sur Android — et l\'historique est scellé en AES-256-GCM avant d\'y arriver. Aucune autre application ne peut les lire, et personne tenant le téléphone ne le peut sans le déverrouiller.';

  @override
  String get storageNotKept => 'Non conservé';

  @override
  String get storageFilesOpened => 'Fichiers que vous avez ouverts';

  @override
  String get storageMemoryOnly => 'En mémoire seulement';

  @override
  String get storageVoiceRecordings => 'Enregistrements vocaux';

  @override
  String get storageShredded => 'Détruits à l\'envoi';

  @override
  String get storageEphemeralNote =>
      'Une photo ou un fichier que vous ouvrez est déchiffré en mémoire et disparaît à la fermeture de l\'application ; rien ne l\'écrit sur le disque. Un message vocal est enregistré dans un fichier temporaire, parce que le micro doit écrire quelque part, et ce fichier est écrasé par des octets aléatoires puis supprimé dès la fin de l\'enregistrement — un fichier supprimé sur une mémoire flash n\'est pas un fichier disparu.';

  @override
  String get storageDelete => 'Supprimer';

  @override
  String get storageDeleteHistory => 'Supprimer l\'historique sur cet appareil';

  @override
  String get storageDeleteNote =>
      'C\'est la seule suppression qui a lieu ici. Ce que le serveur conserve — une sauvegarde, une pièce jointe encore dans ses trente jours — se trouve sur l\'écran Sauvegarde, et ce que possède la personne à qui vous avez écrit lui appartient.';

  @override
  String get storageConfirmTitle =>
      'Supprimer l\'historique sur cet appareil ?';

  @override
  String get storageConfirmBody =>
      'Tous les messages de ce téléphone disparaissent, dans toutes les discussions. Votre compte, vos clés et vos conversations restent : on peut toujours vous écrire, et ce que vous envoyez ensuite arrive toujours.\n\nCela n\'atteint pas leur copie, ni une sauvegarde déjà sur le serveur. Supprimez-la depuis l\'écran Sauvegarde si vous voulez qu\'elle disparaisse aussi.';

  @override
  String get storageDeleteIt => 'Supprimer';

  @override
  String get storageDeleted => 'L\'historique sur cet appareil a disparu.';

  @override
  String get devicesThisDevice => 'Cet appareil';

  @override
  String get devicesOthers => 'Autres appareils';

  @override
  String get devicesOthersTapToSignOut =>
      'Autres appareils — touchez pour déconnecter';

  @override
  String get devicesNone => 'Aucun';

  @override
  String get devicesOnlyThisOne => 'Uniquement celui-ci';

  @override
  String get devicesSignedIn => 'Connecté';

  @override
  String get devicesActiveNow => 'Actif maintenant';

  @override
  String devicesActiveMinutes(int count) {
    return 'Actif il y a $count min';
  }

  @override
  String devicesActiveHours(int count) {
    return 'Actif il y a $count h';
  }

  @override
  String get devicesActiveYesterday => 'Actif hier';

  @override
  String devicesActiveDays(int count) {
    return 'Actif il y a $count jours';
  }

  @override
  String get devicesSignOutNote =>
      'Déconnecter un appareil révoque sa session et supprime tout ce qui est encore en attente pour lui. Il ne peut revenir qu\'en se reconnectant — comme un nouvel appareil, avec de nouvelles clés.';

  @override
  String devicesRevokeTitle(String name) {
    return 'Déconnecter $name ?';
  }

  @override
  String get devicesRevokeBody =>
      'Sa session est révoquée et tout ce qui est encore en attente pour lui est supprimé. Ce qu\'il a déjà déchiffré reste sur cet appareil — rien ici ne peut l\'atteindre. Il ne peut revenir qu\'en se reconnectant.';

  @override
  String get devicesSignItOut => 'Le déconnecter';

  @override
  String devicesSignedOut(String name) {
    return '$name est déconnecté.';
  }

  @override
  String devicesLicenseCovers(int limit) {
    return 'Votre licence couvre $limit appareils.';
  }

  @override
  String devicesLicenseCoversUsed(int limit, int used) {
    return 'Votre licence couvre $limit appareils. $used en service.';
  }

  @override
  String get aboutTagline =>
      'Conçu avec la confidentialité en tête.\nAucun pistage. Aucune publicité. Juste vous.';

  @override
  String get aboutWebsite => 'Site web';

  @override
  String get aboutSupport => 'Assistance';

  @override
  String get aboutAddress => 'Adresse';

  @override
  String get aboutOpenSource => 'Open source';

  @override
  String get aboutEdition => 'Édition';

  @override
  String aboutFreeSoftware(String name) {
    return '$name · logiciel libre';
  }

  @override
  String get aboutLicense => 'Licence';

  @override
  String get aboutSourceCode => 'Code source';

  @override
  String get aboutCopyLink => 'Copier le lien';

  @override
  String get aboutSourceLink => 'Lien du code source';

  @override
  String get aboutThirdParty => 'Licences tierces';

  @override
  String aboutCopied(String what) {
    return '$what copié.';
  }

  @override
  String get aboutFreeBuildNote =>
      'Cette version ne contient aucun code propriétaire et peut être reproduite à partir du code source ci-dessus. Rien ici n\'est à prendre sur parole — compilez-la vous-même et comparez.';

  @override
  String get aboutStoreBuildNote =>
      'Cette version provient d\'une boutique d\'applications et intègre ses services. La version Libre, au code source ci-dessus, n\'en contient aucun.';

  @override
  String get blockedUnblock => 'Débloquer';

  @override
  String blockedUnblockTitle(String name) {
    return 'Débloquer $name ?';
  }

  @override
  String get blockedUnblockBody =>
      'Cette personne pourra de nouveau vous écrire.';

  @override
  String get blockedInvisibleNote =>
      'Le blocage est invisible : leurs messages sont jetés et on ne leur dit rien, un blocage ne peut donc pas servir à découvrir qu\'on a été bloqué.';

  @override
  String get blockedNobody => 'Personne n\'est bloqué';

  @override
  String get blockedEmptyNote =>
      'Bloquez quelqu\'un depuis sa discussion, et il apparaîtra ici.';

  @override
  String get chatsSectionChats => 'Discussions';

  @override
  String get chatsSectionMessages => 'Messages';

  @override
  String get chatsYouPrefix => 'Vous : ';

  @override
  String get chatsNoSearchResults =>
      'Rien ne correspond ici. Seul cet appareil a été interrogé — le serveur détient des messages qu\'il ne peut pas lire, il n\'aurait donc pas pu répondre.';

  @override
  String get chatsFilterAll => 'Tous';

  @override
  String get chatsFilterUnread => 'Non lus';

  @override
  String get chatsFilterGroups => 'Groupes';

  @override
  String get chatsPin => 'Épingler en haut';

  @override
  String get chatsUnpin => 'Détacher';

  @override
  String get chatsPinNote => 'Uniquement sur cet appareil. Rien n\'est envoyé.';

  @override
  String get chatsGroupFallbackName => 'Groupe';

  @override
  String get chatsCouldNotOpenLink => 'Impossible d\'ouvrir ce lien';

  @override
  String get chatsJoinGroupTooltip => 'Rejoindre un groupe avec un lien';

  @override
  String get chatsNewGroupTooltip => 'Nouveau groupe';

  @override
  String get chatsNewChatTooltip => 'Nouvelle discussion';

  @override
  String get chatsEmptyTitle => 'Pas encore de discussions';

  @override
  String get chatsEmptyBody =>
      'Ajoutez quelqu\'un avec son nom d\'utilisateur exact pour commencer à discuter.';

  @override
  String get chatsAddContact => 'Ajouter un contact';

  @override
  String get chatsJoinGroupTitle => 'Rejoindre un groupe';

  @override
  String get chatsJoinGroupNote =>
      'Le lien vous fait entrer. La clé du nom du groupe est ensuite envoyée à votre appareil, chiffrée, par quelqu\'un déjà dans le groupe.';

  @override
  String get chatsJoin => 'Rejoindre';

  @override
  String get commonGotIt => 'C\'est compris';

  @override
  String get commonPause => 'Pause';

  @override
  String get commonPlay => 'Lire';

  @override
  String get commonOpen => 'Ouvrir';

  @override
  String get commonReply => 'Répondre';

  @override
  String get commonFile => 'Fichier';

  @override
  String get scrubRemoved => 'Métadonnées supprimées';

  @override
  String get scrubNothingToRemove => 'Rien à supprimer';

  @override
  String get scrubCouldNotClean => 'N\'a pas pu être nettoyé';

  @override
  String get scrubRemovedBody =>
      'Cela a été retiré avant que le fichier soit chiffré et envoyé. Le destinataire ne le reçoit jamais.';

  @override
  String get scrubNothingBody =>
      'Ce fichier ne portait dès le départ aucune métadonnée identifiante.';

  @override
  String scrubNoCleanerBody(String type) {
    return 'Privio n\'a pas encore de nettoyeur pour $type, le fichier a donc été envoyé tel quel. Il reste chiffré de bout en bout, mais toutes les métadonnées qu\'il contient parviennent au destinataire.';
  }

  @override
  String get webStorageShort =>
      'Dans un navigateur, l\'historique de cet appareil n\'est privé que dans la mesure où ce profil de navigateur l\'est. Les messages en transit sont chiffrés dans tous les cas.';

  @override
  String get webStorageLong =>
      'Vous utilisez Privio dans un navigateur. Les messages restent chiffrés de bout en bout en transit — mais un navigateur n\'a pas de magasin de clés, donc l\'historique conservé sur cet appareil n\'est privé que dans la mesure où ce profil de navigateur l\'est. Quiconque peut le lire — un ordinateur partagé, une extension, une copie du profil — peut lire vos discussions. Les applications mobiles n\'ont pas ce problème.';

  @override
  String get voiceCouldNotOpen => 'Impossible d\'ouvrir cet enregistrement.';

  @override
  String get voiceCannotPlay =>
      'Cet appareil ne peut pas lire cet enregistrement.';

  @override
  String get voiceMicUnavailable =>
      'Le microphone n\'est pas disponible pour le moment.';

  @override
  String get voiceCouldNotSave =>
      'Cet enregistrement n\'a pas pu être enregistré.';

  @override
  String get voiceSlideToCancel => 'Glissez pour annuler';

  @override
  String get voiceResume => 'Reprendre';

  @override
  String get voiceStop => 'Arrêter';

  @override
  String get voiceDeleteRecording => 'Supprimer l\'enregistrement';

  @override
  String get voiceListenBack => 'Réécouter';

  @override
  String get bubbleYouDeleted => 'Vous avez supprimé ce message';

  @override
  String get bubbleMessageDeleted => 'Ce message a été supprimé';

  @override
  String get bubbleCouldNotOpen => 'Impossible d\'ouvrir';

  @override
  String get bubbleEncryptedNotice =>
      'Les messages et les appels sont chiffrés de bout en bout. Personne en dehors de cette discussion ne peut les lire ou les écouter, pas même Privio.';

  @override
  String get linkNotWebAddress => 'Ce lien n\'est pas une adresse web.';

  @override
  String get linkNothingCanOpen =>
      'Rien sur cet appareil n\'a pu ouvrir ce lien.';

  @override
  String get linkOpenTitle => 'Ouvrir ce lien ?';

  @override
  String get linkOpenBody =>
      'Cela s\'ouvre dans votre navigateur, hors de Privio. Le site voit votre connexion comme n\'importe quel site que vous visitez.';

  @override
  String timerBadgeDays(int count) {
    return '$count j';
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
  String get chatSafetyNumberChanged => 'Numéro de sécurité modifié';

  @override
  String get chatEncrypted => 'Chiffré de bout en bout';

  @override
  String get chatEncryptedVerified => 'Chiffré de bout en bout · vérifié';

  @override
  String get chatEncryptedNumberChanged =>
      'Chiffré de bout en bout · numéro modifié';

  @override
  String get chatWaitingGroupKey => 'En attente de la clé du groupe';

  @override
  String chatMembersEncrypted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '1 membre',
    );
    return '$_temp0 · chiffré';
  }

  @override
  String get chatRetrySendTitle => 'Réessayer';

  @override
  String get chatRetryFailed => 'Ce n\'est pas parti. Envoyez-le maintenant.';

  @override
  String get chatRetryQueued =>
      'En attente de réseau. Essayez quand même maintenant.';

  @override
  String get chatCopyText => 'Copier le texte';

  @override
  String get chatDeleteForMe => 'Supprimer pour moi';

  @override
  String get chatDeleteForMeNote =>
      'Disparu de cet appareil. Les autres le gardent.';

  @override
  String get chatDeleteForEveryone => 'Supprimer pour tout le monde';

  @override
  String get chatDeleteForEveryoneNote =>
      'Demande à leur application de l\'oublier. Cela ne peut pas reprendre ce qui a déjà été lu, capturé en image ou restauré depuis une sauvegarde.';

  @override
  String get chatPickerNoResponse =>
      'Le sélecteur de fichiers n\'a pas répondu.';

  @override
  String chatPickerFailed(String reason) {
    return 'Impossible d\'ouvrir le sélecteur de fichiers : $reason';
  }

  @override
  String chatCouldNotReadFile(String name) {
    return 'Impossible de lire $name.';
  }

  @override
  String chatBlockTitle(String name) {
    return 'Bloquer $name ?';
  }

  @override
  String get chatBlockBody =>
      'Leurs messages cessent d\'arriver. On ne leur dit rien, et pour eux rien ne semble avoir changé. Vous pouvez le lever dans Confidentialité et sécurité.';

  @override
  String get chatBlock => 'Bloquer';

  @override
  String chatBlocked(String name) {
    return '$name est bloqué.';
  }

  @override
  String get chatCouldNotBlock => 'Impossible de bloquer cette personne.';

  @override
  String get chatMicrophoneDenied =>
      'Privio ne peut pas enregistrer sans accès au microphone. Vous pouvez l\'accorder dans les réglages de votre appareil.';

  @override
  String get chatNoGroupLink =>
      'Pas encore de lien pour ce groupe — tirez pour actualiser.';

  @override
  String get chatInviteLink => 'Lien d\'invitation';

  @override
  String get chatInviteLinkNote =>
      'Partagez-le n\'importe où — il ne porte aucune clé. Quiconque l\'ouvre rejoint le groupe, et la clé de son nom parvient chiffrée à son appareil.';

  @override
  String get chatTyping => 'écrit…';

  @override
  String get chatVideoCall => 'Appel vidéo';

  @override
  String get chatVoiceCall => 'Appel vocal';

  @override
  String get chatMore => 'Plus';

  @override
  String get chatGroupInfo => 'Infos du groupe';

  @override
  String get chatSafetyNumber => 'Numéro de sécurité';

  @override
  String get chatActivate => 'Activer';

  @override
  String get chatSend => 'Envoyer';

  @override
  String get chatHoldToRecord =>
      'Maintenez le micro pour enregistrer un message vocal.';

  @override
  String get chatReplyingToYourself => 'Réponse à vous-même';

  @override
  String chatReplyingTo(String name) {
    return 'Réponse à $name';
  }

  @override
  String get chatReplying => 'Réponse';

  @override
  String get chatCancelReply => 'Annuler la réponse';

  @override
  String get contactsTitle => 'Contacts';

  @override
  String get contactsSearch => 'Rechercher des contacts';

  @override
  String contactsLastSeen(String username, String when) {
    return '@$username · vu $when';
  }

  @override
  String get contactsSeenJustNow => 'à l\'instant';

  @override
  String contactsSeenMinutes(int count) {
    return 'il y a $count min';
  }

  @override
  String contactsSeenAtTime(String time) {
    return 'à $time';
  }

  @override
  String contactsSeenDays(int count) {
    return 'il y a $count j';
  }

  @override
  String get contactsCouldNotAdd => 'Impossible d\'ajouter cet utilisateur';

  @override
  String get contactsAddTitle => 'Ajouter un contact';

  @override
  String get contactsAddNote =>
      'Saisissez leur nom d\'utilisateur Privio exact. Rien n\'est envoyé depuis votre carnet d\'adresses, et personne ne peut vous trouver en parcourant une liste.';

  @override
  String get contactsUsernameHint => 'nom d\'utilisateur';

  @override
  String get contactsEmptyTitle => 'Pas encore de contacts';

  @override
  String get contactsEmptyBody =>
      'Ajoutez quelqu\'un avec son nom d\'utilisateur exact, ou partagez votre lien d\'invitation depuis l\'onglet Compte.';

  @override
  String get groupCouldNotCreate => 'Impossible de créer le groupe';

  @override
  String get groupNewTitle => 'Nouveau groupe';

  @override
  String get groupCreate => 'Créer';

  @override
  String get groupName => 'Nom du groupe';

  @override
  String get groupNameEncryptedNote =>
      'Le nom est chiffré. Privio stocke un groupe qu\'il ne peut pas nommer.';

  @override
  String get groupChooseMembers => 'Choisir les membres';

  @override
  String groupSelectedCount(int count) {
    return '$count sélectionnés';
  }

  @override
  String get groupAddContactsFirst =>
      'Ajoutez d\'abord des contacts — un groupe a besoin de monde.';

  @override
  String get groupInfoCouldNotRead =>
      'Impossible de lire qui est dans ce groupe.';

  @override
  String get groupAdminOnly => 'Seul un administrateur peut le changer';

  @override
  String get groupRename => 'Renommer le groupe';

  @override
  String get groupRenameAction => 'Renommer';

  @override
  String get groupRenamed =>
      'Renommé. Tous les autres ouvrent le nouveau nom avec la clé qu\'ils ont déjà.';

  @override
  String get groupCouldNotRename => 'Impossible de renommer le groupe.';

  @override
  String groupRemoveTitle(String name) {
    return 'Retirer $name ?';
  }

  @override
  String get groupRemoveBody =>
      'Cette personne ne reçoit plus ce qui est envoyé à partir de maintenant. Ce qu\'elle a déjà reçu reste sur son appareil — rien ici ne peut l\'atteindre.';

  @override
  String get groupCouldNotRemove => 'Impossible de retirer cette personne.';

  @override
  String get groupLeaveTitle => 'Quitter ce groupe ?';

  @override
  String get groupLeaveBody =>
      'Vous ne recevez plus ce qui y est envoyé, et la conversation disparaît de cet appareil avec tout ce qu\'elle contient. Personne n\'est prévenu ; les autres vous voient disparaître de la liste des membres.';

  @override
  String get groupLeave => 'Quitter';

  @override
  String get groupLeaveRow => 'Quitter le groupe';

  @override
  String get groupDeleteTitle => 'Supprimer ce groupe ?';

  @override
  String get groupDeleteBody =>
      'Il disparaît pour tout le monde : plus personne ne peut y envoyer quoi que ce soit. Ce qui a déjà été livré reste sur les appareils qui l\'ont reçu, c\'est-à-dire chaque message que quelqu\'un a lu.';

  @override
  String get groupDeleteRow => 'Supprimer le groupe pour tout le monde';

  @override
  String get groupYouSuffix => 'Vous';

  @override
  String get groupAdminSuffix => 'Administrateur';

  @override
  String get navChats => 'Discussions';

  @override
  String get navChannels => 'Canaux';

  @override
  String get navCalls => 'Appels';

  @override
  String get navContacts => 'Contacts';

  @override
  String get navAccount => 'Compte';

  @override
  String get splashTagline => 'Messagerie sécurisée';

  @override
  String get splashPromise => 'Chiffré. Privé. À vous.';

  @override
  String get splashInitialising => 'Préparation de l\'environnement sécurisé';

  @override
  String accountPickerFailed(String reason) {
    return 'Impossible d\'ouvrir le sélecteur : $reason';
  }

  @override
  String accountCouldNotReadFile(String name, String reason) {
    return 'Impossible de lire $name : $reason';
  }

  @override
  String get accountCouldNotSetPicture => 'Impossible de définir l\'image';

  @override
  String get accountTapToAddPicture => 'Touchez pour ajouter une image';

  @override
  String get accountPictureEncrypted =>
      'Chiffrée — seuls vos contacts peuvent la voir';

  @override
  String get accountUsername => 'Nom d\'utilisateur';

  @override
  String get accountStatus => 'Statut';

  @override
  String get accountStatusDefault => 'Salut ! J’utilise Privio.';

  @override
  String get accountStatusNone => 'Non défini';

  @override
  String get accountStatusTitle => 'Statut';

  @override
  String get accountStatusHint => 'Que faites-vous ?';

  @override
  String get accountStatusEmoji => 'Émoji';

  @override
  String get accountStatusEmojiNone => 'Aucun';

  @override
  String get accountStatusClearsAfter => 'Disparaît après';

  @override
  String get accountStatusNeverClears => 'Jamais';

  @override
  String get accountStatus30Minutes => '30 minutes';

  @override
  String get accountStatus1Hour => '1 heure';

  @override
  String get accountStatus4Hours => '4 heures';

  @override
  String get accountStatusToday => 'Aujourd\'hui';

  @override
  String get accountStatus1Week => '1 semaine';

  @override
  String accountStatusUntil(String time) {
    return 'Jusqu\'à $time';
  }

  @override
  String get accountStatusCouldNotSave =>
      'Votre statut n\'a pas été enregistré. Ce que vous avez écrit est toujours là — réessayez.';

  @override
  String get accountStatusSaving => 'Enregistrement…';

  @override
  String get accountStatusExplainer =>
      'Toute personne autorisée à voir votre statut lit ceci. Il n\'est pas chiffré comme vos messages, et ce n\'est pas votre statut en ligne.';

  @override
  String get privacyProfileStatus => 'Statut';

  @override
  String get privacyProfileStatusEveryone => 'Tout le monde';

  @override
  String get privacyProfileStatusContacts => 'Mes contacts';

  @override
  String get privacyProfileStatusNobody => 'Personne';

  @override
  String get accountId => 'Identifiant du compte';

  @override
  String get accountInviteRow => 'Lien d\'invitation / code QR';

  @override
  String get accountLogOut => 'Se déconnecter';

  @override
  String get accountLogOutQuestion => 'Se déconnecter ?';

  @override
  String get accountLogOutBody =>
      'Vos messages restent chiffrés sur cet appareil jusqu’à ce que vous les supprimiez. Il vous faudra votre mot de passe pour vous reconnecter.';

  @override
  String get accountDelete => 'Supprimer le compte';

  @override
  String get accountDeleteTitle => 'Supprimer ce compte ?';

  @override
  String get accountDeleteBody =>
      'Vos appareils, vos clés, les messages encore en attente de livraison, vos contacts, vos appartenances à des groupes et votre sauvegarde sont tous supprimés sur le serveur. Tout ce qui est sur ce téléphone part avec.\n\nCela n\'atteint pas ce que d\'autres ont déjà reçu, et votre nom d\'utilisateur redevient libre pour quelqu\'un d\'autre.\n\nIl n\'y a ni annulation ni récupération — ni avec la clé de récupération, ni en écrivant à qui que ce soit.';

  @override
  String get accountYourPassword => 'Votre mot de passe';

  @override
  String get accountDeleteIt => 'Supprimer';

  @override
  String get inviteTitle => 'Inviter';

  @override
  String get inviteTabLink => 'Lien d\'invitation';

  @override
  String get inviteTabQr => 'Code QR';

  @override
  String get inviteYourLink => 'Votre lien d\'invitation';

  @override
  String get inviteCopied => 'Lien d\'invitation copié';

  @override
  String get inviteCopyLink => 'Copier le lien';

  @override
  String get inviteCopyInviteLink => 'Copier le lien d\'invitation';

  @override
  String get inviteNote =>
      'Partagez ce lien pour inviter d\'autres personnes sur Privio. Il révèle votre nom d\'utilisateur et rien d\'autre.';

  @override
  String inviteScanToConnect(String username) {
    return 'Scannez pour vous connecter avec @$username';
  }

  @override
  String get callsClearHistory => 'Effacer l\'historique des appels';

  @override
  String get callsClearTitle => 'Effacer l\'historique des appels ?';

  @override
  String get callsClearBody =>
      'Cette liste n\'existe que sur cet appareil — l\'effacer la retire d\'ici et de nulle part ailleurs, parce qu\'elle n\'a jamais été ailleurs.';

  @override
  String get callsClear => 'Effacer';

  @override
  String get callsNeverLeavesNote =>
      'Cette liste ne quitte jamais l\'appareil. Le serveur achemine l\'établissement d\'un appel comme il achemine un message — scellé et illisible pour lui — il ne conserve donc aucune trace de qui a appelé qui.';

  @override
  String callsCallSomeone(String name) {
    return 'Appeler $name';
  }

  @override
  String get callsDeclined => 'Refusé';

  @override
  String get callsNotTaken => 'Non pris';

  @override
  String get callsBusy => 'Occupé';

  @override
  String get callsCouldNotConnect => 'Connexion impossible';

  @override
  String get callsMissed => 'Manqué';

  @override
  String get callsNoAnswer => 'Pas de réponse';

  @override
  String get callsEmptyTitle => 'Pas encore d\'appels';

  @override
  String get callsEmptyBody =>
      'Lancez-en un depuis une discussion. L\'appel est établi sur la session Signal que cette discussion utilise déjà, donc les adresses que vos deux appareils échangent pour se trouver sont scellées l\'une pour l\'autre et non pour le serveur.';

  @override
  String get callCalling => 'Appel en cours…';

  @override
  String get callIncomingVideo => 'Appel vidéo entrant';

  @override
  String get callIncoming => 'Appel entrant';

  @override
  String get callConnecting => 'Connexion…';

  @override
  String get callEnded => 'Appel terminé';

  @override
  String get callDecline => 'Refuser';

  @override
  String get callAccept => 'Accepter';

  @override
  String get callMute => 'Couper le micro';

  @override
  String get callUnmute => 'Réactiver le micro';

  @override
  String get callCamera => 'Caméra';

  @override
  String get callCameraOff => 'Caméra coupée';

  @override
  String get callEnd => 'Raccrocher';

  @override
  String get callSpeaker => 'Haut-parleur';

  @override
  String get welcomePromiseEncrypted => 'Chiffré de bout en bout';

  @override
  String get welcomePromiseNoPhone => 'Aucun numéro de téléphone requis';

  @override
  String get welcomePromiseControl => 'Vous gardez le contrôle';

  @override
  String get welcomePromiseByDesign => 'Confidentialité dès la conception';

  @override
  String get welcomeTo => 'Bienvenue sur';

  @override
  String get welcomeGetStarted => 'Commencer';

  @override
  String get welcomeHaveAccount => 'J\'ai déjà un compte';

  @override
  String get welcomeImportBackup => 'Importer depuis une sauvegarde';

  @override
  String get authCreateTitle => 'Créez votre compte';

  @override
  String get authWelcomeBack => 'Content de vous revoir';

  @override
  String get authCreateNote =>
      'Choisissez un nom d\'utilisateur. Pas de numéro de téléphone, pas d\'e-mail — rien qui relie ce compte à quoi que ce soit d\'autre.';

  @override
  String get authSignInNote =>
      'Connectez-vous avec votre nom d\'utilisateur et votre mot de passe.';

  @override
  String get authUsernameRule =>
      '3 à 32 caractères : a–z, 0–9, point ou tiret bas';

  @override
  String get authPasswordRule =>
      'Au moins 10 caractères — celui-ci protège tout';

  @override
  String get authPasswordRequired => 'Saisissez votre mot de passe';

  @override
  String get authTotpHint => 'code à deux facteurs';

  @override
  String get authCreateAccount => 'Créer un compte';

  @override
  String get authSignIn => 'Se connecter';

  @override
  String get authCreateNew => 'Créer un nouveau compte';

  @override
  String get authPasswordOnlyWay =>
      'Votre mot de passe est le seul accès à ce compte. Privio ne peut pas le réinitialiser, parce que Privio ne peut rien lire de ce qu\'il déverrouillerait.';

  @override
  String get pinEnterPassphrase => 'Saisissez votre phrase secrète';

  @override
  String get pinEnterPasscode => 'Saisissez votre code';

  @override
  String get pinPassphrase => 'Phrase secrète';

  @override
  String get pinWrong => 'Ce n\'est pas ça.';

  @override
  String get pinUnlock => 'Déverrouiller';

  @override
  String get activationTitle => 'Activer Privio';

  @override
  String get activationSignedInNote =>
      'Votre compte est prêt. Ce serveur demande une clé de licence avant de relayer vos messages.';

  @override
  String get activationNewNote =>
      'Ce serveur demande une clé de licence avant de relayer des messages. Saisissez la vôtre maintenant et elle est activée dès que votre compte existe.';

  @override
  String get activationActivate => 'Activer';

  @override
  String get activationNoKeyYet => 'Je n\'ai pas encore de clé';

  @override
  String get activationWithoutKeyNote =>
      'Sans clé, vous pouvez créer un compte, vous connecter et lire ce qui arrive, mais pas envoyer. Vous pourrez la saisir plus tard dans Réglages › Licence Privio.';

  @override
  String activationFreeSoftwareNote(String name, String license) {
    return '$name est un logiciel libre sous $license. La clé ne déverrouille pas l\'application — vous l\'avez déjà en entier et pouvez la compiler vous-même. Elle paie le service hébergé qui relaie vos messages.';
  }

  @override
  String get backupCouldNotReach =>
      'Impossible de joindre Privio pour vérifier la sauvegarde.';

  @override
  String get backupDone => 'Sauvegardé. Privio ne peut pas le lire.';

  @override
  String get backupUploadFailed => 'La sauvegarde n\'a pas pu être envoyée.';

  @override
  String get backupBadKey => 'Cela ne ressemble pas à une clé de récupération.';

  @override
  String backupRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conversations restaurées.',
      one: '1 conversation restaurée.',
    );
    return '$_temp0';
  }

  @override
  String get backupKeyDidNotOpen =>
      'Cette clé n\'a pas ouvert la sauvegarde, ou il n\'y en a aucune à ouvrir.';

  @override
  String get backupLast => 'Dernière sauvegarde';

  @override
  String get backupOnServer => 'Sur le serveur';

  @override
  String get backupNothingYet => 'Rien pour le moment';

  @override
  String get backupAlways => 'Toujours';

  @override
  String get backupNow => 'Sauvegarder maintenant';

  @override
  String get backupAutomatic => 'Sauvegarde automatique';

  @override
  String get backupIntervalDaily => 'Quotidienne';

  @override
  String get backupIntervalWeekly => 'Hebdomadaire';

  @override
  String get backupRecoveryKey => 'Clé de récupération';

  @override
  String get backupRestoreRow => 'Restaurer depuis une sauvegarde';

  @override
  String get backupSealedNote =>
      'Les sauvegardes sont scellées sur cet appareil avec votre clé de récupération. Privio ne peut pas les ouvrir ni réinitialiser la clé — si vous la perdez, la sauvegarde est perdue. Notez-la en lieu sûr.\n\nUne sauvegarde contient vos conversations, pas vos clés : la restaurer sur un nouvel appareil vous rend votre historique, et cet appareil crée sa propre identité pour la suite.';

  @override
  String get backupNever => 'Jamais';

  @override
  String backupToday(String time) {
    return 'Aujourd\'hui, $time';
  }

  @override
  String get backupWriteItDown =>
      'Notez ceci. C\'est la seule chose qui ouvre vos sauvegardes, et personne — pas même Privio — ne peut la reproduire pour vous.';

  @override
  String get backupRestoreReplacesNote =>
      'Cela remplace tout ce qui est sur cet appareil par ce qui se trouve dans la sauvegarde.';

  @override
  String get backupRestore => 'Restaurer';

  @override
  String get twoFactorOnToast =>
      'L\'authentification à deux facteurs est activée. Conservez en sécurité la récupération de votre application d\'authentification.';

  @override
  String get twoFactorOffToast =>
      'L\'authentification à deux facteurs est désactivée.';

  @override
  String get twoFactorTurnOffTitle =>
      'Désactiver l\'authentification à deux facteurs';

  @override
  String get twoFactorTurnOff => 'Désactiver';

  @override
  String get twoFactorTurnOn => 'Activer';

  @override
  String get twoFactorServerNote =>
      'Le code est vérifié à la connexion, sur le serveur. Il protège le compte lui-même — quelqu\'un qui apprend votre mot de passe ne peut toujours pas connecter un nouvel appareil. Ce n\'est pas ce qui chiffre vos messages : c\'est la clé sur cet appareil, et aucun code ne peut la remplacer.';

  @override
  String get twoFactorOffBody =>
      'Avec l\'authentification à deux facteurs, la connexion demande un code à six chiffres de votre application d\'authentification en plus de votre mot de passe.';

  @override
  String get twoFactorSetUp => 'Le configurer';

  @override
  String get twoFactorScanThis => 'Scannez ceci';

  @override
  String get twoFactorScanNote =>
      'Ajoutez-le à votre application d\'authentification, puis saisissez le code qu\'elle affiche. L\'authentification à deux facteurs n\'est pas active tant que ce code n\'a pas été vérifié.';

  @override
  String get twoFactorTypeKey => 'Ou saisissez cette clé';

  @override
  String get twoFactorKeyCopied => 'Clé copiée.';

  @override
  String get twoFactorOnBody =>
      'La connexion demande un code de votre application d\'authentification.';

  @override
  String get passcodeFourDigits => '4 chiffres';

  @override
  String get passcodeSixDigits => '6 chiffres';

  @override
  String get passcodeFourDigitsNote =>
      'Dix mille combinaisons. Rapide, et suffisant contre quelqu’un qui ramasse le téléphone.';

  @override
  String get passcodeSixDigitsNote =>
      'Un million de combinaisons, et toujours un pavé numérique.';

  @override
  String get passcodePhraseNote =>
      'Des lettres, et des chiffres ou symboles si vous le souhaitez. La seule des trois qui résiste à quelqu\'un qui a le téléphone et du temps.';

  @override
  String get passcodeNeedsFourDigits => 'Quatre chiffres.';

  @override
  String get passcodeNeedsSixDigits => 'Six chiffres.';

  @override
  String passcodePhraseTooShort(int count) {
    return 'Au moins $count caractères.';
  }

  @override
  String get passcodePhraseNeedsLetter =>
      'Une phrase secrète a besoin d\'au moins une lettre. Les chiffres et symboles sont les bienvenus à côté.';

  @override
  String get lockEntriesDiffer => 'Les deux saisies ne sont pas identiques.';

  @override
  String get lockOnToast =>
      'Verrouillage de l\'application activé. Privio le demande à son retour.';

  @override
  String get lockOffToast => 'Verrouillage de l\'application désactivé.';

  @override
  String get lockTurnOffTitle =>
      'Désactiver le verrouillage de l\'application ?';

  @override
  String get lockTurnOffBody =>
      'Quiconque tient un téléphone déverrouillé atteint vos messages. Un code de contrainte défini pour l\'écran verrouillé est retiré avec lui.';

  @override
  String get lockTurnOffRow => 'Désactiver le verrouillage de l\'application';

  @override
  String get lockWhatItIsNote =>
      'Un code sur cet appareil, demandé chaque fois que Privio revient au premier plan. Ce n\'est pas le mot de passe de votre compte et il ne quitte jamais le téléphone — il garde l\'historique déjà chiffré dessus.';

  @override
  String get lockNoBiometricsNote =>
      'Il n\'y a pas d\'option visage ou empreinte. Ce sont les seules identités que quelqu\'un peut utiliser en vous mettant le téléphone devant le visage, ou en pressant votre doigt pendant votre sommeil — et dans plusieurs pays un tribunal peut les ordonner là où il ne peut pas ordonner un code.';

  @override
  String get lockChangePasscode => 'Changer le code';

  @override
  String get lockChoosePasscode => 'Choisir un code';

  @override
  String get lockAgain => 'À nouveau';

  @override
  String get lockChangeIt => 'Le changer';

  @override
  String get lockTurnItOn => 'L\'activer';

  @override
  String get lockForgettingNote =>
      'L\'oublier signifie se reconnecter, ce qui est un nouvel appareil pour le serveur : ce qui a déjà été livré ici est perdu sauf s\'il se trouve dans une sauvegarde. Il n\'y a pas de réinitialisation, parce qu\'une réinitialisation que n\'importe qui pourrait demander ne serait pas un verrou.';

  @override
  String get duressNoLockNote =>
      'Sur l\'écran verrouillé, il ne fait encore rien, parce qu\'il n\'y a pas de verrouillage de l\'application sur cet appareil. Activez-en un dans Verrouillage de l\'écran, et un code de contrainte de la même forme que ce verrou y fonctionne aussi — c\'est là qu\'on saisit un téléphone déjà connecté.';

  @override
  String duressShapeNote(String kind) {
    return 'Cet appareil se déverrouille avec $kind. Un code de contrainte de la même forme peut être saisi sur l\'écran verrouillé, où il détruit au lieu de déverrouiller. Toute autre forme ne fonctionne qu\'à la connexion.';
  }

  @override
  String get duressMatchesLock =>
      'Celui-ci correspond au verrou de cet appareil, il fonctionne donc sur l\'écran verrouillé comme à la connexion.';

  @override
  String duressDoesNotMatchLock(String kind) {
    return 'Celui-ci ne correspond pas au verrou de cet appareil ($kind), il ne fonctionne donc qu\'à la connexion — l\'écran verrouillé n\'a nulle part où le saisir.';
  }

  @override
  String get duressAtLeastFour => 'Utilisez au moins quatre caractères.';

  @override
  String get duressCodesDiffer => 'Les deux codes ne sont pas identiques.';

  @override
  String get duressSameAsUnlock =>
      'C\'est le code qui déverrouille cet appareil. Un code de contrainte doit être différent : l\'écran verrouillé le vérifie en premier, donc s\'ils étaient identiques chaque déverrouillage détruirait le compte — sans le dire.';

  @override
  String get duressSetBoth =>
      'Code de contrainte défini. Il détruit le compte à la connexion et sur l\'écran verrouillé.';

  @override
  String get duressSetSignInOnly =>
      'Code de contrainte défini. Le saisir à la connexion détruit le compte.';

  @override
  String get duressRemoved => 'Code de contrainte supprimé.';

  @override
  String get duressRemoveTitle => 'Supprimer le code de contrainte';

  @override
  String get duressWarning =>
      'Saisir ce code à la place de votre mot de passe à la connexion détruit le compte : chaque appareil, chaque message en attente, vos contacts, vos groupes, votre sauvegarde. Il n\'y a ni annulation ni confirmation — c\'est le but.';

  @override
  String get duressIsSet => 'Un code de contrainte est défini';

  @override
  String get duressCannotShow =>
      'Privio ne peut pas vous le montrer — il est stocké comme un mot de passe. En définir un nouveau ci-dessous le remplace.';

  @override
  String get duressRemoveIt => 'Le supprimer';

  @override
  String get duressReplaceIt => 'Le remplacer';

  @override
  String get duressSetOne => 'Définir un code de contrainte';

  @override
  String get duressAccountPassword => 'Le mot de passe de votre compte Privio';

  @override
  String get duressLooksLikePin =>
      'C\'est plus court qu\'un mot de passe de compte. Ce champ attend le mot de passe choisi à la création du compte — pas le code PIN qui déverrouille l\'application.';

  @override
  String get duressCodeField => 'Code de contrainte';

  @override
  String get duressCodeAgain => 'Code de contrainte à nouveau';

  @override
  String get duressReplaceCode => 'Remplacer le code';

  @override
  String get duressSetCode => 'Définir le code';

  @override
  String get duressWhatItDoesNotDo =>
      'Ce qu\'il ne fait pas : le nom du compte reste pris, personne ne peut le réclamer ensuite, et il n\'atteint pas un autre appareil déjà connecté ailleurs. Quiconque regarde voit la tentative refusée exactement comme un mot de passe ou un code mal saisi.';

  @override
  String get disguiseIntro =>
      'Un Privio verrouillé s\'ouvre sur une calculatrice qui fonctionne au lieu d\'un écran de verrouillage. Tout calcul dont le résultat est votre code ouvre Privio quand vous appuyez sur =, le code lui-même n\'a donc jamais à apparaître à l\'écran. Tout autre calcul n\'est qu\'un calcul.';

  @override
  String get disguiseOpenTo => 'Ouvrir sur';

  @override
  String get disguiseLockScreen => 'L\'écran de verrouillage';

  @override
  String disguiseCalculatorNamed(String name) {
    return 'Calculatrice $name';
  }

  @override
  String get disguisePickNote =>
      'Choisissez celle que votre téléphone propose déjà. Une calculatrice qui ne ressemble pas à l\'habituelle, c\'est ce qu\'on remarque.';

  @override
  String get disguiseSeeIt => 'La voir';

  @override
  String disguiseErrorSuffix(String reason) {
    return '$reason L\'écran de verrouillage a changé quand même ; l\'écran d\'accueil non.';
  }

  @override
  String get disguiseNoLock =>
      'Il n\'y a pas encore de verrouillage d\'écran sur cet appareil, il n\'y a donc aucun code à saisir dans une calculatrice.';

  @override
  String get disguisePhraseLock =>
      'Votre verrouillage d\'écran est une phrase secrète. Une calculatrice a dix touches et aucune lettre, il n\'y a donc aucun moyen de la saisir. Passez le verrou à 4 ou 6 chiffres pour utiliser un camouflage.';

  @override
  String get disguiseOnHomeScreen => 'Sur l\'écran d\'accueil';

  @override
  String get disguiseWhatItDoesNotDo => 'Ce que cela ne fait pas';

  @override
  String get disguiseNotADefence =>
      'Ce n\'est pas une défense contre quelqu\'un qui garde le téléphone longtemps. L\'application est toujours installée, et sa taille, ses fichiers et son trafic réseau restent trouvables par qui regarde vraiment. Ce à quoi elle est bonne, c\'est le cas ordinaire — un écran aperçu, ou un téléphone tendu déverrouillé.';

  @override
  String get disguiseHomeScreenChanges =>
      'Sur l\'écran d\'accueil et dans le tiroir d\'applications, Privio devient une icône de calculatrice nommée « Calculatrice ». Votre lanceur peut mettre quelques secondes à se redessiner, et une icône que vous avez épinglée vous-même peut devoir être réépinglée. Désactiver le camouflage la remet en place.\n\nLa liste d\'applications d\'Android elle-même — Réglages, infos de l\'application, le nom affiché quand Privio demande une permission — dit toujours Privio. Ce nom est fixé à la compilation et aucune application ne peut le changer en cours d\'exécution.';

  @override
  String get disguiseIconUnchanged =>
      'Sur cet appareil, l\'icône et le nom ne changent pas — seulement ce sur quoi l\'application s\'ouvre. Quelqu\'un qui parcourt l\'écran d\'accueil trouve toujours Privio par son nom.';

  @override
  String get disguiseClosePreview => 'Fermer l\'aperçu';

  @override
  String get licenseActivatedToast =>
      'Activée. Cette licence appartient désormais à votre compte.';

  @override
  String get licenseNotCheckedTitle => 'Pas encore vérifié';

  @override
  String get licenseNotCheckedBody =>
      'Privio n\'a pas encore pu interroger le serveur au sujet de ce compte. Remettez l\'application en ligne et rouvrez cet écran.';

  @override
  String get licenseNotNeededTitle => 'Aucune licence nécessaire ici';

  @override
  String get licenseNotNeededBody =>
      'Ce serveur n\'en exige pas. Les licences concernent le service Privio hébergé — une licence pour une infrastructure que vous exploitez déjà ne voudrait rien dire.';

  @override
  String get licenseStoreTitle => 'Géré par la boutique';

  @override
  String licenseStoreBody(String store) {
    return 'Cette version a été payée via la boutique d\'où elle vient, il n\'y a donc aucune clé à saisir. Si elle n\'est pas active, restaurez votre achat dans $store.';
  }

  @override
  String get licenseOnePurchaseNote =>
      'Un achat, une clé, un compte, pour de bon. Une clé utilisée est liée au compte qui l\'a utilisée et ne peut être ni transférée ni réutilisée.';

  @override
  String get licenseEnterTitle => 'Saisissez votre clé de licence';

  @override
  String get licenseEnterBody =>
      'Achetez une clé sur getprivio.com/license, puis saisissez-la ici. Tant qu\'elle n\'est pas activée, ce compte peut se connecter et lire ce qui est déjà arrivé, mais pas envoyer.';

  @override
  String get licenseActivated => 'Activée';

  @override
  String licenseRedeemedOn(String date) {
    return 'Utilisée le $date.';
  }

  @override
  String get licenseFromAppStore => 'Achetée via l\'App Store.';

  @override
  String get licenseFromPlay => 'Achetée via Google Play.';

  @override
  String get licenseFromKey =>
      'Activée avec une clé de licence. Accès à vie, sans renouvellement.';

  @override
  String get safetyTrustedToast =>
      'La nouvelle clé est approuvée. Comparez de nouveau le numéro avant de vous y fier.';

  @override
  String get safetyMatches => 'Cela correspond à l\'un des numéros ci-dessous.';

  @override
  String get safetyNoMatch =>
      'Cela ne correspond à aucun des numéros ci-dessous.';

  @override
  String safetyNothingYet(String name) {
    return 'Il n\'y a encore rien à comparer. Un numéro existe dès que $name et vous avez échangé un message, car c\'est seulement alors que cet appareil a fixé une de leurs clés.';
  }

  @override
  String safetyReadThese(String name) {
    return 'Lisez ces chiffres à $name — au téléphone ou en personne. Si la personne voit les mêmes, personne ne s\'est glissé entre vous. Sinon, n\'utilisez plus cette discussion pour ce que vous ne diriez pas en public.';
  }

  @override
  String get safetyMarkNotVerified => 'Marquer comme non vérifié';

  @override
  String get safetyMarkVerified => 'Marquer comme vérifié';

  @override
  String safetyMarkNote(String name) {
    return 'Marquer comme vérifié enregistre exactement les clés à l\'écran. Si l\'une d\'elles change, ou qu\'un nouvel appareil rejoint $name, la marque repasse d\'elle-même à « modifié » — c\'est un relevé de ce que vous avez vérifié, pas une promesse sur la suite.';
  }

  @override
  String get safetyVerified => 'Vérifié';

  @override
  String get safetyChangedSince => 'Modifié depuis votre vérification';

  @override
  String get safetyNotVerified => 'Non vérifié';

  @override
  String safetyTheirDevice(int index) {
    return 'Leur appareil $index';
  }

  @override
  String get safetyCompareTitle => 'Comparer un numéro qu\'on vous a envoyé';

  @override
  String get safetyCompare => 'Comparer';

  @override
  String get safetyKeyNotYours =>
      'La clé sur le serveur n\'est pas celle que vous aviez';

  @override
  String get safetyRefusedUntilDecide =>
      'Les messages vers cette discussion sont refusés jusqu\'à ce que vous décidiez. Réinstaller Privio, ou se connecter sur un nouvel appareil, fait cela légitimement et en est la raison habituelle. Un serveur qui vous remet une clé à lui aussi, et cela se voit exactement pareil d\'ici — d\'où l\'intérêt de recomparer le numéro ci-dessous ensuite.';

  @override
  String get safetyTrustNewKey => 'Faire confiance à la nouvelle clé';

  @override
  String get safetyKeyChangedArrived =>
      'Leur clé a changé, et un message est arrivé avec';

  @override
  String get safetyKeyChangedBody =>
      'La nouvelle clé est déjà en usage — un message qui en apporte une ne peut être refusé sans donner à quiconque le moyen de faire taire une discussion. Une réinstallation fait cela. Quelqu\'un qui s\'interpose aussi. Le numéro ci-dessous est la différence, et il ne vaut quelque chose que comparé à voix haute.';

  @override
  String get channelsCouldNotOpenLink => 'Impossible d\'ouvrir ce lien';

  @override
  String get channelsJoinWithLink => 'Rejoindre avec un lien';

  @override
  String get channelsNewChannel => 'Nouveau canal';

  @override
  String get channelsTabFollowing => 'Abonnements';

  @override
  String get channelsTabDiscover => 'Découvrir';

  @override
  String get channelsSearchMine => 'Rechercher dans vos canaux';

  @override
  String get channelsSearchPublic => 'Rechercher des canaux publics';

  @override
  String get channelsEmptyTitle => 'Pas encore de canaux';

  @override
  String get channelsEmptyBody =>
      'Créez-en un, ou trouvez un canal public dans Découvrir.';

  @override
  String get channelsNothingFound => 'Rien trouvé';

  @override
  String get channelsDiscoverEmptyBody =>
      'Recherchez des canaux publics par nom, identifiant ou description. Les canaux privés n’apparaissent jamais ici.';

  @override
  String channelsHandleAndMembers(String handle, String members) {
    return '@$handle  ·  $members';
  }

  @override
  String get channelsJoinTitle => 'Rejoindre un canal';

  @override
  String get channelsJoinNote =>
      'Collez un lien de canal. Il vous montre le canal ; rejoindre est un bouton là-bas. Rejoindre ne vous donne pas non plus la clé — un membre qui l\'a l\'envoie chiffrée à votre appareil juste après.';

  @override
  String get categoryNews => 'Actualités';

  @override
  String get categoryTechnology => 'Technologie';

  @override
  String get categoryCommunity => 'Communauté';

  @override
  String get categoryEducation => 'Éducation';

  @override
  String get categoryCulture => 'Culture';

  @override
  String newChannelPictureUnreadable(String name) {
    return 'Privio n\'a pas pu lire $name. Essayez une autre image.';
  }

  @override
  String get newChannelCouldNotCreate => 'Impossible de créer le canal';

  @override
  String get newChannelWithoutPicture => 'Le canal a été créé sans l\'image.';

  @override
  String get newChannelCreate => 'Créer';

  @override
  String get newChannelPublicPictureNote =>
      'L\'image d\'un canal public est affichée sur sa page web et dans les aperçus de lien, elle est donc stockée sans chiffrement — comme son nom, son identifiant et sa description.';

  @override
  String get newChannelHandle => 'Identifiant';

  @override
  String get newChannelHandleRule =>
      '3 à 32 caractères : a–z, 0–9, tiret bas ou point';

  @override
  String get newChannelCategory => 'Catégorie';

  @override
  String get newChannelRestrictSaving => 'Restreindre l\'enregistrement';

  @override
  String get newChannelRestrictNote =>
      'Demande aux applications des lecteurs de ne pas enregistrer ni transférer les publications. Une demande, pas une garantie — quiconque peut lire une publication peut la photographier.';

  @override
  String get newChannelPrivateBody =>
      'Accessible uniquement via un lien d\'invitation. Le nom est envoyé chiffré, le serveur stocke donc un canal qu\'il ne peut pas nommer.';

  @override
  String get newChannelPublicBody =>
      'Répertorié et trouvable par la recherche. Le nom, l\'identifiant et la description sont publics par définition ; les publications restent chiffrées de bout en bout.';

  @override
  String get membersCouldNotLift => 'Impossible de lever cela.';

  @override
  String get membersCouldNotChange => 'Impossible de modifier ce membre';

  @override
  String get membersTitle => 'Membres';

  @override
  String get membersWhoRuns => 'Qui gère ce canal';

  @override
  String get membersSilencedCanRead =>
      'Peut lire, ne peut ni publier ni réagir';

  @override
  String get membersAllowAgain => 'Autoriser à nouveau';

  @override
  String get membersRoleAndPermissions => 'Rôle et autorisations';

  @override
  String get membersOwnerEverything => 'Propriétaire · tout';

  @override
  String get membersSubscriberReadOnly => 'Abonné · lecture seule';

  @override
  String get membersGrantPost => 'publier';

  @override
  String get membersGrantEdit => 'modifier';

  @override
  String get membersGrantDeletePosts => 'supprimer des publications';

  @override
  String get membersGrantManageMembers => 'gérer les membres';

  @override
  String get membersGrantDeleteChannel => 'supprimer le canal';

  @override
  String membersRoleLine(String role, String granted) {
    return '$role · $granted';
  }

  @override
  String get membersSubscriber => 'Abonné';

  @override
  String get membersTogglePost => 'Publier';

  @override
  String get membersToggleEditChannel => 'Modifier le canal';

  @override
  String get membersToggleDeletePosts => 'Supprimer des publications';

  @override
  String get membersToggleManageMembers => 'Gérer les membres';

  @override
  String get membersToggleDeleteChannel => 'Supprimer le canal';

  @override
  String get membersGreyedOutNote =>
      'Les autorisations grisées sont celles que vous n\'avez pas vous-même. Personne ne peut en accorder plus qu\'il n\'en a.';

  @override
  String get membersSubscriberNote =>
      'Un abonné lit le canal et rien d\'autre.';

  @override
  String get membersRemoveFromChannel => 'Retirer du canal';

  @override
  String get membersStoppedFromPosting => 'Empêché de publier';

  @override
  String get membersAudienceNote =>
      'Seules les personnes qui gèrent ce canal sont listées. Qui le lit n\'est pas montré aux autres lecteurs — vous compris.';

  @override
  String get channelPicture => 'Image';

  @override
  String get channelLinkCopied => 'Lien copié.';

  @override
  String get adminsMakeSomebodyFirst =>
      'Nommez d\'abord quelqu\'un administrateur.';

  @override
  String get subscribersCouldNotAddAnybody =>
      'Impossible d\'ajouter qui que ce soit.';

  @override
  String subscribersAddCount(int count) {
    return 'Ajouter $count';
  }

  @override
  String get threadCouldNotPost => 'Impossible de publier ce commentaire.';

  @override
  String get threadCouldNotRemove => 'Impossible de retirer ce commentaire.';

  @override
  String threadStopTitle(String name) {
    return 'Empêcher $name de publier ?';
  }

  @override
  String get threadStopBody =>
      'Cette personne reste dans le canal et peut continuer à le lire. Elle ne peut ni commenter ni réagir tant que vous ne le défaites pas.\n\nLa retirer du canal est l\'autre chose, plus lourde : cela fait tourner la clé et lui retire aussi la lecture.';

  @override
  String get threadStopThem => 'L\'empêcher';

  @override
  String get threadStopThemPosting => 'L\'empêcher de publier';

  @override
  String get threadCouldNotDoThat => 'Impossible de faire cela.';

  @override
  String get threadTitle => 'Commentaires';

  @override
  String get threadUnknown => 'Inconnu';

  @override
  String get threadEncryptedNoKey =>
      'Chiffré — cet appareil n\'en a pas la clé.';

  @override
  String get threadCommentHint => 'Commenter';

  @override
  String get threadNoKeyForChannel => 'Aucune clé pour ce canal';

  @override
  String get threadDeletedAccount => 'Compte supprimé';

  @override
  String get threadEncryptedNoKeyHere =>
      'Chiffré — aucune clé pour cela sur cet appareil.';

  @override
  String get threadEmptyTitle => 'Pas encore de commentaires';

  @override
  String get threadEmptyBody =>
      'Les commentaires sont chiffrés avec la clé du canal, comme les publications. Le serveur les stocke et ne peut pas les lire.';

  @override
  String threadStoppedToast(String name) {
    return '$name peut toujours lire le canal, mais pas y publier.';
  }

  @override
  String get threadThem => 'Cette personne';

  @override
  String get threadThemObject => 'cette personne';

  @override
  String get feedCouldNotAskForKey => 'Impossible de demander la clé.';

  @override
  String get feedKeyArrived =>
      'La clé est arrivée. Vous pouvez de nouveau publier.';

  @override
  String get feedAskedAgain =>
      'Demandé à nouveau. La clé est livrée par un autre membre, elle arrive donc quand l\'un d\'eux est en ligne.';

  @override
  String get feedCouldNotJoin => 'Impossible de rejoindre';

  @override
  String get feedPickFutureTime =>
      'Choisissez une heure qui n\'est pas déjà passée.';

  @override
  String get feedCouldNotPublishPoll => 'Impossible de publier ce sondage.';

  @override
  String feedScheduledFor(String when) {
    return 'Programmé pour $when. Jusque-là, il est sous « Programmé ».';
  }

  @override
  String get feedCouldNotPublish => 'Impossible de publier';

  @override
  String get feedCouldNotChangeLink => 'Impossible de modifier le lien.';

  @override
  String get feedOldLinkDead =>
      'L\'ancien lien est mort. Quiconque le détient aura besoin du nouveau.';

  @override
  String get feedSaved => 'Enregistré.';

  @override
  String get feedCouldNotChangeReactions =>
      'Impossible de modifier les réactions.';

  @override
  String get feedCouldNotChangePost => 'Impossible de modifier la publication.';

  @override
  String get feedPublished => 'Publié.';

  @override
  String get feedCouldNotPublishIt => 'Impossible de le publier.';

  @override
  String get feedCouldNotChangeThat => 'Impossible de modifier cela.';

  @override
  String get feedCommentsOn =>
      'Les lecteurs peuvent désormais commenter les publications.';

  @override
  String get feedCommentsOff =>
      'Les commentaires sont désactivés. Les fils existants sont masqués, pas supprimés.';

  @override
  String get feedCouldNotReadNumbers => 'Impossible de lire les chiffres.';

  @override
  String get feedNobodyToHandTo =>
      'Il n\'y a personne d\'autre dans ce canal à qui le confier.';

  @override
  String feedOwnsNow(String name) {
    return '$name est désormais propriétaire de ce canal. Vous y êtes administrateur.';
  }

  @override
  String get feedCouldNotHandOn => 'Impossible de céder le canal.';

  @override
  String get feedReported => 'Signalé. Merci.';

  @override
  String get feedCouldNotSendThat => 'Impossible d\'envoyer cela.';

  @override
  String get feedRemovePicture => 'Retirer l\'image';

  @override
  String get feedPictureRemoved => 'Image retirée.';

  @override
  String get feedCouldNotRemovePicture => 'Impossible de retirer l\'image.';

  @override
  String get feedCouldNotSetPicture => 'Impossible de définir l\'image.';

  @override
  String get feedPictureUpdated => 'Image du canal mise à jour.';

  @override
  String get feedDeleteChannelTitle => 'Supprimer le canal ?';

  @override
  String get feedDeleteChannelBody =>
      'Le canal et toutes ses publications sont supprimés pour tout le monde. Rien ne défait cela.';

  @override
  String get feedCouldNotDeleteChannel => 'Impossible de supprimer le canal';

  @override
  String get feedCouldNotLeaveChannel => 'Impossible de quitter le canal';

  @override
  String get feedScheduled => 'Programmé';

  @override
  String get feedRequestsToJoin => 'Demandes pour rejoindre';

  @override
  String get feedChannelPicture => 'Image du canal';

  @override
  String get feedAddPicture => 'Ajouter une image';

  @override
  String get feedTurnCommentsOff => 'Désactiver les commentaires';

  @override
  String get feedTurnCommentsOn => 'Activer les commentaires';

  @override
  String get feedHandChannelOn => 'Céder ce canal';

  @override
  String get feedDeleteChannel => 'Supprimer le canal';

  @override
  String get dayToday => 'Aujourd\'hui';

  @override
  String get dayYesterday => 'Hier';

  @override
  String get feedNoSearchResultsBody =>
      'La recherche s\'exécute sur cet appareil, sur les publications qu\'il a déjà chargées et pu ouvrir. Le serveur ne peut pas les chercher : il les conserve scellées.';

  @override
  String get feedEdited => '· modifié';

  @override
  String feedCommentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commentaires',
      one: '1 commentaire',
      zero: 'Commenter',
    );
    return '$_temp0';
  }

  @override
  String get feedUnpin => 'Détacher';

  @override
  String get feedPin => 'Épingler';

  @override
  String get feedRemoveFile => 'Retirer le fichier';

  @override
  String get feedAttach => 'Joindre une image ou un fichier';

  @override
  String get feedPublishLater => 'Publier plus tard';

  @override
  String get feedAskQuestion => 'Poser une question';

  @override
  String get feedWritePost => 'Écrire une publication';

  @override
  String get feedEditPost => 'Modifier la publication';

  @override
  String get feedPost => 'Publication';

  @override
  String get feedEditUnseenNote =>
      'Personne ne l\'a encore vu, il ne sera donc pas marqué comme modifié.';

  @override
  String get feedEditSeenNote =>
      'La publication sera marquée comme modifiée. Son fichier, le cas échéant, reste tel quel.';

  @override
  String get feedWaiting => 'En attente';

  @override
  String get feedEncryptedNoKeyHere => 'Chiffré — aucune clé sur cet appareil.';

  @override
  String get feedDiscard => 'Abandonner';

  @override
  String get feedPublishNow => 'Publier maintenant';

  @override
  String get feedNothingWaiting => 'Rien en attente';

  @override
  String get feedNothingWaitingBody =>
      'Les publications que vous programmez attendent ici jusqu\'à leur heure. Personne d\'autre ne peut les voir, ni savoir qu\'elles existent.';

  @override
  String feedTodayAt(String time) {
    return 'aujourd\'hui à $time';
  }

  @override
  String feedTomorrowAt(String time) {
    return 'demain à $time';
  }

  @override
  String feedDateAt(String date, String time) {
    return '$date à $time';
  }

  @override
  String get feedReactionsNote =>
      'Ce que les lecteurs peuvent mettre sous une publication. Les réactions déjà présentes sur une publication restent, même si vous retirez l\'émoji de cette liste.';

  @override
  String feedChosenOfLimit(int chosen, int limit) {
    return '$chosen sur $limit';
  }

  @override
  String get feedPollNoKey => 'Un sondage dont cet appareil n\'a pas la clé.';

  @override
  String feedPollPickUpTo(int count) {
    return 'Choisissez jusqu\'à $count';
  }

  @override
  String get feedPollPickOne => 'Choisissez-en une';

  @override
  String feedPollCloses(String when) {
    return 'se termine $when';
  }

  @override
  String feedPollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votants',
      one: '1 votant',
    );
    return '$_temp0';
  }

  @override
  String get feedPollClearAnswer => 'Effacer ma réponse';

  @override
  String get feedPollAnswer => 'Répondre';

  @override
  String get feedPollQuestion => 'Question';

  @override
  String feedPollAnswerN(int index) {
    return 'Réponse $index';
  }

  @override
  String get feedPollAddAnswer => 'Ajouter une réponse';

  @override
  String get feedPollSeveral => 'Plusieurs réponses';

  @override
  String get feedPollNote =>
      'La question et les réponses sont chiffrées avec la clé du canal, comme une publication. Le serveur compte les votes sans jamais apprendre ce qu\'ils disent.';

  @override
  String get feedPollAsk => 'Demander';

  @override
  String get feedCouldNotOpenFile => 'Impossible d\'ouvrir ce fichier.';

  @override
  String get feedOpened => 'Ouvert';

  @override
  String get statsPosts => 'Publications';

  @override
  String get statsWaitingToPublish => 'En attente de publication';

  @override
  String get statsPeopleWhoVoted => 'Personnes qui ont voté';

  @override
  String get statsWaitingToJoin => 'En attente d\'entrée';

  @override
  String get statsNoViewCountNote =>
      'Il n\'y a pas de compteur de vues, et c\'est une décision, pas une lacune. Compter qui a lu une publication — sans compter personne deux fois — signifie garder une ligne pour chaque lecteur de chaque publication, ce qui est un relevé de ce que chacun a lu. Tout ce qui précède est compté à partir de quelque chose que quelqu\'un a choisi de faire.';

  @override
  String get feedPollClosed => 'terminé';

  @override
  String get inviteNever => 'Jamais';

  @override
  String inviteExpires(String when) {
    return 'expire $when';
  }

  @override
  String requestsAsked(String when) {
    return 'Demandé $when';
  }

  @override
  String get inviteAskMeFirst => 'Me demander d\'abord';

  @override
  String get inviteAskMeFirstNote =>
      'Les personnes qui suivent le lien attendent votre approbation au lieu d\'entrer directement. Elles n\'ont aucune clé tant que vous ne les laissez pas entrer.';

  @override
  String get inviteExpiresLabel => 'Expire';

  @override
  String get invitePickATime => 'Choisir une heure';

  @override
  String get inviteHowMany => 'Combien peuvent le rejoindre avec';

  @override
  String get inviteNoLimit => 'Sans limite';

  @override
  String inviteJoinedSoFar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ont rejoint via ce lien jusqu\'ici.',
      one: '1 personne a rejoint via ce lien jusqu\'ici.',
    );
    return '$_temp0 L\'ouvrir et repartir ne compte pas.';
  }

  @override
  String get inviteReplaceLink => 'Remplacer le lien';

  @override
  String get inviteReplaceNote =>
      'Remplacer, c\'est ainsi qu\'on révoque un lien : l\'ancien cesse de fonctionner aussitôt, partout. Aucun lien à moitié fonctionnel ne subsiste.';

  @override
  String get inviteReplaceTitle => 'Remplacer le lien ?';

  @override
  String get inviteReplaceBody =>
      'Le lien que vous avez partagé cesse de fonctionner immédiatement — dans les messages, sur les affiches, partout où il a été collé. Personne qui le détient ne peut rejoindre.\n\nLes personnes déjà dans le canal y restent. Il n\'y a aucun moyen de récupérer l\'ancien lien.';

  @override
  String get inviteReplaceIt => 'Le remplacer';

  @override
  String get inviteExpired =>
      'Ce lien a expiré — personne ne peut le rejoindre avec.';

  @override
  String get inviteUsedUp => 'Ce lien est épuisé.';

  @override
  String get inviteNeedsApproval => 'Rejoindre nécessite votre approbation';

  @override
  String get inviteOpenJoin => 'Quiconque le possède rejoint directement';

  @override
  String inviteUsedOf(int used, int max) {
    return '$used sur $max utilisés';
  }

  @override
  String get inviteShareNote =>
      'Partagez-le n\'importe où — il ne porte aucune clé. Quiconque l\'ouvre rejoint le canal, et la clé pour le lire est ensuite envoyée à son appareil, chiffrée, par quelqu\'un qui l\'a déjà.';

  @override
  String get requestsNobodyWaiting => 'Personne en attente';

  @override
  String get requestsNobodyWaitingBody =>
      'Les personnes qui suivent le lien d\'invitation apparaissent ici tant que le lien est réglé pour vous demander d\'abord.';

  @override
  String get requestsNo => 'Non';

  @override
  String get requestsLetIn => 'Laisser entrer';

  @override
  String get feedSettings => 'Réglages';

  @override
  String feedKeyRotating(int epoch) {
    return 'Quelqu\'un a quitté ce canal, il change donc de clé (version $epoch). Les publications d\'avant restent lisibles. Les nouvelles s\'ouvriront quand la nouvelle clé atteindra cet appareil.';
  }

  @override
  String get feedWaitingForKey =>
      'En attente de la clé. Elle est envoyée à cet appareil, chiffrée, par quelqu\'un déjà dans le canal — le serveur ne la détient jamais.';

  @override
  String get feedJoinNote =>
      'Rejoindre vous donne les publications. La clé qui les ouvre est ensuite envoyée à votre appareil par un membre, jamais par le serveur.';

  @override
  String get feedJoinChannel => 'Rejoindre le canal';

  @override
  String get feedNoPostsYet => 'Pas encore de publications';

  @override
  String get feedPickNewOwnerNote =>
      'Seulement quelqu\'un déjà dans le canal. Le confier à un inconnu le mettrait à la tête d\'une clé qu\'il ne détient pas.';

  @override
  String feedTransferTitle(String name) {
    return 'Donner le canal à $name ?';
  }

  @override
  String get feedTransferBody =>
      'Cette personne en deviendra propriétaire. Vous restez administrateur avec tout ce que vous avez aujourd\'hui sauf le droit de supprimer le canal — et elle peut vous retirer ensuite.\n\nVous ne pouvez pas défaire cela vous-même. C\'est pourquoi votre mot de passe est demandé plutôt que de se fier à un téléphone déverrouillé.';

  @override
  String get feedYourPrivioPassword => 'Votre mot de passe Privio';

  @override
  String get feedHandItOn => 'Le céder';

  @override
  String get feedReportTitle => 'Signaler ce canal';

  @override
  String get feedReportPublicNote =>
      'Le signalement transmet ce canal et le motif que vous choisissez. Celui qui exploite le serveur peut voir le nom et la description d\'un canal public, car c\'est ainsi qu\'on le recherche — mais pas ses publications, qui sont chiffrées.';

  @override
  String get feedReportPrivateNote =>
      'Le signalement transmet ce canal et le motif que vous choisissez, et rien d\'autre. Son nom et ses publications sont chiffrés, celui qui exploite le serveur ne peut donc pas les lire. C\'est la limite honnête de ce que fait le signalement d\'un canal privé.';

  @override
  String get feedReportNoMessageNote =>
      'Il n\'y a délibérément pas de champ de message : ce serait le seul endroit de Privio où quelqu\'un collerait la chose chiffrée qu\'il signale dans un champ que le serveur peut lire.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportAbuse => 'Abus ou harcèlement';

  @override
  String get reportIllegal => 'Contenu illégal';

  @override
  String get reportImpersonation => 'Usurpation d\'identité';

  @override
  String get reportOther => 'Autre chose';

  @override
  String get feedReactionLimit => 'Réactions';

  @override
  String get failureUnreachable => 'Impossible de joindre Privio.';

  @override
  String get failureUnreachableCheckConnection =>
      'Impossible de joindre Privio. Vérifiez votre connexion.';

  @override
  String get failureUnreachableTryAgain =>
      'Impossible de joindre Privio. Vérifiez votre connexion et réessayez.';

  @override
  String get failureCouldNotSave =>
      'Impossible d\'enregistrer. Vérifiez votre connexion.';

  @override
  String get failureChangeNotSaved =>
      'Impossible de joindre Privio. La modification n\'a pas été enregistrée.';

  @override
  String get failureRateLimited => 'Trop de requêtes. Patientez un instant.';

  @override
  String get failureTooManyAttempts =>
      'Trop de tentatives. Patientez quelques minutes.';

  @override
  String get failureLicenseRequired =>
      'Activez votre licence pour envoyer des messages.';

  @override
  String get failureIdentityChanged =>
      'Le numéro de sécurité a changé. Rien n\'a été envoyé — vérifiez-le avant.';

  @override
  String get failureCouldNotSendMessage => 'Impossible d\'envoyer le message';

  @override
  String get failureCouldNotSendFile => 'Impossible d\'envoyer le fichier';

  @override
  String get failureCouldNotReadMessage => 'Impossible de lire un message';

  @override
  String failureMessagesUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages n\'ont pas pu être lus',
      one: 'Un message n\'a pas pu être lu',
    );
    return '$_temp0';
  }

  @override
  String get failureCouldNotOpenFile => 'Impossible d\'ouvrir ce fichier.';

  @override
  String get failureNotAnImage =>
      'Ce fichier n\'est pas une image utilisable par Privio.';

  @override
  String get failureCouldNotSetPicture => 'Impossible de définir l\'image';

  @override
  String get failureDeletedHereOnly =>
      'Supprimé ici. La demande de suppression à distance n\'est pas partie.';

  @override
  String get failureCouldNotCreateGroup => 'Impossible de créer le groupe';

  @override
  String get failureNotAGroupLink =>
      'Cela ne ressemble pas à un lien de groupe Privio.';

  @override
  String get failureGroupNotFound =>
      'Ce groupe n\'existe pas, ou le lien est incorrect.';

  @override
  String get failureGroupKeyMissing =>
      'Cet appareil n\'a pas encore la clé du groupe.';

  @override
  String get failureNotAChannelLink =>
      'Cela ne ressemble pas à un lien de canal Privio.';

  @override
  String get failureHandleTaken => 'Cet identifiant est déjà utilisé.';

  @override
  String get failureChannelNotFound =>
      'Ce canal n\'existe pas, ou le lien est incorrect.';

  @override
  String get failureNotAMember => 'Vous n\'êtes pas dans ce canal.';

  @override
  String get failureInsufficientPermission =>
      'Vous n\'avez pas l\'autorisation de faire cela.';

  @override
  String get failureCannotChangeOwnRole =>
      'Vous ne pouvez pas modifier votre propre rôle.';

  @override
  String get failureOwnerIsFixed =>
      'Le propriétaire du canal ne peut être ni modifié ni retiré.';

  @override
  String get failureTargetOutranksYou =>
      'Ce membre détient des autorisations que vous n\'avez pas.';

  @override
  String get failureCannotGrantWhatYouLack =>
      'Vous ne pouvez pas accorder une autorisation que vous n\'avez pas vous-même.';

  @override
  String get failureOwnerCannotLeave =>
      'Transférez le canal ou supprimez-le à la place.';

  @override
  String get failureUsernameTaken => 'Ce nom d\'utilisateur est déjà pris.';

  @override
  String get failureInvalidCredentials =>
      'Nom d\'utilisateur ou mot de passe incorrect.';

  @override
  String get failureTotpRequired => 'Saisissez votre code à deux facteurs.';

  @override
  String get failureInvalidTwoFactorCode =>
      'Ce code à deux facteurs n\'est pas correct.';

  @override
  String get failureTooManyDevices =>
      'Ce compte a déjà atteint le nombre maximal d\'appareils.';

  @override
  String failureCheckUsernameAndPassword(String detail) {
    return 'Vérifiez le nom d\'utilisateur et le mot de passe : $detail';
  }

  @override
  String get failureInvalidTotp =>
      'Ce code n\'est pas correct. Vérifiez l\'heure de votre téléphone et réessayez.';

  @override
  String get failureTotpAlreadyEnabled =>
      'La double authentification est déjà activée pour ce compte.';

  @override
  String get failureTotpNotSetUp =>
      'Recommencez la configuration — le secret n\'existe plus.';

  @override
  String get failureInvalidPassword => 'Ce mot de passe n\'est pas correct.';

  @override
  String get failureDuressMatchesPassword =>
      'Le code de contrainte doit être différent de votre mot de passe, sinon une connexion ordinaire détruirait le compte.';

  @override
  String get failureDeviceNotFound => 'Cet appareil est déjà déconnecté.';

  @override
  String get failureCouldNotLiftBlock => 'Impossible de lever ce blocage.';

  @override
  String failureLicenseKeyIncomplete(String format) {
    return 'Cette clé est incomplète. Elle ressemble à $format.';
  }

  @override
  String get failureNotALicenseKey =>
      'Cela ne ressemble pas à une clé de licence Privio.';

  @override
  String get failureLicenseNotFound =>
      'Aucune licence ne correspond à cette clé. Vérifiez-la et réessayez.';

  @override
  String get failureLicenseAlreadyRedeemed =>
      'Cette clé a déjà été utilisée par un autre compte. Une clé ne peut être utilisée qu\'une seule fois.';

  @override
  String get failureLicenseRevoked =>
      'Cette licence a été révoquée. Contactez le support si vous l\'avez payée.';

  @override
  String get failureAccountAlreadyLicensed =>
      'Ce compte a déjà une licence ; la clé saisie n\'a donc pas été utilisée.';

  @override
  String get failureNoPlayServices =>
      'Ce téléphone n\'a pas les services Google Play, Privio ne peut donc pas être réveillé lorsqu\'il est fermé. Les messages arrivent tant que Privio est ouvert.';

  @override
  String get failureNoApnsToken =>
      'iOS n\'a pas émis de jeton push pour Privio, il ne peut donc pas être réveillé lorsqu\'il est fermé. Les messages arrivent tant que Privio est ouvert.';

  @override
  String get failureNoPushService =>
      'Aucun service push n\'a répondu. Les messages arrivent tant que Privio est ouvert.';

  @override
  String get failureNoDistributor =>
      'Aucun distributeur UnifiedPush n\'a répondu. Installez-en un — ntfy, par exemple — et réessayez.';

  @override
  String get failureDistributorUnreachable =>
      'Privio ne peut pas joindre ce distributeur. Ce doit être une adresse https accessible sur Internet.';

  @override
  String get failureChannelKeyAwaitingGeneration =>
      'Ce canal change de clé après le départ d\'un membre. Vous pourrez publier à nouveau dès qu\'une personne qui gère le canal ouvrira Privio.';

  @override
  String get failureChannelKeyPending =>
      'En attente de la nouvelle clé du canal sur cet appareil. Votre publication n\'est pas perdue — réessayez dans un instant.';

  @override
  String get failureUnexpected =>
      'Quelque chose n\'a pas fonctionné comme prévu. Réessayez.';

  @override
  String get failureCallDevicesUnavailable =>
      'Privio n\'a pas pu ouvrir la caméra ou le microphone.';

  @override
  String get failureCallMicrophoneUnavailable =>
      'Privio n\'a pas pu ouvrir le microphone.';

  @override
  String get failureCallNotOpen => 'L\'appel n\'était pas ouvert.';

  @override
  String get deepLinkChannelGone =>
      'Ce lien ne mène plus à aucun canal. Demandez-en un nouveau à la personne qui vous l\'a envoyé.';

  @override
  String get chatsPreviewDeleted => 'Message supprimé';

  @override
  String get chatsPreviewPhoto => 'Photo';

  @override
  String get chatsPreviewVideo => 'Vidéo';

  @override
  String get chatsPreviewVoice => 'Message vocal';

  @override
  String get chatsPreviewFile => 'Fichier';

  @override
  String get notificationsPermissionDenied =>
      'Les notifications sont désactivées pour Privio dans les réglages du système. Les messages arrivent toujours tant que Privio est ouvert — mais vous n\'en serez pas informé, et un appel ne sonnera pas.';

  @override
  String get notificationsPermissionNotAsked =>
      'Privio n\'a pas encore l\'autorisation de vous notifier.';

  @override
  String get failureCallMediaNotEncrypted =>
      'L\'appel a été interrompu : l\'autre partie a demandé une connexion que Privio ne peut pas chiffrer. Privio ne bascule jamais sur un appel non chiffré.';

  @override
  String get failureCallFarEndNotBound =>
      'L\'appel a été interrompu : rien dans la négociation ne prouvait qui se trouvait à l\'autre bout. Privio ne connecte pas un appel qu\'il ne peut pas rattacher à une clé.';

  @override
  String get failureCallCertificateChanged =>
      'L\'appel a été interrompu : l\'autre bout a changé en cours de négociation. Un appel a un seul autre bout, celui-ci en avait deux.';

  @override
  String failureCallIdentityChanged(String who) {
    return 'L\'appel a été interrompu : le numéro de sécurité de $who n\'est pas celui que Privio avait. Comparez-le avec cette personne par un autre canal avant de rappeler.';
  }

  @override
  String get failureCallWrongParty =>
      'L\'appel a été interrompu : un message le concernant provenait de quelqu\'un qui n\'y participe pas.';

  @override
  String failureCallNotVerified(String who) {
    return 'L\'appel a été interrompu : vous n\'acceptez que les appels de personnes dont vous avez confirmé le numéro de sécurité, et celui de $who ne l\'est pas sur cet appareil.';
  }

  @override
  String get callEncrypted => 'Chiffré de bout en bout';

  @override
  String get callEncryptedVerified => 'Chiffré de bout en bout · vérifié';

  @override
  String get securityVerifiedCallsOnly =>
      'Uniquement les appels de contacts vérifiés';

  @override
  String get securityVerifiedCallsOnlyBody =>
      'Chaque appel est chiffré de bout en bout dans tous les cas. Avec cette option, Privio refuse en plus un appel tant que vous n\'avez pas comparé le numéro de sécurité avec cette personne et ne l\'avez pas confirmé — une clé que cet appareil a simplement rencontrée en premier ne suffit alors pas. Les appels de toute autre personne se terminent avec une explication, des deux côtés.';

  @override
  String get privacyCalls => 'Appels';

  @override
  String get appearanceAccentColour => 'Couleur d\'accent';

  @override
  String get appearanceAccentNote =>
      'Cela change l\'apparence de Privio sur cet appareil, pour ce compte. Personne à qui vous écrivez ne le voit, et vos autres comptes gardent la leur. Le rouge, pour supprimer et raccrocher, reste rouge quel que soit l\'accent choisi.';

  @override
  String get accentGreen => 'Vert';

  @override
  String get accentBlue => 'Bleu';

  @override
  String get accentTeal => 'Turquoise';

  @override
  String get accentPurple => 'Violet';

  @override
  String get accentPink => 'Rose';

  @override
  String get accentRed => 'Rouge';

  @override
  String get accentOrange => 'Orange';

  @override
  String get accentYellow => 'Jaune';

  @override
  String get accentPrivioDefault => 'Par défaut de Privio';

  @override
  String get appearanceAccentReset => 'Rétablir la valeur par défaut';

  @override
  String get appearanceAccentPreview => 'Aperçu';

  @override
  String get appearancePreviewSend => 'Envoyer';

  @override
  String get appearancePreviewSetting => 'Accusés de lecture';

  @override
  String get appearancePreviewMessage =>
      'Voilà à quoi ressembleront vos propres messages.';

  @override
  String accentSelected(String colour) {
    return '$colour, sélectionné';
  }

  @override
  String get appearanceAppIcon => 'Icône de l\'app';

  @override
  String get appearanceAppIconNote =>
      'C\'est l\'icône sur votre écran d\'accueil, et elle appartient à ce téléphone plutôt qu\'à votre compte : se connecter avec un autre compte ne la change pas. Elle reste telle que vous l\'avez réglée même si vous choisissez ensuite une autre couleur d\'accent.';

  @override
  String get appearanceAppIconMatchAccent =>
      'Utiliser la couleur d\'accent actuelle';

  @override
  String get appearanceAppIconReset => 'Rétablir l\'icône d\'origine';

  @override
  String get appearanceAppIconSlow =>
      'L\'écran d\'accueil peut mettre quelques secondes à se redessiner. Cette attente appartient au lanceur, pas à Privio.';

  @override
  String get appearanceAppIconUnavailable =>
      'Cet appareil ne peut pas changer l\'icône de l\'app, Privio ne le propose donc pas.';

  @override
  String get appearanceAppIconOriginal => 'Originale';

  @override
  String get failureAppIconUnsupported =>
      'L\'icône de l\'app n\'a pas pu être changée : cet appareil ne le propose pas.';

  @override
  String get failureAppIconHiddenByDisguise =>
      'Tant que le camouflage est activé, l\'écran d\'accueil affiche la calculatrice : la couleur de l\'icône n\'a donc pas été changée. Désactivez d\'abord le camouflage.';

  @override
  String appIconSelected(String colour) {
    return 'Icône en $colour, sélectionnée';
  }

  @override
  String appIconChoose(String colour) {
    return 'Icône en $colour';
  }
}
