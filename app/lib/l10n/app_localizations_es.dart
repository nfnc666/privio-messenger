// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppTextEs extends AppText {
  AppTextEs([String locale = 'es']) : super(locale);

  @override
  String get proxyTitle => 'Proxy SOCKS5';

  @override
  String get proxyEnable => 'Usar proxy';

  @override
  String get proxyHost => 'Servidor (nombre o IP)';

  @override
  String get proxyPort => 'Puerto';

  @override
  String get proxyUsername => 'Usuario (opcional)';

  @override
  String get proxyPassword => 'Contraseña (opcional)';

  @override
  String get proxyScope =>
      'Para este dispositivo: acceso, mensajes, archivos y copias. Las llamadas se desactivan con el proxy. Sin conexión directa automática. Guarda los cambios.';

  @override
  String get proxyPrivacy =>
      'Las notificaciones del sistema y los enlaces abiertos en el navegador no usan este proxy. SOCKS5 no cifra las credenciales del proxy; utiliza una red y un proxy de confianza. El proxy ve tu IP y el destino; HTTPS sigue cifrado. No admite proxys MTProto de Telegram.';

  @override
  String get proxyTest => 'Probar conexión';

  @override
  String get proxySave => 'Guardar';

  @override
  String get proxyRemove => 'Eliminar proxy y conectar directamente';

  @override
  String get proxyInvalid =>
      'Introduce un servidor válido y un puerto (1–65535). Completa usuario y contraseña o deja ambos vacíos.';

  @override
  String get proxyTestSuccess =>
      'Privio es accesible mediante este proxy. Los ajustes aún no se han guardado.';

  @override
  String get proxySaved => 'Ajustes de red guardados.';

  @override
  String get proxyFailed =>
      'No se pudo completar. Revisa el proxy, las credenciales y la conexión, y finaliza las llamadas. Sin conexión directa automática.';

  @override
  String get proxyCallsBlocked =>
      'Las llamadas no están disponibles con el proxy activo.';

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
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsNotifications => 'Notificaciones';

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

  @override
  String get settingsPrivacy => 'Privacidad y seguridad';

  @override
  String get settingsStorage => 'Datos y almacenamiento';

  @override
  String get settingsAbout => 'Acerca de Privio';

  @override
  String get settingsDevices => 'Dispositivos';

  @override
  String get settingsBackup => 'Copia de seguridad';

  @override
  String get settingsDisguise => 'Modo camuflaje';

  @override
  String get settingsLicense => 'Licencia de Privio';

  @override
  String get settingsLicenseNotActive => 'No activa';

  @override
  String get appearanceTextSize => 'Tamaño del texto';

  @override
  String get appearanceTextSizeNote =>
      'Este es un ajuste propio de Privio y se aplica en toda la aplicación. No anula el tamaño que tu teléfono tiene puesto para todo lo demás: ese sigue aplicándose por debajo.';

  @override
  String get appearanceDarkOnly =>
      'Privio solo tiene tema oscuro. El diseño está hecho para eso, el negro puro no cuesta nada en los paneles OLED que llevan la mayoría de los teléfonos, y un tema claro que solo existe a medias no merece un interruptor que finja lo contrario.';

  @override
  String get textSizeSmall => 'Pequeño';

  @override
  String get textSizeMedium => 'Mediano';

  @override
  String get textSizeLarge => 'Grande';

  @override
  String get textSizeLarger => 'Más grande';

  @override
  String get notificationsPushNote =>
      'Una notificación push no lleva contenido, solo un aviso para despertar. El mensaje se descarga y se descifra en este dispositivo, así que nadie en medio ve quién te ha escrito, ni siquiera quien gestiona el servicio que lo ha despertado.';

  @override
  String get notificationsPhoneNote =>
      'El sonido, la vibración, la luz y si aparece algo en la pantalla de bloqueo pertenecen a los ajustes que tu teléfono tiene para Privio, no a esta pantalla.';

  @override
  String get notificationsDelivery => 'Entrega';

  @override
  String notificationsDistributorFound(String app) {
    return 'Una aplicación distribuidora en este teléfono mantiene una sola conexión para todas las aplicaciones que la usan y reenvía un aviso sin contenido. $app no necesita ningún servicio de Google para ello, y puedes ejecutar el distribuidor tú mismo.';
  }

  @override
  String get notificationsNoDistributor =>
      'No se ha encontrado ningún distribuidor. Instala uno —ntfy, por ejemplo— para que te despierte mientras Privio está cerrado. Sin él, los mensajes llegan mientras la aplicación está abierta.';

  @override
  String get privacyWhoCanSee => 'Quién puede ver';

  @override
  String get privacyLastSeen => 'Última vez';

  @override
  String get privacyLastSeenEveryone => 'Todos';

  @override
  String get privacyLastSeenContacts => 'Mis contactos';

  @override
  String get privacyLastSeenNobody => 'Nadie';

  @override
  String get privacyMessaging => 'Mensajes';

  @override
  String get privacyReadReceipts => 'Confirmaciones de lectura';

  @override
  String get privacyTypingIndicators => 'Indicador de escritura';

  @override
  String get privacyDisappearing => 'Mensajes temporales';

  @override
  String get privacyPerChat => 'Por chat';

  @override
  String get privacyAccess => 'Acceso';

  @override
  String get privacyScreenLock => 'Bloqueo de pantalla';

  @override
  String get privacyPin => 'PIN';

  @override
  String get privacyTwoFactor => 'Autenticación en dos pasos';

  @override
  String get privacyDuressCode => 'Código de coacción';

  @override
  String get privacyScreenShield => 'Protección de pantalla';

  @override
  String get privacyScreenShieldAndroid =>
      'Bloquea las capturas y las grabaciones de pantalla de la aplicación.';

  @override
  String get privacyScreenShieldIos =>
      'Oculta el contenido sensible cuando se detecta una grabación o una transmisión de pantalla. En iOS las capturas de pantalla no se pueden impedir de forma fiable.';

  @override
  String get privacyScreenShieldUnavailable =>
      'Este dispositivo no puede proteger la pantalla.';

  @override
  String get privacyScreenShieldScope =>
      'Esto solo protege tu propio dispositivo. No impide que otras personas graben su pantalla ni que alguien haga una foto con otra cámara.';

  @override
  String get privacyScreenShieldCovering =>
      'Hay una grabación de pantalla en curso. Privio permanece oculto hasta que termine.';

  @override
  String get privacySet => 'Definido';

  @override
  String get privacyBlockedUsers => 'Usuarios bloqueados';

  @override
  String get privacyMutualNote =>
      'Las confirmaciones de lectura y el indicador de escritura son mutuos: si los desactivas, tampoco verás los de los demás.';

  @override
  String get storageOnThisDevice => 'En este dispositivo';

  @override
  String get storageHistory => 'Historial de conversaciones';

  @override
  String get storageInIt => 'Contenido';

  @override
  String storageChatsAndMessages(int chats, int messages) {
    String _temp0 = intl.Intl.pluralLogic(
      chats,
      locale: localeName,
      other: '$chats chats',
      one: '1 chat',
    );
    String _temp1 = intl.Intl.pluralLogic(
      messages,
      locale: localeName,
      other: '$messages mensajes',
      one: '1 mensaje',
    );
    return '$_temp0, $_temp1';
  }

  @override
  String get storageKeys => 'Claves y sesiones';

  @override
  String get storageKeystoreNote =>
      'Ambos están en el almacén de claves de la plataforma —el Llavero en iOS, almacenamiento respaldado por Keystore en Android— y el historial se sella con AES-256-GCM antes de llegar ahí. Ninguno de los dos puede leerlo otra aplicación, ni nadie que tenga el teléfono sin desbloquearlo.';

  @override
  String get storageNotKept => 'No se guarda';

  @override
  String get storageFilesOpened => 'Archivos que has abierto';

  @override
  String get storageMemoryOnly => 'Solo en memoria';

  @override
  String get storageVoiceRecordings => 'Grabaciones de voz';

  @override
  String get storageShredded => 'Se destruyen al enviarlas';

  @override
  String get storageEphemeralNote =>
      'Una foto o un archivo que abras se descifra en memoria y desaparece cuando se cierra la aplicación; nada lo escribe en el disco. Un mensaje de voz se graba en un archivo temporal, porque el micrófono tiene que escribir en algún sitio, y ese archivo se sobrescribe con bytes aleatorios y se borra en cuanto termina la grabación: un archivo borrado en memoria flash no es un archivo desaparecido.';

  @override
  String get storageDelete => 'Eliminar';

  @override
  String get storageDeleteHistory =>
      'Eliminar el historial de este dispositivo';

  @override
  String get storageDeleteNote =>
      'Esta es la única eliminación que ocurre aquí. Lo que guarda el servidor —una copia de seguridad, un adjunto aún dentro de sus treinta días— está en la pantalla de copia de seguridad, y lo que tiene la persona a la que escribiste es suyo.';

  @override
  String get storageConfirmTitle =>
      '¿Eliminar el historial de este dispositivo?';

  @override
  String get storageConfirmBody =>
      'Desaparecen todos los mensajes de este teléfono, en todos los chats. Tu cuenta, tus claves y tus conversaciones se quedan: la gente sigue pudiendo escribirte, y lo que envíes después sigue llegando.\n\nNo alcanza su copia, ni una copia de seguridad que ya esté en el servidor. Elimínala desde la pantalla de copia de seguridad si también quieres que desaparezca.';

  @override
  String get storageDeleteIt => 'Eliminarlo';

  @override
  String get storageDeleted =>
      'El historial de este dispositivo ha desaparecido.';

  @override
  String get devicesThisDevice => 'Este dispositivo';

  @override
  String get devicesOthers => 'Otros dispositivos';

  @override
  String get devicesOthersTapToSignOut =>
      'Otros dispositivos: toca para cerrar la sesión';

  @override
  String get devicesNone => 'Ninguno';

  @override
  String get devicesOnlyThisOne => 'Solo este';

  @override
  String get devicesSignedIn => 'Sesión iniciada';

  @override
  String get devicesActiveNow => 'Activo ahora';

  @override
  String devicesActiveMinutes(int count) {
    return 'Activo hace $count min';
  }

  @override
  String devicesActiveHours(int count) {
    return 'Activo hace $count h';
  }

  @override
  String get devicesActiveYesterday => 'Activo ayer';

  @override
  String devicesActiveDays(int count) {
    return 'Activo hace $count días';
  }

  @override
  String get devicesSignOutNote =>
      'Cerrar la sesión de un dispositivo revoca su sesión y elimina todo lo que siga en cola para él. Solo puede volver iniciando sesión de nuevo, como dispositivo nuevo y con claves nuevas.';

  @override
  String devicesRevokeTitle(String name) {
    return '¿Cerrar la sesión de $name?';
  }

  @override
  String get devicesRevokeBody =>
      'Su sesión se revoca y se elimina todo lo que siga en cola para él. Lo que ya haya descifrado se queda en ese dispositivo: desde aquí no se puede alcanzar. Solo puede volver iniciando sesión de nuevo.';

  @override
  String get devicesSignItOut => 'Cerrar su sesión';

  @override
  String devicesSignedOut(String name) {
    return 'Se ha cerrado la sesión de $name.';
  }

  @override
  String devicesLicenseCovers(int limit) {
    return 'Tu licencia cubre $limit dispositivos.';
  }

  @override
  String devicesLicenseCoversUsed(int limit, int used) {
    return 'Tu licencia cubre $limit dispositivos. $used en uso.';
  }

  @override
  String get aboutTagline =>
      'Creado pensando en la privacidad.\nSin rastreo. Sin anuncios. Solo tú.';

  @override
  String get aboutWebsite => 'Sitio web';

  @override
  String get aboutSupport => 'Soporte';

  @override
  String get aboutAddress => 'Dirección';

  @override
  String get aboutOpenSource => 'Código abierto';

  @override
  String get aboutEdition => 'Edición';

  @override
  String aboutFreeSoftware(String name) {
    return '$name · software libre';
  }

  @override
  String get aboutLicense => 'Licencia';

  @override
  String get aboutSourceCode => 'Código fuente';

  @override
  String get aboutCopyLink => 'Copiar enlace';

  @override
  String get aboutSourceLink => 'Enlace al código';

  @override
  String get aboutThirdParty => 'Licencias de terceros';

  @override
  String aboutCopied(String what) {
    return '$what: copiado.';
  }

  @override
  String get aboutFreeBuildNote =>
      'Esta compilación no contiene código propietario y puede reproducirse a partir del código fuente de arriba. Nada de esto hay que creerlo: compílalo tú y compara.';

  @override
  String get aboutStoreBuildNote =>
      'Esta compilación viene de una tienda de aplicaciones y enlaza sus servicios. La compilación Libre, en el código fuente de arriba, no incluye ninguno.';

  @override
  String get blockedUnblock => 'Desbloquear';

  @override
  String blockedUnblockTitle(String name) {
    return '¿Desbloquear a $name?';
  }

  @override
  String get blockedUnblockBody => 'Podrá volver a enviarte mensajes.';

  @override
  String get blockedInvisibleNote =>
      'El bloqueo es invisible: sus mensajes se descartan y no se les dice nada, así que un bloqueo no sirve para averiguar que se ha sido bloqueado.';

  @override
  String get blockedNobody => 'No hay nadie bloqueado';

  @override
  String get blockedEmptyNote =>
      'Bloquea a alguien desde su chat y aparecerá aquí.';

  @override
  String get chatsSectionChats => 'Chats';

  @override
  String get chatsSectionMessages => 'Mensajes';

  @override
  String get chatsYouPrefix => 'Tú: ';

  @override
  String get chatsNoSearchResults =>
      'Aquí no coincide nada. Solo se ha preguntado a este dispositivo: el servidor guarda mensajes que no puede leer, así que no habría podido responder.';

  @override
  String get chatsFilterAll => 'Todos';

  @override
  String get chatsJoin => 'Unirse';

  @override
  String get chatsFilterUnread => 'No leídos';

  @override
  String get chatsFilterGroups => 'Grupos';

  @override
  String get chatsPin => 'Fijar arriba';

  @override
  String get chatsUnpin => 'Dejar de fijar';

  @override
  String get chatsPinNote => 'Solo en este dispositivo. No se envía nada.';

  @override
  String get chatsGroupFallbackName => 'Grupo';

  @override
  String get chatsNewGroupTooltip => 'Grupo nuevo';

  @override
  String get chatsNewChatTooltip => 'Chat nuevo';

  @override
  String get chatsEmptyTitle => 'Todavía no hay chats';

  @override
  String get chatsEmptyBody =>
      'Añade a alguien con su nombre de usuario exacto para empezar a hablar.';

  @override
  String get chatsAddContact => 'Añadir un contacto';

  @override
  String get commonGotIt => 'Entendido';

  @override
  String get commonPause => 'Pausa';

  @override
  String get commonPlay => 'Reproducir';

  @override
  String get commonOpen => 'Abrir';

  @override
  String get commonReply => 'Responder';

  @override
  String get commonFile => 'Archivo';

  @override
  String get scrubRemoved => 'Metadatos eliminados';

  @override
  String get scrubNothingToRemove => 'Nada que eliminar';

  @override
  String get scrubCouldNotClean => 'No se ha podido limpiar';

  @override
  String get scrubRemovedBody =>
      'Esto se ha quitado antes de cifrar y enviar el archivo. Quien lo recibe nunca lo obtiene.';

  @override
  String get scrubNothingBody =>
      'Este archivo no llevaba metadatos identificativos desde el principio.';

  @override
  String scrubNoCleanerBody(String type) {
    return 'Privio todavía no tiene un limpiador para $type, así que el archivo se ha enviado tal cual. Sigue cifrado de extremo a extremo, pero los metadatos que contenga llegan a quien lo recibe.';
  }

  @override
  String get webStorageShort =>
      'En un navegador, el historial de este dispositivo es tan privado como este perfil del navegador. Los mensajes en tránsito están cifrados en cualquier caso.';

  @override
  String get webStorageLong =>
      'Estás usando Privio en un navegador. Los mensajes siguen cifrados de extremo a extremo en tránsito, pero un navegador no tiene almacén de claves, así que el historial guardado en este dispositivo es tan privado como este perfil del navegador. Cualquiera que pueda leerlo —un ordenador compartido, una extensión, una copia del perfil— puede leer tus chats. Las aplicaciones para teléfono no tienen este problema.';

  @override
  String get voiceCouldNotOpen => 'No se ha podido abrir esta grabación.';

  @override
  String get voiceCannotPlay =>
      'Este dispositivo no puede reproducir esa grabación.';

  @override
  String get voiceMicUnavailable =>
      'El micrófono no está disponible ahora mismo.';

  @override
  String get voiceCouldNotSave => 'No se ha podido guardar esa grabación.';

  @override
  String get voiceSlideToCancel => 'Desliza para cancelar';

  @override
  String get voiceResume => 'Reanudar';

  @override
  String get voiceStop => 'Detener';

  @override
  String get voiceDeleteRecording => 'Eliminar la grabación';

  @override
  String get voiceListenBack => 'Escucharla';

  @override
  String get bubbleYouDeleted => 'Has eliminado este mensaje';

  @override
  String get bubbleMessageDeleted => 'Este mensaje se ha eliminado';

  @override
  String get bubbleCouldNotOpen => 'No se ha podido abrir';

  @override
  String get bubbleEncryptedNotice =>
      'Los mensajes y las llamadas están cifrados de extremo a extremo. Nadie fuera de este chat puede leerlos ni escucharlos, ni siquiera Privio.';

  @override
  String get linkNotWebAddress => 'Ese enlace no es una dirección web.';

  @override
  String get linkNothingCanOpen =>
      'Nada en este dispositivo ha podido abrir ese enlace.';

  @override
  String get linkOpenTitle => '¿Abrir este enlace?';

  @override
  String get linkOpenBody =>
      'Esto se abre en tu navegador, fuera de Privio. El sitio ve tu conexión igual que cualquier sitio que visites.';

  @override
  String timerBadgeDays(int count) {
    return '$count d';
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
  String get chatSafetyNumberChanged => 'El número de seguridad ha cambiado';

  @override
  String get chatEncrypted => 'Cifrado de extremo a extremo';

  @override
  String get chatEncryptedVerified =>
      'Cifrado de extremo a extremo · verificado';

  @override
  String get chatEncryptedNumberChanged =>
      'Cifrado de extremo a extremo · número cambiado';

  @override
  String get chatWaitingGroupKey => 'Esperando la clave del grupo';

  @override
  String chatMembersEncrypted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count miembros',
      one: '1 miembro',
    );
    return '$_temp0 · cifrado';
  }

  @override
  String get chatRetrySendTitle => 'Reintentar';

  @override
  String get chatRetryFailed => 'No ha salido. Envíalo ahora.';

  @override
  String get chatRetryQueued =>
      'Esperando a una red. Inténtalo ahora igualmente.';

  @override
  String get chatCopyText => 'Copiar el texto';

  @override
  String get chatDeleteForMe => 'Eliminar para mí';

  @override
  String get chatDeleteForMeNote =>
      'Desaparece de este dispositivo. Los demás la conservan.';

  @override
  String get chatDeleteForEveryone => 'Eliminar para todos';

  @override
  String get chatDeleteForEveryoneNote =>
      'Pide a su aplicación que lo olvide. No puede recuperar lo que ya se leyó, se capturó o se restauró de una copia de seguridad.';

  @override
  String get chatPickerNoResponse =>
      'El selector de archivos no ha respondido.';

  @override
  String chatPickerFailed(String reason) {
    return 'No se ha podido abrir el selector de archivos: $reason';
  }

  @override
  String chatCouldNotReadFile(String name) {
    return 'No se ha podido leer $name.';
  }

  @override
  String chatBlockTitle(String name) {
    return '¿Bloquear a $name?';
  }

  @override
  String get chatBlockBody =>
      'Sus mensajes dejan de llegar. No se les avisa, y para ellos parece que nada ha cambiado. Puedes deshacerlo en Privacidad y seguridad.';

  @override
  String get chatBlock => 'Bloquear';

  @override
  String chatBlocked(String name) {
    return '$name está bloqueado.';
  }

  @override
  String get chatCouldNotBlock => 'No se ha podido bloquear.';

  @override
  String get chatMicrophoneDenied =>
      'Privio no puede grabar sin acceso al micrófono. Puedes concederlo en los ajustes de tu dispositivo.';

  @override
  String get chatNoGroupLink =>
      'Todavía no hay enlace para este grupo: desliza para actualizar.';

  @override
  String get chatInviteLink => 'Enlace de invitación';

  @override
  String get chatInviteLinkNote =>
      'Compártelo donde quieras: no lleva ninguna clave. Quien lo abra entra en el grupo, y la clave de su nombre llega cifrada a su dispositivo.';

  @override
  String get chatTyping => 'escribiendo…';

  @override
  String get chatVideoCall => 'Videollamada';

  @override
  String get chatVoiceCall => 'Llamada de voz';

  @override
  String get chatMore => 'Más';

  @override
  String get chatGroupInfo => 'Información del grupo';

  @override
  String get chatSafetyNumber => 'Número de seguridad';

  @override
  String get chatActivate => 'Activar';

  @override
  String get chatSend => 'Enviar';

  @override
  String get chatHoldToRecord =>
      'Mantén pulsado el micrófono para grabar un mensaje de voz.';

  @override
  String get chatReplyingToYourself => 'Respondiéndote a ti mismo';

  @override
  String chatReplyingTo(String name) {
    return 'Respondiendo a $name';
  }

  @override
  String get chatReplying => 'Respondiendo';

  @override
  String get chatCancelReply => 'Cancelar la respuesta';

  @override
  String get contactsTitle => 'Contactos';

  @override
  String get contactsSearch => 'Buscar contactos';

  @override
  String contactsLastSeen(String username, String when) {
    return '@$username · última vez $when';
  }

  @override
  String get contactsSeenJustNow => 'ahora mismo';

  @override
  String contactsSeenMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String contactsSeenAtTime(String time) {
    return 'a las $time';
  }

  @override
  String contactsSeenDays(int count) {
    return 'hace $count d';
  }

  @override
  String get contactsCouldNotAdd => 'No se ha podido añadir a ese usuario';

  @override
  String get contactsAddTitle => 'Añadir contacto';

  @override
  String get contactsAddNote =>
      'Escribe su nombre de usuario exacto de Privio. No se sube nada de tu agenda, y nadie puede encontrarte curioseando.';

  @override
  String get contactsUsernameHint => 'nombre de usuario';

  @override
  String get contactsEmptyTitle => 'Todavía no hay contactos';

  @override
  String get contactsEmptyBody =>
      'Añade a alguien con su nombre de usuario exacto, o comparte tu enlace de invitación desde la pestaña Cuenta.';

  @override
  String get groupCouldNotCreate => 'No se ha podido crear el grupo';

  @override
  String get groupNewTitle => 'Grupo nuevo';

  @override
  String get groupCreate => 'Crear';

  @override
  String get groupName => 'Nombre del grupo';

  @override
  String get groupNameEncryptedNote =>
      'El nombre está cifrado. Privio guarda un grupo que no puede nombrar.';

  @override
  String get groupChooseMembers => 'Elegir miembros';

  @override
  String groupSelectedCount(int count) {
    return '$count seleccionados';
  }

  @override
  String get groupAddContactsFirst =>
      'Añade primero algunos contactos: un grupo necesita gente dentro.';

  @override
  String get groupInfoCouldNotRead =>
      'No se ha podido leer quién está en este grupo.';

  @override
  String get groupAdminOnly => 'Solo un administrador puede cambiarlo';

  @override
  String get groupRename => 'Cambiar el nombre del grupo';

  @override
  String get groupRenameAction => 'Cambiar el nombre';

  @override
  String get groupRenamed =>
      'Nombre cambiado. Los demás abren el nuevo nombre con la clave que ya tienen.';

  @override
  String get groupCouldNotRename =>
      'No se ha podido cambiar el nombre del grupo.';

  @override
  String groupRemoveTitle(String name) {
    return '¿Quitar a $name?';
  }

  @override
  String get groupRemoveBody =>
      'Dejan de recibir lo que se envíe a partir de ahora. Lo que ya recibieron se queda en su dispositivo: desde aquí no se puede alcanzar.';

  @override
  String get groupCouldNotRemove => 'No se ha podido quitar.';

  @override
  String get groupLeaveTitle => '¿Salir de este grupo?';

  @override
  String get groupLeaveBody =>
      'Dejas de recibir lo que se envíe ahí, y la conversación desaparece de este dispositivo con todo lo que contiene. No se avisa a nadie; los demás te ven desaparecer de la lista de miembros.';

  @override
  String get groupLeave => 'Salir';

  @override
  String get groupLeaveRow => 'Salir del grupo';

  @override
  String get groupDeleteTitle => '¿Eliminar este grupo?';

  @override
  String get groupDeleteBody =>
      'Desaparece para todos: nadie puede volver a enviar ahí. Lo que ya se entregó se queda en los dispositivos que lo recibieron, que es cada mensaje que alguien haya leído.';

  @override
  String get groupDeleteRow => 'Eliminar el grupo para todos';

  @override
  String get groupYouSuffix => 'Tú';

  @override
  String get groupAdminSuffix => 'Administrador';

  @override
  String get navChats => 'Chats';

  @override
  String get navChannels => 'Canales';

  @override
  String get navCalls => 'Llamadas';

  @override
  String get navContacts => 'Contactos';

  @override
  String get navAccount => 'Cuenta';

  @override
  String get splashTagline => 'Mensajería segura';

  @override
  String get splashPromise => 'Cifrado. Privado. Tuyo.';

  @override
  String get splashInitialising => 'Preparando el entorno seguro';

  @override
  String accountPickerFailed(String reason) {
    return 'No se ha podido abrir el selector: $reason';
  }

  @override
  String accountCouldNotReadFile(String name, String reason) {
    return 'No se ha podido leer $name: $reason';
  }

  @override
  String get accountCouldNotSetPicture => 'No se ha podido poner la imagen';

  @override
  String get accountTapToAddPicture => 'Toca para añadir una imagen';

  @override
  String get accountPictureEncrypted =>
      'Cifrada: solo tus contactos pueden verla';

  @override
  String get accountUsername => 'Nombre de usuario';

  @override
  String get accountStatus => 'Estado';

  @override
  String get accountStatusDefault => '¡Hola! Estoy usando Privio.';

  @override
  String get accountStatusNone => 'Sin definir';

  @override
  String get accountStatusTitle => 'Estado';

  @override
  String get accountStatusHint => '¿Qué estás haciendo?';

  @override
  String get accountStatusEmoji => 'Emoji';

  @override
  String get accountStatusEmojiNone => 'Ninguno';

  @override
  String get accountStatusClearsAfter => 'Se borra tras';

  @override
  String get accountStatusNeverClears => 'Nunca';

  @override
  String get accountStatus30Minutes => '30 minutos';

  @override
  String get accountStatus1Hour => '1 hora';

  @override
  String get accountStatus4Hours => '4 horas';

  @override
  String get accountStatusToday => 'Hoy';

  @override
  String get accountStatus1Week => '1 semana';

  @override
  String accountStatusUntil(String time) {
    return 'Hasta las $time';
  }

  @override
  String get accountStatusCouldNotSave =>
      'Tu estado no se guardó. Lo que escribiste sigue aquí: inténtalo de nuevo.';

  @override
  String get accountStatusSaving => 'Guardando…';

  @override
  String get accountStatusExplainer =>
      'Quien pueda ver tu estado leerá esto. No está cifrado como tus mensajes, y no es tu estado de conexión.';

  @override
  String get privacyProfileStatus => 'Estado';

  @override
  String get privacyProfileStatusEveryone => 'Todos';

  @override
  String get privacyProfileStatusContacts => 'Mis contactos';

  @override
  String get privacyProfileStatusNobody => 'Nadie';

  @override
  String get accountId => 'ID de la cuenta';

  @override
  String get accountInviteRow => 'Enlace de invitación / código QR';

  @override
  String get accountLogOut => 'Cerrar sesión';

  @override
  String get accountLogOutQuestion => '¿Cerrar sesión?';

  @override
  String get accountLogOutBody =>
      'Tus mensajes se quedan cifrados en este dispositivo hasta que los elimines. Necesitarás tu contraseña para volver a entrar.';

  @override
  String get accountDelete => 'Eliminar la cuenta';

  @override
  String get accountDeleteTitle => '¿Eliminar esta cuenta?';

  @override
  String get accountDeleteBody =>
      'Tus dispositivos, tus claves, los mensajes que aún esperan a entregarse, tus contactos, tus grupos y tu copia de seguridad se eliminan todos en el servidor. Todo lo que hay en este teléfono se va con ellos.\n\nNo alcanza lo que otras personas ya han recibido, y tu nombre de usuario queda libre para que lo tome alguien más.\n\nNo hay deshacer ni recuperación: ni con la clave de recuperación, ni escribiendo a nadie.';

  @override
  String get accountYourPassword => 'Tu contraseña';

  @override
  String get accountDeleteIt => 'Eliminarla';

  @override
  String get inviteTitle => 'Invitar';

  @override
  String get inviteTabLink => 'Enlace de invitación';

  @override
  String get inviteTabQr => 'Código QR';

  @override
  String get inviteYourLink => 'Tu enlace de invitación';

  @override
  String get inviteCopied => 'Enlace de invitación copiado';

  @override
  String get inviteCopyLink => 'Copiar el enlace';

  @override
  String get inviteCopyInviteLink => 'Copiar el enlace de invitación';

  @override
  String get inviteNote =>
      'Comparte este enlace para invitar a otras personas a Privio. Revela tu nombre de usuario y nada más.';

  @override
  String inviteScanToConnect(String username) {
    return 'Escanea para conectar con @$username';
  }

  @override
  String get callsClearHistory => 'Borrar el historial de llamadas';

  @override
  String get callsClearTitle => '¿Borrar el historial de llamadas?';

  @override
  String get callsClearBody =>
      'Esta lista solo está en este dispositivo: borrarla la quita de aquí y de ningún otro sitio, porque nunca estuvo en otro sitio.';

  @override
  String get callsClear => 'Borrar';

  @override
  String get callsNeverLeavesNote =>
      'Esta lista nunca sale del dispositivo. El servidor enruta el establecimiento de una llamada igual que un mensaje —sellado e ilegible para él—, así que no guarda ningún registro de quién llamó a quién.';

  @override
  String callsCallSomeone(String name) {
    return 'Llamar a $name';
  }

  @override
  String get callsDeclined => 'Rechazada';

  @override
  String get callsNotTaken => 'No atendida';

  @override
  String get callsBusy => 'Ocupado';

  @override
  String get callsCouldNotConnect => 'No se ha podido conectar';

  @override
  String get callsMissed => 'Perdida';

  @override
  String get callsNoAnswer => 'Sin respuesta';

  @override
  String get callsEmptyTitle => 'Todavía no hay llamadas';

  @override
  String get callsEmptyBody =>
      'Empieza una desde un chat. La llamada se establece sobre la sesión de Signal que ese chat ya usa, así que las direcciones que intercambian vuestros dos dispositivos para encontrarse están selladas entre sí y no para el servidor.';

  @override
  String get callCalling => 'Llamando…';

  @override
  String get callIncomingVideo => 'Videollamada entrante';

  @override
  String get callIncoming => 'Llamada entrante';

  @override
  String get callConnecting => 'Conectando…';

  @override
  String get callEnded => 'Llamada finalizada';

  @override
  String get callDecline => 'Rechazar';

  @override
  String get callAccept => 'Aceptar';

  @override
  String get callMute => 'Silenciar';

  @override
  String get callUnmute => 'Activar el sonido';

  @override
  String get callCamera => 'Cámara';

  @override
  String get callCameraOff => 'Cámara apagada';

  @override
  String get callEnd => 'Colgar';

  @override
  String get callSpeaker => 'Altavoz';

  @override
  String get welcomePromiseEncrypted => 'Cifrado de extremo a extremo';

  @override
  String get welcomePromiseNoPhone => 'No hace falta número de teléfono';

  @override
  String get welcomePromiseControl => 'Tú tienes el control';

  @override
  String get welcomePromiseByDesign => 'Privacidad desde el diseño';

  @override
  String get welcomeTo => 'Te damos la bienvenida a';

  @override
  String get welcomeGetStarted => 'Empezar';

  @override
  String get welcomeHaveAccount => 'Ya tengo una cuenta';

  @override
  String get welcomeImportBackup => 'Importar desde una copia de seguridad';

  @override
  String get authCreateTitle => 'Crea tu cuenta';

  @override
  String get authWelcomeBack => 'Bienvenido de nuevo';

  @override
  String get authCreateNote =>
      'Elige un nombre de usuario. Sin número de teléfono, sin correo: nada que vincule esta cuenta con nada más.';

  @override
  String get authSignInNote =>
      'Inicia sesión con tu nombre de usuario y contraseña.';

  @override
  String get authUsernameRule =>
      'De 3 a 32 caracteres: a-z, 0-9, punto o guion bajo';

  @override
  String get authPasswordRule => 'Al menos 10 caracteres: esta protege todo';

  @override
  String get authPasswordRequired => 'Escribe tu contraseña';

  @override
  String get authTotpHint => 'código de dos factores';

  @override
  String get authCreateAccount => 'Crear cuenta';

  @override
  String get authSignIn => 'Iniciar sesión';

  @override
  String get authCreateNew => 'Crear una cuenta nueva';

  @override
  String get authPasswordOnlyWay =>
      'Tu contraseña es la única forma de entrar en esta cuenta. Privio no puede restablecerla, porque Privio no puede leer nada de lo que abriría.';

  @override
  String get pinEnterPassphrase => 'Escribe tu frase de contraseña';

  @override
  String get pinEnterPasscode => 'Escribe tu código';

  @override
  String get pinPassphrase => 'Frase de contraseña';

  @override
  String get pinWrong => 'No es eso.';

  @override
  String get pinUnlock => 'Desbloquear';

  @override
  String get activationTitle => 'Activar Privio';

  @override
  String get activationSignedInNote =>
      'Tu cuenta está lista. Este servidor pide una clave de licencia antes de retransmitir tus mensajes.';

  @override
  String get activationNewNote =>
      'Este servidor pide una clave de licencia antes de retransmitir mensajes. Introduce la tuya ahora y se activará en cuanto exista tu cuenta.';

  @override
  String get activationActivate => 'Activar';

  @override
  String get activationNoKeyYet => 'Todavía no tengo una clave';

  @override
  String get activationWithoutKeyNote =>
      'Sin clave puedes crear una cuenta, iniciar sesión y leer lo que llegue, pero no enviar. Puedes introducirla más tarde en Ajustes › Licencia de Privio.';

  @override
  String activationFreeSoftwareNote(String name, String license) {
    return '$name es software libre bajo $license. La clave no desbloquea la aplicación: ya la tienes entera y puedes compilarla tú. Paga el servicio alojado que retransmite tus mensajes.';
  }

  @override
  String get backupCouldNotReach =>
      'No se ha podido contactar con Privio para comprobar la copia de seguridad.';

  @override
  String get backupDone => 'Copia hecha. Privio no puede leerla.';

  @override
  String get backupUploadFailed =>
      'No se ha podido subir la copia de seguridad.';

  @override
  String get backupBadKey => 'Eso no parece una clave de recuperación.';

  @override
  String backupRestored(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se han restaurado $count conversaciones.',
      one: 'Se ha restaurado 1 conversación.',
    );
    return '$_temp0';
  }

  @override
  String get backupKeyDidNotOpen =>
      'Esa clave no ha abierto la copia de seguridad, o no hay ninguna que abrir.';

  @override
  String get backupLast => 'Última copia de seguridad';

  @override
  String get backupOnServer => 'En el servidor';

  @override
  String get backupNothingYet => 'Todavía nada';

  @override
  String get backupAlways => 'Siempre';

  @override
  String get backupNow => 'Hacer una copia ahora';

  @override
  String get backupAutomatic => 'Copia de seguridad automática';

  @override
  String get backupIntervalDaily => 'A diario';

  @override
  String get backupIntervalWeekly => 'Semanal';

  @override
  String get backupRecoveryKey => 'Clave de recuperación';

  @override
  String get backupRestoreRow => 'Restaurar desde una copia de seguridad';

  @override
  String get backupSealedNote =>
      'Las copias de seguridad se sellan en este dispositivo con tu clave de recuperación. Privio no puede abrirlas ni restablecer la clave: si la pierdes, la copia se pierde. Apúntala en un sitio seguro.\n\nUna copia guarda tus conversaciones, no tus claves: restaurarla en un dispositivo nuevo te devuelve tu historial, y ese dispositivo crea su propia identidad para lo que venga después.';

  @override
  String get backupNever => 'Nunca';

  @override
  String backupToday(String time) {
    return 'Hoy, $time';
  }

  @override
  String get backupWriteItDown =>
      'Apunta esto. Es lo único que abre tus copias de seguridad, y nadie —tampoco Privio— puede volver a generártelo.';

  @override
  String get backupRestoreReplacesNote =>
      'Esto sustituye lo que haya en este dispositivo por lo que contenga la copia de seguridad.';

  @override
  String get backupRestore => 'Restaurar';

  @override
  String get twoFactorOnToast =>
      'La verificación en dos pasos está activada. Guarda bien la recuperación de tu aplicación de autenticación.';

  @override
  String get twoFactorOffToast =>
      'La verificación en dos pasos está desactivada.';

  @override
  String get twoFactorTurnOffTitle => 'Desactivar la verificación en dos pasos';

  @override
  String get twoFactorTurnOff => 'Desactivar';

  @override
  String get twoFactorTurnOn => 'Activar';

  @override
  String get twoFactorServerNote =>
      'El código se comprueba al iniciar sesión, en el servidor. Protege la cuenta en sí: quien averigüe tu contraseña sigue sin poder dar de alta un dispositivo nuevo. No es lo que cifra tus mensajes: eso lo hace la clave de este dispositivo, y ningún código puede sustituirla.';

  @override
  String get twoFactorOffBody =>
      'Con la verificación en dos pasos, iniciar sesión pide un código de seis dígitos de tu aplicación de autenticación además de la contraseña.';

  @override
  String get twoFactorSetUp => 'Configurarla';

  @override
  String get twoFactorScanThis => 'Escanea esto';

  @override
  String get twoFactorScanNote =>
      'Añádelo a tu aplicación de autenticación y luego escribe el código que muestre. La verificación en dos pasos no está activa hasta que se compruebe ese código.';

  @override
  String get twoFactorTypeKey => 'O escribe esta clave';

  @override
  String get twoFactorKeyCopied => 'Clave copiada.';

  @override
  String get twoFactorOnBody =>
      'Al iniciar sesión se pide un código de tu aplicación de autenticación.';

  @override
  String get passcodeFourDigits => '4 dígitos';

  @override
  String get passcodeSixDigits => '6 dígitos';

  @override
  String get passcodeFourDigitsNote =>
      'Diez mil combinaciones. Rápido, y suficiente contra quien coja el teléfono.';

  @override
  String get passcodeSixDigitsNote =>
      'Un millón de combinaciones, y sigue siendo un teclado numérico.';

  @override
  String get passcodePhraseNote =>
      'Letras, y dígitos o símbolos si los quieres. La única de las tres que aguanta ante alguien con el teléfono y tiempo.';

  @override
  String get passcodeNeedsFourDigits => 'Cuatro dígitos.';

  @override
  String get passcodeNeedsSixDigits => 'Seis dígitos.';

  @override
  String passcodePhraseTooShort(int count) {
    return 'Al menos $count caracteres.';
  }

  @override
  String get passcodePhraseNeedsLetter =>
      'Una frase de contraseña necesita al menos una letra. Los dígitos y símbolos son bienvenidos junto a ella.';

  @override
  String get lockEntriesDiffer => 'Las dos entradas no coinciden.';

  @override
  String get lockOnToast =>
      'Bloqueo de la aplicación activado. Privio lo pedirá al volver.';

  @override
  String get lockOffToast => 'Bloqueo de la aplicación desactivado.';

  @override
  String get lockTurnOffTitle => '¿Desactivar el bloqueo de la aplicación?';

  @override
  String get lockTurnOffBody =>
      'Cualquiera que tenga el teléfono desbloqueado llega a tus mensajes. Un código de coacción puesto para la pantalla de bloqueo se quita con él.';

  @override
  String get lockTurnOffRow => 'Desactivar el bloqueo de la aplicación';

  @override
  String get lockWhatItIsNote =>
      'Un código en este dispositivo, que se pide cada vez que Privio vuelve al primer plano. No es la contraseña de tu cuenta y nunca sale del teléfono: protege el historial ya cifrado en él.';

  @override
  String get lockNoBiometricsNote =>
      'No hay opción de cara ni de huella. Son la única credencial que alguien puede usar poniéndote el teléfono delante de la cara, o apretando tu dedo mientras duermes; y en varios sitios un tribunal puede exigirlas donde no puede exigir un código.';

  @override
  String get lockChangePasscode => 'Cambiar el código';

  @override
  String get lockChoosePasscode => 'Elegir un código';

  @override
  String get lockAgain => 'Otra vez';

  @override
  String get lockChangeIt => 'Cambiarlo';

  @override
  String get lockTurnItOn => 'Activarlo';

  @override
  String get lockForgettingNote =>
      'Olvidarlo significa volver a iniciar sesión, lo que para el servidor es un dispositivo nuevo: lo que ya se entregó aquí se pierde salvo que esté en una copia de seguridad. No hay restablecimiento, porque un restablecimiento que cualquiera pudiera pedir no sería un bloqueo.';

  @override
  String get duressNoLockNote =>
      'En la pantalla de bloqueo todavía no hace nada, porque este dispositivo no tiene bloqueo de aplicación. Actívalo en Bloqueo de pantalla y un código de coacción con la forma de ese bloqueo también funcionará ahí, que es donde se arrebata un teléfono que ya tiene la sesión iniciada.';

  @override
  String duressShapeNote(String kind) {
    return 'Este dispositivo se desbloquea con $kind. Un código de coacción con la misma forma se puede escribir en la pantalla de bloqueo, donde destruye en vez de desbloquear. Cualquier otra forma solo funciona al iniciar sesión.';
  }

  @override
  String get duressMatchesLock =>
      'Este coincide con el bloqueo de este dispositivo, así que funciona tanto en la pantalla de bloqueo como al iniciar sesión.';

  @override
  String duressDoesNotMatchLock(String kind) {
    return 'Este no coincide con el bloqueo de este dispositivo ($kind), así que solo funciona al iniciar sesión: la pantalla de bloqueo no tiene dónde escribirlo.';
  }

  @override
  String get duressAtLeastFour => 'Usa al menos cuatro caracteres.';

  @override
  String get duressCodesDiffer => 'Los dos códigos no coinciden.';

  @override
  String get duressSameAsUnlock =>
      'Ese es el código que desbloquea este dispositivo. Un código de coacción tiene que ser distinto: la pantalla de bloqueo lo comprueba primero, así que si fueran iguales cada desbloqueo destruiría la cuenta, sin decirlo.';

  @override
  String get duressSetBoth =>
      'Código de coacción definido. Destruye la cuenta al iniciar sesión y en la pantalla de bloqueo.';

  @override
  String get duressSetSignInOnly =>
      'Código de coacción definido. Escribirlo al iniciar sesión destruye la cuenta.';

  @override
  String get duressRemoved => 'Código de coacción eliminado.';

  @override
  String get duressRemoveTitle => 'Quitar el código de coacción';

  @override
  String get duressWarning =>
      'Escribir este código en vez de tu contraseña al iniciar sesión destruye la cuenta: todos los dispositivos, todos los mensajes que esperan, tus contactos, tus grupos, tu copia de seguridad. No hay deshacer ni confirmación: esa es la idea.';

  @override
  String get duressIsSet => 'Hay un código de coacción definido';

  @override
  String get duressCannotShow =>
      'Privio no puede mostrártelo: se guarda como se guarda una contraseña. Definir uno nuevo abajo lo sustituye.';

  @override
  String get duressRemoveIt => 'Quitarlo';

  @override
  String get duressReplaceIt => 'Sustituirlo';

  @override
  String get duressSetOne => 'Definir un código de coacción';

  @override
  String get duressAccountPassword => 'La contraseña de tu cuenta de Privio';

  @override
  String get duressLooksLikePin =>
      'Eso es más corto que una contraseña de cuenta. Este campo quiere la contraseña que elegiste al crear la cuenta, no el PIN que desbloquea la aplicación.';

  @override
  String get duressCodeField => 'Código de coacción';

  @override
  String get duressCodeAgain => 'Repite el código de coacción';

  @override
  String get duressReplaceCode => 'Sustituir el código';

  @override
  String get duressSetCode => 'Definir el código';

  @override
  String get duressWhatItDoesNotDo =>
      'Lo que no hace: el nombre de la cuenta sigue ocupado, así que nadie puede reclamarlo después, y no alcanza otro dispositivo que ya tenga la sesión iniciada en otro sitio. Quien mire ve el intento rechazado exactamente igual que una contraseña o un PIN mal escritos.';

  @override
  String get disguiseIntro =>
      'Un Privio bloqueado se abre como una calculadora que funciona en vez de una pantalla de bloqueo. Cualquier operación cuyo resultado sea tu código abre Privio al pulsar =, así que el código nunca tiene que aparecer en pantalla. Cualquier otra operación es solo una operación.';

  @override
  String get disguiseOpenTo => 'Abrir como';

  @override
  String get disguiseLockScreen => 'La pantalla de bloqueo';

  @override
  String disguiseCalculatorNamed(String name) {
    return 'Calculadora $name';
  }

  @override
  String get disguisePickNote =>
      'Elige la que ya trae tu teléfono. Una calculadora que no se parece a la de siempre es justo lo que llama la atención.';

  @override
  String get disguiseSeeIt => 'Verla';

  @override
  String disguiseErrorSuffix(String reason) {
    return '$reason La pantalla de bloqueo ha cambiado igualmente; la pantalla de inicio no.';
  }

  @override
  String get disguiseNoLock =>
      'Este dispositivo todavía no tiene bloqueo de pantalla, así que no hay ningún código que escribir en una calculadora.';

  @override
  String get disguisePhraseLock =>
      'Tu bloqueo de pantalla es una frase de contraseña. Una calculadora tiene diez teclas y ninguna letra, así que no hay forma de escribirla. Cambia el bloqueo a 4 o 6 dígitos para usar un camuflaje.';

  @override
  String get disguiseOnHomeScreen => 'En la pantalla de inicio';

  @override
  String get disguiseWhatItDoesNotDo => 'Lo que esto no hace';

  @override
  String get disguiseNotADefence =>
      'No es una defensa contra quien tenga el teléfono durante un rato largo. La aplicación sigue instalada, y su tamaño, sus archivos y su tráfico de red siguen ahí para quien mire en serio. En lo que es buena es en el caso corriente: una pantalla vista de reojo, o un teléfono entregado desbloqueado.';

  @override
  String get disguiseHomeScreenChanges =>
      'En la pantalla de inicio y en el cajón de aplicaciones, Privio pasa a ser un icono de calculadora llamado «Calculadora». Tu lanzador puede tardar unos segundos en redibujarse, y un icono que hayas anclado tú a la pantalla de inicio puede necesitar anclarse otra vez. Desactivar el camuflaje lo devuelve a su sitio.\n\nLa propia lista de aplicaciones de Android —Ajustes, información de la aplicación, el nombre que aparece cuando Privio pide un permiso— sigue diciendo Privio. Ese nombre se fija al compilar la aplicación y ninguna aplicación puede cambiarlo en marcha.';

  @override
  String get disguiseIconUnchanged =>
      'En este dispositivo el icono y el nombre no cambian, solo lo que abre la aplicación. Quien repase la pantalla de inicio sigue encontrando Privio por su nombre.';

  @override
  String get disguiseClosePreview => 'Cerrar la vista previa';

  @override
  String get licenseActivatedToast =>
      'Activada. Esta licencia pertenece ya a tu cuenta.';

  @override
  String get licenseNotCheckedTitle => 'Todavía sin comprobar';

  @override
  String get licenseNotCheckedBody =>
      'Privio todavía no ha podido preguntar al servidor por esta cuenta. Vuelve a poner la aplicación en línea y abre otra vez esta pantalla.';

  @override
  String get licenseNotNeededTitle => 'Aquí no hace falta licencia';

  @override
  String get licenseNotNeededBody =>
      'Este servidor no la pide. Las licencias son para el servicio alojado de Privio: una licencia para una infraestructura que ya administras no significaría nada.';

  @override
  String get licenseStoreTitle => 'Lo gestiona la tienda';

  @override
  String licenseStoreBody(String store) {
    return 'Esta compilación se pagó a través de la tienda de la que vino, así que no hay ninguna clave que introducir. Si no está activa, restaura tu compra en $store.';
  }

  @override
  String get licenseOnePurchaseNote =>
      'Una compra, una clave, una cuenta, para siempre. Una clave canjeada queda ligada a la cuenta que la canjeó y no se puede mover ni volver a usar.';

  @override
  String get licenseEnterTitle => 'Introduce tu clave de licencia';

  @override
  String get licenseEnterBody =>
      'Compra una clave en getprivio.com/license y escríbela aquí. Hasta que se active, esta cuenta puede iniciar sesión y leer lo que ya haya llegado, pero no enviar.';

  @override
  String get licenseActivated => 'Activada';

  @override
  String licenseRedeemedOn(String date) {
    return 'Canjeada el $date.';
  }

  @override
  String get licenseFromAppStore => 'Comprada en la App Store.';

  @override
  String get licenseFromPlay => 'Comprada en Google Play.';

  @override
  String get licenseFromKey =>
      'Activada con una clave de licencia. Acceso de por vida, sin renovaciones.';

  @override
  String get safetyTrustedToast =>
      'La nueva clave está marcada como de confianza. Compara otra vez el número antes de fiarte de él.';

  @override
  String get safetyMatches => 'Eso coincide con uno de los números de abajo.';

  @override
  String get safetyNoMatch =>
      'Eso no coincide con ninguno de los números de abajo.';

  @override
  String safetyNothingYet(String name) {
    return 'Todavía no hay nada que comparar. Existe un número en cuanto $name y tú habéis intercambiado un mensaje, porque solo entonces este dispositivo ha fijado una clave suya.';
  }

  @override
  String safetyReadThese(String name) {
    return 'Léele estos dígitos a $name, por llamada o en persona. Si ve los mismos, nadie está en medio. Si no, deja de usar este chat para nada que no dirías en público.';
  }

  @override
  String get safetyMarkNotVerified => 'Marcar como no verificado';

  @override
  String get safetyMarkVerified => 'Marcar como verificado';

  @override
  String safetyMarkNote(String name) {
    return 'Marcarlo como verificado registra exactamente las claves que hay en pantalla. Si alguna cambia, o se suma un dispositivo nuevo a $name, la marca vuelve por sí sola a «cambiado»: es un registro de lo que comprobaste, no una promesa sobre lo que venga después.';
  }

  @override
  String get safetyVerified => 'Verificado';

  @override
  String get safetyChangedSince => 'Ha cambiado desde que lo comprobaste';

  @override
  String get safetyNotVerified => 'No verificado';

  @override
  String safetyTheirDevice(int index) {
    return 'Su dispositivo $index';
  }

  @override
  String get safetyCompareTitle => 'Comparar un número que te hayan enviado';

  @override
  String get safetyCompare => 'Comparar';

  @override
  String get safetyKeyNotYours => 'La clave del servidor no es la que tenías';

  @override
  String get safetyRefusedUntilDecide =>
      'Los mensajes a este chat se rechazan hasta que decidas. Reinstalar Privio, o iniciar sesión en un dispositivo nuevo, hace esto de forma legítima y es el motivo habitual. También lo hace un servidor que te entregue una clave suya, que desde aquí se ve exactamente igual; por eso conviene volver a comparar el número de abajo después.';

  @override
  String get safetyTrustNewKey => 'Confiar en la clave nueva';

  @override
  String get safetyKeyChangedArrived =>
      'Su clave ha cambiado, y con ella ha llegado un mensaje';

  @override
  String get safetyKeyChangedBody =>
      'La clave nueva ya está en uso: un mensaje que trae una no se puede rechazar sin darle a cualquiera la forma de silenciar un chat. Reinstalar hace esto. También alguien que se meta en medio. El número de abajo es la diferencia, y solo vale algo si se compara en voz alta.';

  @override
  String get channelsCouldNotOpenLink => 'No se ha podido abrir ese enlace';

  @override
  String get channelsJoinWithLink => 'Unirse con un enlace';

  @override
  String get channelsNewChannel => 'Canal nuevo';

  @override
  String get channelsTabFollowing => 'Siguiendo';

  @override
  String get channelsTabDiscover => 'Descubrir';

  @override
  String get channelsSearchMine => 'Buscar en tus canales';

  @override
  String get channelsSearchPublic => 'Buscar canales públicos';

  @override
  String get channelsEmptyTitle => 'Todavía no hay canales';

  @override
  String get channelsEmptyBody =>
      'Crea uno, o encuentra un canal público en Descubrir.';

  @override
  String get channelsNothingFound => 'No se ha encontrado nada';

  @override
  String get channelsDiscoverEmptyBody =>
      'Busca canales públicos por nombre, alias o descripción. Los canales privados nunca aparecen aquí.';

  @override
  String channelsHandleAndMembers(String handle, String members) {
    return '@$handle  ·  $members';
  }

  @override
  String get channelsJoinTitle => 'Unirse a un canal';

  @override
  String get channelsJoinNote =>
      'Pega un enlace de canal. Te muestra el canal; unirse es un botón allí. Unirse tampoco te entrega la clave: un miembro que la tenga la envía cifrada a tu dispositivo justo después.';

  @override
  String get categoryNews => 'Noticias';

  @override
  String get categoryTechnology => 'Tecnología';

  @override
  String get categoryCommunity => 'Comunidad';

  @override
  String get categoryEducation => 'Educación';

  @override
  String get categoryCulture => 'Cultura';

  @override
  String newChannelPictureUnreadable(String name) {
    return 'Privio no ha podido leer $name. Prueba con otra imagen.';
  }

  @override
  String get newChannelCouldNotCreate => 'No se ha podido crear el canal';

  @override
  String get newChannelWithoutPicture => 'El canal se ha creado sin la imagen.';

  @override
  String get newChannelCreate => 'Crear';

  @override
  String get newChannelPublicPictureNote =>
      'La imagen de un canal público se muestra en su página web y en las vistas previas de enlace, así que se guarda sin cifrar, igual que su nombre, su alias y su descripción.';

  @override
  String get newChannelHandle => 'Alias';

  @override
  String get newChannelHandleRule =>
      'De 3 a 32 caracteres: a-z, 0-9, guion bajo o punto';

  @override
  String get newChannelCategory => 'Categoría';

  @override
  String get newChannelRestrictSaving => 'Restringir el guardado';

  @override
  String get newChannelRestrictNote =>
      'Pide a las aplicaciones de quien lee que no guarden ni reenvíen las publicaciones. Una petición, no una garantía: quien puede leer una publicación puede fotografiarla.';

  @override
  String get newChannelPrivateBody =>
      'Solo se llega con un enlace de invitación. El nombre se sube cifrado, así que el servidor guarda un canal que no puede nombrar.';

  @override
  String get newChannelPublicBody =>
      'Aparece en listados y se puede buscar. El nombre, el alias y la descripción son públicos por definición; las publicaciones siguen cifradas de extremo a extremo.';

  @override
  String get membersCouldNotLift => 'No se ha podido levantar.';

  @override
  String get membersCouldNotChange => 'No se ha podido cambiar ese miembro';

  @override
  String get membersTitle => 'Miembros';

  @override
  String get membersWhoRuns => 'Quién lleva este canal';

  @override
  String get membersSilencedCanRead => 'Puede leer, no publicar ni reaccionar';

  @override
  String get membersAllowAgain => 'Permitir otra vez';

  @override
  String get membersRoleAndPermissions => 'Rol y permisos';

  @override
  String get membersOwnerEverything => 'Propietario · todo';

  @override
  String get membersSubscriberReadOnly => 'Suscriptor · solo lectura';

  @override
  String get membersGrantPost => 'publicar';

  @override
  String get membersGrantEdit => 'editar';

  @override
  String get membersGrantDeletePosts => 'eliminar publicaciones';

  @override
  String get membersGrantManageMembers => 'gestionar miembros';

  @override
  String get membersGrantDeleteChannel => 'eliminar el canal';

  @override
  String membersRoleLine(String role, String granted) {
    return '$role · $granted';
  }

  @override
  String get membersSubscriber => 'Suscriptor';

  @override
  String get membersTogglePost => 'Publicar';

  @override
  String get membersToggleEditChannel => 'Editar el canal';

  @override
  String get membersToggleDeletePosts => 'Eliminar publicaciones';

  @override
  String get membersToggleManageMembers => 'Gestionar miembros';

  @override
  String get membersToggleDeleteChannel => 'Eliminar el canal';

  @override
  String get membersGreyedOutNote =>
      'Los permisos en gris son los que tú no tienes. Nadie puede repartir más de lo que tiene.';

  @override
  String get membersSubscriberNote => 'Un suscriptor lee el canal y nada más.';

  @override
  String get membersRemoveFromChannel => 'Quitar del canal';

  @override
  String get membersStoppedFromPosting => 'Sin permiso para publicar';

  @override
  String get membersAudienceNote =>
      'Solo se listan las personas que llevan este canal. Quién lo lee no se muestra a otros lectores, tú incluido.';

  @override
  String get channelPicture => 'Imagen';

  @override
  String get channelLinkCopied => 'Enlace copiado.';

  @override
  String get adminsMakeSomebodyFirst => 'Haz antes administrador a alguien.';

  @override
  String get subscribersCouldNotAddAnybody => 'No se ha podido añadir a nadie.';

  @override
  String subscribersAddCount(int count) {
    return 'Añadir $count';
  }

  @override
  String get threadCouldNotPost => 'No se ha podido publicar ese comentario.';

  @override
  String get threadCouldNotRemove => 'No se ha podido quitar ese comentario.';

  @override
  String threadStopTitle(String name) {
    return '¿Impedir que $name publique?';
  }

  @override
  String get threadStopBody =>
      'Sigue en el canal y puede continuar leyéndolo. No puede comentar ni reaccionar hasta que lo deshagas.\n\nQuitarla del canal es la otra opción, más dura: eso rota la clave y se lleva también su lectura.';

  @override
  String get threadStopThem => 'Impedírselo';

  @override
  String get threadStopThemPosting => 'Impedirle publicar';

  @override
  String get threadCouldNotDoThat => 'No se ha podido hacer.';

  @override
  String get threadTitle => 'Comentarios';

  @override
  String get threadUnknown => 'Desconocido';

  @override
  String get threadEncryptedNoKey =>
      'Cifrado: este dispositivo no tiene la clave.';

  @override
  String get threadCommentHint => 'Comentar';

  @override
  String get threadNoKeyForChannel => 'No hay clave para este canal';

  @override
  String get threadDeletedAccount => 'Cuenta eliminada';

  @override
  String get threadEncryptedNoKeyHere =>
      'Cifrado: no hay clave para ello en este dispositivo.';

  @override
  String get threadEmptyTitle => 'Todavía no hay comentarios';

  @override
  String get threadEmptyBody =>
      'Los comentarios se cifran con la clave del canal, igual que las publicaciones. El servidor los guarda y no puede leerlos.';

  @override
  String threadStoppedToast(String name) {
    return '$name puede seguir leyendo el canal, pero no publicar en él.';
  }

  @override
  String get threadThem => 'Esa persona';

  @override
  String get threadThemObject => 'esa persona';

  @override
  String get feedCouldNotAskForKey => 'No se ha podido pedir la clave.';

  @override
  String get feedKeyArrived =>
      'La clave ha llegado. Ya puedes volver a publicar.';

  @override
  String get feedAskedAgain =>
      'Se ha vuelto a pedir. La clave la entrega otro miembro, así que llega cuando alguno esté conectado.';

  @override
  String get feedCouldNotJoin => 'No se ha podido unir';

  @override
  String get feedPickFutureTime => 'Elige una hora que no haya pasado ya.';

  @override
  String get feedCouldNotPublishPoll =>
      'No se ha podido publicar esa encuesta.';

  @override
  String feedScheduledFor(String when) {
    return 'Programado para $when. Hasta entonces está en «Programado».';
  }

  @override
  String get feedCouldNotPublish => 'No se ha podido publicar';

  @override
  String get feedCouldNotChangeLink => 'No se ha podido cambiar el enlace.';

  @override
  String get feedOldLinkDead =>
      'El enlace antiguo está muerto. Quien lo tenga necesitará el nuevo.';

  @override
  String get feedSaved => 'Guardado.';

  @override
  String get feedCouldNotChangeReactions =>
      'No se han podido cambiar las reacciones.';

  @override
  String get feedCouldNotChangePost =>
      'No se ha podido cambiar la publicación.';

  @override
  String get feedPublished => 'Publicado.';

  @override
  String get feedCouldNotPublishIt => 'No se ha podido publicar.';

  @override
  String get feedCouldNotChangeThat => 'No se ha podido cambiar.';

  @override
  String get feedCommentsOn =>
      'Ahora quien lee puede comentar las publicaciones.';

  @override
  String get feedCommentsOff =>
      'Los comentarios están desactivados. Los hilos existentes se ocultan, no se eliminan.';

  @override
  String get feedCouldNotReadNumbers => 'No se han podido leer los números.';

  @override
  String get feedNobodyToHandTo =>
      'No hay nadie más en este canal a quien entregárselo.';

  @override
  String feedOwnsNow(String name) {
    return 'Ahora $name es propietario de este canal. Tú eres administrador en él.';
  }

  @override
  String get feedCouldNotHandOn => 'No se ha podido entregar el canal.';

  @override
  String get feedReported => 'Denunciado. Gracias.';

  @override
  String get feedCouldNotSendThat => 'No se ha podido enviar.';

  @override
  String get feedRemovePicture => 'Quitar la imagen';

  @override
  String get feedPictureRemoved => 'Imagen quitada.';

  @override
  String get feedCouldNotRemovePicture => 'No se ha podido quitar la imagen.';

  @override
  String get feedCouldNotSetPicture => 'No se ha podido poner la imagen.';

  @override
  String get feedPictureUpdated => 'Imagen del canal actualizada.';

  @override
  String get feedDeleteChannelTitle => '¿Eliminar el canal?';

  @override
  String get feedDeleteChannelBody =>
      'El canal y todas sus publicaciones se eliminan para todos. Nada deshace esto.';

  @override
  String get feedCouldNotDeleteChannel => 'No se ha podido eliminar el canal';

  @override
  String get feedCouldNotLeaveChannel => 'No se ha podido salir del canal';

  @override
  String get feedScheduled => 'Programado';

  @override
  String get feedRequestsToJoin => 'Solicitudes para unirse';

  @override
  String get feedChannelPicture => 'Imagen del canal';

  @override
  String get feedAddPicture => 'Añadir una imagen';

  @override
  String get feedTurnCommentsOff => 'Desactivar los comentarios';

  @override
  String get feedTurnCommentsOn => 'Activar los comentarios';

  @override
  String get feedHandChannelOn => 'Entregar este canal';

  @override
  String get feedDeleteChannel => 'Eliminar el canal';

  @override
  String get dayToday => 'Hoy';

  @override
  String get dayYesterday => 'Ayer';

  @override
  String get feedNoSearchResultsBody =>
      'La búsqueda se hace en este dispositivo, sobre las publicaciones que ya ha cargado y ha podido abrir. El servidor no puede buscarlas: las guarda selladas.';

  @override
  String get feedEdited => '· editado';

  @override
  String feedCommentCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count comentarios',
      one: '1 comentario',
      zero: 'Comentar',
    );
    return '$_temp0';
  }

  @override
  String get feedUnpin => 'Dejar de fijar';

  @override
  String get feedPin => 'Fijar';

  @override
  String get feedRemoveFile => 'Quitar el archivo';

  @override
  String get feedAttach => 'Adjuntar una imagen o un archivo';

  @override
  String get feedPublishLater => 'Publicar más tarde';

  @override
  String get feedAskQuestion => 'Hacer una pregunta';

  @override
  String get feedWritePost => 'Escribe una publicación';

  @override
  String get feedEditPost => 'Editar la publicación';

  @override
  String get feedPost => 'Publicación';

  @override
  String get feedEditUnseenNote =>
      'Todavía no lo ha visto nadie, así que no se marcará como editado.';

  @override
  String get feedEditSeenNote =>
      'La publicación se marcará como editada. Su archivo, si lo tiene, se queda como está.';

  @override
  String get feedWaiting => 'En espera';

  @override
  String get feedEncryptedNoKeyHere =>
      'Cifrado: no hay clave en este dispositivo.';

  @override
  String get feedDiscard => 'Descartar';

  @override
  String get feedPublishNow => 'Publicar ahora';

  @override
  String get feedNothingWaiting => 'Nada en espera';

  @override
  String get feedNothingWaitingBody =>
      'Las publicaciones que programes esperan aquí hasta que llegue su hora. Nadie más puede verlas, ni saber que existen.';

  @override
  String feedTodayAt(String time) {
    return 'hoy a las $time';
  }

  @override
  String feedTomorrowAt(String time) {
    return 'mañana a las $time';
  }

  @override
  String feedDateAt(String date, String time) {
    return '$date a las $time';
  }

  @override
  String get feedReactionsNote =>
      'Lo que quien lee puede poner debajo de una publicación. Las reacciones que ya estén en una publicación se quedan, aunque quites el emoji de esta lista.';

  @override
  String feedChosenOfLimit(int chosen, int limit) {
    return '$chosen de $limit';
  }

  @override
  String get feedPollNoKey =>
      'Una encuesta para la que este dispositivo no tiene clave.';

  @override
  String feedPollPickUpTo(int count) {
    return 'Elige hasta $count';
  }

  @override
  String get feedPollPickOne => 'Elige una';

  @override
  String feedPollCloses(String when) {
    return 'se cierra $when';
  }

  @override
  String feedPollVoters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votantes',
      one: '1 votante',
    );
    return '$_temp0';
  }

  @override
  String get feedPollClearAnswer => 'Borrar mi respuesta';

  @override
  String get feedPollAnswer => 'Responder';

  @override
  String get feedPollQuestion => 'Pregunta';

  @override
  String feedPollAnswerN(int index) {
    return 'Respuesta $index';
  }

  @override
  String get feedPollAddAnswer => 'Añadir una respuesta';

  @override
  String get feedPollSeveral => 'Varias respuestas';

  @override
  String get feedPollNote =>
      'La pregunta y las respuestas se cifran con la clave del canal, igual que una publicación. El servidor cuenta los votos sin llegar a saber qué dice ninguno.';

  @override
  String get feedPollAsk => 'Preguntar';

  @override
  String get feedCouldNotOpenFile => 'No se ha podido abrir ese archivo.';

  @override
  String get feedOpened => 'Abierto';

  @override
  String get statsPosts => 'Publicaciones';

  @override
  String get statsWaitingToPublish => 'Pendientes de publicar';

  @override
  String get statsPeopleWhoVoted => 'Personas que han votado';

  @override
  String get statsWaitingToJoin => 'Pendientes de unirse';

  @override
  String get statsNoViewCountNote =>
      'No hay recuento de vistas, y eso es una decisión, no una carencia. Contar quién ha leído una publicación —sin contar a nadie dos veces— significa guardar una fila por cada lector de cada publicación, que es un registro de lo que ha leído cada persona. Todo lo de arriba se cuenta a partir de algo que alguien decidió hacer.';

  @override
  String get feedPollClosed => 'cerrada';

  @override
  String get inviteNever => 'Nunca';

  @override
  String inviteExpires(String when) {
    return 'caduca $when';
  }

  @override
  String requestsAsked(String when) {
    return 'Solicitado $when';
  }

  @override
  String get inviteAskMeFirst => 'Preguntarme antes';

  @override
  String get inviteAskMeFirstNote =>
      'Quien siga el enlace espera tu aprobación en vez de entrar sin más. No tienen ninguna clave hasta que les dejas pasar.';

  @override
  String get inviteExpiresLabel => 'Caduca';

  @override
  String get invitePickATime => 'Elegir una hora';

  @override
  String get inviteHowMany => 'Cuántos pueden entrar con él';

  @override
  String get inviteNoLimit => 'Sin límite';

  @override
  String inviteJoinedSoFar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count han entrado con este enlace hasta ahora.',
      one: '1 persona ha entrado con este enlace hasta ahora.',
    );
    return '$_temp0 Abrirlo y marcharse no cuenta.';
  }

  @override
  String get inviteReplaceLink => 'Sustituir el enlace';

  @override
  String get inviteReplaceNote =>
      'Sustituirlo es la forma de revocar un enlace: el antiguo deja de funcionar al instante, en todas partes. No queda ningún enlace a medias.';

  @override
  String get inviteReplaceTitle => '¿Sustituir el enlace?';

  @override
  String get inviteReplaceBody =>
      'El enlace que has compartido deja de funcionar de inmediato: en mensajes, en carteles, allá donde se haya pegado. Nadie que lo tenga puede entrar.\n\nQuien ya esté en el canal se queda. No hay forma de recuperar el enlace antiguo.';

  @override
  String get inviteReplaceIt => 'Sustituirlo';

  @override
  String get inviteExpired =>
      'Este enlace ha caducado: nadie puede entrar con él.';

  @override
  String get inviteUsedUp => 'Este enlace se ha agotado.';

  @override
  String get inviteNeedsApproval => 'Entrar necesita tu aprobación';

  @override
  String get inviteOpenJoin => 'Quien lo tenga entra directamente';

  @override
  String inviteUsedOf(int used, int max) {
    return '$used de $max usados';
  }

  @override
  String get inviteShareNote =>
      'Compártelo donde quieras: no lleva ninguna clave. Quien lo abra entra en el canal, y la clave para leerlo se la envía después a su dispositivo, cifrada, alguien que ya la tiene.';

  @override
  String get requestsNobodyWaiting => 'Nadie esperando';

  @override
  String get requestsNobodyWaitingBody =>
      'Quien siga el enlace de invitación aparece aquí mientras el enlace esté puesto en «preguntarme antes».';

  @override
  String get requestsNo => 'No';

  @override
  String get requestsLetIn => 'Dejar entrar';

  @override
  String get feedSettings => 'Ajustes';

  @override
  String feedKeyRotating(int epoch) {
    return 'Alguien ha salido de este canal, así que está cambiando su clave (versión $epoch). Las publicaciones anteriores siguen siendo legibles. Las nuevas se abren cuando la clave nueva llegue a este dispositivo.';
  }

  @override
  String get feedWaitingForKey =>
      'Esperando la clave. La envía a este dispositivo, cifrada, alguien que ya está en el canal; el servidor nunca la tiene.';

  @override
  String get feedJoinNote =>
      'Unirte te trae las publicaciones. La clave que las abre te la envía después un miembro a tu dispositivo, nunca el servidor.';

  @override
  String get feedJoinChannel => 'Unirse al canal';

  @override
  String get feedNoPostsYet => 'Todavía no hay publicaciones';

  @override
  String get feedPickNewOwnerNote =>
      'Solo alguien que ya esté en el canal. Entregárselo a un desconocido le pondría al mando de una clave que no tiene.';

  @override
  String feedTransferTitle(String name) {
    return '¿Dar el canal a $name?';
  }

  @override
  String get feedTransferBody =>
      'Pasará a ser suyo. Tú te quedas como administrador con todo lo que tienes ahora salvo el derecho a eliminar el canal, y puede quitarte después.\n\nNo puedes deshacer esto tú. Por eso pide tu contraseña en vez de fiarse de un teléfono desbloqueado.';

  @override
  String get feedYourPrivioPassword => 'Tu contraseña de Privio';

  @override
  String get feedHandItOn => 'Entregarlo';

  @override
  String get feedReportTitle => 'Denunciar este canal';

  @override
  String get feedReportPublicNote =>
      'La denuncia lleva este canal y el motivo que elijas. Quien gestione el servidor puede ver el nombre y la descripción de un canal público, porque así es como se busca, pero no sus publicaciones, que están cifradas.';

  @override
  String get feedReportPrivateNote =>
      'La denuncia lleva este canal y el motivo que elijas, y nada más. Su nombre y sus publicaciones están cifrados, así que quien gestione el servidor no puede leerlos. Ese es el límite honesto de lo que hace denunciar un canal privado.';

  @override
  String get feedReportNoMessageNote =>
      'No hay campo de mensaje a propósito: sería el único sitio de Privio donde alguien pegaría lo cifrado que está denunciando en un campo que el servidor puede leer.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportAbuse => 'Abuso o acoso';

  @override
  String get reportIllegal => 'Contenido ilegal';

  @override
  String get reportImpersonation => 'Hacerse pasar por otra persona';

  @override
  String get reportOther => 'Otra cosa';

  @override
  String get feedReactionLimit => 'Reacciones';

  @override
  String get failureUnreachable => 'No se ha podido conectar con Privio.';

  @override
  String get failureUnreachableCheckConnection =>
      'No se ha podido conectar con Privio. Comprueba tu conexión.';

  @override
  String get failureUnreachableTryAgain =>
      'No se ha podido conectar con Privio. Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get failureCouldNotSave =>
      'No se ha podido guardar. Comprueba tu conexión.';

  @override
  String get failureChangeNotSaved =>
      'No se ha podido conectar con Privio. El cambio no se ha guardado.';

  @override
  String get failureRateLimited => 'Demasiadas solicitudes. Espera un momento.';

  @override
  String get failureTooManyAttempts =>
      'Demasiados intentos. Espera unos minutos.';

  @override
  String get failureLicenseRequired =>
      'Activa tu licencia para enviar mensajes.';

  @override
  String get failureIdentityChanged =>
      'El número de seguridad ha cambiado. No se ha enviado nada: compruébalo antes.';

  @override
  String get failureCouldNotSendMessage => 'No se ha podido enviar el mensaje';

  @override
  String get failureCouldNotSendFile => 'No se ha podido enviar el archivo';

  @override
  String get failureCouldNotReadMessage => 'No se ha podido leer un mensaje';

  @override
  String failureMessagesUnreadable(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No se han podido leer $count mensajes',
      one: 'No se ha podido leer un mensaje',
    );
    return '$_temp0';
  }

  @override
  String get failureCouldNotOpenFile => 'No se ha podido abrir ese archivo.';

  @override
  String get failureNotAnImage =>
      'Ese archivo no es una imagen que Privio pueda usar.';

  @override
  String get failureCouldNotSetPicture =>
      'No se ha podido establecer la imagen';

  @override
  String get failureDeletedHereOnly =>
      'Eliminado aquí. La solicitud para eliminarlo allí no ha salido.';

  @override
  String get failureCouldNotCreateGroup => 'No se ha podido crear el grupo';

  @override
  String get failureNotAGroupLink =>
      'Eso no parece un enlace de grupo de Privio.';

  @override
  String get failureGroupNotFound =>
      'Ese grupo no existe o el enlace es incorrecto.';

  @override
  String get failureGroupKeyMissing =>
      'Este dispositivo aún no tiene la clave del grupo.';

  @override
  String get failureNotAChannelLink =>
      'Eso no parece un enlace de canal de Privio.';

  @override
  String get failureHandleTaken => 'Ese identificador ya está en uso.';

  @override
  String get failureChannelNotFound =>
      'Ese canal no existe o el enlace es incorrecto.';

  @override
  String get failureNotAMember => 'No estás en este canal.';

  @override
  String get failureInsufficientPermission =>
      'No tienes permiso para hacer eso.';

  @override
  String get failureCannotChangeOwnRole => 'No puedes cambiar tu propio rol.';

  @override
  String get failureOwnerIsFixed =>
      'El propietario del canal no se puede cambiar ni eliminar.';

  @override
  String get failureTargetOutranksYou =>
      'Ese miembro tiene permisos que tú no tienes.';

  @override
  String get failureCannotGrantWhatYouLack =>
      'No puedes conceder un permiso que tú mismo no tienes.';

  @override
  String get failureOwnerCannotLeave =>
      'Transfiere el canal o elimínalo en su lugar.';

  @override
  String get failureUsernameTaken => 'Ese nombre de usuario ya está en uso.';

  @override
  String get failureInvalidCredentials =>
      'El nombre de usuario o la contraseña no son correctos.';

  @override
  String get failureTotpRequired => 'Introduce tu código de doble factor.';

  @override
  String get failureInvalidTwoFactorCode =>
      'Ese código de doble factor no es correcto.';

  @override
  String get failureTooManyDevices =>
      'Esta cuenta ya tiene el número máximo de dispositivos.';

  @override
  String failureCheckUsernameAndPassword(String detail) {
    return 'Comprueba el nombre de usuario y la contraseña: $detail';
  }

  @override
  String get failureInvalidTotp =>
      'Ese código no es correcto. Comprueba la hora de tu teléfono e inténtalo de nuevo.';

  @override
  String get failureTotpAlreadyEnabled =>
      'El doble factor ya está activado en esta cuenta.';

  @override
  String get failureTotpNotSetUp =>
      'Vuelve a empezar la configuración: el secreto ya no está.';

  @override
  String get failureInvalidPassword => 'Esa contraseña no es correcta.';

  @override
  String get failureDuressMatchesPassword =>
      'El código de coacción tiene que ser distinto de tu contraseña; de lo contrario, un inicio de sesión normal destruiría la cuenta.';

  @override
  String get failureDeviceNotFound => 'Ese dispositivo ya ha cerrado sesión.';

  @override
  String get failureCouldNotLiftBlock =>
      'No se ha podido levantar ese bloqueo.';

  @override
  String failureLicenseKeyIncomplete(String format) {
    return 'Esa clave está incompleta. Tiene el formato $format.';
  }

  @override
  String get failureNotALicenseKey =>
      'Eso no parece una clave de licencia de Privio.';

  @override
  String get failureLicenseNotFound =>
      'Ninguna licencia coincide con esa clave. Compruébala e inténtalo de nuevo.';

  @override
  String get failureLicenseAlreadyRedeemed =>
      'Esa clave ya la ha usado otra cuenta. Una clave solo se puede canjear una vez.';

  @override
  String get failureLicenseRevoked =>
      'Esa licencia fue revocada. Contacta con soporte si la pagaste.';

  @override
  String get failureAccountAlreadyLicensed =>
      'Esta cuenta ya tiene una licencia, así que la clave que has introducido no se ha usado.';

  @override
  String get failureNoPlayServices =>
      'Este teléfono no tiene los servicios de Google Play, así que Privio no puede despertarse mientras está cerrado. Los mensajes llegan mientras Privio está abierto.';

  @override
  String get failureNoApnsToken =>
      'iOS no ha emitido un token push para Privio, así que no puede despertarse mientras está cerrado. Los mensajes llegan mientras Privio está abierto.';

  @override
  String get failureNoPushService =>
      'Ningún servicio push ha respondido. Los mensajes llegan mientras Privio está abierto.';

  @override
  String get failureNoDistributor =>
      'Ningún distribuidor de UnifiedPush ha respondido. Instala uno, por ejemplo ntfy, e inténtalo de nuevo.';

  @override
  String get failureDistributorUnreachable =>
      'Privio no puede conectar con ese distribuidor. Tiene que ser una dirección https en la internet pública.';

  @override
  String get failureChannelKeyAwaitingGeneration =>
      'Este canal está cambiando su clave después de que se fuera un miembro. Podrás volver a publicar cuando alguien que gestione el canal abra Privio.';

  @override
  String get failureChannelKeyPending =>
      'Esperando a que la nueva clave del canal llegue a este dispositivo. Tu publicación no se ha perdido: inténtalo de nuevo en un momento.';

  @override
  String get failureUnexpected =>
      'Algo no ha funcionado como se esperaba. Inténtalo de nuevo.';

  @override
  String get failureCallDevicesUnavailable =>
      'Privio no ha podido abrir la cámara o el micrófono.';

  @override
  String get failureCallMicrophoneUnavailable =>
      'Privio no ha podido abrir el micrófono.';

  @override
  String get failureCallNotOpen => 'La llamada no estaba abierta.';

  @override
  String get deepLinkChannelGone =>
      'Ese enlace ya no apunta a ningún canal. Pide uno nuevo a quien te lo envió.';

  @override
  String get chatsPreviewDeleted => 'Mensaje eliminado';

  @override
  String get chatsPreviewPhoto => 'Foto';

  @override
  String get chatsPreviewVideo => 'Vídeo';

  @override
  String get chatsPreviewVoice => 'Mensaje de voz';

  @override
  String get chatsPreviewFile => 'Archivo';

  @override
  String get notificationsPermissionDenied =>
      'Las notificaciones están desactivadas para Privio en los ajustes del sistema. Los mensajes siguen llegando mientras Privio está abierto, pero no se te avisará y una llamada no sonará.';

  @override
  String get notificationsPermissionNotAsked =>
      'Privio todavía no tiene permiso para enviarte notificaciones.';

  @override
  String get failureCallMediaNotEncrypted =>
      'La llamada ha terminado: el otro extremo ha pedido una conexión que Privio no puede cifrar. Privio nunca recurre a una llamada sin cifrar.';

  @override
  String get failureCallFarEndNotBound =>
      'La llamada ha terminado: nada en la negociación demostraba quién estaba al otro lado. Privio no conecta una llamada que no puede ligar a una clave.';

  @override
  String get failureCallCertificateChanged =>
      'La llamada ha terminado: el otro extremo cambió a mitad de la negociación. Una llamada tiene un solo otro extremo, y esta tenía dos.';

  @override
  String failureCallIdentityChanged(String who) {
    return 'La llamada ha terminado: el número de seguridad de $who no es el que Privio tenía. Compáralo con esa persona por otro canal antes de volver a llamar.';
  }

  @override
  String get failureCallWrongParty =>
      'La llamada ha terminado: llegó un mensaje sobre ella de alguien que no participa en ella.';

  @override
  String failureCallNotVerified(String who) {
    return 'La llamada ha terminado: solo aceptas llamadas de personas cuyo número de seguridad has confirmado, y el de $who no está confirmado en este dispositivo.';
  }

  @override
  String get callEncrypted => 'Cifrado de extremo a extremo';

  @override
  String get callEncryptedVerified =>
      'Cifrado de extremo a extremo · verificado';

  @override
  String get securityVerifiedCallsOnly =>
      'Solo llamadas de contactos verificados';

  @override
  String get securityVerifiedCallsOnlyBody =>
      'Toda llamada está cifrada de extremo a extremo de todos modos. Con esto activado, Privio además rechaza una llamada mientras no hayas comparado el número de seguridad con esa persona y lo hayas confirmado: una clave que este dispositivo simplemente encontró primero no basta. Las llamadas de cualquier otra persona terminan con una explicación, en ambos lados.';

  @override
  String get privacyCalls => 'Llamadas';

  @override
  String get appearanceAccentColour => 'Color de acento';

  @override
  String get appearanceAccentNote =>
      'Esto cambia el aspecto de Privio en este dispositivo, para esta cuenta. Nadie a quien escribas lo ve, y tus otras cuentas conservan la suya. El rojo, para eliminar y colgar, sigue siendo rojo elijas el acento que elijas.';

  @override
  String get accentGreen => 'Verde';

  @override
  String get accentBlue => 'Azul';

  @override
  String get accentTeal => 'Turquesa';

  @override
  String get accentPurple => 'Violeta';

  @override
  String get accentPink => 'Rosa';

  @override
  String get accentRed => 'Rojo';

  @override
  String get accentOrange => 'Naranja';

  @override
  String get accentYellow => 'Amarillo';

  @override
  String get accentPrivioDefault => 'Predeterminado de Privio';

  @override
  String get appearanceAccentReset => 'Restablecer el valor predeterminado';

  @override
  String get appearanceAccentPreview => 'Vista previa';

  @override
  String get appearancePreviewSend => 'Enviar';

  @override
  String get appearancePreviewSetting => 'Confirmaciones de lectura';

  @override
  String get appearancePreviewMessage => 'Así se verán tus propios mensajes.';

  @override
  String accentSelected(String colour) {
    return '$colour, seleccionado';
  }

  @override
  String get appearanceAppIcon => 'Icono de la app';

  @override
  String get appearanceAppIconNote =>
      'Este es el icono de tu pantalla de inicio y pertenece a este teléfono, no a tu cuenta: iniciar sesión como otra persona no lo cambia. Se mantiene como lo dejaste aunque después elijas otro color de acento.';

  @override
  String get appearanceAppIconMatchAccent => 'Usar el color de acento actual';

  @override
  String get appearanceAppIconReset => 'Restaurar el icono original';

  @override
  String get appearanceAppIconSlow =>
      'La pantalla de inicio puede tardar unos segundos en redibujarse. Esa espera es del lanzador, no de Privio.';

  @override
  String get appearanceAppIconUnavailable =>
      'Este dispositivo no puede cambiar el icono de la app, así que Privio no lo ofrece.';

  @override
  String get appearanceAppIconOriginal => 'Original';

  @override
  String get failureAppIconUnsupported =>
      'No se ha podido cambiar el icono de la app: este dispositivo no lo permite.';

  @override
  String get failureAppIconHiddenByDisguise =>
      'Mientras el disfraz está activado, la pantalla de inicio muestra la calculadora, así que no se ha cambiado el color del icono. Desactiva primero el disfraz.';

  @override
  String appIconSelected(String colour) {
    return 'Icono en $colour, seleccionado';
  }

  @override
  String appIconChoose(String colour) {
    return 'Icono en $colour';
  }

  @override
  String get failureStickerNotAnImage =>
      'Ese archivo no es una imagen PNG ni WebP.';

  @override
  String get failureStickerAnimated =>
      'Los stickers animados todavía no se admiten. Usa un PNG o WebP fijo.';

  @override
  String failureStickerTooLarge(int limit) {
    return 'Un sticker tiene que ocupar menos de $limit KB.';
  }

  @override
  String failureStickerTooWide(int limit) {
    return 'Un sticker puede tener como máximo $limit×$limit píxeles.';
  }

  @override
  String failureStickerTooSmall(int limit) {
    return 'Un sticker tiene que tener al menos $limit×$limit píxeles.';
  }

  @override
  String get failureStickerPackFull =>
      'Este paquete está lleno. Quita algo para hacer sitio.';

  @override
  String get failureStickerTooManyPacks =>
      'Tienes tantos paquetes como Privio admite. Borra uno para crear otro.';

  @override
  String get failureStickerPackNotFound => 'Ese paquete ya no existe.';

  @override
  String get failureStickerLinkDead =>
      'Este enlace ya no abre nada: se retiró o el paquete se borró.';

  @override
  String get settingsStickers => 'Stickers y emojis';

  @override
  String get stickersTitle => 'Stickers y emojis';

  @override
  String get stickersMyPacks => 'Mis paquetes';

  @override
  String get stickersInstalled => 'Añadidos';

  @override
  String get stickersEmptyTitle => 'Todavía no hay paquetes';

  @override
  String get stickersEmptyBody =>
      'Crea un paquete con tus propias imágenes o abre un enlace que te hayan enviado.';

  @override
  String get stickersNewPack => 'Paquete nuevo';

  @override
  String get stickersNewStickerPack => 'Paquete de stickers';

  @override
  String get stickersNewEmojiPack => 'Paquete de emojis';

  @override
  String get stickersNameLabel => 'Nombre';

  @override
  String get stickersNameHint => 'Cómo se llama este paquete';

  @override
  String get stickersCreate => 'Crear';

  @override
  String get stickersRename => 'Cambiar el nombre';

  @override
  String get stickersDelete => 'Borrar el paquete';

  @override
  String stickersDeleteConfirm(String title) {
    return '¿Borrar «$title»?';
  }

  @override
  String get stickersDeleteExplain =>
      'El enlace deja de funcionar y el paquete desaparece de tu selector. Los stickers que ya enviaste siguen viéndose en esas conversaciones.';

  @override
  String get stickersRemovePack => 'Quitar de mis paquetes';

  @override
  String get stickersAddPack => 'Añadir el paquete';

  @override
  String get stickersAlreadyAdded => 'Ya está en tus paquetes';

  @override
  String get stickersShare => 'Compartir este paquete';

  @override
  String get stickersSharedOn => 'Cualquiera con el enlace puede añadirlo';

  @override
  String get stickersSharedOff => 'Privado. Solo tú lo ves.';

  @override
  String get stickersShareExplain =>
      'Un paquete es privado hasta que lo compartes. Las imágenes de los stickers no están cifradas: un enlace es para gente que no tiene ninguna clave tuya, así que quien tenga el enlace —y también este servidor— puede verlas. Retirar el enlace impide que se añadan nuevas personas; no se lo quita a quien ya lo tiene.';

  @override
  String get stickersCopyLink => 'Copiar el enlace';

  @override
  String get stickersLinkCopied => 'Enlace copiado';

  @override
  String get stickersWithdrawLink => 'Retirar el enlace';

  @override
  String get stickersNewLinkNote =>
      'Compartir otra vez crea un enlace nuevo e invalida el anterior.';

  @override
  String get stickersAddItem => 'Añadir una imagen';

  @override
  String get stickersItemEmoji => 'Emoji para este';

  @override
  String get stickersItemEmojiWhy =>
      'A qué corresponde: lo que muestra en su lugar una app que no tiene este paquete, y cómo lo encuentras después.';

  @override
  String get stickersEmptyPack => 'Este paquete todavía está vacío.';

  @override
  String stickersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count imágenes',
      one: '1 imagen',
      zero: 'Vacío',
    );
    return '$_temp0';
  }

  @override
  String get stickersRemoveItem => 'Quitar';

  @override
  String get stickersReorderHint => 'Mantén pulsado y arrastra para reordenar.';

  @override
  String get stickersCropTitle => 'Recortar';

  @override
  String get stickersCropHint =>
      'Arrastra y pellizca para elegir el cuadrado. Se conserva la transparencia.';

  @override
  String get stickersUse => 'Usar';

  @override
  String get stickersPreviewTitle => 'Paquete de stickers';

  @override
  String get stickersOpenLinkTitle => 'Abrir un enlace de paquete';

  @override
  String get stickersOpenLinkHint =>
      'Pega el enlace o el código que te hayan enviado.';

  @override
  String get stickersOpen => 'Abrir';

  @override
  String get stickersKindSticker => 'Stickers';

  @override
  String get stickersKindEmoji => 'Emojis propios';

  @override
  String get stickersPickFailed => 'No se pudo abrir esa imagen.';

  @override
  String get notificationsIphoneNote =>
      'Puedes gestionar las notificaciones de Privio en los ajustes del iPhone.';

  @override
  String get notificationsOpenIphoneSettings => 'Abrir ajustes del iPhone';

  @override
  String get notificationsSettingsFailed =>
      'No se pudieron abrir los ajustes. Abre la app Ajustes y selecciona Privio.';

  @override
  String get pickerEmoji => 'Emojis';

  @override
  String get pickerStickers => 'Stickers';

  @override
  String get pickerMine => 'Míos';

  @override
  String get pickerFavourites => 'Favoritos';

  @override
  String get pickerRecent => 'Usados hace poco';

  @override
  String get pickerNoStickers => 'Todavía no hay paquetes de stickers.';

  @override
  String get pickerNoCustomEmoji => 'Todavía no hay emojis propios.';

  @override
  String get pickerManagePacks => 'Gestionar paquetes';

  @override
  String get pickerAddFavourite => 'Añadir a favoritos';

  @override
  String get pickerRemoveFavourite => 'Quitar de favoritos';

  @override
  String get pickerOpenPack => 'Abrir el paquete';

  @override
  String stickerFromPack(String title) {
    return 'Sticker de «$title»';
  }

  @override
  String get stickerPackGone => 'Este paquete no está disponible para ti.';

  @override
  String get chatSticker => 'Sticker';

  @override
  String get pickerOpenTooltip => 'Stickers y emojis';

  @override
  String get failurePhoneInvalid =>
      'Ese no es un número de teléfono que PRIVIO pueda usar. Incluye el prefijo del país, por ejemplo +34.';

  @override
  String get failurePhoneSmsUnavailable =>
      'Este servidor todavía no puede enviar SMS, así que aquí no se puede verificar un número. Puedes seguir usando PRIVIO sin él.';

  @override
  String get failurePhoneDiscoveryUnavailable =>
      'En este servidor la búsqueda de contactos está desactivada.';

  @override
  String get failurePhoneWrongCode => 'Ese código no es correcto.';

  @override
  String get failurePhoneCodeExpired =>
      'Ese código ha caducado. Pide uno nuevo.';

  @override
  String get failurePhoneTooManyAttempts =>
      'Demasiados códigos incorrectos. Pide uno nuevo.';

  @override
  String get failurePhoneTooManySends =>
      'PRIVIO ha enviado ese código todas las veces que lo hace. Inténtalo más tarde.';

  @override
  String get failurePhoneResendTooSoon =>
      'Espera un momento antes de pedir otro código.';

  @override
  String get failurePhoneNoVerification => 'Pide primero un código.';

  @override
  String get failurePhoneUnchanged =>
      'Ese número ya está verificado en esta cuenta.';

  @override
  String get failurePhoneNotLinked =>
      'En esta cuenta no hay ningún número verificado.';

  @override
  String get failurePhoneLookupBudgetSpent =>
      'PRIVIO ha comparado hoy todos los números que compara para esta cuenta. Inténtalo mañana.';

  @override
  String get failureContactsPermissionDenied =>
      'PRIVIO no tiene acceso a tus contactos. Puedes seguir añadiendo personas con su PRIVIO ID o un enlace de invitación.';

  @override
  String get channelVerifiedTooltip => 'Canal oficial de PRIVIO';

  @override
  String get phoneFieldLabel => 'Número de teléfono (opcional)';

  @override
  String get phoneFieldHint => 'Número de teléfono (opcional)';

  @override
  String get phoneFieldExplain =>
      'Vincula tu número de teléfono para que tus contactos puedan encontrarte. También puedes usar PRIVIO sin número de teléfono.';

  @override
  String get phoneCountryCode => 'Prefijo del país';

  @override
  String get phoneVerifyTitle => 'Confirma tu número';

  @override
  String phoneVerifySent(String hint) {
    return 'Hemos enviado un código a $hint.';
  }

  @override
  String get phoneVerifyCode => 'Código de seis dígitos';

  @override
  String get phoneVerifyConfirm => 'Confirmar';

  @override
  String get phoneVerifyResend => 'Enviar un código nuevo';

  @override
  String get phoneVerifySkip => 'Continuar sin número';

  @override
  String phoneVerifyStub(String code) {
    return 'Servidor de desarrollo: no se ha enviado ningún SMS. El código es $code.';
  }

  @override
  String get privacyPhoneSection => 'Número de teléfono y contactos';

  @override
  String get phoneAdd => 'Añadir un número de teléfono';

  @override
  String get phoneChange => 'Cambiar el número';

  @override
  String get phoneRemove => 'Quitar el número';

  @override
  String get phoneRemoveExplain =>
      'Se borran el número y el vínculo que el servidor guarda para encontrarte. Tus chats no se tocan.';

  @override
  String get phoneDiscoverable => 'Que me encuentren por mi número de teléfono';

  @override
  String get phoneDiscoverableExplain =>
      'Desactivado mientras no lo actives. Cuando está activado, quien tenga tu número en sus contactos ve tu cuenta de PRIVIO.';

  @override
  String get phoneContactSync => 'Sincronizar los contactos del dispositivo';

  @override
  String get phoneContactSyncExplain =>
      'Desactivado mientras no lo actives. PRIVIO lee los números de teléfono de tus contactos, convierte cada uno en un valor ilegible en este dispositivo y pregunta al servidor cuáles pertenecen a una cuenta de PRIVIO. Los nombres, las notas y la propia agenda nunca se envían ni se guardan en el servidor.';

  @override
  String get phoneSyncNow => 'Comparar contactos ahora';

  @override
  String phoneSyncFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personas encontradas.',
      one: '1 persona encontrada.',
      zero:
          'Nadie de tus contactos está en PRIVIO, o nadie ha activado que lo encuentren.',
    );
    return '$_temp0';
  }

  @override
  String get phoneImportedRemove => 'Quitar los contactos importados';

  @override
  String get phoneImportedRemoveExplain =>
      'Quita solo a las personas añadidas por la comparación. Tus chats con ellas se mantienen.';

  @override
  String get phoneNotLinkedYet => 'Ningún número vinculado';
}
