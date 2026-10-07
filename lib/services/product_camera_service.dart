import 'dart:io';
import 'dart:async';
import 'ai_recognition_service.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductCameraService {
  static Future<CameraController> open() async {
    final camera = await select().timeout(const Duration(seconds: 5));
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize().timeout(const Duration(seconds: 10));
      return controller;
    } catch (_) {
      unawaited(close(controller));
      rethrow;
    }
  }

  /// A faulty/disconnected accessory must not hold cashier navigation hostage.
  /// SDK disposal continues even when the UI's bounded wait expires.
  static Future<void> close(
    CameraController controller, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      await controller.dispose().timeout(timeout);
    } catch (_) {
      /* Cleanup must never disable manual checkout. */
    }
  }

  static Future<List<double>> captureEmbedding() async {
    final controller = await open();
    String? path;
    try {
      path = (await controller.takePicture().timeout(
        const Duration(seconds: 12),
      )).path;
      return await AiRecognitionService().embedImage(path);
    } finally {
      await close(controller);
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          /* Temporary capture. */
        }
      }
    }
  }

  static Future<CameraDescription> select() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw StateError('No Android camera found');
    final selected = (await SharedPreferences.getInstance()).getString(
      'produce_camera_name',
    );
    if (selected != null) {
      // Fail closed when a configured accessory is disconnected: do not sample
      // the ceiling/front-facing camera against the accessory's product data.
      return cameras.firstWhere(
        (camera) => camera.name == selected,
        orElse: () =>
            throw StateError('Configured product camera disconnected'),
      );
    }
    return cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.external,
      orElse: () => cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      ),
    );
  }
}
