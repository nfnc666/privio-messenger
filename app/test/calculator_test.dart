import 'package:flutter_test/flutter_test.dart';
import 'package:privio/disguise/calculator.dart';

/// Presses a sequence written the way someone would say it: `'12+34='`.
Calculator run(String keys) {
  final calculator = Calculator();
  for (final character in keys.split('')) {
    calculator.press(switch (character) {
      '+' => CalculatorKey.add,
      '-' => CalculatorKey.subtract,
      '*' => CalculatorKey.multiply,
      '/' => CalculatorKey.divide,
      '=' => CalculatorKey.equals,
      '.' => CalculatorKey.decimal,
      '%' => CalculatorKey.percent,
      '~' => CalculatorKey.negate,
      'C' => CalculatorKey.clear,
      _ => CalculatorKey.values[int.parse(character)],
    },);
  }
  return calculator;
}

void main() {
  group('the disguise calculates', () {
    test('it adds, subtracts, multiplies and divides', () {
      expect(run('12+34=').display, '46');
      expect(run('50-8=').display, '42');
      expect(run('6*7=').display, '42');
      expect(run('84/2=').display, '42');
    });

    test('operations chain the way a phone does, left to right', () {
      // Not precedence: the pad this imitates computes as you go, so 2+3×4 is
      // 20, and matching that matters more than being a better calculator.
      expect(run('2+3*4=').display, '20');
      expect(run('10-2-3=').display, '5');
    });

    test('an operator mid-sum shows the running total', () {
      final calculator = run('7+8+');
      expect(calculator.display, '15', reason: 'the total so far, before the next number');
    });

    test('decimals work and do not accumulate points', () {
      expect(run('1.5+2.25=').display, '3.75');
      expect(run('1..5').display, '1.5', reason: 'the second point is ignored');
      expect(run('.5+.5=').display, '1');
    });

    test('equals again repeats the last operation', () {
      final calculator = run('2+3=');
      expect(calculator.display, '5');
      calculator.press(CalculatorKey.equals);
      expect(calculator.display, '8');
      calculator.press(CalculatorKey.equals);
      expect(calculator.display, '11');
    });

    test('dividing by zero says Error, and clearing recovers', () {
      final calculator = run('9/0=');
      expect(calculator.display, 'Error');

      calculator.press(CalculatorKey.five);
      expect(calculator.display, 'Error', reason: 'nothing works until it is cleared');

      calculator.press(CalculatorKey.clear);
      expect(calculator.display, '0');
      calculator.press(CalculatorKey.seven);
      expect(calculator.display, '7');
    });

    test('percent means what it means on a phone', () {
      expect(run('50%').display, '0.5', reason: 'on its own, a hundredth');
      expect(
        run('200+10%=').display,
        '220',
        reason: 'after + it is ten percent of the total — the tip this key is for',
      );
      expect(run('200-10%=').display, '180');
      expect(run('200*50%=').display, '100', reason: 'after x it is plainly a half');
    });

    test('sign toggles both ways', () {
      expect(run('5~').display, '-5');
      expect(run('5~~').display, '5');
      expect(run('5~+3=').display, '-2');
    });

    test('thousands are grouped, as they are on a phone', () {
      expect(run('1000*1000=').display, '1,000,000');
      expect(run('999+1=').display, '1,000');
    });

    test('a number too big for the screen goes exponential rather than wrapping', () {
      expect(run('999999999*999999999=').display, contains('e'));
    });

    test('clear empties the entry, then the sum', () {
      final calculator = run('12+34');
      calculator.press(CalculatorKey.clear);
      expect(calculator.display, '0');
      calculator.press(CalculatorKey.five);
      calculator.press(CalculatorKey.equals);
      expect(calculator.display, '17', reason: 'C dropped the 34, not the 12+');
    });

    test('leading zeroes do not pile up', () {
      expect(run('000').display, '0');
      expect(run('007').display, '7');
    });

    test('the entry is what the fingers typed, not what the screen shows', () {
      final calculator = run('1234');
      expect(calculator.display, '1,234');
      expect(
        calculator.entry,
        '1234',
        reason: 'a passcode is matched against this, so grouping cannot break it',
      );
    });
  });
}
