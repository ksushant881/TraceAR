import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:tracear/models/step_set.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';
import 'package:tracear/providers/app_providers.dart';
import 'package:tracear/services/camera_service.dart';
import 'package:tracear/services/session_store.dart';

enum RecordingKind { none, video, timelapse }

class TraceState {
  const TraceState({
    required this.image,
    required this.session,
    this.fullImage,
    this.stepImages = const [],
    this.stepSet,
    this.cameraReady = false,
    this.permissionPermanentlyDenied = false,
    this.cameraError,
    this.flashOn = false,
    this.zoomMin = 1.0,
    this.zoomMax = 1.0,
    this.hideImage = false,
    this.showFullPicture = false,
    this.recordingKind = RecordingKind.none,
    this.timelapseFrames = 0,
    this.encodingProgress,
    this.loadingSteps = false,
    this.statusMessage,
    this.statusSeq = 0,
  });

  final TraceImage image;
  final TraceSession session;
  final ui.Image? fullImage;
  final List<ui.Image> stepImages;
  final StepSet? stepSet;
  final bool cameraReady;
  final bool permissionPermanentlyDenied;
  final String? cameraError;
  final bool flashOn;

  /// Zoom range of the active camera; equal when zoom is unsupported.
  final double zoomMin;
  final double zoomMax;
  final bool hideImage;
  final bool showFullPicture;
  final RecordingKind recordingKind;
  final int timelapseFrames;
  final double? encodingProgress;
  final bool loadingSteps;
  final String? statusMessage;

  /// Increments every time a status message is posted, so the UI shows the
  /// same message again if it is posted twice in a row.
  final int statusSeq;

  int get totalSteps => stepImages.length;

  bool get zoomSupported => zoomMax > zoomMin + 0.01;

  /// The zoom actually in effect: the saved zoom clamped to this camera.
  double get effectiveZoom => session.cameraZoom.clamp(zoomMin, zoomMax);

  TraceState copyWith({
    TraceImage? image,
    TraceSession? session,
    ui.Image? fullImage,
    List<ui.Image>? stepImages,
    StepSet? stepSet,
    bool? cameraReady,
    bool? permissionPermanentlyDenied,
    String? cameraError,
    bool clearCameraError = false,
    bool? flashOn,
    double? zoomMin,
    double? zoomMax,
    bool? hideImage,
    bool? showFullPicture,
    RecordingKind? recordingKind,
    int? timelapseFrames,
    double? encodingProgress,
    bool clearEncodingProgress = false,
    bool? loadingSteps,
    String? statusMessage,
    bool clearStatus = false,
  }) {
    return TraceState(
      image: image ?? this.image,
      session: session ?? this.session,
      fullImage: fullImage ?? this.fullImage,
      stepImages: stepImages ?? this.stepImages,
      stepSet: stepSet ?? this.stepSet,
      cameraReady: cameraReady ?? this.cameraReady,
      permissionPermanentlyDenied:
          permissionPermanentlyDenied ?? this.permissionPermanentlyDenied,
      cameraError: clearCameraError ? null : (cameraError ?? this.cameraError),
      flashOn: flashOn ?? this.flashOn,
      zoomMin: zoomMin ?? this.zoomMin,
      zoomMax: zoomMax ?? this.zoomMax,
      hideImage: hideImage ?? this.hideImage,
      showFullPicture: showFullPicture ?? this.showFullPicture,
      recordingKind: recordingKind ?? this.recordingKind,
      timelapseFrames: timelapseFrames ?? this.timelapseFrames,
      encodingProgress: clearEncodingProgress
          ? null
          : (encodingProgress ?? this.encodingProgress),
      loadingSteps: loadingSteps ?? this.loadingSteps,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      statusSeq: statusMessage != null ? statusSeq + 1 : statusSeq,
    );
  }
}

/// Outcome of a camera (re)initialization.
typedef _CameraInit = ({bool ready, bool permanentlyDenied, String? error});

class TraceController extends AsyncNotifier<TraceState> {
  TraceController(this.imageId);

  final String imageId;
  Timer? _saveDebounce;
  TraceSession? _pendingSave;
  Timer? _timelapseTimer;
  Directory? _timelapseDir;
  int _timelapseFrameIndex = 0;
  bool _timelapsePaused = false;
  Future<void>? _inFlightCapture;
  StreamSubscription<double>? _progressSub;

