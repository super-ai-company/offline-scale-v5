import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/menu_item.dart';
import 'db_service.dart';
import 'produce_recognition_policy.dart';

/// ADB/run-as bridge, restricted to the isolated debug application. No network
/// listener, account secrets, checkout or printing commands are exposed.
class ProduceDiagnosticService {
  final Map<String, Object?> Function() state;
  final Future<void> Function() configure;
  final ValueChanged<MenuItem> select;
  final Future<List<double>> Function() capture;
  Timer? _timer;
  bool _busy = false;
  bool _closed = false;
  String? _directory;
  ProduceDiagnosticService({
    required this.state,
    required this.configure,
    required this.select,
    required this.capture,
  });

  Future<void> start() async {
    if (!kDebugMode) return;
    try {
      _directory = await const MethodChannel(
        'cashier/ai_embedding',
      ).invokeMethod<String>('diagnosticsPath');
      if (_directory != null && !_closed) {
        _timer = Timer.periodic(
          const Duration(milliseconds: 300),
          (_) => _poll(),
        );
      }
    } on PlatformException {
      /* Not available in non-isolated builds. */
    } on MissingPluginException {
      /* Widget tests have no Android bridge. */
    }
  }

  Future<void> _poll() async {
    if (_busy || _closed || _directory == null) return;
    _busy = true;
    String? id;
    try {
      final file = File('$_directory/request.json');
      if (!await file.exists() || await file.length() > 200000) return;
      final request =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      id = request['request_id'] as String?;
      if (id == null || !RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(id)) return;
      final prefs = await SharedPreferences.getInstance();
      final responseFile = File('$_directory/response.json');
      final completedSamples =
          prefs.getStringList('produce_diagnostic_sample_ids') ?? <String>[];
      if (prefs.getString('produce_diagnostic_last_id') == id ||
          completedSamples.contains(id)) {
        Map<String, dynamic>? previous;
        if (await responseFile.exists()) {
          try {
            previous =
                jsonDecode(await responseFile.readAsString())
                    as Map<String, dynamic>;
          } catch (_) {
            /* A broken reply cannot authorize another sample write. */
          }
        }
        if (previous?['request_id'] != id) {
          await responseFile.writeAsString(
            jsonEncode({'request_id': id, 'code': 'outcome_unknown'}),
          );
        }
        return;
      }
      if (request['action'] == 'capture_sample' && request['apply'] == true) {
        await prefs.setStringList('produce_diagnostic_sample_ids', [
          ...completedSamples,
          id,
        ]);
      }
      // Mark before mutation. A lost reply never blindly repeats enrolment.
      await prefs.setString('produce_diagnostic_last_id', id);
      Map<String, Object?> data;
      final db = DbService();
      final items = await db.getMenuItems();
      switch (request['action']) {
        case 'status':
          data = {
            'code': 'ok',
            ...state(),
            'configuration': {
              'camera_enabled':
                  prefs.getBool('product_camera_enabled') ?? false,
              'auto_enabled': prefs.getBool('produce_auto_enabled') ?? false,
              'auto_select': prefs.getBool('produce_auto_select') ?? false,
              'camera_name': prefs.getString('produce_camera_name'),
            },
            'sample_counts': (await db.visualSampleCounts()).map(
              (key, value) => MapEntry('$key', value),
            ),
            'products': [for (final item in items) item.toMap()],
          };
        case 'cameras':
          data = {
            'code': 'ok',
            'cameras': [
              for (final c in await availableCameras().timeout(
                const Duration(seconds: 5),
              ))
                {
                  'name': c.name,
                  'lens_direction': c.lensDirection.name,
                  'orientation': c.sensorOrientation,
                },
            ],
          };
        case 'configure':
          if (request['apply'] != true) {
            data = {
              'code': 'dry_run',
              'detail': 'Pass apply=true to change debug configuration',
            };
            break;
          }
          final config = request['configuration'] as Map<String, dynamic>;
          for (final entry in const {
            'camera_enabled': 'product_camera_enabled',
            'auto_enabled': 'produce_auto_enabled',
            'auto_select': 'produce_auto_select',
          }.entries) {
            if (config[entry.key] != null) {
              await prefs.setBool(entry.value, config[entry.key] as bool);
            }
          }
          if (config.containsKey('camera_name')) {
            final name = config['camera_name'] as String?;
            if (name == null) {
              await prefs.remove('produce_camera_name');
            } else {
              await prefs.setString('produce_camera_name', name);
            }
          }
          await configure();
          data = {'code': 'ok'};
        case 'select':
          final product = items.firstWhere(
            (item) => item.id == request['item_id'],
          );
          if (request['apply'] == true) select(product);
          data = {
            'code': request['apply'] == true ? 'ok' : 'dry_run',
            'item_id': product.id,
          };
        case 'capture_sample':
          final product = items.firstWhere(
            (item) => item.id == request['item_id'] && !item.isQuickWeigh,
          );
          if (request['apply'] != true) {
            data = {'code': 'dry_run', 'item_id': product.id};
            break;
          }
          final embedding = await capture();
          await db.addVisualSample(product.id!, embedding);
          data = {
            'code': 'ok',
            'item_id': product.id,
            'dimensions': embedding.length,
          };
        case 'recognize':
        case 'replay':
          final query = request['action'] == 'recognize'
              ? await capture()
              : (request['embedding'] as List)
                    .map((v) => (v as num).toDouble())
                    .toList();
          data = const ProduceRecognitionPolicy()
              .evaluate(query, await db.visualSamples(), items)
              .toJson();
        default:
          data = {'code': 'invalid_action'};
      }
      final temporary = File('$_directory/response.tmp');
      await temporary.writeAsString(jsonEncode({'request_id': id, ...data}));
      await temporary.rename(responseFile.path);
    } catch (_) {
      if (id != null && _directory != null) {
        await File('$_directory/response.json').writeAsString(
          jsonEncode({
            'request_id': id,
            'code': 'command_failed',
            'detail':
                'Invalid request, camera unavailable, or local operation failed',
          }),
        );
      }
    } finally {
      _busy = false;
    }
  }

  void close() {
    _closed = true;
    _timer?.cancel();
  }
}
