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
  String get settingsAccount => 'Compte';

  @override
  String get settingsPrivacy => 'Confidentialité';

  @override
  String get settingsSecurity => 'Sécurité';

  @override
  String get settingsAppearance => 'Apparence';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsStorage => 'Stockage';

  @override
  String get settingsAbout => 'À propos de PRIVIO';

  @override
  String get settingsSupport => 'Assistance';

  @override
  String get settingsSignOut => 'Se déconnecter';

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
}
