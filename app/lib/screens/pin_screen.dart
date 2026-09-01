import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../core/passcode.dart';
import '../theme/privio_colors.dart';

/// Screen 4: the local lock.
///
/// It guards the on-device database. It is not the account password and it
/// never leaves the phone.
///
/// There is no biometric shortcut, and that is the design rather than a gap: a
/// face or a fingerprint is something a person can be held in front of or have
/// pressed onto a sensor, and in several places compelled by a court that could
/// not compel a passcode. A lock that a sleeping or unwilling owner opens is
/// not the lock this app is for.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key});

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final _phrase = TextEditingController();
  String _entered = '';
  bool _error = false;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _append(String digit, int length) async {
    if (_entered.length >= length) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length == length) await _submit(_entered);
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _submit(String passcode) async {
    if (passcode.isEmpty) return;
    final state = PrivioScope.of(context);
    final ok = await state.unlockWithPasscode(passcode);
    if (!ok && mounted) {
      // Wrong: shake-free, silent, and no hint about how wrong it was. The
      // duress code lands here too, by design.
      await HapticFeedback.heavyImpact();
      _phrase.clear();
      setState(() {
        _entered = '';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A device that somehow has a lock but no recorded shape gets the keypad:
    // it is what every lock was before the shapes existed.
    final kind = PrivioScope.of(context).passcodeKind ?? PasscodeKind.digits4;
    final length = kind.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Text(
              length == null ? 'Enter your passphrase' : 'Enter your passcode',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: PrivioSpacing.xxl),
            if (length == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
                child: TextField(
                  controller: _phrase,
                  obscureText: true,
                  autofocus: true,
                  onChanged: (_) {
                    if (_error) setState(() => _error = false);
                  },
                  onSubmitted: _submit,
                  decoration: InputDecoration(
                    hintText: 'Passphrase',
                    errorText: _error ? 'That is not it.' : null,
                  ),
                ),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < length; i++)
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: PrivioSpacing.sm),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _entered.length ? PrivioColors.accent : Colors.transparent,
                        border: Border.all(
                          color: _error
                              ? PrivioColors.danger
                              : i < _entered.length
                                  ? PrivioColors.accent
                                  : PrivioColors.surfaceHigh,
                          width: 1.5,
                        ),
                      ),
                    ),
                ],
              ),
            const Spacer(),
            if (length == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xxxl),
                child: FilledButton(
                  onPressed: () => _submit(_phrase.text),
                  child: const Text('Unlock'),
                ),
              )
            else
              _Keypad(
                onDigit: (digit) => _append(digit, length),
                onBackspace: _backspace,
              ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];

    return SizedBox(
      width: 280,
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: PrivioSpacing.lg,
        crossAxisSpacing: PrivioSpacing.xxl,
        children: [
          for (final key in keys)
            if (key.isEmpty)
              const SizedBox.shrink()
            else if (key == '<')
              _KeypadButton(
                onTap: onBackspace,
                child: const Icon(Icons.backspace_outlined, size: 22, color: PrivioColors.textSecondary),
              )
            else
              _KeypadButton(
                onTap: () => onDigit(key),
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: PrivioColors.textPrimary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PrivioColors.surface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Center(child: child)),
    );
  }
}
