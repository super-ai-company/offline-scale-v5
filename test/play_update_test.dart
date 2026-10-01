import 'package:flutter_test/flutter_test.dart';
import 'package:cashier_trae/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Play refuses GitHub checks and APK installation', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(UpdateService.channel, (call) async {
          calls.add(call.method);
          return call.method == 'distribution' ? 'play' : true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(UpdateService.channel, null),
    );
    final service = UpdateService();
    await expectLater(service.check('1.2.2'), throwsUnsupportedError);
    await expectLater(
      service.install(const AppUpdate('1.2.3', 'invalid', 'invalid', 1)),
      throwsUnsupportedError,
    );
    expect(calls, ['distribution', 'distribution']);
    expect(await service.openStore(), isTrue);
    expect(calls.last, 'openStore');
  });
}
