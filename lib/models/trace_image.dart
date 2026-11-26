import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:tracear/core/constants.dart';

enum DrawMode { full, stepByStep }

enum ImageSource { userPhoto, template }

class TraceImage {
  const TraceImage({
    required this.id,
    required this.source,
    required this.originalPath,
    this.lineArtPath,
    required this.width,
    required this.height,
    required this.lastUsedAt,
  });

  final String id;
  final ImageSource source;
  final String originalPath;
  final String? lineArtPath;
  final int width;
  final int height;
  final DateTime lastUsedAt;

  TraceImage copyWith({
    String? id,
    ImageSource? source,
    String? originalPath,
    String? lineArtPath,
    bool clearLineArtPath = false,
    int? width,
    int? height,
    DateTime? lastUsedAt,
  }) {
    return TraceImage(
      id: id ?? this.id,
      source: source ?? this.source,
      originalPath: originalPath ?? this.originalPath,
      lineArtPath: clearLineArtPath ? null : (lineArtPath ?? this.lineArtPath),
      width: width ?? this.width,
      height: height ?? this.height,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source.name,
    'originalPath': originalPath,
    'lineArtPath': lineArtPath,
    'width': width,
    'height': height,
    'lastUsedAt': lastUsedAt.toIso8601String(),
  };

  factory TraceImage.fromJson(Map<String, dynamic> json) {
    return TraceImage(
      id: json['id'] as String,
      source: ImageSource.values.byName(json['source'] as String),
      originalPath: json['originalPath'] as String,
      lineArtPath: json['lineArtPath'] as String?,
      width: json['width'] as int,
      height: json['height'] as int,
      lastUsedAt: DateTime.parse(json['lastUsedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TraceImage &&
          id == other.id &&
          source == other.source &&
          originalPath == other.originalPath &&
          lineArtPath == other.lineArtPath &&
          width == other.width &&
          height == other.height &&
          lastUsedAt == other.lastUsedAt;

  @override
  int get hashCode => Object.hash(
    id,
    source,
    originalPath,
    lineArtPath,
    width,
    height,
    lastUsedAt,
  );
}

class LineArtParams {
  const LineArtParams({
    this.strength = 0.55,
    this.thickness = 1,
    this.stepCount = 5,
    this.includeShading = false,
  });

  final double strength; // 0..1 -> threshold
  final int thickness; // 0..3 -> dilation radius
  final int stepCount; // 3..8
  final bool includeShading;

  LineArtParams copyWith({
    double? strength,
    int? thickness,
    int? stepCount,
    bool? includeShading,
  }) {
    return LineArtParams(
      strength: (strength ?? this.strength).clamp(0.0, 1.0),
      thickness: (thickness ?? this.thickness).clamp(0, 3),
      stepCount: (stepCount ?? this.stepCount).clamp(3, 8),
      includeShading: includeShading ?? this.includeShading,
    );
  }

  Map<String, dynamic> toJson() => {
    'strength': double.parse(strength.toStringAsFixed(3)),
    'thickness': thickness,
    'stepCount': stepCount,
    'includeShading': includeShading,
  };

  factory LineArtParams.fromJson(Map<String, dynamic> json) {
    return LineArtParams(
      strength: (json['strength'] as num?)?.toDouble() ?? 0.55,
      thickness: json['thickness'] as int? ?? 1,
      stepCount: json['stepCount'] as int? ?? 5,
      includeShading: json['includeShading'] as bool? ?? false,
    );
  }

  String computeHash(String imageId) {
    final payload =
        '$imageId:v${AppConstants.lineArtAlgorithmVersion}:'
        '${jsonEncode(toJson())}';
    return sha1.convert(utf8.encode(payload)).toString();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineArtParams &&
          (strength - other.strength).abs() < 1e-6 &&
          thickness == other.thickness &&
          stepCount == other.stepCount &&
          includeShading == other.includeShading;

  @override
  int get hashCode => Object.hash(
    strength.toStringAsFixed(3),
    thickness,
    stepCount,
    includeShading,
  );
}
