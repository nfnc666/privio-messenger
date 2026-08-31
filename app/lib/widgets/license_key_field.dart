import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/license_key.dart';

/// The license key input, shared by the activation step at first start and the
/// License screen in Settings.
///
/// One widget rather than two, because a key typed in one place and a key typed
/// in the other have to reach the server in exactly the same shape.
class LicenseKeyField extends StatelessWidget {
  const LicenseKeyField({
    required this.controller,
    required this.enabled,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback? onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      enabled: enabled,
      inputFormatters: const [LicenseKeyFormatter()],
      onChanged: onChanged == null ? null : (_) => onChanged!(),
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: const InputDecoration(hintText: licenseKeyFormat),
    );
  }
}

/// Formats the field as `PRIVIO-XXXX-XXXX-XXXX-XXXX` while it is being typed,
/// folding Crockford aliases on the way in so an O typed for a zero is simply
/// shown as a zero rather than rejected later.
class LicenseKeyFormatter extends TextInputFormatter {
  const LicenseKeyFormatter();

  static const String _prefix = 'PRIVIO';

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text.toUpperCase().replaceAll(RegExp('[^0-9A-Z]'), '');
    // Backspace has to be able to leave. Holding the prefix on screen while
    // someone is deleting would put "PRIVIO-" back on every keystroke and make
    // the field impossible to clear — and then the next key typed would be
    // folded onto the leftover prefix.
    final deleting = newValue.text.length < oldValue.text.length;

    // Someone halfway through typing the prefix has typed none of the key yet.
    // Folding those characters as key body would turn the prefix's own I and O
    // into 1 and 0 — and because every keystroke is formatted again, the
    // "PR1V1" that produced would then stick in front of everything typed
    // after it. A key body can never contain an I, so nothing real is held
    // back by waiting to see whether the prefix is what is being typed.
    if (!deleting &&
        cleaned.isNotEmpty &&
        cleaned.length < _prefix.length &&
        _prefix.startsWith(cleaned)) {
      return TextEditingValue(
        text: cleaned,
        selection: TextSelection.collapsed(offset: cleaned.length),
      );
    }
    if (!deleting && cleaned == _prefix) {
      return const TextEditingValue(
        text: '$_prefix-',
        selection: TextSelection.collapsed(offset: _prefix.length + 1),
      );
    }

    final body = normaliseLicenseKey(cleaned);
    final capped =
        body.length > licenseKeyBodyLength ? body.substring(0, licenseKeyBodyLength) : body;
    final text = formatLicenseKey(capped);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
