import 'dart:math' as math;

/// Every key on the pad.
enum CalculatorKey {
  zero('0'),
  one('1'),
  two('2'),
  three('3'),
  four('4'),
  five('5'),
  six('6'),
  seven('7'),
  eight('8'),
  nine('9'),
  decimal('.'),
  add('+'),
  subtract('−'),
  multiply('×'),
  divide('÷'),
  equals('='),
  percent('%'),
  negate('±'),
  clear('AC');

  const CalculatorKey(this.label);

  final String label;

  bool get isDigit => index <= CalculatorKey.nine.index;

  int get digit => index;

  bool get isOperator =>
      this == CalculatorKey.add ||
      this == CalculatorKey.subtract ||
      this == CalculatorKey.multiply ||
      this == CalculatorKey.divide;
}

/// A calculator that calculates.
///
/// The disguise is only a disguise if it survives being used: someone who picks
/// up the phone and works out a tip has to get the right answer, and a keypad
/// that shows the digits back without adding them is a tell. So this is a real
/// immediate-execution calculator — the model every phone ships — written as a
/// plain object with no widgets in it, because arithmetic is where the edge
/// cases are and they are worth testing.
class Calculator {
  /// What the screen shows.
  String get display => _display;
  String _display = '0';

  /// The digits typed since the last clear or operator, exactly as typed.
  ///
  /// This, and not [display], is what a secret code is compared against: the
  /// display is formatted — grouped, trimmed — and a code should be matched
  /// against what someone's fingers did.
  String get entry => _entry;
  String _entry = '';

  /// What is on the screen, with the formatting taken back off.
  ///
  /// The display is grouped — `1,234` — and a code is not. This is what a
  /// passcode is compared against after `=`, so that any sum reaching the right
  /// answer opens Privio and the digits of the code never have to appear on
  /// screen at all.
  String get result => _display.replaceAll(',', '');

  /// True while nothing has been typed and no sum is in progress, which is when
  /// the clear key says AC rather than C.
  bool get isCleared => _entry.isEmpty && _pending == null && _display == '0';

  double _accumulator = 0;
  CalculatorKey? _pending;

  /// The last operation and operand, so pressing `=` again repeats it — which
  /// every calculator does and its absence is noticeable.
  CalculatorKey? _repeatOperator;
  double? _repeatOperand;

  bool _error = false;

  void press(CalculatorKey key) {
    if (_error && key != CalculatorKey.clear) return;

    switch (key) {
      case CalculatorKey.clear:
        _clear();
      case CalculatorKey.decimal:
        _typeDecimal();
      case CalculatorKey.negate:
        _negate();
      case CalculatorKey.percent:
        _percent();
      case CalculatorKey.equals:
        _equals();
      default:
        if (key.isDigit) {
          _typeDigit(key.digit);
        } else if (key.isOperator) {
          _operator(key);
        }
    }
  }

  /// Types a code without disturbing anything, for the tests and for entering
  /// a passcode from somewhere other than the pad.
  void type(String digits) {
    for (final character in digits.split('')) {
      final value = int.tryParse(character);
      if (value != null) press(CalculatorKey.values[value]);
    }
  }

  void _clear() {
    // One press clears the entry, the second clears the sum — the AC/C
    // behaviour of the pad this is imitating.
    if (_entry.isNotEmpty || _display != '0') {
      _entry = '';
      _percentValue = null;
      _display = '0';
      if (_pending == null) _reset();
      return;
    }
    _reset();
  }

  void _reset() {
    _percentValue = null;
    _entry = '';
    _display = '0';
    _accumulator = 0;
    _pending = null;
    _repeatOperator = null;
    _repeatOperand = null;
    _error = false;
  }

  void _typeDigit(int digit) {
    _percentValue = null;
    if (_entry.replaceAll('.', '').replaceAll('-', '').length >= _maxDigits) return;
    if (_entry.isEmpty && digit == 0) {
      _entry = '0';
      _display = '0';
      return;
    }
    if (_entry == '0') _entry = '';
    _entry = '$_entry$digit';
    _display = _format(_asNumber(_entry), typing: true);
  }

