import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../ffi/decode_result.dart';
import '../../ffi/decoder_service.dart';
import 'link_pairing.dart';

/// Returns the pairing payload when [text] is an Exalted pairing code,
/// otherwise null. Expiry is checked later, by the link controller.
PairingPayload? pairingFromScan(String text) {
  try {
    return PairingPayload.parse(text.trim());
  } catch (_) {
    return null;
  }
}

enum _Phase { starting, ready, denied, blocked, noCamera, error }

/// Scans the pairing QR code shown on the desktop. It uses its own camera and
/// decoder and saves nothing: the code holds a one-time token. It closes with
/// the code text, or with null when the user leaves.
class PairingScanScreen extends StatefulWidget {
  const PairingScanScreen({super.key});

  @override
  State<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends State<PairingScanScreen> {
  final DecoderService _decoder = DecoderService();
  CameraController? _camera;
  _Phase _phase = _Phase.starting;
  String? _hint;
  bool _done = false;
  bool _busy = false;
  int _lastMs = 0;
  Future<void>? _inflight;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    if (mounted) setState(() => _phase = _Phase.starting);
    try {
      if (!_decoder.isAvailable) {
        if (mounted) setState(() => _phase = _Phase.error);
        return;
      }
      var perm = await Permission.camera.status;
      if (!perm.isGranted) perm = await Permission.camera.request();
      if (!mounted) return;
      if (perm.isPermanentlyDenied) {
        setState(() => _phase = _Phase.blocked);
        return;
      }
      if (!perm.isGranted) {
        setState(() => _phase = _Phase.denied);
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _phase = _Phase.noCamera);
        return;
      }
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted || _done) {
        await controller.dispose();
        return;
      }
      _camera = controller;
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _phase = _Phase.ready);
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.error);
    }
  }

  void _onFrame(CameraImage image) {
    if (_done || _busy) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMs < 150) return;
    _lastMs = now;
    _busy = true;
    final y = image.planes.first;
    _inflight = _decode(y.bytes, image.width, image.height, y.bytesPerRow);
  }

  Future<void> _decode(
    Uint8List luma,
    int width,
    int height,
    int stride,
  ) async {
    try {
      final r = await _decoder.decodeAsync(
        luma: luma,
        width: width,
        height: height,
        rowStride: stride,
        formatsMask: BarcodeKind.qrCode.flag,
      );
      if (r == null || _done || !mounted) return;
      if (pairingFromScan(r.text) != null) {
        _done = true;
        Navigator.of(context).pop(r.text.trim());
      } else if (_hint == null) {
        setState(() => _hint = 'That QR code is not an Exalted pairing code.');
      }
    } catch (_) {
      // A failed frame is skipped; the next one is tried.
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _done = true;
    final cam = _camera;
    final inflight = _inflight;
    final decoder = _decoder;
    unawaited(() async {
      try {
        if (cam != null && cam.value.isStreamingImages) {
          await cam.stopImageStream();
        }
      } catch (_) {}
      try {
        await cam?.dispose();
      } catch (_) {}
      try {
        await inflight;
      } catch (_) {}
      decoder.dispose();
    }());
    super.dispose();
  }

  Widget _message(String text, {bool retry = false, bool settings = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (retry)
              FilledButton(onPressed: _start, child: const Text('Try again')),
            if (settings)
              FilledButton(
                onPressed: openAppSettings,
                child: const Text('Open settings'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    final Widget body;
    switch (_phase) {
      case _Phase.starting:
        body = const Center(child: CircularProgressIndicator());
      case _Phase.ready:
        body = Stack(
          fit: StackFit.expand,
          children: [
            if (cam != null) Center(child: CameraPreview(cam)),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black54,
                padding: const EdgeInsets.all(16),
                child: Text(
                  _hint ?? 'Point the camera at the QR code on the desktop.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      case _Phase.denied:
        body = _message(
          'Camera access is needed to scan the pairing code.',
          retry: true,
        );
      case _Phase.blocked:
        body = _message(
          'Camera access is turned off for Exalted. Turn it on in the '
          'phone settings, or go back and paste the code instead.',
          settings: true,
        );
      case _Phase.noCamera:
        body = _message('No camera was found on this device.');
      case _Phase.error:
        body = _message(
          'The camera could not be started. Go back and paste the code '
          'instead.',
          retry: true,
        );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Scan pairing code')),
      body: body,
    );
  }
}
