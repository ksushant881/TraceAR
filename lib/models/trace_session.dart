import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:tracear/models/trace_image.dart';

class OverlayTransform {
  const OverlayTransform({
    this.dx = 0.0,
    this.dy = 0.0,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.flipH = false,
  });

  final double dx; // offset in logical pixels, relative to center
  final double dy;
  final double scale; // 0.1..10
  final double rotation; // radians
  final bool flipH;

  static const double minScale = 0.1;
  static const double maxScale = 10.0;

  OverlayTransform copyWith({
    double? dx,
    double? dy,
    double? scale,
    double? rotation,
    bool? flipH,
  }) {
    return OverlayTransform(
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      scale: (scale ?? this.scale).clamp(minScale, maxScale),
      rotation: rotation ?? this.rotation,
      flipH: flipH ?? this.flipH,
    );
  }

  /// Applies a scale gesture to this transform (the transform at gesture
  /// start), so that the image point that was under [startFocal] stays under
  /// [focal]: zoom and rotation pivot around the fingers.
  ///
  /// [startFocal] and [focal] are in logical pixels relative to the overlay
  /// center (the same space as [dx]/[dy]). [scaleFactor] and [rotationDelta]
  /// are the cumulative values since gesture start (`details.scale`,
  /// `details.rotation`).
  OverlayTransform applyFocalGesture({
    required Offset startFocal,
    required Offset focal,
    required double scaleFactor,
    required double rotationDelta,
  }) {
    final newScale = (scale * scaleFactor).clamp(minScale, maxScale);
    final k = newScale / scale;
    // Vector from the image origin to the finger at gesture start.
    final vx = startFocal.dx - dx;
    final vy = startFocal.dy - dy;
    final c = math.cos(rotationDelta);
    final s = math.sin(rotationDelta);
    final rx = (vx * c - vy * s) * k;
    final ry = (vx * s + vy * c) * k;
    return OverlayTransform(
      dx: focal.dx - rx,
      dy: focal.dy - ry,
      scale: newScale,
      rotation: rotation + rotationDelta,
      flipH: flipH,
    );
  }

  /// Builds Matrix4: translate -> rotateZ -> scale -> (flip: scale x by -1).
  Matrix4 toMatrix4() {
    final m = Matrix4.identity();
    m.translateByDouble(dx, dy, 0.0, 1.0);
    m.rotateZ(rotation);
    final sx = flipH ? -scale : scale;
    m.scaleByDouble(sx, scale, 1.0, 1.0);
    return m;
  }

  Map<String, dynamic> toJson() => {
    'dx': dx,
    'dy': dy,
    'scale': scale,
    'rotation': rotation,
    'flipH': flipH,
  };

  factory OverlayTransform.fromJson(Map<String, dynamic> json) {
    return OverlayTransform(
      dx: (json['dx'] as num?)?.toDouble() ?? 0.0,
      dy: (json['dy'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      flipH: json['flipH'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlayTransform &&
          dx == other.dx &&
          dy == other.dy &&
          scale == other.scale &&
          rotation == other.rotation &&
          flipH == other.flipH;

  @override
  int get hashCode => Object.hash(dx, dy, scale, rotation, flipH);
}

class TraceSession {
  const TraceSession({
    required this.imageId,
    this.mode = DrawMode.full,
    this.useLineArt = true,
    this.transform = const OverlayTransform(),
    this.opacity = 0.5,
    this.locked = false,
    this.inverted = false,
    this.gridOn = false,
    this.currentStep = 0,
    this.highlightColor = const Color(0xFF00E5FF),
    this.lineArtParams = const LineArtParams(),
  });

  final String imageId;
  final DrawMode mode;
  final bool useLineArt;
  final OverlayTransform transform;
  final double opacity;
  final bool locked;
  final bool inverted;
  final bool gridOn;
  final int currentStep; // 0-based
  final Color highlightColor;
  final LineArtParams lineArtParams;

  TraceSession copyWith({
    String? imageId,
    DrawMode? mode,
    bool? useLineArt,
    OverlayTransform? transform,
    double? opacity,
    bool? locked,
    bool? inverted,
    bool? gridOn,
    int? currentStep,
    Color? highlightColor,
    LineArtParams? lineArtParams,
  }) {
    return TraceSession(
      imageId: imageId ?? this.imageId,
      mode: mode ?? this.mode,
      useLineArt: useLineArt ?? this.useLineArt,
      transform: transform ?? this.transform,
      opacity: (opacity ?? this.opacity).clamp(0.0, 1.0),
      locked: locked ?? this.locked,
      inverted: inverted ?? this.inverted,
      gridOn: gridOn ?? this.gridOn,
      currentStep: currentStep ?? this.currentStep,
      highlightColor: highlightColor ?? this.highlightColor,
      lineArtParams: lineArtParams ?? this.lineArtParams,
    );
  }

  Map<String, dynamic> toJson() => {
    'imageId': imageId,
    'mode': mode.name,
    'useLineArt': useLineArt,
    'transform': transform.toJson(),
    'opacity': opacity,
    'locked': locked,
    'inverted': inverted,
    'gridOn': gridOn,
    'currentStep': currentStep,
    'highlightColor': highlightColor.toARGB32(),
    'lineArtParams': lineArtParams.toJson(),
  };

  factory TraceSession.fromJson(Map<String, dynamic> json) {
    return TraceSession(
      imageId: json['imageId'] as String,
      mode: DrawMode.values.byName(json['mode'] as String? ?? 'full'),
      useLineArt: json['useLineArt'] as bool? ?? true,
      transform: json['transform'] != null
          ? OverlayTransform.fromJson(json['transform'] as Map<String, dynamic>)
          : const OverlayTransform(),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.5,
      locked: json['locked'] as bool? ?? false,
      inverted: json['inverted'] as bool? ?? false,
      gridOn: json['gridOn'] as bool? ?? false,
      currentStep: json['currentStep'] as int? ?? 0,
      highlightColor: Color(json['highlightColor'] as int? ?? 0xFF00E5FF),
      lineArtParams: json['lineArtParams'] != null
          ? LineArtParams.fromJson(
              json['lineArtParams'] as Map<String, dynamic>,
            )
          : const LineArtParams(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceSession &&
          imageId == other.imageId &&
          mode == other.mode &&
          useLineArt == other.useLineArt &&
          transform == other.transform &&
          opacity == other.opacity &&
          locked == other.locked &&
          inverted == other.inverted &&
          gridOn == other.gridOn &&
          currentStep == other.currentStep &&
          highlightColor == other.highlightColor &&
          lineArtParams == other.lineArtParams;

  @override
  int get hashCode => Object.hash(
    imageId,
    mode,
    useLineArt,
    transform,
    opacity,
    locked,
    inverted,
    gridOn,
    currentStep,
    highlightColor,
    lineArtParams,
  );
}
