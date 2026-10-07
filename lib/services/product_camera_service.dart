import 'dart:io';
import 'ai_recognition_service.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductCameraService {
  static Future<List<double>> captureEmbedding() async {
    final controller = CameraController(
      await select(),
      ResolutionPreset.medium,
      enableAudio: false,
    );
    String? path;
    try {
      await controller.initialize();
      path = (await controller.takePicture()).path;
      return await AiRecognitionService().embedImage(path);
    } finally {
      await controller.dispose();
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
