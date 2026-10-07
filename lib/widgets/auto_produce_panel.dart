import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/locale_provider.dart';
import '../models/menu_item.dart';
import '../services/ai_recognition_service.dart';
import '../services/db_service.dart';
import '../services/product_camera_service.dart';
import '../services/produce_recognition_policy.dart';

class AutoProducePanel extends StatefulWidget {
  final double kg;
  final bool ready;
  final bool blocked;
  final bool autoSelect;
  final bool selectionLocked;
  final List<MenuItem> items;
  final ValueChanged<MenuItem> onSelect;
  final VoidCallback onNewCycle;
  const AutoProducePanel({
    super.key,
    required this.kg,
    required this.ready,
    required this.blocked,
    required this.autoSelect,
    required this.selectionLocked,
    required this.items,
    required this.onSelect,
    required this.onNewCycle,
  });
  @override
  State<AutoProducePanel> createState() => AutoProducePanelState();
}

class AutoProducePanelState extends State<AutoProducePanel>
    with WidgetsBindingObserver {
  final cycle = ProduceScanCycle();
  CameraController? _camera;
  Future<void>? _opening;
  Timer? _timer;
  bool _busy = false;
  bool _foreground = true;
  bool _stopped = false;
  bool _fixedCamera = false;
  bool _cameraFailed = false;
  int _cameraEpoch = 0;
  int _attempts = 0;
  ProduceDecision? _decision;
  String _status = 'waiting_weight';

  Map<String, Object?> get diagnostics => {
    'code': _cameraFailed ? 'camera_error' : _status,
    'camera_ready': _camera != null,
    'generation': cycle.generation,
    'attempts': _attempts,
    'locked': cycle.locked,
    'busy': _busy,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.selectionLocked) {
      cycle.manualOverride();
      _status = 'manual';
    }
    _opening = _open();
    _timer = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
  }

  Future<void> _open() async {
    final epoch = ++_cameraEpoch;
    try {
      final camera = await ProductCameraService.select();
      _fixedCamera =
          (await SharedPreferences.getInstance()).getString(
            'produce_camera_name',
          ) !=
          null;
      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || _stopped || !_foreground || epoch != _cameraEpoch) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _cameraFailed = false;
      });
    } catch (_) {
      if (mounted && !_stopped && epoch == _cameraEpoch) {
        setState(() {
          _status = 'camera_error';
          _cameraFailed = true;
        });
      }
    }
  }

  void manualOverride() {
    cycle.manualOverride();
    if (mounted) {
      setState(() {
        _decision = null;
        _status = 'manual';
      });
    }
  }

  Future<void> stop() async {
    _stopped = true;
    _cameraEpoch++;
    cycle.invalidate();
    _timer?.cancel();
    await _opening;
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _cameraEpoch++;
    cycle.invalidate();
    _decision = null;
    _attempts = 0;
    if (!_foreground) {
      final camera = _camera;
      _camera = null;
      // Reopening waits for release of the camera on the next resume.
      final pending = _opening;
      _opening = () async {
        await pending;
        await camera?.dispose();
      }();
    } else if (!_stopped) {
      final pending = _opening;
      _opening = () async {
        await pending;
        if (!_stopped && _foreground) {
          await _open();
        }
      }();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(AutoProducePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectionLocked && !cycle.locked) {
      cycle.manualOverride();
    }
    final previous = cycle.generation;
    cycle.update(widget.kg, widget.ready && !widget.blocked, DateTime.now());
    if (previous != cycle.generation) {
      _decision = null;
      _attempts = 0;
      _status = cycle.locked ? 'manual' : 'waiting_weight';
      // Schedule parent state updates outside its build.
      if (!cycle.locked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.onNewCycle();
          }
        });
      }
    }
  }

  Future<void> _tick() async {
    if (_busy ||
        _stopped ||
        !_foreground ||
        widget.blocked ||
        widget.selectionLocked ||
        ModalRoute.of(context)?.isCurrent != true ||
        _camera == null ||
        _attempts >= 4) {
      return;
    }
    cycle.update(widget.kg, widget.ready, DateTime.now());
    if (!cycle.ready(DateTime.now())) return;
    final token = cycle.generation;
    final camera = _camera!;
    _busy = true;
    String? path;
    try {
      setState(() {
        _status = 'scanning';
        _cameraFailed = false;
      });
      path = (await camera.takePicture()).path;
      final embedding = await AiRecognitionService().embedImage(path);
      final samples = await DbService().visualSamples();
      final decision = const ProduceRecognitionPolicy().evaluate(
        embedding,
        samples,
        widget.items,
      );
      if (!mounted ||
          _stopped ||
          !_foreground ||
          widget.blocked ||
          token != cycle.generation ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _attempts++;
      final consistent = cycle.confirm(decision, token);
      setState(() {
        _decision = decision;
        _status = decision.accepted
            ? (consistent
                  ? (widget.autoSelect && !_fixedCamera
                        ? 'needs_camera'
                        : 'confirm')
                  : 'scanning')
            : decision.code;
      });
      if (consistent && widget.autoSelect && _fixedCamera) {
        cycle.manualOverride();
        setState(() => _status = 'selected');
        widget.onSelect(decision.candidates.first.item);
      }
    } catch (_) {
      if (mounted && !_stopped && token == cycle.generation) {
        _attempts = 4;
        setState(() {
          _decision = null;
          _status = 'camera_error';
          _cameraFailed = true;
        });
      }
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } on FileSystemException {
          /* Temporary capture already removed. */
        }
      }
      _busy = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LocaleProvider>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_camera != null)
                  SizedBox(
                    width: 86,
                    height: 60,
                    child: ClipRect(child: CameraPreview(_camera!)),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lp.tr(
                      'produce_${_cameraFailed ? 'camera_error' : _status}',
                    ),
                    maxLines: 3,
                  ),
                ),
                IconButton(
                  tooltip: lp.tr('produce_retry'),
                  onPressed: cycle.locked || _busy
                      ? null
                      : () async {
                          cycle.invalidate();
                          setState(() {
                            _attempts = 0;
                            _decision = null;
                            _status = 'waiting_weight';
                          });
                          if (_camera == null) {
                            final pending = _opening;
                            _opening = () async {
                              await pending;
                              if (!_stopped) {
                                await _open();
                              }
                            }();
                            await _opening;
                          }
                        },
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_decision != null) ...[
              Text(
                lp.tr('produce_similarity'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              for (final match in _decision!.candidates)
                SizedBox(
                  height: 32,
                  width: double.infinity,
                  child: TextButton(
                    onPressed: cycle.locked || !widget.ready || widget.blocked
                        ? null
                        : () {
                            cycle.manualOverride();
                            setState(() => _status = 'selected');
                            widget.onSelect(match.item);
                          },
                    child: Text(
                      '${match.item.nameFor(lp.localeStr)} · ${match.item.price.toStringAsFixed(2)} THB/kg · ${(match.similarity * 100).toStringAsFixed(1)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
