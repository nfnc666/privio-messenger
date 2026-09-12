// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppTextEs extends AppText {
  AppTextEs([String locale = 'es']) : super(locale);

  @override
  String get languageName => 'Idioma';

  @override
  String get languagePickerTitle => 'Idioma';

  @override
  String get languagePickerNote =>
      'La interfaz cambia al instante. Los mensajes, los nombres de canal y todo lo demás que haya escrito una persona se quedan en el idioma en que se escribieron.';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonRemove => 'Quitar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonSearch => 'Buscar';

  @override
  String get commonEdit => 'Editar';

  @override
  String get commonAdd => 'Añadir';

  @override
  String get commonBack => 'Atrás';

  @override
  String get commonNext => 'Siguiente';

  @override
  String get commonSkip => 'Omitir';

  @override
  String get commonContinue => 'Continuar';

  @override
  String get commonYes => 'Sí';

  @override
  String get commonNo => 'No';

  @override
  String get commonOk => 'De acuerdo';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonCopied => 'Copiado.';

  @override
  String get commonShare => 'Compartir';

  @override
  String get commonLoading => 'Cargando…';

  @override
  String get commonSomethingWentWrong => 'Algo ha salido mal.';

  @override
  String get commonNotNow => 'Ahora no';

  @override
  String get commonOn => 'Activado';

  @override
  String get commonOff => 'Desactivado';

  @override
  String get commonDefault => 'Predeterminado';

  @override
  String get commonCustom => 'Personalizado';

  @override
  String get commonUnavailable => 'No disponible';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsAccount => 'Cuenta';

  @override
  String get settingsPrivacy => 'Privacidad';

  @override
  String get settingsSecurity => 'Seguridad';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsNotifications => 'Notificaciones';

  @override
  String get settingsStorage => 'Almacenamiento';

  @override
  String get settingsAbout => 'Acerca de PRIVIO';

  @override
  String get settingsSupport => 'Soporte';

  @override
  String get settingsSignOut => 'Cerrar sesión';

  @override
  String get disappearingTitle => 'Mensajes temporales';

  @override
  String get disappearingExplainer =>
      'Los mensajes nuevos se eliminan automáticamente pasado este tiempo. La cuenta atrás empieza al enviar el mensaje.';

  @override
  String get disappearingCoversChat =>
      'Incluye texto, fotos, archivos y mensajes de voz, y se aplica solo a este chat. Los mensajes ya enviados no se ven afectados, y ambos recibís aviso cuando cambia.';

  @override
  String get disappearingCoversGroup =>
      'Incluye texto, fotos, archivos y mensajes de voz, y se aplica solo a este grupo. Los mensajes ya enviados no se ven afectados, todo el mundo recibe aviso cuando cambia, y solo un administrador puede cambiarlo.';

  @override
  String get disappearingScreenshotCaveat =>
      'No puede deshacer una captura de pantalla, una foto ya guardada ni nada anotado en otro sitio.';

  @override
  String get disappearingOff => 'Desactivado';

  @override
  String get disappearing30Seconds => '30 segundos';

  @override
  String get disappearing1Minute => '1 minuto';

  @override
  String get disappearing5Minutes => '5 minutos';

  @override
  String get disappearing1Hour => '1 hora';

  @override
  String get disappearing24Hours => '24 horas';

  @override
  String get disappearing7Days => '7 días';

  @override
  String get disappearingAdminOnly =>
      'Solo un administrador puede cambiar esto';

  @override
  String noticeTimerSetBy(String who, String duration) {
    return '$who ha puesto los mensajes temporales en $duration';
  }

  @override
  String noticeTimerOffBy(String who) {
    return '$who ha desactivado los mensajes temporales';
  }

  @override
  String get noticeYou => 'Tú';

  @override
  String get noticeThey => 'La otra persona';

  @override
  String get noticeSomeone => 'Alguien';

  @override
  String noticeMessageDeletedBy(String who) {
    return '$who ha eliminado un mensaje';
  }

  @override
  String noticeSafetyNumberChanged(String who) {
    return 'Tu número de seguridad con $who ha cambiado';
  }

  @override
  String noticeUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes',
      one: 'Un mensaje',
    );
    return '$_temp0 no se ha podido leer. Estaba sellado con una clave que este dispositivo ya no tiene.';
  }

  @override
  String noticeUnreadableFrom(int count, String who) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes',
      one: 'Un mensaje',
    );
    return '$_temp0 de $who no se ha podido leer. Estaba sellado con una clave que este dispositivo ya no tiene.';
  }

  @override
  String durationSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segundos',
      one: '1 segundo',
    );
    return '$_temp0';
  }

  @override
  String durationMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutos',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String durationHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String durationDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String durationWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count semanas',
      one: '1 semana',
    );
    return '$_temp0';
  }

  @override
  String channelSubscribers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suscriptores',
      one: '1 suscriptor',
    );
    return '$_temp0';
  }

  @override
  String channelMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '1 miembro',
    );
    return '$_temp0';
  }

  @override
  String get channelPublic => 'Público';

  @override
  String get channelPrivate => 'Privado';

  @override
  String get channelAdministrators => 'Administradores';

  @override
  String get channelSubscribersRow => 'Suscriptores';

  @override
  String get channelSettings => 'Ajustes del canal';

  @override
  String get channelShareLink => 'Compartir enlace';

  @override
  String get channelDescription => 'Descripción';

  @override
  String get channelMedia => 'Multimedia';

  @override
  String get channelLinks => 'Enlaces';

  @override
  String get channelNoMedia => 'Todavía no hay imágenes';

  @override
  String get channelNoLinks => 'Todavía no hay enlaces';

  @override
  String get channelNoPosts => 'Todavía no hay publicaciones';

  @override
  String get channelActionLivestream => 'directo';

  @override
  String get channelActionMute => 'silenciar';

  @override
  String get channelActionUnmute => 'reactivar';

  @override
  String get channelActionSearch => 'buscar';

  @override
  String get channelActionMore => 'más';

  @override
  String get channelMuteTitle => 'Silenciar este canal';

  @override
  String get channelMuteNote =>
      'Se queda silenciado en todos los dispositivos en los que tengas la sesión iniciada: silenciarlo aquí no es «hasta que coja el portátil».';

  @override
  String get channelMuteForHour => 'Durante 1 hora';

  @override
  String get channelMuteForEightHours => 'Durante 8 horas';

  @override
  String get channelMuteForTwoDays => 'Durante 2 días';

  @override
  String get channelMuteUntilOff => 'Hasta que lo reactive';

  @override
  String get channelCopyLink => 'Copiar enlace';

  @override
  String get channelQrCode => 'Código QR';

  @override
  String get channelInviteSettings => 'Ajustes de invitación';

  @override
  String get channelStatistics => 'Estadísticas';

  @override
  String get channelReport => 'Denunciar canal';

  @override
  String get channelLeave => 'Salir del canal';

  @override
  String get channelLeaveTitle => '¿Salir de este canal?';

  @override
  String get channelLeaveBody =>
      'Dejas de recibir sus publicaciones. El canal pasa a una clave nueva, así que nada de lo que se publique a partir de ahora te resultará legible.';

  @override
  String get channelStay => 'Quedarme';

  @override
  String get channelNoLinkToShare =>
      'Este canal no tiene ningún enlace que compartir.';

  @override
  String get channelInfo => 'Información del canal';

  @override
  String get adminsTitle => 'Administradores';

  @override
  String get adminsSectionHeader => 'ADMINISTRADORES DEL CANAL';

  @override
  String get adminsAdd => 'Añadir administrador';

  @override
  String get adminsSearch => 'Buscar administradores';

  @override
  String get adminsRoleOwner => 'Propietario';

  @override
  String get adminsRoleAdmin => 'Administrador';

  @override
  String adminsPromotedBy(String who) {
    return 'nombrado por $who';
  }

  @override
  String get adminsHelpOwner =>
      'Los administradores te ayudan a llevar tu canal.';

  @override
  String get adminsHelpMember =>
      'Los administradores ayudan a llevar este canal. Solo quien pueda nombrar administradores puede cambiar esta lista.';

  @override
  String get adminsNobodyYet => 'Todavía nadie.';

  @override
  String get adminsShowSenderName => 'Mostrar el nombre de quien publica';

  @override
  String get adminsShowSenderNameOn =>
      'Las publicaciones nuevas llevan el nombre de quien las escribe';

  @override
  String get adminsShowSenderNameLocked =>
      'Solo un administrador que pueda editar el canal puede cambiar esto';

  @override
  String get adminsShowSenderNameNote =>
      'Con esto desactivado, todo lo que publica el canal lo publica el canal: no se adjunta ningún nombre de administrador y quien lee ve una sola voz.';

  @override
  String get adminsTransfer => 'Transferir la propiedad';

  @override
  String get adminsTransferNote => 'Pide tu contraseña y no se puede deshacer';

  @override
  String get adminsEverybodyAlready =>
      'Todo el mundo en este canal ya es administrador.';

  @override
  String get adminsWhoShouldBe => '¿Quién debería ser administrador?';

  @override
  String get adminsDismiss => 'Retirar como administrador';

  @override
  String get adminsAppoint => 'Nombrar';

  @override
  String get adminsOwnerFixed =>
      'El propietario tiene todos los permisos, y eso no se puede editar: ni aquí ni en el servidor.';

  @override
  String get adminsOutranksYou =>
      'Tiene permisos que tú no tienes, así que no puedes cambiar lo que le está permitido hacer.';

  @override
  String get adminsOnlyWhatYouHold =>
      'Solo puedes conceder lo que tú mismo tienes. Lo que no tengas aparece desactivado y no se puede activar.';

  @override
  String get adminsYouDoNotHold => 'Tú no tienes este permiso';

  @override
  String get adminsCouldNotChange => 'No se ha podido cambiar.';

  @override
  String get permissionEditChannel => 'Editar el canal';

  @override
  String get permissionEditChannelDetail =>
      'Nombre, imagen, descripción y ajustes';

  @override
  String get permissionPost => 'Publicar';

  @override
  String get permissionPostDetail => 'Y editar o programar lo suyo';

  @override
  String get permissionDeletePosts => 'Eliminar publicaciones';

  @override
  String get permissionDeletePostsDetail => 'También las de otras personas';

  @override
  String get permissionModerate => 'Moderar la conversación';

  @override
  String get permissionModerateDetail =>
      'Quitar comentarios y silenciar a personas';

  @override
  String get permissionManageMembers => 'Gestionar suscriptores';

  @override
  String get permissionManageMembersDetail => 'Añadir, quitar y silenciar';

  @override
  String get permissionManageInvites => 'Gestionar invitaciones';

  @override
  String get permissionManageInvitesDetail =>
      'El enlace, sus límites y quién está esperando';

  @override
  String get permissionManageLivestreams => 'Gestionar directos';

  @override
  String get permissionManageLivestreamsDetail => 'Iniciarlos y terminarlos';

  @override
  String get permissionAppointAdmins => 'Nombrar administradores';

  @override
  String get permissionAppointAdminsDetail =>
      'Ceder esta autoridad a otra persona';

  @override
  String get subscribersTitle => 'Suscriptores';

  @override
  String get subscribersAdd => 'Añadir suscriptores';

  @override
  String get subscribersSearch => 'Buscar suscriptores';

  @override
  String get subscribersAdminsOnlyNote =>
      'Solo los administradores del canal ven esta lista.';

  @override
  String get subscribersPartialNote =>
      'Esta no es la lista completa. Solo los administradores del canal pueden ver quién está suscrito; lo que ves aquí son las personas que lo llevan, y tú.';

  @override
  String get subscribersCompleteNote => 'Todo el mundo en este canal.';

  @override
  String get subscribersContactsSection => 'CONTACTOS EN ESTE CANAL';

  @override
  String get subscribersOthersSection => 'OTROS SUSCRIPTORES';

  @override
  String get subscribersOnlySection => 'SUSCRIPTORES';

  @override
  String get subscribersNobodyFound => 'No se ha encontrado a nadie.';

  @override
  String get subscribersNoContacts => 'Todavía no hay contactos que añadir.';

  @override
  String get subscribersEverybodyHere => 'Todos tus contactos ya están aquí.';

  @override
  String get subscribersAddedOne => 'Añadido.';

  @override
  String subscribersAddedMany(int count) {
    return 'Se han añadido $count personas.';
  }

  @override
  String get subscribersNobodyAdded => 'No se ha podido añadir a nadie';

  @override
  String subscribersAddedCount(int count) {
    return 'Añadidos: $count';
  }

  @override
  String subscribersNeedInvite(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas han configurado su cuenta',
      one: '1 persona ha configurado su cuenta',
    );
    return '$_temp0 para que solo sus propios contactos puedan añadirla a cosas. Mándale el enlace y deja que decida.';
  }

  @override
  String get subscribersCopyTheLink => 'Copiar el enlace';

  @override
  String get subscribersOwnerCannotBeRemoved =>
      'Al propietario no se le puede quitar.';

  @override
  String get subscribersSilenced => 'Silenciado';

  @override
  String get subscribersSilence => 'Silenciar';

  @override
  String get subscribersSilenceDetail =>
      'Sigue suscrito y deja de poder comentar';

  @override
  String get subscribersUnsilence => 'Dejar que vuelva a hablar';

  @override
  String get subscribersUnsilenceDetail => 'Puede volver a comentar';

  @override
  String get subscribersRemoveFromChannel => 'Quitar del canal';

  @override
  String get subscribersRemoveDetail =>
      'El canal pasa a una clave nueva, así que no podrá leer lo que venga después';

  @override
  String get subscribersCouldNotDoThat => 'No se ha podido hacer.';

  @override
  String get presenceOnline => 'en línea';

  @override
  String presenceMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutos',
      one: '1 minuto',
    );
    return 'visto por última vez hace $_temp0';
  }

  @override
  String presenceHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count horas',
      one: '1 hora',
    );
    return 'visto por última vez hace $_temp0';
  }

  @override
  String presenceDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return 'visto por última vez hace $_temp0';
  }

  @override
  String presenceOnDate(String date) {
    return 'visto por última vez el $date';
  }

  @override
  String get editChannelName => 'Nombre del canal';

  @override
  String get editChannelDescriptionHint => 'Descripción';

  @override
  String get editChannelChangePicture => 'Cambiar la imagen';

  @override
  String get editChannelChoosePicture => 'Elegir una imagen';

  @override
  String get editChannelRemovePicture => 'Quitarla';

  @override
  String get editChannelPrivateNameNote =>
      'Este canal es privado, así que su nombre está cifrado con la clave del canal. Cambiarlo vuelve a sellarlo para cada miembro.';

  @override
  String get editChannelType => 'Tipo de canal';

  @override
  String get editChannelDiscussion => 'Conversación';

  @override
  String get editChannelReactions => 'Reacciones';

  @override
  String editChannelReactionsValue(int count) {
    return '$count emojis';
  }

  @override
  String get editChannelWelcome => 'Mensaje de bienvenida';

  @override
  String get editChannelAppearance => 'Apariencia';

  @override
  String get editChannelAutoTranslate => 'Traducción automática';

  @override
  String get editChannelDirectMessages => 'Mensajes directos';

  @override
  String get editChannelNeedsName => 'Un canal necesita un nombre.';

  @override
  String get editChannelDiscardTitle => '¿Descartar los cambios?';

  @override
  String get editChannelDiscardBody =>
      'Todavía no se ha guardado nada de esto.';

  @override
  String get editChannelKeepEditing => 'Seguir editando';

  @override
  String get editChannelDiscard => 'Descartar';

  @override
  String get editChannelCouldNotSave => 'No se han podido guardar los cambios.';

  @override
  String get editChannelCouldNotUsePicture =>
      'No se ha podido usar esa imagen.';

  @override
  String get editChannelPublicPictureTitle => 'Esta imagen será pública';

  @override
  String get editChannelPublicPictureBody =>
      'La imagen de un canal público se muestra en su página web y en las vistas previas de enlace, así que se guarda sin cifrar, igual que su nombre, su alias y su descripción. Las publicaciones siguen cifradas de extremo a extremo.';

  @override
  String get editChannelUseIt => 'Usarla';

  @override
  String get editChannelSignatureNote =>
      'Las publicaciones firmadas muestran el nombre de quien las escribe. Con esto desactivado, todo lo que publica el canal lo publica el canal.';

  @override
  String get livestreamNotSetUpTitle => 'Los directos no están configurados';

  @override
  String get livestreamNotSetUpBody =>
      'Un directo necesita un servidor multimedia: una persona envía vídeo y todas las demás lo reciben, y eso no se puede hacer de dispositivo a dispositivo como en una llamada.\n\nEste servidor de PRIVIO no tiene ninguno configurado, así que todavía no hay nada a lo que unirse. Quien lo administre puede configurarlo.';

  @override
  String get livestreamYouAreLive => 'Estás en directo';

  @override
  String get livestreamRunning => 'Hay un directo en marcha';

  @override
  String get livestreamPublisherBody =>
      'La sala está abierta y tu dispositivo tiene un token para publicar en ella. PRIVIO todavía no transporta el vídeo (lo hace el servidor multimedia), así que desde esta pantalla no se está enviando nada.\n\nTermínalo cuando acabes.';

  @override
  String get livestreamViewerBody =>
      'Hay un directo en marcha y este dispositivo tiene un token para verlo. PRIVIO todavía no puede mostrar el vídeo.';

  @override
  String get livestreamEndIt => 'Terminarlo';

  @override
  String get livestreamNobodyStreaming => 'Ahora mismo no hay nadie emitiendo.';

  @override
  String get livestreamCouldNotStart => 'No se ha podido iniciar el directo.';

  @override
  String get translationNotSetUpTitle =>
      'La traducción automática no está configurada';

  @override
  String get translationNotSetUpBody =>
      'Traducir una publicación significa enviar lo que dice a un servicio de traducción. El servidor de PRIVIO no puede hacerlo, porque guarda texto cifrado y no tiene la clave, así que tendría que ocurrir en tu dispositivo y el texto saldría de él en claro.\n\nEsa es una decisión que tiene que habilitar quien administre este servidor y aceptar cada persona que lee, así que está desactivada hasta que ocurran ambas cosas. No se ha enviado ninguna publicación a ningún sitio.';

  @override
  String get visibilityPublicTitle => 'Este canal es público';

  @override
  String get visibilityPrivateTitle => 'Este canal es privado';

  @override
  String visibilityPublicBody(String handle) {
    return 'Cualquiera puede encontrarlo por su nombre y leer sus publicaciones. Su alias es @$handle.\n\nPRIVIO no puede hacer privado un canal público a posteriori: su nombre y su descripción han sido legibles, y desdecir eso no es algo que una aplicación pueda hacer.';
  }

  @override
  String get visibilityPrivateBody =>
      'No aparece en listados, no se puede buscar y solo se llega a él por su enlace de invitación. Su nombre está cifrado con la clave del canal.\n\nHacerlo público publicaría ese nombre, y esa no es una decisión que PRIVIO tome por ti: crea un canal público en su lugar.';

  @override
  String get discussionBody =>
      'Con esto activado, cada publicación tiene un hilo debajo. Los comentarios se sellan con la misma clave de canal que la publicación, así que un dispositivo que no pueda leer la publicación no puede leer el hilo.\n\nDesactivarlo más adelante oculta los hilos en vez de eliminarlos.';

  @override
  String get discussionTurnOn => 'Activar';

  @override
  String get discussionTurnOff => 'Desactivar';

  @override
  String get welcomeShowToNew => 'Mostrarlo a los nuevos suscriptores';

  @override
  String get welcomeHint => 'Se muestra una vez, al unirse';

  @override
  String get welcomePrivateNote =>
      'Este canal es privado, así que el mensaje está cifrado con la clave del canal, igual que su nombre.';

  @override
  String get appearanceNote =>
      'Un conjunto fijo en vez de un selector de color: cada combinación se ha comprobado en contraste, para que un canal no pueda elegir algo que quien lo lee no pueda leer.';

  @override
  String get appearancePreviewPost => 'Una publicación en este canal';

  @override
  String get appearancePreviewLink => 'y un enlace dentro';

  @override
  String get appearanceAccent => 'Color de acento';

  @override
  String get appearanceBackground => 'Fondo';

  @override
  String get appearanceUseDefault => 'Usar el predeterminado';

  @override
  String get composerHint => 'Escribe un mensaje…';

  @override
  String get composerAttach => 'Adjuntar un archivo';

  @override
  String get composerTimerOff => 'Los mensajes temporales están desactivados';

  @override
  String composerTimerOn(String badge) {
    return 'Los mensajes desaparecen tras $badge';
  }

  @override
  String get searchPostsHint => 'Buscar en las publicaciones que puedes leer';

  @override
  String get searchThisChannel => 'Buscar en este canal';

  @override
  String get searchClose => 'Cerrar la búsqueda';

  @override
  String get searchNoResults => 'Nada coincide';
}
