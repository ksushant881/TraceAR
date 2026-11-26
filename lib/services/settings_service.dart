import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracear/models/app_settings.dart';

class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static const _kDefaultOpacity = 'settings.defaultOpacity';
  static const _kGridSize = 'settings.gridSize';
  static const _kTimelapseIntervalSec = 'settings.timelapseIntervalSec';
  static const _kTimelapseFps = 'settings.timelapseFps';
  static const _kDefaultLineArt = 'settings.defaultLineArt';
  static const _kDefaultStepCount = 'settings.defaultStepCount';
  static const _kLandscapeAllowed = 'settings.landscapeAllowed';
  static const _kHighlightColor = 'settings.highlightColor';

  AppSettings load() {
    return AppSettings(
      defaultOpacity: _prefs.getDouble(_kDefaultOpacity) ?? 0.5,
      gridSize: _prefs.getInt(_kGridSize) ?? 3,
      timelapseIntervalSec: _prefs.getInt(_kTimelapseIntervalSec) ?? 2,
      timelapseFps: _prefs.getInt(_kTimelapseFps) ?? 24,
      defaultLineArt: _prefs.getBool(_kDefaultLineArt) ?? true,
      defaultStepCount: _prefs.getInt(_kDefaultStepCount) ?? 5,
      landscapeAllowed: _prefs.getBool(_kLandscapeAllowed) ?? false,
      highlightColor: Color(_prefs.getInt(_kHighlightColor) ?? 0xFF00E5FF),
    );
  }

  Future<void> save(AppSettings settings) async {
    await Future.wait([
      _prefs.setDouble(_kDefaultOpacity, settings.defaultOpacity),
      _prefs.setInt(_kGridSize, settings.gridSize),
      _prefs.setInt(_kTimelapseIntervalSec, settings.timelapseIntervalSec),
      _prefs.setInt(_kTimelapseFps, settings.timelapseFps),
      _prefs.setBool(_kDefaultLineArt, settings.defaultLineArt),
      _prefs.setInt(_kDefaultStepCount, settings.defaultStepCount),
      _prefs.setBool(_kLandscapeAllowed, settings.landscapeAllowed),
      _prefs.setInt(_kHighlightColor, settings.highlightColor.toARGB32()),
    ]);
  }
}
