import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracear/models/template_item.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';
import 'package:tracear/providers/app_providers.dart';
import 'package:tracear/services/lineart/lineart_pipeline.dart';
import 'package:tracear/services/lineart/step_generator.dart';

class PrepareState {
  const PrepareState({
    required this.image,
    required this.session,
    this.template,
    this.showLineArt = true,
    this.lineArtBytes,
    this.stepPreviewPngs = const [],
    this.stepPreviewParams,
    this.isProcessingLineArt = false,
    this.isProcessingSteps = false,
    this.isCropping = false,
    this.isStarting = false,
    this.errorMessage,
  });

  final TraceImage image;
  final TraceSession session;
  final TemplateItem? template;
  final bool showLineArt;
  final Uint8List? lineArtBytes;
  final List<Uint8List> stepPreviewPngs;

  /// The params [stepPreviewPngs] were generated with, so "Start tracing"
  /// can reuse them instead of generating the same steps again.
  final LineArtParams? stepPreviewParams;
  final bool isProcessingLineArt;
  final bool isProcessingSteps;
  final bool isCropping;
  final bool isStarting;
  final String? errorMessage;

  bool get isTemplate => image.source == ImageSource.template;

  PrepareState copyWith({
    TraceImage? image,
    TraceSession? session,
    TemplateItem? template,
    bool? showLineArt,
    Uint8List? lineArtBytes,
    List<Uint8List>? stepPreviewPngs,
    LineArtParams? stepPreviewParams,
    bool clearStepPreview = false,
    bool? isProcessingLineArt,
    bool? isProcessingSteps,
    bool? isCropping,
    bool? isStarting,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PrepareState(
      image: image ?? this.image,
      session: session ?? this.session,
      template: template ?? this.template,
      showLineArt: showLineArt ?? this.showLineArt,
      lineArtBytes: lineArtBytes ?? this.lineArtBytes,
      stepPreviewPngs: clearStepPreview
          ? const []
          : (stepPreviewPngs ?? this.stepPreviewPngs),
      stepPreviewParams: clearStepPreview
          ? null
          : (stepPreviewParams ?? this.stepPreviewParams),
      isProcessingLineArt: isProcessingLineArt ?? this.isProcessingLineArt,
      isProcessingSteps: isProcessingSteps ?? this.isProcessingSteps,
      isCropping: isCropping ?? this.isCropping,
      isStarting: isStarting ?? this.isStarting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PrepareController extends AsyncNotifier<PrepareState> {
  PrepareController(this.imageId);

  final String imageId;
  Timer? _debounceTimer;
  Timer? _stepsDebounceTimer;
  int _lineArtSeq = 0;
  int _stepsSeq = 0;

  @override
  Future<PrepareState> build() async {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _stepsDebounceTimer?.cancel();
    });

    final library = ref.read(imageLibraryServiceProvider);
    final sessionStore = ref.read(sessionStoreProvider);
    final settings = ref.read(settingsProvider);

    final image = await library.getById(imageId);
    if (image == null) {
      throw StateError('Image $imageId not found.');
    }

    final template = await library.getTemplateForImageId(imageId);
    final existingSession = await sessionStore.load(imageId);
    final session =
        existingSession ??
        TraceSession(
          imageId: imageId,
          useLineArt: settings.defaultLineArt,
          opacity: settings.defaultOpacity,
          highlightColor: settings.highlightColor,
          lineArtParams: LineArtParams(stepCount: settings.defaultStepCount),
        );

    Uint8List? lineArtBytes;
    List<Uint8List> stepPngs = const [];

    if (template != null) {
      final data = await rootBundle.load(template.fullAssetPath);
      lineArtBytes = data.buffer.asUint8List();
      final loadedSteps = <Uint8List>[];
      for (final assetPath in template.stepAssetPaths) {
        final stepData = await rootBundle.load(assetPath);
        loadedSteps.add(stepData.buffer.asUint8List());
      }
      stepPngs = loadedSteps;
    } else if (image.lineArtPath != null &&
        await File(image.lineArtPath!).exists()) {
      lineArtBytes = await File(image.lineArtPath!).readAsBytes();
    }

    final initial = PrepareState(
      image: image,
      session: session,
      template: template,
      showLineArt: template != null ? true : session.useLineArt,
      lineArtBytes: lineArtBytes,
      stepPreviewPngs: stepPngs,
    );

    if (template == null) {
      if (lineArtBytes == null) {
        Future.microtask(() => _runLineArt(initial.session.lineArtParams));
      }
      if (session.mode == DrawMode.stepByStep) {
        Future.microtask(() => _runStepPreview(initial.session.lineArtParams));
      }
    }

    return initial;
  }

  void togglePreview(bool showLineArt) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        showLineArt: showLineArt,
        session: current.session.copyWith(useLineArt: showLineArt),
      ),
    );
  }

  void updateLineArtParams({double? strength, int? thickness}) {
    final current = state.value;
    if (current == null || current.isTemplate) return;

    final nextParams = current.session.lineArtParams.copyWith(
      strength: strength,
      thickness: thickness,
    );
    state = AsyncData(
      current.copyWith(
        session: current.session.copyWith(lineArtParams: nextParams),
      ),
    );

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _runLineArt(nextParams);
      if (state.value?.session.mode == DrawMode.stepByStep) {
        _runStepPreview(nextParams);
      }
    });
  }

  void setMode(DrawMode mode) {
    final current = state.value;
    if (current == null) return;
    final nextSession = current.session.copyWith(mode: mode);
    state = AsyncData(current.copyWith(session: nextSession));

    if (mode == DrawMode.stepByStep &&
        !current.isTemplate &&
        current.stepPreviewPngs.isEmpty) {
      _runStepPreview(nextSession.lineArtParams);
    }
  }

  void updateStepParams({int? stepCount, bool? includeShading}) {
    final current = state.value;
    if (current == null || current.isTemplate) return;

    final nextParams = current.session.lineArtParams.copyWith(
      stepCount: stepCount,
      includeShading: includeShading,
    );
    state = AsyncData(
      current.copyWith(
        session: current.session.copyWith(lineArtParams: nextParams),
      ),
    );

    _stepsDebounceTimer?.cancel();
    _stepsDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      _runStepPreview(nextParams);
    });
  }

  Future<void> rotate90() async {
    final current = state.value;
    if (current == null || current.isTemplate) return;

    state = AsyncData(current.copyWith(isProcessingLineArt: true));
    final updated = await ref
        .read(imageLibraryServiceProvider)
        .rotate90(current.image.id);
    if (!ref.mounted) return;
    final refreshed = state.value;
    if (refreshed == null) return;
    state = AsyncData(
      refreshed.copyWith(image: updated, clearStepPreview: true),
    );
    await _runLineArt(refreshed.session.lineArtParams);
    if (refreshed.session.mode == DrawMode.stepByStep) {
      await _runStepPreview(refreshed.session.lineArtParams);
    }
  }

  void setCropping(bool cropping) {
    final current = state.value;
    if (current == null || current.isTemplate) return;
    state = AsyncData(current.copyWith(isCropping: cropping));
  }

  Future<void> applyCrop(Rect normalizedRect) async {
    final current = state.value;
    if (current == null || current.isTemplate) return;

    state = AsyncData(
      current.copyWith(isCropping: false, isProcessingLineArt: true),
    );
    final updated = await ref
        .read(imageLibraryServiceProvider)
        .cropNormalized(current.image.id, normalizedRect);
    if (!ref.mounted) return;
    final refreshed = state.value;
    if (refreshed == null) return;
    state = AsyncData(
      refreshed.copyWith(image: updated, clearStepPreview: true),
    );
    await _runLineArt(refreshed.session.lineArtParams);
    if (refreshed.session.mode == DrawMode.stepByStep) {
      await _runStepPreview(refreshed.session.lineArtParams);
    }
  }

  Future<void> _runLineArt(LineArtParams params) async {
    final current = state.value;
    if (current == null || current.isTemplate) return;

    final seq = ++_lineArtSeq;
    state = AsyncData(
      current.copyWith(isProcessingLineArt: true, clearError: true),
    );

    try {
      final origBytes = await File(current.image.originalPath).readAsBytes();
      final result = await LineArtPipeline.generate(origBytes, params);
      if (!ref.mounted || seq != _lineArtSeq) return;

      final savedImage = await ref
          .read(imageLibraryServiceProvider)
          .saveLineArt(current.image.id, result.pngBytes);

      if (!ref.mounted) return;
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          image: savedImage,
          lineArtBytes: result.pngBytes,
          isProcessingLineArt: false,
        ),
      );
    } catch (e) {
      if (!ref.mounted || seq != _lineArtSeq) return;
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          isProcessingLineArt: false,
          errorMessage: 'Line art failed: $e',
        ),
      );
    }
  }

  Future<void> _runStepPreview(LineArtParams params) async {
    final current = state.value;
    if (current == null || current.isTemplate) return;

    final seq = ++_stepsSeq;
    state = AsyncData(current.copyWith(isProcessingSteps: true));
    try {
      final origBytes = await File(current.image.originalPath).readAsBytes();
      final result = await StepGenerator.generate(origBytes, params);
      if (!ref.mounted || seq != _stepsSeq) return;
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(
        latest.copyWith(
          stepPreviewPngs: result.stepPngs,
          stepPreviewParams: params,
          isProcessingSteps: false,
        ),
      );
    } catch (_) {
      if (!ref.mounted || seq != _stepsSeq) return;
      final latest = state.value;
      if (latest == null) return;
      state = AsyncData(latest.copyWith(isProcessingSteps: false));
    }
  }

  Future<bool> startTracing() async {
    final current = state.value;
    if (current == null) return false;

    state = AsyncData(current.copyWith(isStarting: true));
    try {
      final library = ref.read(imageLibraryServiceProvider);
      final sessionStore = ref.read(sessionStoreProvider);
      final stepCache = ref.read(stepCacheServiceProvider);

      if (!current.isTemplate && current.image.lineArtPath == null) {
        await _runLineArt(current.session.lineArtParams);
      }
      if (!ref.mounted) return false;

      final latest = state.value!;
      if (!latest.isTemplate && latest.session.mode == DrawMode.stepByStep) {
        final params = latest.session.lineArtParams;
        final cached = await stepCache.getCached(
          image: latest.image,
          params: params,
        );
        if (cached == null) {
          if (!latest.isProcessingSteps &&
              latest.stepPreviewPngs.isNotEmpty &&
              latest.stepPreviewParams == params) {
            // Reuse the steps already generated for the preview strip.
            await stepCache.store(
              image: latest.image,
              params: params,
              stepPngs: latest.stepPreviewPngs,
            );
          } else {
            await stepCache.getOrGenerate(image: latest.image, params: params);
          }
        }
      }

      await library.touchLastUsed(current.image.id);

      // Merge only the fields Prepare owns onto the stored session, so
      // changes made on Trace (transform, opacity, lock, ...) are kept.
      final prepared = state.value!.session;
      final stored = await sessionStore.load(current.image.id);
      final paramsChanged =
          stored != null && stored.lineArtParams != prepared.lineArtParams;
      final merged = stored == null
          ? prepared
          : stored.copyWith(
              mode: prepared.mode,
              useLineArt: prepared.useLineArt,
              lineArtParams: prepared.lineArtParams,
              currentStep: paramsChanged ? 0 : stored.currentStep,
            );
      await sessionStore.save(merged);
      if (!ref.mounted) return true;
      state = AsyncData(
        state.value!.copyWith(session: merged, isStarting: false),
      );
      return true;
    } catch (e) {
      if (ref.mounted) {
        state = AsyncData(
          (state.value ?? current).copyWith(
            isStarting: false,
            errorMessage: 'Failed to prepare session: $e',
          ),
        );
      }
      return false;
    }
  }
}

final prepareControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PrepareController, PrepareState, String>(PrepareController.new);
