import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_state.dart';
import '../disguise/calculator.dart';
import '../disguise/skin.dart';
import '../theme/privio_colors.dart';

/// Screens 15–16: the disguise.
///
/// What a locked Privio opens to when the disguise is on. It is a working
/// calculator and nothing else on the surface: no logo, no hint, no "enter
/// your code" — the whole value is that there is nothing here to ask about.
///
/// Typing the passcode and pressing `=` opens Privio. Typing the duress code
/// and pressing `=` does what the duress code always does. Any other sum is
/// a sum.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({required this.skin, super.key});

  final CalculatorSkin skin;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  /// Five rows of keys against four columns, plus the gaps between them.
  static const double _padRatio = 5.15 / 4;

  final Calculator _calculator = Calculator();
  bool _checking = false;

  Future<void> _press(CalculatorKey key) async {
    if (_checking) return;

    // The sum happens first, always. A wrong code is not a wrong code here: it
    // is a number, and the calculator adds it up — no shake, no counter, no
    // pause that says something was checked. That pause is the only thing a
    // disguise really has to avoid.
    setState(() => _calculator.press(key));
    unawaited(HapticFeedback.selectionClick());
    if (key != CalculatorKey.equals) return;

    // Then the answer is compared, not the keys. Typing the code and pressing
    // `=` works because a number on its own evaluates to itself — and so does
    // any sum that reaches it, which means the code itself never has to appear
    // on the screen for anyone standing nearby to read.
    final answer = _calculator.result;
    if (answer.isEmpty || answer == '0') return;

    _checking = true;
    final opened = await PrivioScope.of(context).unlockWithPasscode(answer);
    if (!mounted) return;
    _checking = false;
    // Right code: the app is already switching away from this screen. Wrong
    // one: the answer is on the screen, which is where it would be anyway.
    if (opened) return;
  }

  @override
  Widget build(BuildContext context) {
    final samsung = widget.skin == CalculatorSkin.samsung;
    final keypad = _Keypad(
      skin: widget.skin,
      cleared: _calculator.isCleared,
      onPress: _press,
    );
    final box = MediaQuery.sizeOf(context);
    final padHeight = math.min(box.width * _padRatio, box.height * 0.62);

    return Scaffold(
      backgroundColor: samsung ? const Color(0xFF1B1B1D) : Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.xl),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomRight,
                    child: Text(
                      _calculator.display,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: samsung ? 62 : 76,
                        fontWeight: samsung ? FontWeight.w400 : FontWeight.w300,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: PrivioSpacing.lg),
            // The pad is as wide as the screen and as tall as that makes it,
            // until the screen is too short — then it gives up height rather
            // than overflowing. Sized per key it ran 446 pixels past the bottom
            // of a short screen, and a calculator with its last row cut off is
            // not a disguise. Sized purely from the leftover space it came out
            // narrow, with side margins no phone's calculator has.
            SizedBox(height: padHeight, child: keypad),
            SizedBox(height: samsung ? PrivioSpacing.lg : PrivioSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// The four-by-five grid both skins share.
///
/// One layout, two sets of clothes: the arithmetic and the key positions are
/// the same on every phone, and only the shapes and colours differ.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.skin, required this.cleared, required this.onPress});

  final CalculatorSkin skin;
  final bool cleared;
  final void Function(CalculatorKey) onPress;

  static const List<List<CalculatorKey>> _rows = [
    [CalculatorKey.clear, CalculatorKey.negate, CalculatorKey.percent, CalculatorKey.divide],
    [CalculatorKey.seven, CalculatorKey.eight, CalculatorKey.nine, CalculatorKey.multiply],
    [CalculatorKey.four, CalculatorKey.five, CalculatorKey.six, CalculatorKey.subtract],
    [CalculatorKey.one, CalculatorKey.two, CalculatorKey.three, CalculatorKey.add],
    [CalculatorKey.zero, CalculatorKey.decimal, CalculatorKey.equals],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PrivioSpacing.md),
      child: Column(
        children: [
          for (final row in _rows)
            Expanded(
              child: Row(
                children: [
                  for (final key in row)
                    Expanded(
                      // The zero key is double width on both phones, which is
                      // the one place the grid is not a grid.
                      flex: key == CalculatorKey.zero ? 2 : 1,
                      child: _Key(
                        skin: skin,
                        label: key == CalculatorKey.clear && !cleared ? 'C' : key.label,
                        kind: _kindOf(key),
                        onTap: () => onPress(key),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static _KeyKind _kindOf(CalculatorKey key) {
    if (key.isOperator || key == CalculatorKey.equals) return _KeyKind.operator;
    if (key == CalculatorKey.clear ||
        key == CalculatorKey.negate ||
        key == CalculatorKey.percent) {
      return _KeyKind.function;
    }
    return _KeyKind.digit;
  }
}

enum _KeyKind { digit, function, operator }

class _Key extends StatelessWidget {
  const _Key({
    required this.skin,
    required this.label,
    required this.kind,
    required this.onTap,
  });

  final CalculatorSkin skin;
  final String label;
  final _KeyKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iphone = skin == CalculatorSkin.iphone;
    final background = switch (kind) {
      _KeyKind.digit => iphone ? const Color(0xFF333333) : const Color(0xFF2C2C2E),
      _KeyKind.function => iphone ? const Color(0xFFA5A5A5) : const Color(0xFF3A3A3C),
      _KeyKind.operator => iphone ? PrivioColors.calculatorOperator : PrivioColors.accent,
    };
    final foreground = switch (kind) {
      _KeyKind.function when iphone => Colors.black,
      _KeyKind.operator when !iphone => Colors.black,
      _ => Colors.white,
    };

    return Padding(
      padding: const EdgeInsets.all(PrivioSpacing.xs),
      child: Material(
          color: background,
          shape: iphone
              ? const StadiumBorder()
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: InkWell(
            onTap: onTap,
            customBorder: iphone
                ? const StadiumBorder()
                : RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(PrivioSpacing.xs),
                child: Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 30,
                    fontWeight: iphone ? FontWeight.w400 : FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
