import 'sale_precision.dart';
import 'menu_item.dart';

class CartItem {
  final MenuItem menuItem;
  final double weight; // kg（称重商品），或件数（固定价格商品）
  final double subtotal;
  final int weightDigits;
  final int moneyDigits;

  const CartItem({
    required this.menuItem,
    required this.weight,
    required this.subtotal,
    this.weightDigits = 3,
    this.moneyDigits = 2,
  });

  /// 称重精确到克、单价精确到分；每行金额按分四舍五入。
  static double saleSubtotal({
    required bool byWeight,
    required double quantity,
    required double price,
    int weightDigits = 3,
    int moneyDigits = 2,
    bool truncate = false,
  }) {
    final policy = SalePrecision(
      weightDigits: weightDigits,
      moneyDigits: moneyDigits,
      truncate: truncate,
    );
    return policy.subtotal(
      byWeight: byWeight,
      quantity: quantity,
      price: price,
    );
  }

  String get weightLabel => menuItem.isByWeight
      ? '${weight.toStringAsFixed(weightDigits)} kg'
      : 'x${weight.toStringAsFixed(0)}';

  /// 转为传给 Android 打印的 Map
  Map<String, dynamic> toPrintMap(String language) => {
    'weightDigits': weightDigits,
    'moneyDigits': moneyDigits,
    'name': menuItem.nameFor(language),
    'weight': weight,
    'price': menuItem.price,
    'subtotal': subtotal,
    'byWeight': menuItem.isByWeight,
  };
}