  /// Serializes every camera-controller operation so init/dispose/record
  /// calls never overlap (e.g. lifecycle events racing a re-init).
  Future<void> _cameraQueue = Future<void>.value();

  /// > 0 while a system permission dialog is showing. The dialog makes the
  /// app briefly `inactive`; that must not tear down the camera.
  int _permissionDialogs = 0;

  /// True after the camera was released because the app went `inactive`.
  /// Only then does `resumed` re-create it.
  bool _cameraSuspended = false;

  /// Latest zoom requested while a zoom change is still being applied.
  /// Slider drags fire many updates; only the newest one is sent.
  double? _zoomTarget;
  bool _zoomApplying = false;

  CameraService get _camera => ref.read(cameraServiceProvider);
  SessionStore get _sessionStore => ref.read(sessionStoreProvider);

  @override
  Future<TraceState> build() async {
    // Captured now: `ref` must not be used inside onDispose.
    final camera = ref.read(cameraServiceProvider);
    final sessionStore = ref.read(sessionStoreProvider);
    ref.onDispose(() {
      _saveDebounce?.cancel();
      final pending = _pendingSave;
      _pendingSave = null;
      if (pending != null) {
        unawaited(sessionStore.save(pending).catchError((Object _) {}));
      }
      _timelapseTimer?.cancel();
      _progressSub?.cancel();
      final tlDir = _timelapseDir;
      _timelapseDir = null;
      if (tlDir != null) {
        unawaited(
          tlDir.delete(recursive: true).then((_) {}, onError: (Object _) {}),
        );
      }
      unawaited(_serialCamera(camera.dispose).catchError((Object _) {}));
    });

    final library = ref.read(imageLibraryServiceProvider);
    final settings = ref.read(settingsProvider);

    final image = await library.getById(imageId);
    if (image == null) {
      throw StateError('Image $imageId not found.');
    }

    final session =
        (await sessionStore.load(imageId)) ??
        TraceSession(
          imageId: imageId,
          useLineArt: settings.defaultLineArt,
          opacity: settings.defaultOpacity,
          highlightColor: settings.highlightColor,
          lineArtParams: LineArtParams(stepCount: settings.defaultStepCount),
        );

    final fullImage = await _loadFullUiImage(image, session.useLineArt);
    final stepResult = await _loadSteps(image, session);

    var clampedSession = session;
    if (stepResult.images.isNotEmpty &&
        session.currentStep >= stepResult.images.length) {
      clampedSession = session.copyWith(
        currentStep: stepResult.images.length - 1,
      );
    }

    final initial = TraceState(
      image: image,
      session: clampedSession,
      fullImage: fullImage,
      stepImages: stepResult.images,
      stepSet: stepResult.stepSet,
    );

    final cam = await _initCamera(zoom: clampedSession.cameraZoom);
    return _applyCameraInit(initial, cam);
  }

  // ---------------------------------------------------------------------------
  // Helpers

