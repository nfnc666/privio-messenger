import '../models/security_event.dart';
import 'app_localizations.dart';

/// Turning a stored [SecurityEvent] into a sentence, in the reader's language.
///
/// The other half of storing events rather than sentences, exactly as
/// `notice_text.dart` is for the chat: the device that saw the thing happen
/// records the fact, and the words are built at the moment they are drawn. A
/// log written last year on a phone set to English reads in German today if
/// that is what the app is set to now.
String describeSecurityEvent(AppText text, SecurityEvent event) {
  // A name the user already knows, or a neutral stand-in. Never an account id
  // and never a phone number — see the note on [SecurityEvent.subject].
  final who = event.subject;
  return switch (event.kind) {
    SecurityEventKind.deviceAdded =>
      text.securityEventDeviceAdded(who ?? text.securityEventADevice),
    SecurityEventKind.deviceRemoved =>
      text.securityEventDeviceRemoved(who ?? text.securityEventADevice),
    SecurityEventKind.passwordChanged => text.securityEventPasswordChanged,
    SecurityEventKind.twoFactorEnabled => text.securityEventTwoFactorOn,
    SecurityEventKind.twoFactorDisabled => text.securityEventTwoFactorOff,
    SecurityEventKind.backupRestored => text.securityEventBackupRestored,
    SecurityEventKind.phoneLinked => text.securityEventPhoneLinked,
    SecurityEventKind.phoneRemoved => text.securityEventPhoneRemoved,
    SecurityEventKind.proxyEnabled => text.securityEventProxyOn,
    SecurityEventKind.proxyDisabled => text.securityEventProxyOff,
    SecurityEventKind.contactKeyChanged =>
      text.securityEventKeyChanged(who ?? text.securityEventAContact),
    SecurityEventKind.contactVerified =>
      text.securityEventContactVerified(who ?? text.securityEventAContact),
    SecurityEventKind.contactVerificationCleared =>
      text.securityEventVerificationCleared(who ?? text.securityEventAContact),
    SecurityEventKind.screenLockChanged => text.securityEventScreenLock,
    SecurityEventKind.duressCodeChanged => text.securityEventDuressCode,
  };
}
