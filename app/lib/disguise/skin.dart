/// Which calculator the disguise imitates.
///
/// Two, because the disguise works by being unremarkable: a calculator that
/// does not look like the one the phone already ships is the thing someone
/// notices. Both drive the same [Calculator]; only the keys differ.
enum CalculatorSkin {
  /// Circular keys, orange operator column on the right.
  iphone,

  /// Rounded squares, accent operators, and a lighter ground.
  samsung;

  static CalculatorSkin? parse(String? raw) {
    for (final skin in CalculatorSkin.values) {
      if (skin.name == raw) return skin;
    }
    return null;
  }

  String get label => switch (this) {
        CalculatorSkin.iphone => 'iPhone',
        CalculatorSkin.samsung => 'Samsung',
      };

  String get description => switch (this) {
        CalculatorSkin.iphone => 'Circular keys, orange operators.',
        CalculatorSkin.samsung => 'Rounded keys, green operators.',
      };
}
