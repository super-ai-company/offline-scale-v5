import 'dart:convert';
import 'dart:io';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/services/db_service.dart';
import 'package:cashier_trae/services/produce_diagnostic_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'debug JSON commands default to dry-run and sample retry stays idempotent after status queries',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp(
        'vision-command-',
      );
      await databaseFactoryFfi.setDatabasesPath(directory.path);
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('cashier/ai_embedding');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => directory.path,
      );
      final db = DbService();
      final item = await db.insertMenuItem(
        const MenuItem(nameEn: 'Potato', price: 10),
      );
      var captures = 0;
      var configured = 0;
      final service = ProduceDiagnosticService(
        state: () => {'stable': true},
        configure: () async {
          configured++;
        },
        select: (_) {},
        capture: () async {
          captures++;
          return [1, 0];
        },
      );
      Future<Map<String, dynamic>> send(Map<String, dynamic> request) async {
        await File(
          '${directory.path}/request.json',
        ).writeAsString(jsonEncode(request));
        final deadline = DateTime.now().add(const Duration(seconds: 4));
        while (DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final file = File('${directory.path}/response.json');
          if (!await file.exists()) continue;
          try {
            final response =
                jsonDecode(await file.readAsString()) as Map<String, dynamic>;
            if (response['request_id'] == request['request_id'])
              return response;
          } on FormatException {
            /* Atomic reply may be between writes. */
          }
        }
        throw StateError('No diagnostic reply');
      }

      try {
        await service.start();
        expect(
          (await send({
            'request_id': 'config-dry',
            'action': 'configure',
            'configuration': {'auto_enabled': true},
          }))['code'],
          'dry_run',
        );
        expect(configured, 0);
        expect(
          (await SharedPreferences.getInstance()).getBool(
            'produce_auto_enabled',
          ),
          isNull,
        );
        final command = {
          'request_id': 'sample-once',
          'action': 'capture_sample',
          'item_id': item.id,
          'apply': true,
        };
        expect((await send(command))['code'], 'ok');
        expect(captures, 1);
        expect(
          (await send({
            'request_id': 'status-after',
            'action': 'status',
          }))['code'],
          'ok',
        );
        expect((await send(command))['code'], 'outcome_unknown');
        expect(captures, 1);
        expect((await db.visualSampleCounts())[item.id], 1);
        expect(
          (await send({'request_id': 'invalid', 'action': 'print'}))['code'],
          'invalid_action',
        );
      } finally {
        service.close();
        messenger.setMockMethodCallHandler(channel, null);
        await (await db.db).close();
        await directory.delete(recursive: true);
      }
    },
  );
}
