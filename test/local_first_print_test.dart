import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cashier_trae/services/print_service.dart';
import 'package:cashier_trae/services/feie_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cashier/print');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var cloudLoads = 0;
  var cloudPrints = 0;
  var localPrints = 0;
  var localOpen = true;
  var localResult = true;
  PrintService service() => PrintService.forTesting(
    cloudLoader: () async {
      cloudLoads++;
      return FeieService(
        const FeieConfig(
          user: 'demo@example.invalid',
          sn: '123456789',
          region: 'jp',
          ukey: 'test',
        ),
        transport: (_, fields) async {
          if (fields['apiname'] == 'Open_printMsg') {
            cloudPrints++;
            return {'ret': 0, 'data': 'test-order'};
          }
          return {'ret': 0, 'data': 'online and working normally'};
        },
      );
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cloudLoads = cloudPrints = localPrints = 0;
    localOpen = localResult = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openPort') return localOpen;
      if (call.method == 'printTicket') {
        localPrints++;
        return localResult;
      }
      return true;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test(
    'legacy cloud selection still defaults to local with backup disabled',
    () async {
      SharedPreferences.setMockInitialValues({'printer_backend': 'feie'});
      expect(
        await service().printTicket(shopName: 'Test', items: [], total: 0),
        true,
      );
      expect(localPrints, 1);
      expect(cloudLoads, 0);
    },
  );
  test('enabled backup never touches cloud when local works', () async {
    SharedPreferences.setMockInitialValues({'feie_enabled': true});
    expect(
      await service().printTicket(shopName: 'Test', items: [], total: 0),
      true,
    );
    expect(localPrints, 1);
    expect(cloudLoads, 0);
  });
  test(
    'no local printer with default settings never contacts network',
    () async {
      localOpen = false;
      expect(await service().connect(), false);
      expect(
        await service().printTicket(shopName: 'Test', items: [], total: 0),
        false,
      );
      expect(cloudLoads, 0);
      expect(localPrints, 0);
    },
  );
  test(
    'explicit backup prints once only after local connection failure',
    () async {
      SharedPreferences.setMockInitialValues({'feie_enabled': true});
      localOpen = false;
      final p = service();
      expect(await p.printTicket(shopName: 'Test', items: [], total: 0), true);
      expect(p.resultKey, 'feie_accepted');
      expect(cloudPrints, 1);
      expect(localPrints, 0);
    },
  );
  test(
    'uncertain local write blocks both retries and cloud across service restart',
    () async {
      SharedPreferences.setMockInitialValues({'feie_enabled': true});
      localResult = false;
      final p = service();
      expect(await p.printTicket(shopName: 'Test', items: [], total: 0), false);
      expect(p.resultKey, 'print_local_uncertain');
      localOpen = false;
      expect(
        await service().printTicket(shopName: 'Test', items: [], total: 0),
        false,
      );
      expect(localPrints, 1);
      expect(cloudLoads, 0);
    },
  );
}
