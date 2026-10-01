import 'package:shared_preferences/shared_preferences.dart';

/// Quantize integer grams/cents before billing; never round display alone.
class SalePrecision {
  final int weightDigits;
  final int moneyDigits;
  final bool truncate;
  const SalePrecision({
    this.weightDigits = 3,
    this.moneyDigits = 2,
    this.truncate = false,
  });
  static SalePrecision fromPrefs(SharedPreferences p) => SalePrecision(
    weightDigits: (p.getInt('weight_digits') ?? 3).clamp(0, 3),
    moneyDigits: (p.getInt('money_digits') ?? 2).clamp(0, 2),
    truncate: p.getString('decimal_mode') == 'truncate',
  );
  int _power(int n) => [1, 10, 100, 1000][n];
  int _divide(int numerator, int denominator) {
    final sign = numerator < 0 ? -1 : 1;
    return sign *
        ((numerator.abs() + (truncate ? 0 : denominator ~/ 2)) ~/ denominator);
  }

  double weight(double raw) =>
      _divide((raw * 1000).round(), _power(3 - weightDigits)) /
      _power(weightDigits);
  double money(double raw) =>
      _divide((raw * 100).round(), _power(2 - moneyDigits)) /
      _power(moneyDigits);
  double subtotal({
    required bool byWeight,
    required double quantity,
    required double price,
  }) {
    final cents = (money(price) * 100).round();
    final numerator = byWeight
        ? (weight(quantity) * 1000).round() * cents
        : quantity.round() * cents * 1000;
    return _divide(numerator, 1000 * _power(2 - moneyDigits)) /
        _power(moneyDigits);
  }

  String weightText(double raw) => weight(raw).toStringAsFixed(weightDigits);
  String moneyText(double raw) => money(raw).toStringAsFixed(moneyDigits);
}