  Future<T> _serialCamera<T>(Future<T> Function() op) {
    final completer = Completer<T>();
    _cameraQueue = _cameraQueue.then((_) async {
      try {
        completer.complete(await op());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<PermissionStatus> _requestPermission(Permission permission) async {
    _permissionDialogs++;
    try {
      return await permission.request();
    } finally {
      _permissionDialogs--;
    }
  }

  /// Sets state only while the provider is alive.
  void _emit(TraceState Function(TraceState current) update) {
    if (!ref.mounted) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(update(current));
  }

  void _status(String message) {
    _emit((s) => s.copyWith(statusMessage: message));
  }

  Future<ui.Image> _loadFullUiImage(TraceImage image, bool useLineArt) async {
    final Uint8List bytes;
    if (image.source == ImageSource.template) {
      final data = await rootBundle.load(image.originalPath);
      bytes = data.buffer.asUint8List();
    } else {
      final path = (useLineArt && image.lineArtPath != null)
          ? image.lineArtPath!
          : image.originalPath;
      bytes = await File(path).readAsBytes();
    }
    final decode = ref.read(imageDecoderProvider);
    return decode(bytes);
  }

  Future<({List<ui.Image> images, StepSet? stepSet})> _loadSteps(
    TraceImage image,
    TraceSession session,
  ) async {
    if (image.source == ImageSource.template) {
      final template = await ref
          .read(imageLibraryServiceProvider)
          .getTemplateForImageId(image.id);
      if (template == null) return (images: <ui.Image>[], stepSet: null);
      final uiImages = <ui.Image>[];
      final decode = ref.read(imageDecoderProvider);
      for (final assetPath in template.stepAssetPaths) {
        final data = await rootBundle.load(assetPath);
        uiImages.add(await decode(data.buffer.asUint8List()));
      }
      return (
        images: uiImages,
        stepSet: StepSet(
          imageId: image.id,
          paramsHash: 'bundled',
          stepPaths: template.stepAssetPaths,
          isAsset: true,
        ),
      );
    }

    if (session.mode != DrawMode.stepByStep) {
      return (images: <ui.Image>[], stepSet: null);
    }

    final stepSet = await ref
        .read(stepCacheServiceProvider)
        .getOrGenerate(image: image, params: session.lineArtParams);
    final uiImages = <ui.Image>[];
    final decode = ref.read(imageDecoderProvider);
    for (final path in stepSet.stepPaths) {
      final bytes = await File(path).readAsBytes();
      uiImages.add(await decode(bytes));
    }
    return (images: uiImages, stepSet: stepSet);
  }

  /// Requests the camera permission (optionally) and (re)creates the camera
  /// controller, locking orientation and restoring the torch.
  Future<_CameraInit> _initCamera({
    bool enableAudio = false,
    bool requestPermission = true,
    bool restoreTorch = false,
    double? zoom,
  }) async {
    if (requestPermission) {
      try {
        final camStatus = await _requestPermission(Permission.camera);
        if (camStatus.isPermanentlyDenied) {
          return (ready: false, permanentlyDenied: true, error: null);
        }
        if (!camStatus.isGranted) {
          return (
            ready: false,
            permanentlyDenied: false,
            error: 'Camera permission is required to trace.',
          );
        }
      } on MissingPluginException {
        // Widget tests have no permission plugin; continue to CameraService.
      } catch (_) {
        // Same as above for other test/platform setups.
      }
    }

    if (!ref.mounted) {
      return (ready: false, permanentlyDenied: false, error: null);
    }
    final cam = _camera;
    final landscapeAllowed = ref.read(settingsProvider).landscapeAllowed;
    final targetZoom = zoom ?? state.value?.session.cameraZoom ?? 1.0;
    try {
      await _serialCamera(() async {
        await cam.initialize(enableAudio: enableAudio);
        if (!landscapeAllowed) {
          await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
        }
        if (restoreTorch) {
          await cam.setFlashOn(true);
        }
        try {
          await cam.setZoom(targetZoom);
        } catch (_) {}
      });
      return (ready: true, permanentlyDenied: false, error: null);
    } catch (e) {
      return (
        ready: false,
        permanentlyDenied: false,
        error: 'Camera error: $e',
      );
    }
  }

  TraceState _applyCameraInit(TraceState s, _CameraInit r) {
    if (r.ready) {
      final cam = _camera;
      return s.copyWith(
        cameraReady: true,
        zoomMin: cam.minZoom,
        zoomMax: cam.maxZoom,
        permissionPermanentlyDenied: false,
        clearCameraError: true,
      );
    }
    return s.copyWith(
      cameraReady: false,
      flashOn: false,
      permissionPermanentlyDenied: r.permanentlyDenied,
      cameraError: r.error,
    );
  }

  // ---------------------------------------------------------------------------
  // Lifecycle

  Future<void> onAppInactive() async {
    if (_permissionDialogs > 0 || _cameraSuspended) return;
    _cameraSuspended = true;

    final current = state.value;
    if (current != null) {
      if (current.recordingKind == RecordingKind.video) {
        // The controller is about to be released; finish and save the clip
        // instead of losing it.
        await stopRecording();
      } else if (current.recordingKind == RecordingKind.timelapse) {
        _timelapseTimer?.cancel();
        _timelapseTimer = null;
        _timelapsePaused = true;
        await _inFlightCapture;
      }
      await saveSessionNow();
    }

    if (!ref.mounted) return;
    // Remove the preview from the tree before releasing its controller.
    _emit((s) => s.copyWith(cameraReady: false, flashOn: false));
    final cam = _camera;
    await _serialCamera(cam.dispose).catchError((Object _) {});
  }

  Future<void> onAppResumed() async {
    if (!_cameraSuspended) return;
    _cameraSuspended = false;
    if (state.value == null) return;

    final r = await _initCamera();
    if (!ref.mounted) return;
    _emit((s) => _applyCameraInit(s, r));

    if (_timelapsePaused) {
      _timelapsePaused = false;
      if (r.ready && state.value?.recordingKind == RecordingKind.timelapse) {
        _startTimelapseTimer();
      }
    }
  }

  /// Re-tries camera setup (e.g. after the user denied the permission once).
  Future<void> retryCamera() async {
    final r = await _initCamera();
    _emit((s) => _applyCameraInit(s, r));
  }

  /// Stops any recording and flushes the session before leaving the screen.
  Future<void> prepareToLeave() async {
    final current = state.value;
    if (current != null && current.recordingKind != RecordingKind.none) {
      await stopRecording();
    }
    await saveSessionNow();
  }

  // ---------------------------------------------------------------------------
  // Session

  void _updateSession(TraceSession nextSession) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(session: nextSession));
    _pendingSave = nextSession;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      final pending = _pendingSave;
      _pendingSave = null;
      if (pending == null || !ref.mounted) return;
      unawaited(_sessionStore.save(pending).catchError((Object _) {}));
    });
  }

