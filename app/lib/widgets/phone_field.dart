import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/phone_number.dart';
import '../l10n/app_localizations.dart';
import '../theme/privio_colors.dart';

/// A phone number field: a country code beside the rest of the number.
///
/// Two things this deliberately does not do.
///
/// It **never reads the device's own number.** Filling the field from the SIM
/// would be attaching somebody to a number they were not asked about, and on a
/// dual-SIM phone it would often be the wrong one. The field starts empty.
///
/// It **never blocks.** Empty is a complete answer — an account without a phone
/// number is an account — so there is no validation that stops anything, and
/// [value] returns null for empty exactly as it does for nonsense. The caller
/// decides what that means, and in registration it means "carry on".
class PhoneField extends StatefulWidget {
  const PhoneField({
    required this.controller,
    super.key,
    this.onChanged,
    this.autofocus = false,
  });

  /// Holds the local part — what comes after the country code.
  final TextEditingController controller;

  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<PhoneField> createState() => PhoneFieldState();
}

class PhoneFieldState extends State<PhoneField> {
  /// The calling code, without the `+`.
  String _code = PhoneNumbers.commonCountries.first.code;

  /// Everything typed, as one E.164 string, or null when it is not a number.
  ///
  /// Null covers both "empty" and "not a number", because the field treats them
  /// the same: neither is something to send, and neither stops anything.
  PhoneNumber? get value {
    final local = widget.controller.text.trim();
    if (local.isEmpty) return null;
    return PhoneNumbers.normalise('+$_code$local');
  }

  /// Whether anything has been typed at all, which is what a screen asks to
  /// decide between "they skipped it" and "they typed something wrong".
  bool get isEmpty => widget.controller.text.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountryButton(
          code: _code,
          onPicked: (code) => setState(() => _code = code),
        ),
        const SizedBox(width: PrivioSpacing.sm),
        Expanded(
          child: TextField(
            controller: widget.controller,
            autofocus: widget.autofocus,
            // The number pad, with the characters people paste from a contact
            // card. `phone` rather than `number` so a phone shows its dialling
            // keyboard rather than a calculator's.
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 \-()]')),
              LengthLimitingTextInputFormatter(20),
            ],
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: text.phoneFieldLabel,
              hintText: text.phoneFieldHint,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// The country code, as a button that opens a short list.
///
/// A short list and a typed code rather than every country on earth: the field
/// accepts a pasted `+…` number too, so this is a convenience, and a scroll
/// through two hundred entries is a worse one.
class _CountryButton extends StatelessWidget {
  const _CountryButton({required this.code, required this.onPicked});

  final String code;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final country = PhoneNumbers.commonCountries
        .cast<({String code, String name, String flag})?>()
        .firstWhere((entry) => entry!.code == code, orElse: () => null);

    return Semantics(
      label: text.phoneCountryCode,
      child: OutlinedButton(
        onPressed: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            backgroundColor: PrivioColors.surface,
            builder: (context) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in PhoneNumbers.commonCountries)
                    ListTile(
                      leading: Text(entry.flag, style: const TextStyle(fontSize: 22)),
                      title: Text(entry.name),
                      trailing: Text('+${entry.code}'),
                      selected: entry.code == code,
                      onTap: () => Navigator.of(context).pop(entry.code),
                    ),
                ],
              ),
            ),
          );
          if (picked != null) onPicked(picked);
        },
        child: Text('${country?.flag ?? ''} +$code'),
      ),
    );
  }
}
