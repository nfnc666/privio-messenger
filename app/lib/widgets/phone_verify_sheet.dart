import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/phone_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/failure_text.dart';
import '../theme/privio_colors.dart';

/// Asks for the six-digit code, and links the number if it is right.
///
/// Returns true when a number was linked, false when the person backed out.
/// **Backing out is a first-class answer**: cancelling, a code that never
/// arrives, a server that cannot send texts — all of them end with no number
/// attached and nothing else changed, because an account without a number is a
/// complete account.
Future<bool> showPhoneVerifySheet(BuildContext context, PhoneController controller) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PrivioColors.surface,
      builder: (context) => _PhoneVerifySheet(controller: controller),
    ) ??
    false;

class _PhoneVerifySheet extends StatefulWidget {
  const _PhoneVerifySheet({required this.controller});

  final PhoneController controller;

  @override
  State<_PhoneVerifySheet> createState() => _PhoneVerifySheetState();
}

class _PhoneVerifySheetState extends State<_PhoneVerifySheet> {
  final TextEditingController _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (await widget.controller.confirmCode(_code.text.trim()) && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final stub = widget.controller.stubCode;
        return Padding(
          padding: EdgeInsets.only(
            left: PrivioSpacing.xl,
            right: PrivioSpacing.xl,
            top: PrivioSpacing.xl,
            bottom: MediaQuery.of(context).viewInsets.bottom + PrivioSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(text.phoneVerifyTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: PrivioSpacing.sm),
              Text(
                text.phoneVerifySent(widget.controller.pendingHint ?? ''),
                style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.textTertiary),
              ),
              if (stub != null) ...[
                const SizedBox(height: PrivioSpacing.md),
                // Said in full rather than shown as a convenience: a server that
                // did not send a text has not verified anything, and the person
                // looking at this should know which of the two they are in.
                Container(
                  padding: const EdgeInsets.all(PrivioSpacing.md),
                  decoration: BoxDecoration(
                    color: PrivioColors.surfaceRaised,
                    borderRadius: const BorderRadius.all(PrivioRadius.card),
                    border: Border.all(color: PrivioColors.warning),
                  ),
                  child: Text(
                    text.phoneVerifyStub(stub),
                    style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.warning),
                  ),
                ),
              ],
              const SizedBox(height: PrivioSpacing.lg),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onSubmitted: (_) => _confirm(),
                decoration: InputDecoration(labelText: text.phoneVerifyCode, isDense: true),
              ),
              if (widget.controller.failure != null) ...[
                const SizedBox(height: PrivioSpacing.sm),
                Text(
                  widget.controller.failure!.words(text),
                  style: theme.textTheme.bodySmall?.copyWith(color: PrivioColors.danger),
                ),
              ],
              const SizedBox(height: PrivioSpacing.lg),
              FilledButton(
                onPressed: widget.controller.busy ? null : _confirm,
                child: Text(text.phoneVerifyConfirm),
              ),
              const SizedBox(height: PrivioSpacing.sm),
              TextButton(
                onPressed: widget.controller.busy
                    ? null
                    : () {
                        widget.controller.cancelVerification();
                        Navigator.of(context).pop(false);
                      },
                child: Text(text.commonCancel),
              ),
            ],
          ),
        );
      },
    );
  }
}
