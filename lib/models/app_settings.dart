import 'package:material_ui/material_ui.dart';

class AppSettings {
  const AppSettings({
    this.defaultOpacity = 0.5,
    this.gridSize = 3,
    this.timelapseIntervalSec = 2,
    this.timelapseFps = 24,
    this.defaultLineArt = true,
    this.defaultStepCount = 5,
    this.landscapeAllowed = false,
    this.highlightColor = const Color(0xFF00E5FF),
  });

  final double defaultOpacity;
  final int gridSize;
  final int timelapseIntervalSec;
  final int timelapseFps;
  final bool defaultLineArt;
  final int defaultStepCount;
  final bool landscapeAllowed;
  final Color highlightColor;

  AppSettings copyWith({
    double? defaultOpacity,
    int? gridSize,
    int? timelapseIntervalSec,
    int? timelapseFps,
    bool? defaultLineArt,
    int? defaultStepCount,
    bool? landscapeAllowed,
    Color? highlightColor,
  }) {
    return AppSettings(
      defaultOpacity: (defaultOpacity ?? this.defaultOpacity).clamp(0.1, 1.0),
      gridSize: (gridSize ?? this.gridSize).clamp(2, 8),
      timelapseIntervalSec: (timelapseIntervalSec ?? this.timelapseIntervalSec)
          .clamp(1, 30),
      timelapseFps: (timelapseFps ?? this.timelapseFps).clamp(10, 60),
      defaultLineArt: defaultLineArt ?? this.defaultLineArt,
      defaultStepCount: (defaultStepCount ?? this.defaultStepCount).clamp(3, 8),
      landscapeAllowed: landscapeAllowed ?? this.landscapeAllowed,
      highlightColor: highlightColor ?? this.highlightColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          defaultOpacity == other.defaultOpacity &&
          gridSize == other.gridSize &&
          timelapseIntervalSec == other.timelapseIntervalSec &&
          timelapseFps == other.timelapseFps &&
          defaultLineArt == other.defaultLineArt &&
          defaultStepCount == other.defaultStepCount &&
          landscapeAllowed == other.landscapeAllowed &&
          highlightColor == other.highlightColor;

  @override
  int get hashCode => Object.hash(
    defaultOpacity,
    gridSize,
    timelapseIntervalSec,
    timelapseFps,
    defaultLineArt,
    defaultStepCount,
    landscapeAllowed,
    highlightColor,
  );
}
