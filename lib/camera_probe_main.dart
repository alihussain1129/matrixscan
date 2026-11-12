import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:camera_desktop/camera_desktop.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: ProbeScreen()),
  );
}

class ProbeScreen extends StatefulWidget {
  const ProbeScreen({super.key});

  @override
  State<ProbeScreen> createState() => _ProbeScreenState();
}

class _ProbeScreenState extends State<ProbeScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _selected = 0;
  String _status = 'Starting';
  int _frames = 0;
  int _windowFrames = 0;
  double _fps = 0;
  String _frameInfo = 'no frame yet';
  Timer? _timer;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _fps = _windowFrames.toDouble();
        _windowFrames = 0;
      });
    });
    unawaited(_discover());
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_close(refresh: false));
    super.dispose();
  }

  void _say(String message) {
    final line = '[PROBE] $message';
    debugPrint(line);
    if (!mounted) return;
    setState(() {
      _log.add(line);
      if (_log.length > 60) _log.removeAt(0);
    });
  }

  Future<void> _discover() async {
    _say('platform=${Platform.operatingSystem}');
    try {
      final cameras = await availableCameras();
      _say('availableCameras returned ${cameras.length}');
      for (final c in cameras) {
        _say(
          'camera name=${c.name} lens=${c.lensDirection.name} '
          'sensor=${c.sensorOrientation}',
        );
      }
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
      });
      if (cameras.isEmpty) {
        _say('NO CAMERAS FOUND');
        setState(() {
          _status = 'No cameras found';
        });
        return;
      }
      await _open(0);
    } catch (e) {
      _say('availableCameras FAILED: $e');
      if (mounted) {
        setState(() {
          _status = 'Error';
        });
      }
    }
  }

  Future<void> _open(int index) async {
    await _close();
    if (!mounted || index >= _cameras.length) return;
    final controller = CameraController(
      _cameras[index],
      ResolutionPreset.high,
      enableAudio: false,
    );
    setState(() {
      _controller = controller;
      _selected = index;
      _status = 'Initializing';
      _frames = 0;
      _windowFrames = 0;
      _frameInfo = 'no frame yet';
    });
    try {
      await controller.initialize();
      _say('initialized, previewSize=${controller.value.previewSize}');
      if (Platform.isLinux) {
        try {
          await CameraDesktopPlugin().setMirror(controller.cameraId, false);
          _say('mirror turned off');
        } catch (e) {
          _say('setMirror failed: $e');
        }
      }
      await controller.startImageStream(_onFrame);
      _say('image stream started');
      if (mounted) {
        setState(() {
          _status = 'Ready';
        });
      }
    } catch (e) {
      _say('open FAILED: $e');
      if (mounted) {
        setState(() {
          _status = 'Error';
        });
      }
    }
  }

  void _onFrame(CameraImage image) {
    _frames++;
    _windowFrames++;
    if (_frames == 1 || _frames % 120 == 0) {
      final p = image.planes.first;
      _frameInfo =
          '${image.width}x${image.height} '
          'group=${image.format.group.name} raw=${image.format.raw} '
          'planes=${image.planes.length} bytesPerRow=${p.bytesPerRow} '
          'bytes=${p.bytes.length}';
      debugPrint('[PROBE] frame #$_frames $_frameInfo');
    }
  }

  Future<void> _close({bool refresh = true}) async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    if (refresh && mounted) {
      setState(() {
        _status = 'Closed';
      });
    }
    try {
      if (c.value.isStreamingImages) {
        await c.stopImageStream();
      }
    } catch (e) {
      _say('stopImageStream: $e');
    }
    try {
      await c.dispose();
      _say('controller disposed');
    } catch (e) {
      _say('dispose: $e');
    }
  }

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      _say('no camera open');
      return;
    }
    try {
      final file = await c.takePicture();
      _say('photo saved: ${file.path}');
    } catch (e) {
      _say('takePicture FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final size = c?.value.previewSize;
    final ratio = (size == null || size.height == 0)
        ? 16 / 9
        : size.width / size.height;
    final cameraName = _cameras.isEmpty ? '-' : _cameras[_selected].name;
    return Scaffold(
      appBar: AppBar(title: const Text('Exalted camera probe')),
      body: Row(
        children: [
          Expanded(
            child: Center(
              child: (c != null && c.value.isInitialized)
                  ? AspectRatio(aspectRatio: ratio, child: CameraPreview(c))
                  : Text(_status),
            ),
          ),
          SizedBox(
            width: 440,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: $_status'),
                  Text('Camera: $cameraName'),
                  Text(
                    'Frames: $_frames  (${_fps.toStringAsFixed(0)} per second)',
                  ),
                  Text('Last frame: $_frameInfo'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _cameras.isEmpty
                            ? null
                            : () => _open((_selected + 1) % _cameras.length),
                        child: const Text('Next camera'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _close(),
                        child: const Text('Close camera'),
                      ),
                      FilledButton.tonal(
                        onPressed: _cameras.isEmpty
                            ? null
                            : () => _open(_selected),
                        child: const Text('Open camera'),
                      ),
                      FilledButton.tonal(
                        onPressed: _takePhoto,
                        child: const Text('Take photo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final l in _log.reversed)
                          Text(
                            l,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