  Future<void> saveSessionNow() async {
    _saveDebounce?.cancel();
    _pendingSave = null;
    if (!ref.mounted) return;
    final current = state.value;
    if (current != null) {
      try {
        await _sessionStore.save(current.session);
      } catch (_) {}
    }
  }

  void updateTransform(OverlayTransform transform) {
    final current = state.value;
    if (current == null || current.session.locked) return;
    _updateSession(current.session.copyWith(transform: transform));
  }

  void resetTransform() {
    final current = state.value;
    if (current == null || current.session.locked) return;
    _updateSession(
      current.session.copyWith(transform: const OverlayTransform()),
    );
  }

  void setOpacity(double opacity) {
    final current = state.value;
    if (current == null) return;
    _updateSession(current.session.copyWith(opacity: opacity));
  }

  void setLocked(bool locked) {
    final current = state.value;
    if (current == null) return;
    _updateSession(current.session.copyWith(locked: locked));
  }

  void toggleFlip() {
    final current = state.value;
    if (current == null) return;
    final t = current.session.transform;
    _updateSession(
      current.session.copyWith(transform: t.copyWith(flipH: !t.flipH)),
    );
  }

  void toggleGrid() {
    final current = state.value;
    if (current == null) return;
    _updateSession(current.session.copyWith(gridOn: !current.session.gridOn));
  }

  void toggleInvert() {
    final current = state.value;
    if (current == null) return;
    _updateSession(
      current.session.copyWith(inverted: !current.session.inverted),
    );
  }

  void setHideImage(bool hide) {
    _emit((s) => s.copyWith(hideImage: hide));
  }

  void setShowFullPicture(bool show) {
    _emit((s) => s.copyWith(showFullPicture: show));
  }

  Future<void> toggleFlash() async {
    final current = state.value;
    if (current == null || !current.cameraReady) return;
    final next = !current.flashOn;
    final cam = _camera;
    try {
      await _serialCamera(() => cam.setFlashOn(next));
      _emit((s) => s.copyWith(flashOn: next));
    } catch (e) {
      _status('Flashlight unavailable: $e');
    }
  }

  /// Changes the camera zoom. Disabled while locked: zooming would move the
  /// paper relative to the already-aligned overlay.
  void setCameraZoom(double zoom) {
    final current = state.value;
    if (current == null ||
        current.session.locked ||
        !current.cameraReady ||
        !current.zoomSupported) {
      return;
    }
    final clamped = zoom.clamp(current.zoomMin, current.zoomMax);
    _updateSession(current.session.copyWith(cameraZoom: clamped));
    _zoomTarget = clamped;
    if (!_zoomApplying) unawaited(_drainZoom());
  }

  Future<void> _drainZoom() async {
    _zoomApplying = true;
    final cam = _camera;
    try {
      while (_zoomTarget != null && ref.mounted) {
        final target = _zoomTarget!;
        _zoomTarget = null;
        await _serialCamera(() => cam.setZoom(target))
            .catchError((Object _) {});
      }
    } finally {
      _zoomApplying = false;
    }
  }

