import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cashier_trae/models/sale_precision.dart';
import 'package:cashier_trae/models/cart_item.dart';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/services/feie_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'defaults and corrupt preferences stay within supported precision',
    () async {
      SharedPreferences.setMockInitialValues({
        'weight_digits': 99,
        'money_digits': -2,
      });
      final p = SalePrecision.fromPrefs(await SharedPreferences.getInstance());
      expect(p.weightDigits, 3);
      expect(p.moneyDigits, 0);
      SharedPreferences.setMockInitialValues({});
      final defaults = SalePrecision.fromPrefs(
        await SharedPreferences.getInstance(),
      );
      expect(defaults.weightDigits, 3);
      expect(defaults.moneyDigits, 2);
    },
  );
  test('cash precision rounds half up and truncates toward zero', () {
    const round = SalePrecision(moneyDigits: 0);
    const cut = SalePrecision(moneyDigits: 0, truncate: true);
    expect(round.money(12.49), 12);
    expect(round.money(12.50), 13);
    expect(cut.money(12.99), 12);
    expect(const SalePrecision(moneyDigits: 1).money(12.55), 12.6);
    expect(
      const SalePrecision(moneyDigits: 1, truncate: true).money(12.59),
      12.5,
    );
    expect(cut.money(-12.99), -12);
  });
  test('selected weight is the billed weight and line sum stays exact', () {
    const r = SalePrecision(weightDigits: 2, moneyDigits: 0);
    const t = SalePrecision(weightDigits: 2, moneyDigits: 0, truncate: true);
    expect(r.weight(1.235), 1.24);
    expect(t.weight(1.239), 1.23);
    expect(r.subtotal(byWeight: true, quantity: 0.725, price: 10), 7);
    expect(t.subtotal(byWeight: true, quantity: 0.725, price: 10), 7);
    expect(
      const SalePrecision(
        moneyDigits: 0,
      ).subtotal(byWeight: true, quantity: 0.755, price: 10),
      8,
    );
    expect(
      const SalePrecision(
        moneyDigits: 0,
        truncate: true,
      ).subtotal(byWeight: true, quantity: 0.755, price: 10),
      7,
    );
  });
  test('zero digit receipt and native payload preserve snapshot precision', () {
    const item = CartItem(
      menuItem: MenuItem(
        nameCn: '测试',
        nameEn: 'Test',
        nameTh: 'Test',
        price: 10,
      ),
      weight: 0.72,
      subtotal: 7,
      weightDigits: 2,
      moneyDigits: 0,
    );
    final receipt = FeieService.receipt(
      shopName: 'Test',
      items: [item],
      total: 7,
      totalLabel: 'Total',
      date: DateTime(2026),
      language: 'zh',
    );
    expect(receipt, contains('0.72 kg x 10 = 7 THB'));
    expect(receipt, contains('Total: 7 THB'));
    expect(item.toPrintMap('zh')['moneyDigits'], 0);
    expect(item.toPrintMap('zh')['weightDigits'], 2);
  });
  test('all supported precisions produce the requested digit count', () {
    for (var wd = 0; wd <= 3; wd++) {
      for (var md = 0; md <= 2; md++) {
        for (final truncate in [true, false]) {
          final p = SalePrecision(
            weightDigits: wd,
            moneyDigits: md,
            truncate: truncate,
          );
          expect(
            p.weightText(1.235),
            matches(wd == 0 ? r'^\d+$' : '^\\d+\\.\\d{$wd}\$'),
          );
          expect(
            p.moneyText(12.55),
            matches(md == 0 ? r'^\d+$' : '^\\d+\\.\\d{$md}\$'),
          );
        }
      }
    }
  });
}
