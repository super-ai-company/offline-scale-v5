import 'dart:async';
import 'package:camera/camera.dart';
import 'package:cashier_trae/services/product_camera_service.dart';
import 'package:flutter_test/flutter_test.dart';

class StalledCamera extends Fake implements CameraController {
  final completion = Completer<void>();
  int disposals = 0;
  @override
  Future<void> dispose() {
    disposals++;
    return completion.future;
  }
}

void main() {
  test(
    'hung accessory cleanup returns control while SDK disposal continues',
    () async {
      final camera = StalledCamera();
      await ProductCameraService.close(
        camera,
        timeout: const Duration(milliseconds: 10),
      );
      expect(camera.disposals, 1);
      expect(camera.completion.isCompleted, isFalse);
      camera.completion.complete();
    },
  );
}
