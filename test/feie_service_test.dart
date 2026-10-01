import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cashier_trae/models/cart_item.dart';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/services/feie_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const config = FeieConfig(
    user: 'demo@example.invalid',
    sn: '123456789',
    region: 'jp',
    ukey: 'test-only-not-a-real-key',
  );
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('concurrent callers cannot race into duplicate submissions', () async {
    final reply = Completer<Map<String, dynamic>>();
    final called = Completer<void>();
    var calls = 0;
    final service = FeieService(
      config,
      transport: (_, _) {
        calls++;
        called.complete();
        return reply.future;
      },
    );
    final first = service.print('Test');
    await called.future;
    expect((await service.print('Test')).state, CloudPrintState.blocked);
    reply.complete({'ret': 0, 'data': 'one-order'});
    expect((await first).state, CloudPrintState.accepted);
    expect(calls, 1);
  });

  test('uses HTTPS split API URL and exact documented SHA1 fields', () async {
    final date = DateTime.fromMillisecondsSinceEpoch(1700000000000);
    final service = FeieService(
      config,
      now: () => date,
      transport: (uri, fields) async {
        expect(
          uri.toString(),
          'https://api.jp.feieyun.com/Api/Open/queryPrinterStatus',
        );
        expect(fields['apiname'], 'Open_queryPrinterStatus');
        expect(fields['stime'], '1700000000');
        expect(
          fields['sig'],
          sha1
              .convert(utf8.encode('${config.user}${config.ukey}1700000000'))
              .toString(),
        );
        expect(fields.containsKey('ukey'), isFalse);
        return {'ret': 0, 'data': '在线，工作状态正常'};
      },
    );
    expect(await service.printerStatus(), 1);
  });

  test(
    'offline, abnormal, translated and unknown statuses fail safely',
    () async {
      for (final pair in [
        ('离线', 0),
        ('在线，工作状态异常', 2),
        ('The online working condition is normal', 1),
      ]) {
        final service = FeieService(
          config,
          transport: (_, _) async => {'ret': 0, 'data': pair.$1},
        );
        expect(await service.printerStatus(), pair.$2);
      }
      final unknown = FeieService(
        config,
        transport: (_, _) async => {'ret': 0, 'data': 'new status'},
      );
      await expectLater(unknown.printerStatus(), throwsFormatException);
    },
  );

  test(
    'accepted order persists ID and queries physical confirmation separately',
    () async {
      final service = FeieService(
        config,
        transport: (uri, fields) async {
          if (fields['apiname'] == 'Open_queryOrderState') {
            expect(uri.path, '/Api/Open/queryOrderState');
            expect(fields['orderid'], 'test-order');
            return {'ret': 0, 'data': false};
          }
          expect(uri.path, '/Api/Open/printMsg');
          expect(fields['times'], '1');
          return {'ret': 0, 'data': 'test-order'};
        },
      );
      final result = await service.print('Test<BR>');
      expect(result.state, CloudPrintState.accepted);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('feie_last_order'), 'test-order');
      expect(prefs.getBool('feie_uncertain'), false);
      expect(await service.orderPrinted(result.orderId!), false);
    },
  );

  test(
    'lost reply blocks all later submissions across service restarts',
    () async {
      var calls = 0;
      final service = FeieService(
        config,
        transport: (_, _) async {
          calls++;
          throw const SocketException('Lost reply');
        },
      );
      expect((await service.print('Test')).state, CloudPrintState.uncertain);
      final restarted = FeieService(
        config,
        transport: (_, _) async {
          calls++;
          return {'ret': 0, 'data': 'unexpected'};
        },
      );
      expect((await restarted.print('Test')).state, CloudPrintState.blocked);
      expect(calls, 1);
    },
  );

  test(
    'known cloud rejection allows retry; malformed success keeps guard',
    () async {
      final rejected = FeieService(
        config,
        transport: (_, _) async => {'ret': 1002},
      );
      expect((await rejected.print('Test')).state, CloudPrintState.rejected);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('feie_uncertain'), false);
      final malformed = FeieService(
        config,
        transport: (_, _) async => {'ret': 0, 'data': null},
      );
      expect((await malformed.print('Test')).state, CloudPrintState.uncertain);
      expect(prefs.getBool('feie_uncertain'), true);
    },
  );

  test(
    'timeout is not retried; oversized content never calls network',
    () async {
      var calls = 0;
      final service = FeieService(
        config,
        transport: (_, _) async {
          calls++;
          throw TimeoutException('Timeout');
        },
      );
      expect((await service.print('中' * 1667)).state, CloudPrintState.rejected);
      expect(calls, 0);
      expect((await service.print('Test')).state, CloudPrintState.uncertain);
      expect(calls, 1);
    },
  );

  test(
    'receipt preserves cent-rounded values and neutralizes control tags',
    () {
      const item = CartItem(
        menuItem: MenuItem(nameEn: 'Apple', nameCn: '苹果<CUT>', price: 1),
        weight: .265,
        subtotal: .27,
      );
      final receipt = FeieService.receipt(
        shopName: 'Shop<PLUGIN>',
        items: [item],
        total: .27,
        totalLabel: '合计',
        date: DateTime(2026, 10, 1),
        language: 'zh',
      );
      expect(receipt, contains('0.265 kg x 1.00 = 0.27 THB'));
      expect(receipt, contains('合计: 0.27 THB'));
      expect(receipt, contains('苹果'));
      expect(receipt, isNot(contains('<CUT>')));
      expect(receipt, isNot(contains('<PLUGIN>')));
    },
  );
}
