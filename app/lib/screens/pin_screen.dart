import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../theme/privio_colors.dart';

/// Screen 4: the local PIN lock, with biometrics as the shortcut.
///
/// This guards the on-device database. It is not the account password and it
/// never leaves the phone.
class PinScreen extends StatefulWidget {
  const PinScreen({super.key, this.pinLength = 4});

  final int pinLength;

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _entered = '';
  bool _error = false;

  @override
  void initState() {
    super.initState();
    // Offer Face ID immediately, the way the platform messengers do.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  Future<void> _tryBiometrics() async {
    if (!mounted) return;
    await PrivioScope.of(context).unlockWithBiometrics();
  }

  Future<void> _append(String digit) async {
    if (_entered.length >= widget.pinLength) return;
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length == widget.pinLength) await _submit();
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _submit() async {
    final state = PrivioScope.of(context);
    final ok = await state.unlockWithPin(_entered);
    if (!ok && mounted) {
      // Wrong PIN: shake-free, silent, and no hint about how wrong it was.
      await HapticFeedback.heavyImpact();
      setState(() {
        _entered = '';
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biometrics = PrivioScope.of(context).biometricsAvailable;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            Text('Enter your PIN', style: theme.textTheme.titleLarge),
            const SizedBox(height: PrivioSpacing.xxl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.pinLength; i++)
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
            _Keypad(onDigit: _append, onBackspace: _backspace),
            const SizedBox(height: PrivioSpacing.xl),
            if (biometrics)
              IconButton(
                onPressed: _tryBiometrics,
                iconSize: 30,
                color: PrivioColors.accent,
                icon: const Icon(Icons.fingerprint_rounded),
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