  void _typeDecimal() {
    _percentValue = null;
    if (_entry.contains('.')) return;
    _entry = _entry.isEmpty ? '0.' : '$_entry.';
    _display = _entry;
  }

  void _negate() {
    if (_entry.isEmpty) {
      final value = -_asNumber(_display);
      _display = _format(value);
      _accumulator = value;
      return;
    }
    _entry = _entry.startsWith('-') ? _entry.substring(1) : '-$_entry';
    _display = _format(_asNumber(_entry), typing: true);
  }

  /// Percent, as the phone means it rather than as arithmetic means it.
  ///
  /// After a `+` or a `−` it is a percentage *of the running total*, so
  /// 200 + 10 % = is 220 — the tip calculation the key exists for. Anywhere
  /// else it is plainly a hundredth. This is what the pads being imitated do,
  /// and matching them matters more here than being consistent.
  void _percent() {
    final fraction = _current / 100;
    final relative = _pending == CalculatorKey.add || _pending == CalculatorKey.subtract;
    final value = relative ? _accumulator * fraction : fraction;
    _entry = '';
    _percentValue = value;
    _display = _format(value);
    if (_pending == null) _accumulator = value;
  }

  /// The operand `%` produced, used by the next operator or by `=` in place of
  /// what was typed. Cleared whenever anything else is typed.
  double? _percentValue;

  void _operator(CalculatorKey key) {
    if (_pending != null && _entry.isNotEmpty) {
      final result = _apply(_pending!, _accumulator, _current);
      if (result == null) return _fail();
      _accumulator = result;
      _display = _format(result);
    } else {
      _accumulator = _current;
    }
    _entry = '';
    _percentValue = null;
    _pending = key;
  }

  void _equals() {
    final pending = _pending;
    if (pending != null) {
      final operand = _percentValue ?? (_entry.isEmpty ? _accumulator : _current);
      final result = _apply(pending, _accumulator, operand);
      if (result == null) return _fail();
      _repeatOperator = pending;
      _repeatOperand = operand;
      _accumulator = result;
      _display = _format(result);
      _pending = null;
      _entry = '';
      return;
    }
    // Pressing equals again repeats the last operation on the running total.
    final repeat = _repeatOperator;
    final operand = _repeatOperand;
    if (repeat != null && operand != null) {
      final result = _apply(repeat, _current, operand);
      if (result == null) return _fail();
      _accumulator = result;
      _display = _format(result);
      _entry = '';
    }
  }

  double get _current =>
      _percentValue ?? (_entry.isEmpty ? _asNumber(_display) : _asNumber(_entry));

  void _fail() {
    _error = true;
    _display = 'Error';
    _entry = '';
    _pending = null;
  }

  static double? _apply(CalculatorKey operator, double left, double right) => switch (operator) {
        CalculatorKey.add => left + right,
        CalculatorKey.subtract => left - right,
        CalculatorKey.multiply => left * right,
        // Not an exception and not infinity: the pad this imitates says Error,
        // and a disguise that says something else is a disguise that is asked
        // about.
        CalculatorKey.divide => right == 0 ? null : left / right,
        _ => null,
      };

  static double _asNumber(String raw) =>
      double.tryParse(raw.replaceAll(',', '').replaceAll('−', '-')) ?? 0;

  /// How many digits fit before the display would have to shrink.
  static const int _maxDigits = 9;

  /// Formats the way a phone's calculator does: grouped thousands, no trailing
  /// `.0`, and exponent notation once a number outruns the screen.
  static String _format(double value, {bool typing = false}) {
    if (value.isNaN || value.isInfinite) return 'Error';
    if (value.abs() >= math.pow(10, _maxDigits)) {
      return value.toStringAsExponential(3).replaceAll('e+', 'e');
    }

    final whole = value.truncateToDouble() == value;
    var text = whole
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(_maxDigits - value.abs().truncate().toString().length);
    if (!whole) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    }

    final negative = text.startsWith('-');
    if (negative) text = text.substring(1);
    final parts = text.split('.');
    final grouped = _group(parts.first);
    final joined = parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
    return negative ? '-$joined' : joined;
  }

  static String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