  Future<void> focusAt(Offset normalizedPoint) async {
    final current = state.value;
    if (current == null || current.session.locked || !current.cameraReady) {
      return;
    }
    final cam = _camera;
    await _serialCamera(() => cam.setFocusAndExposurePoint(normalizedPoint));
  }

  Future<void> toggleMode() async {
    final current = state.value;
    if (current == null || current.loadingSteps) return;
    final nextMode = current.session.mode == DrawMode.full
        ? DrawMode.stepByStep
        : DrawMode.full;
    var nextSession = current.session.copyWith(mode: nextMode);
    if (nextMode == DrawMode.stepByStep && current.stepImages.isEmpty) {
      _emit((s) => s.copyWith(loadingSteps: true));
      try {
        final loaded = await _loadSteps(current.image, nextSession);
        if (!ref.mounted) return;
        if (loaded.images.isNotEmpty) {
          nextSession = nextSession.copyWith(
            currentStep: nextSession.currentStep.clamp(
              0,
              loaded.images.length - 1,
            ),
          );
        }
        _emit((s) {
          // Keep any session edits made while steps were generating.
          final merged = s.session.copyWith(
            mode: nextSession.mode,
            currentStep: nextSession.currentStep,
          );
          return s.copyWith(
            stepImages: loaded.images,
            stepSet: loaded.stepSet,
            session: merged,
            loadingSteps: false,
          );
        });
        await saveSessionNow();
      } catch (e) {
        _emit(
          (s) => s.copyWith(
            loadingSteps: false,
            statusMessage: 'Could not create steps: $e',
          ),
        );
      }
      return;
    }
    _updateSession(nextSession);
  }

  void setStep(int index) {
    final current = state.value;
    if (current == null || current.totalSteps == 0) return;
    final clamped = index.clamp(0, current.totalSteps - 1);
    _updateSession(current.session.copyWith(currentStep: clamped));
  }

  // ---------------------------------------------------------------------------
  // Recording

  Future<void> startVideoRecording({required bool withAudio}) async {
    final current = state.value;
    if (current == null ||
        !current.cameraReady ||
        current.recordingKind != RecordingKind.none) {
      return;
    }

    if (withAudio) {
      PermissionStatus mic;
      try {
        mic = await _requestPermission(Permission.microphone);
      } catch (_) {
        mic = PermissionStatus.denied;
      }
      if (!ref.mounted) return;
      if (!mic.isGranted) {
        _status('Microphone permission denied.');
        return;
      }
      // Re-create the controller with audio. Hide the preview first so it is
      // never built with a disposed controller.
      final torch = state.value?.flashOn ?? false;
      _emit((s) => s.copyWith(cameraReady: false));
      final r = await _initCamera(
        enableAudio: true,
        requestPermission: false,
        restoreTorch: torch,
      );
      if (!ref.mounted) return;
      _emit((s) => _applyCameraInit(s, r));
      if (!r.ready) return;
    }

    final cam = _camera;
    try {
      await _serialCamera(cam.startVideoRecording);
    } catch (e) {
      _status('Could not start recording: $e');
      return;
    }
    _emit(
      (s) => s.copyWith(recordingKind: RecordingKind.video, clearStatus: true),
    );
  }

  Future<void> startTimelapse() async {
    final current = state.value;
    if (current == null ||
        !current.cameraReady ||
        current.recordingKind != RecordingKind.none) {
      return;
    }

    final recService = ref.read(recordingServiceProvider);
    final Directory dir;
    try {
      dir = await recService.createTempTimelapseDir();
    } catch (e) {
      _status('Could not start timelapse: $e');
      return;
    }
    if (!ref.mounted) return;
    _timelapseDir = dir;
    _timelapseFrameIndex = 0;
    _timelapsePaused = false;

    _emit(
      (s) => s.copyWith(
        recordingKind: RecordingKind.timelapse,
        timelapseFrames: 0,
        clearStatus: true,
      ),
    );

    await _captureFrame();
    _startTimelapseTimer();
  }

  void _startTimelapseTimer() {
    if (!ref.mounted) return;
    final intervalSec = ref.read(settingsProvider).timelapseIntervalSec;
    _timelapseTimer?.cancel();
    _timelapseTimer = Timer.periodic(
      Duration(seconds: intervalSec),
      (_) => _captureFrame(),
    );
  }

