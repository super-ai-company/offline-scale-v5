import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cashier_trae/l10n/locale_provider.dart';
import 'package:cashier_trae/widgets/app_update_settings.dart';

void main() {
  testWidgets(
    'manual update stays offline on render and pending sale blocks action',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('cashier/update'), (
            call,
          ) async {
            calls++;
            return '1.2.2';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cashier/update'),
              null,
            ),
      );
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => LocaleProvider(),
          child: const MaterialApp(
            home: Scaffold(body: AppUpdateSettings(allowed: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(
        find.text('Finish or clear the current cart before updating'),
        findsOneWidget,
      );
    },
  );
}
