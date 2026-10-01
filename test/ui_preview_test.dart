import 'dart:io';
import 'dart:ui' as ui;

import 'package:cashier_trae/l10n/locale_provider.dart';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/screens/cashier_screen.dart';
import 'package:cashier_trae/screens/settings_screen.dart';
import 'package:cashier_trae/services/db_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Optional reproducible documentation renders. All data is synthetic.
/// flutter test test/ui_preview_test.dart --dart-define=GENERATE_SCREENSHOTS=true
/// --dart-define=PREVIEW_FONT=/absolute/path/to/a/CJK-capable/font.ttf
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('render bilingual cashier and Feie setup previews', (
    tester,
  ) async {
    const fontPath = String.fromEnvironment('PREVIEW_FONT');
    for (final family in ['Preview']) {
      final font = FontLoader(family);
      font.addFont(
        Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())),
      );
      await font.load();
    }
    const iconPath = String.fromEnvironment('PREVIEW_ICONS');
    final roboto = FontLoader('Roboto');
    roboto.addFont(
      Future.value(
        ByteData.sublistView(
          File(
            iconPath.replaceAll(
              'MaterialIcons-Regular.otf',
              'Roboto-Regular.ttf',
            ),
          ).readAsBytesSync(),
        ),
      ),
    );
    await roboto.load();
    final icons = FontLoader('MaterialIcons');
    icons.addFont(
      Future.value(ByteData.sublistView(File(iconPath).readAsBytesSync())),
    );
    await icons.load();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final temp = await tester.runAsync(() async {
      final temp = await Directory.systemTemp.createTemp(
        'offline-scale-preview-',
      );
      await databaseFactoryFfi.setDatabasesPath(temp.path);
      return temp;
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('cashier/weight'),
      (_) async => false,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('cashier/print'),
      (_) async => false,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('cashier/secrets'),
      (_) async => '',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('presentation_displays_plugin'),
      (_) async => '[]',
    );
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    final boundary = GlobalKey();

    Future<void> capture(String name) async {
      await tester.pump();
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          'docs/screenshots/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    try {
      SharedPreferences.setMockInitialValues({
        'print_enabled': false,
        'default_weight_price': 50.0,
      });
      await tester.runAsync(() async {
        await DbService().insertMenuItem(
          const MenuItem(
            nameEn: 'Apples',
            nameCn: '苹果',
            nameTh: 'แอปเปิล',
            price: 50,
          ),
        );
        await DbService().insertMenuItem(
          const MenuItem(
            nameEn: 'Bread',
            nameCn: '面包',
            nameTh: 'ขนมปัง',
            price: 15,
            isByWeight: false,
          ),
        );
      });
      final lp = LocaleProvider();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ChangeNotifierProvider.value(
            value: lp,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Roboto',
                fontFamilyFallback: const ['Preview'],
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF0077B6),
                  primary: const Color(0xFF0077B6),
                  surface: Colors.white,
                ),
              ),
              home: const CashierScreen(),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bread').first);
      await tester.tap(find.text('Add to Cart'));
      await tester.pump();
      await capture('cashier-en');
      await tester.runAsync(() => lp.setLocale('zh'));
      await tester.pumpAndSettle();
      await capture('cashier-zh');

      await tester.pumpWidget(const SizedBox());
      SharedPreferences.setMockInitialValues({
        'feie_enabled': true,
        'language': 'zh',
      });
      final settingsLp = LocaleProvider();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ChangeNotifierProvider.value(
            value: settingsLp,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Roboto',
                fontFamilyFallback: const ['Preview'],
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF0077B6),
                  primary: const Color(0xFF0077B6),
                  surface: Colors.white,
                ),
              ),
              home: const SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -390));
      await tester.pumpAndSettle();
      await capture('precision-settings-zh');
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      await capture('feie-settings-zh');
      await tester.runAsync(() => settingsLp.setLocale('en'));
      await tester.pumpAndSettle();
      await capture('feie-settings-en');
      await tester.drag(find.byType(ListView), const Offset(0, 420));
      await tester.pumpAndSettle();
      await capture('precision-settings-en');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final name in [
        'cashier/weight',
        'cashier/print',
        'cashier/secrets',
        'presentation_displays_plugin',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.runAsync(() => temp!.delete(recursive: true));
    }
  }, skip: !const bool.fromEnvironment('GENERATE_SCREENSHOTS'));
}
