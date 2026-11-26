import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Maps a tap at [tap] on a screen of [screenSize] to normalized (0..1)
/// coordinates of a camera preview that is laid out with `BoxFit.cover`.
///
/// [displayedPreviewSize] is the preview's aspect size as laid out on screen
/// (already swapped for portrait). If it is null, the screen is assumed to
/// show the full preview.
Offset coverTapToPreviewPoint({
  required Offset tap,
  required Size screenSize,
  Size? displayedPreviewSize,
}) {
  if (screenSize.isEmpty) return const Offset(0.5, 0.5);
  final preview = displayedPreviewSize;
  if (preview == null || preview.isEmpty) {
    return Offset(
      (tap.dx / screenSize.width).clamp(0.0, 1.0),
      (tap.dy / screenSize.height).clamp(0.0, 1.0),
    );
  }
  final scale = math.max(
    screenSize.width / preview.width,
    screenSize.height / preview.height,
  );
  final shownW = preview.width * scale;
  final shownH = preview.height * scale;
  final offX = (screenSize.width - shownW) / 2;
  final offY = (screenSize.height - shownH) / 2;
  return Offset(
    ((tap.dx - offX) / shownW).clamp(0.0, 1.0),
    ((tap.dy - offY) / shownH).clamp(0.0, 1.0),
  );
}

abstract class CameraService {
  bool get isInitialized;
  Size? get previewSize;
  bool get isFlashOn;
  bool get isRecordingVideo;

  Future<void> initialize({bool enableAudio = false});
  Future<void> dispose();
  Future<void> setFlashOn(bool on);
  Future<void> setFocusAndExposurePoint(Offset normalizedPoint);
  Future<void> lockCaptureOrientation(DeviceOrientation orientation);
  Future<void> unlockCaptureOrientation();
  Future<void> startVideoRecording();
  Future<String> stopVideoRecording();
  Future<String> takePicture();
  Widget buildPreview();
}

class DeviceCameraService implements CameraService {
  CameraController? _controller;
  bool _flashOn = false;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  Size? get previewSize => _controller?.value.previewSize;

  @override
  bool get isFlashOn => _flashOn;

  @override
  bool get isRecordingVideo => _controller?.value.isRecordingVideo ?? false;

  @override
  Future<void> initialize({bool enableAudio = false}) async {
    await dispose();
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available on this device.');
    }
    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.high,
      enableAudio: enableAudio,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.jpeg
          : ImageFormatGroup.yuv420,
    );
    _controller = controller;
    await controller.initialize();
    _flashOn = false;
  }

  @override
  Future<void> dispose() async {
    final c = _controller;
    _controller = null;
    _flashOn = false;
    await c?.dispose();
  }

  @override
  Future<void> setFlashOn(bool on) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    _flashOn = on;
  }

  @override
  Future<void> setFocusAndExposurePoint(Offset normalizedPoint) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final clamped = Offset(
      normalizedPoint.dx.clamp(0.0, 1.0),
      normalizedPoint.dy.clamp(0.0, 1.0),
    );
    try {
      await c.setFocusPoint(clamped);
    } catch (_) {}
    try {
      await c.setExposurePoint(clamped);
    } catch (_) {}
  }

  @override
  Future<void> lockCaptureOrientation(DeviceOrientation orientation) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.lockCaptureOrientation(orientation);
    } catch (_) {}
  }

  @override
  Future<void> unlockCaptureOrientation() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.unlockCaptureOrientation();
    } catch (_) {}
  }

  @override
  Future<void> startVideoRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw StateError('Camera not initialized.');
    }
    await c.startVideoRecording();
  }

  @override
  Future<String> stopVideoRecording() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw StateError('Camera not initialized.');
    }
    final file = await c.stopVideoRecording();
    return file.path;
  }

  @override
  Future<String> takePicture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      throw StateError('Camera not initialized.');
    }
    final file = await c.takePicture();
    return file.path;
  }

  @override
  Widget buildPreview() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(c);
  }
}
