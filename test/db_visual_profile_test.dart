import 'dart:io';
import 'package:cashier_trae/models/menu_item.dart';
import 'package:cashier_trae/services/db_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'switching accessories isolates samples without deleting legacy or other camera samples',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final directory = await Directory.systemTemp.createTemp(
        'camera-samples-',
      );
      await databaseFactoryFfi.setDatabasesPath(directory.path);
      SharedPreferences.setMockInitialValues({});
      final service = DbService();
      try {
        final item = await service.insertMenuItem(
          const MenuItem(nameEn: 'Potato', price: 20),
        );
        final id = item.id!;
        await service.addVisualSample(id, [1, 0]);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('produce_camera_name', 'tray-camera');
        expect(await service.visualSampleCounts(), isEmpty);
        expect(await service.visualSamples(), isEmpty);
        await service.addVisualSample(id, [0, 1]);
        expect((await service.visualSampleCounts())[id], 1);
        await prefs.setString('produce_camera_name', 'other-camera');
        expect(await service.visualSamples(), isEmpty);
        await prefs.setString('produce_camera_name', 'tray-camera');
        expect((await service.visualSamples()).single.$2, [0, 1]);
        await prefs.remove('produce_camera_name');
        expect((await service.visualSamples()).single.$2, [1, 0]);
        expect(await (await service.db).query('visual_samples'), hasLength(2));
      } finally {
        await (await service.db).close();
        await directory.delete(recursive: true);
      }
    },
  );
}
