import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/locale_provider.dart';
import '../services/ai_recognition_service.dart';
import '../services/product_camera_service.dart';

class AiCameraScreen extends StatefulWidget {
  const AiCameraScreen({super.key});

  @override
  State<AiCameraScreen> createState() => _AiCameraScreenState();
}

class _AiCameraScreenState extends State<AiCameraScreen> {
  CameraController? _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final controller = await ProductCameraService.open();
      if (!mounted) {
        await ProductCameraService.close(controller);
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? path;
    try {
      final image = await controller.takePicture().timeout(
        const Duration(seconds: 12),
      );
      path = image.path;
      final embedding = await AiRecognitionService().embedImage(path);
      if (mounted) Navigator.pop(context, embedding);
    } catch (error) {
      if (mounted) {
        final lp = Provider.of<LocaleProvider>(context, listen: false);
        setState(
          () => _error =
              error is PlatformException && error.code == 'IMAGE_TOO_DARK'
              ? lp.tr('ai_image_too_dark')
              : error.toString(),
        );
      }
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          // Camera plug-in may already have removed the temporary image.
        }
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) ProductCameraService.close(controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lp = Provider.of<LocaleProvider>(context);
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(lp.tr('ai_camera'))),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: controller == null
                  ? (_error == null
                        ? const CircularProgressIndicator()
                        : Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              '${lp.tr('ai_camera_error')}\n$_error',
                              textAlign: TextAlign.center,
                            ),
                          ))
                  : CameraPreview(controller),
            ),
          ),
          if (controller != null && _error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton.icon(
              onPressed: controller == null || _busy ? null : _capture,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: Text(lp.tr('ai_capture')),
            ),
          ),
        ],
      ),
    );
  }
}
