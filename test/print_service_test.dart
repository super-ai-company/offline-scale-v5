import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_trae/models/cart_item.dart';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/services/print_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cashier/print');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  tearDown(() async {
    await PrintService().disconnect();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('failed device print keeps result false', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openPort') return true;
      if (call.method == 'printTicket') return false;
      return true;
    });

    final result = await PrintService().printTicket(
      shopName: 'Shop', items: <CartItem>[], total: 0,
    );
    expect(result, isFalse);
  });

  test('successful device print returns true', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openPort') return true;
      if (call.method == 'printTicket') return true;
      return true;
    });

    final result = await PrintService().printTicket(
      shopName: 'Shop', items: <CartItem>[], total: 0,
    );
    expect(result, isTrue);
  });

  test('receipt passes selected language product and total label', () async {
    Map<Object?, Object?>? printed;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openPort') return true;
      if (call.method == 'printTicket') {
        printed = call.arguments as Map<Object?, Object?>;
        return true;
      }
      return true;
    });
    const product = MenuItem(
      nameEn: 'Apple', nameTh: 'แอปเปิล', nameCn: '苹果', price: 10,
    );
    const item = CartItem(menuItem: product, weight: 1, subtotal: 10);

    final result = await PrintService().printTicket(
      shopName: '商店',
      items: [item],
      total: 10,
      language: 'zh',
      totalLabel: '合计',
    );

    expect(result, isTrue);
    expect(printed?['shopName'], '商店');
    expect(printed?['language'], 'zh');
    expect(printed?['totalLabel'], '合计');
    final items = printed?['items'] as List<Object?>;
    expect((items.single as Map<Object?, Object?>)['name'], '苹果');
  });
}
