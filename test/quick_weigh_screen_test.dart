import 'dart:io';

import 'package:cashier_trae/l10n/locale_provider.dart';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/screens/cashier_screen.dart';
import 'package:cashier_trae/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty menu still opens ready to price a weighing item', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final directory = await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('cashier-home-');
      await databaseFactoryFfi.setDatabasesPath(directory.path);
      final db = await DbService.openAt(join(directory.path, 'cashier.db'));
      await db.delete('menu_items');
      await db.close();
      return directory;
    });
    expect(directory, isNotNull);
    SharedPreferences.setMockInitialValues({
      'print_enabled': false,
      'default_weight_price': 2.5,
    });

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('cashier/weight'),
      (call) async => call.method == 'open' ? false : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('presentation_displays_plugin'),
      (call) async => '[]',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('cashier/print'),
      (call) async => null,
    );

    try {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: const MaterialApp(home: CashierScreen()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();

      expect(find.text('Weighing Item'), findsWidgets);
      expect(find.text('Unit price'), findsOneWidget);
      expect(find.text('Item total'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Tare'), findsNothing);
      expect(find.text('Zero'), findsNothing);
      expect(find.byTooltip('Product Camera'), findsNothing);
      expect(tester.getTopLeft(find.text('Cart is empty')).dy,
          greaterThan(tester.getTopLeft(find.text('Unit price')).dy));
      final priceField = tester.widget<TextField>(find.byType(TextField).first);
      expect(priceField.controller!.text, '2.50');
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Enable product camera'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Enable product camera'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile).last).value, false);
      await tester.tap(find.text('Enable product camera'));
      await tester.scrollUntilVisible(
        find.text('Save Settings'), 300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Save Settings'));
      await tester.pump();
      await tester.pageBack();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Product Camera'), findsOneWidget);

      await tester.tap(find.text('Weighing Item').first);
      await tester.tap(find.widgetWithText(FilledButton, '5'));
      await tester.tap(find.widgetWithText(FilledButton, '0'));
      await tester.pumpAndSettle();
      expect(priceField.controller!.text, '50');

      await tester.tap(find.text('Save default'));
      await tester.pump();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble('default_weight_price'), 50);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.runAsync(() => DbService().insertMenuItem(const MenuItem(
        nameEn: 'Test Item', price: 9, isByWeight: false,
      )));
      await tester.tap(find.byTooltip('Manage Menu'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Item').first);
      await tester.pump();
      expect(priceField.controller!.text, '9.00');
      await tester.tap(find.widgetWithText(FilledButton, '5'));
      await tester.pump();
      expect(priceField.controller!.text, '5');
      await tester.tap(find.text('Add to Cart'));
      await tester.pump();
      expect(find.text('฿ 5.00'), findsWidgets);

      await tester.pump(const Duration(seconds: 3));
    } finally {
      await tester.pumpWidget(const SizedBox());
      messenger.setMockMethodCallHandler(const MethodChannel('cashier/weight'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('presentation_displays_plugin'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('cashier/print'), null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(() => directory!.delete(recursive: true));
    }
  });
}
