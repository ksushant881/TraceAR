import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tracear/features/trace/trace_controller.dart';
import 'package:tracear/features/trace/widgets/grid_painter.dart';
import 'package:tracear/features/trace/widgets/overlay_layer.dart';
import 'package:tracear/features/trace/widgets/step_bar.dart';
import 'package:tracear/features/trace/widgets/toolbar.dart';
import 'package:tracear/features/trace/widgets/zoom_control.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';
import 'package:tracear/providers/app_providers.dart';
import 'package:tracear/services/camera_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TraceScreen extends ConsumerStatefulWidget {
  const TraceScreen({super.key, required this.imageId});

  final String imageId;

  @override
  ConsumerState<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends ConsumerState<TraceScreen>
    with WidgetsBindingObserver {
  static const Duration _hintDuration = Duration(seconds: 4);

  OverlayTransform _gestureStartTransform = const OverlayTransform();
  Offset _gestureStartFocal = Offset.zero;
  bool _showHints = true;
  Timer? _hintTimer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enableWakelock();
    _applyOrientation();
    _scheduleHideHints();
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _applyOrientation() async {
    final landscapeAllowed = ref.read(settingsProvider).landscapeAllowed;
    if (!landscapeAllowed) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void _scheduleHideHints() {
    _hintTimer?.cancel();
    _hintTimer = Timer(_hintDuration, () {
      if (mounted) setState(() => _showHints = false);
    });
  }

  void _showGestureHints() {
    setState(() => _showHints = true);
    _scheduleHideHints();
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(traceControllerProvider(widget.imageId).notifier);
    if (state == AppLifecycleState.inactive) {
      notifier.onAppInactive();
    } else if (state == AppLifecycleState.paused) {
      notifier.saveSessionNow();
    } else if (state == AppLifecycleState.resumed) {
      notifier.onAppResumed();
    }
  }

  /// Stops any recording and saves the session, then leaves the screen.
  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      await ref
          .read(traceControllerProvider(widget.imageId).notifier)
          .prepareToLeave();
    } finally {
      _leaving = false;
    }
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Size? _displayedPreviewSize(BuildContext context) {
    final preview = ref.read(cameraServiceProvider).previewSize;
    if (preview == null) return null;
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return isPortrait ? Size(preview.height, preview.width) : preview;
  }

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(traceControllerProvider(widget.imageId));
    final settings = ref.watch(settingsProvider);

    ref.listen<AsyncValue<TraceState>>(
      traceControllerProvider(widget.imageId),
      (prev, next) {
        final value = next.value;
        if (value == null || !mounted) return;
        final msg = value.statusMessage;
        if (msg != null && value.statusSeq != prev?.value?.statusSeq) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
          );
        }
        final wasLocked = prev?.value?.session.locked ?? false;
        if (wasLocked && !value.session.locked) {
          _showGestureHints();
        }
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: asyncState.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Error: $err')),
          data: (state) => _buildTrace(context, state, settings.gridSize),
        ),
      ),
    );
  }

  Widget _buildTrace(BuildContext context, TraceState state, int gridSize) {
    if (state.permissionPermanentlyDenied) {
      return _PermissionDeniedView(
        onOpenSettings: () => openAppSettings(),
        onBack: _leave,
      );
    }

    final controller = ref.read(
      traceControllerProvider(widget.imageId).notifier,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. Camera preview
        if (state.cameraReady)
          _CameraLayer(ref: ref)
        else
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.cameraError ?? 'Starting camera...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (state.cameraError != null) ...[
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: controller.retryCamera,
                    child: const Text('Try again'),
                  ),
                ],
              ],
            ),
          ),

        // 2. Overlay layer + gestures
        LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            final center = size.center(Offset.zero);
            return IgnorePointer(
              ignoring: state.session.locked,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (details) {
                  _gestureStartTransform = state.session.transform;
                  _gestureStartFocal = details.localFocalPoint - center;
                },
                onScaleUpdate: (details) {
                  final next = _gestureStartTransform.applyFocalGesture(
                    startFocal: _gestureStartFocal,
                    focal: details.localFocalPoint - center,
                    scaleFactor: details.scale,
                    rotationDelta: details.rotation,
                  );
                  controller.updateTransform(next);
                },
                onDoubleTap: controller.resetTransform,
                onTapUp: (details) {
                  controller.focusAt(
                    coverTapToPreviewPoint(
                      tap: details.localPosition,
                      screenSize: size,
                      displayedPreviewSize: _displayedPreviewSize(context),
                    ),
                  );
                },
                child: OverlayLayer(
                  session: state.session,
                  fullImage: state.fullImage,
                  stepImages: state.stepImages,
                  hideImage: state.hideImage,
                  showFullPicture: state.showFullPicture,
                ),
              ),
            );
          },
        ),

        // 3. Grid
        if (state.session.gridOn)
          IgnorePointer(
            child: CustomPaint(painter: GridPainter(gridSize: gridSize)),
          ),

        // Gesture hints (hidden while locked)
        if (_showHints && !state.session.locked)
          const Positioned(
            left: 24,
            right: 24,
            bottom: 200,
            child: IgnorePointer(child: _GestureHints()),
          ),

        // Camera zoom (right edge). Hidden while locked so the paper can't
        // shift under an aligned overlay.
        if (state.cameraReady && state.zoomSupported && !state.session.locked)
          Positioned(
            right: 8,
            top: MediaQuery.paddingOf(context).top + 120,
            bottom: 190,
            child: Center(
              child: ZoomControl(
                zoom: state.effectiveZoom,
                minZoom: state.zoomMin,
                maxZoom: state.zoomMax,
                onChanged: controller.setCameraZoom,
              ),
            ),
          ),

        // Top bar: Back + Lock badge + Step bar
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      IconButton.filledTonal(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        onPressed: _leave,
                      ),
                      const Spacer(),
                      if (state.loadingSteps)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      if (state.recordingKind != RecordingKind.none)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            state.recordingKind == RecordingKind.timelapse
                                ? 'TL • ${state.timelapseFrames}'
                                : 'REC',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      if (state.session.locked) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock, size: 14),
                              SizedBox(width: 4),
                              Text('Locked', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (state.session.mode == DrawMode.stepByStep)
                  StepBar(
                    currentStep: state.session.currentStep,
                    totalSteps: state.totalSteps,
                    onPrevious: () =>
                        controller.setStep(state.session.currentStep - 1),
                    onNext: () =>
                        controller.setStep(state.session.currentStep + 1),
                    onFinish: () =>
                        _showCompletionSheet(context, controller, state),
                    onSelectStep: controller.setStep,
                    onShowFullStart: () => controller.setShowFullPicture(true),
                    onShowFullEnd: () => controller.setShowFullPicture(false),
                  ),
              ],
            ),
          ),
        ),

        // 5. Toolbar at the bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: TraceToolbar(
            session: state.session,
            flashOn: state.flashOn,
            recordingKind: state.recordingKind,
            timelapseFrames: state.timelapseFrames,
            onOpacityChanged: controller.setOpacity,
            onToggleLock: () => controller.setLocked(true),
            onUnlockLongPress: () => controller.setLocked(false),
            onFlip: controller.toggleFlip,
            onToggleFlash: controller.toggleFlash,
            onToggleGrid: controller.toggleGrid,
            onToggleInvert: controller.toggleInvert,
            onHideStart: () => controller.setHideImage(true),
            onHideEnd: () => controller.setHideImage(false),
            onRecordTap: () {
              if (state.recordingKind != RecordingKind.none) {
                controller.stopRecording();
              } else {
                _showRecordSheet(context, controller);
              }
            },
            onToggleMode: controller.toggleMode,
            onReset: controller.resetTransform,
            onTakeResultPhoto: controller.takeResultPhoto,
          ),
        ),

        if (state.encodingProgress != null)
          ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Encoding timelapse...'),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(value: state.encodingProgress),
                      const SizedBox(height: 8),
                      Text('${((state.encodingProgress ?? 0) * 100).round()}%'),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _showRecordSheet(BuildContext context, TraceController controller) {
    var withAudio = false;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Record drawing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Record audio (video only)'),
                  value: withAudio,
                  onChanged: (v) => setModalState(() => withAudio = v),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('Video'),
                  subtitle: const Text('Standard real-time video'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.startVideoRecording(withAudio: withAudio);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.timelapse),
                  title: const Text('Timelapse'),
                  subtitle: const Text('Captures frames at set interval'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    controller.startTimelapse();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCompletionSheet(
    BuildContext context,
    TraceController controller,
    TraceState state,
  ) async {
    String? lastSavedPath;
    if (state.recordingKind != RecordingKind.none) {
      lastSavedPath = await controller.stopRecording();
    }
    if (!context.mounted) return;

    var takingPhoto = false;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Drawing complete!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: takingPhoto
                      ? null
                      : () async {
                          setSheetState(() => takingPhoto = true);
                          final photo = await controller.takeResultPhoto();
                          if (!ctx.mounted) return;
                          setSheetState(() {
                            takingPhoto = false;
                            if (photo != null) lastSavedPath = photo;
                          });
                        },
                  icon: const Icon(Icons.camera_alt),
                  label: Text(
                    takingPhoto ? 'Taking photo...' : 'Take photo of result',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: lastSavedPath == null
                      ? null
                      : () => SharePlus.instance.share(
                          ShareParams(files: [XFile(lastSavedPath!)]),
                        ),
                  icon: const Icon(Icons.share),
                  label: Text(
                    lastSavedPath == null
                        ? 'Share (take a photo first)'
                        : 'Share',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go('/');
                  },
                  child: const Text('Back to Home'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GestureHints extends StatelessWidget {
  const _GestureHints();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Drag to move · pinch to resize · twist to rotate · double-tap to reset · slider on the right zooms the camera',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }
}

class _CameraLayer extends StatelessWidget {
  const _CameraLayer({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cam = ref.watch(cameraServiceProvider);
    final previewSize = cam.previewSize;
    if (previewSize == null) {
      return cam.buildPreview();
    }
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final width = isPortrait ? previewSize.height : previewSize.width;
    final height = isPortrait ? previewSize.width : previewSize.height;

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: width,
          height: height,
          child: cam.buildPreview(),
        ),
      ),
    );
  }
}

class _PermissionDeniedView extends StatelessWidget {
  const _PermissionDeniedView({
    required this.onOpenSettings,
    required this.onBack,
  });

  final VoidCallback onOpenSettings;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Camera access needed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'TraceAR shows your paper through the camera so you can trace over it. Please enable camera access in Settings.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onBack, child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}