  /// Captures one timelapse frame; never overlaps a capture in progress.
  Future<void> _captureFrame() async {
    if (_inFlightCapture != null || !ref.mounted) return;
    final s = state.value;
    final dir = _timelapseDir;
    if (s == null ||
        dir == null ||
        s.recordingKind != RecordingKind.timelapse ||
        !s.cameraReady) {
      return;
    }
    final capture = _captureFrameInto(dir);
    _inFlightCapture = capture;
    try {
      await capture;
    } finally {
      _inFlightCapture = null;
    }
  }

  Future<void> _captureFrameInto(Directory dir) async {
    final cam = _camera;
    try {
      final tempPath = await _serialCamera(cam.takePicture);
      final index = _timelapseFrameIndex + 1;
      final name = 'frame_${index.toString().padLeft(5, '0')}.jpg';
      final dest = '${dir.path}${Platform.pathSeparator}$name';
      await File(tempPath).copy(dest);
      _timelapseFrameIndex = index;
      try {
        await File(tempPath).delete();
      } catch (_) {}
      _emit((s) => s.copyWith(timelapseFrames: index));
    } catch (_) {
      // A single failed frame is skipped.
    }
  }

  Future<String?> stopRecording() async {
    final current = state.value;
    if (current == null || current.recordingKind == RecordingKind.none) {
      return null;
    }
    final recService = ref.read(recordingServiceProvider);

    if (current.recordingKind == RecordingKind.video) {
      // Mark stopped first so a second tap can't stop twice.
      _emit((s) => s.copyWith(recordingKind: RecordingKind.none));
      final cam = _camera;
      try {
        final tempPath = await _serialCamera(cam.stopVideoRecording);
        final savedPath = await recService.saveVideoToLibraryAndGallery(
          tempPath,
        );
        _status('Video saved to Gallery');
        return savedPath;
      } catch (e) {
        _status('Video could not be saved: $e');
        return null;
      }
    }

    // Timelapse
    _timelapseTimer?.cancel();
    _timelapseTimer = null;
    _timelapsePaused = false;
    _emit(
      (s) =>
          s.copyWith(recordingKind: RecordingKind.none, encodingProgress: 0.0),
    );

    // Let a frame that is still being written finish before encoding.
    await _inFlightCapture;

    final dir = _timelapseDir;
    _timelapseDir = null;
    final frameCount = _timelapseFrameIndex;
    if (dir == null) {
      _emit((s) => s.copyWith(clearEncodingProgress: true));
      return null;
    }
    if (frameCount == 0) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      _emit(
        (s) => s.copyWith(
          clearEncodingProgress: true,
          statusMessage: 'No timelapse frames were captured.',
        ),
      );
      return null;
    }

    final bridge = ref.read(nativeBridgeProvider);
    final fps = ref.read(settingsProvider).timelapseFps;
    await _progressSub?.cancel();
    _progressSub = bridge.timelapseProgressStream.listen(
      (progress) => _emit((s) => s.copyWith(encodingProgress: progress)),
      onError: (Object _) {},
    );

    final res = await recService.finalizeTimelapse(frameDir: dir, fps: fps);

    await _progressSub?.cancel();
    _progressSub = null;

    return res.when(
      ok: (outPath) {
        _emit(
          (s) => s.copyWith(
            clearEncodingProgress: true,
            statusMessage: 'Timelapse saved to Gallery',
          ),
        );
        return outPath;
      },
      err: (msg, _) {
        _emit(
          (s) => s.copyWith(clearEncodingProgress: true, statusMessage: msg),
        );
        return null;
      },
    );
  }

  Future<String?> takeResultPhoto() async {
    final current = state.value;
    if (current == null || !current.cameraReady) return null;
    final cam = _camera;
    final recService = ref.read(recordingServiceProvider);
    try {
      final tempPath = await _serialCamera(cam.takePicture);
      final saved = await recService.savePhotoToLibraryAndGallery(tempPath);
      _status('Result photo saved to Gallery');
      return saved;
    } catch (e) {
      _status('Photo failed: $e');
      return null;
    }
  }
}

final traceControllerProvider = AsyncNotifierProvider.autoDispose
    .family<TraceController, TraceState, String>(TraceController.new);
