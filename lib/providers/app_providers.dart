import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracear/models/app_settings.dart';
import 'package:tracear/platform/native_bridge.dart';
import 'package:tracear/services/camera_service.dart';
import 'package:tracear/services/image_library_service.dart';
import 'package:tracear/services/recording_service.dart';
import 'package:tracear/services/session_store.dart';
import 'package:tracear/services/settings_service.dart';
import 'package:tracear/services/step_cache_service.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref.watch(sharedPreferencesProvider));
});

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    return ref.watch(settingsServiceProvider).load();
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(settingsServiceProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final sessionStoreProvider = Provider<SessionStore>((ref) {
  return SessionStore();
});

final imageLibraryServiceProvider = Provider<ImageLibraryService>((ref) {
  return ImageLibraryService(sessionStore: ref.watch(sessionStoreProvider));
});

final stepCacheServiceProvider = Provider<StepCacheService>((ref) {
  return StepCacheService();
});

final nativeBridgeProvider = Provider<NativeBridge>((ref) {
  return NativeBridge();
});

final recordingServiceProvider = Provider<RecordingService>((ref) {
  return RecordingService(nativeBridge: ref.watch(nativeBridgeProvider));
});

final cameraServiceProvider = Provider<CameraService>((ref) {
  return DeviceCameraService();
});

Future<ui.Image> defaultDecodeUiImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

final imageDecoderProvider = Provider<Future<ui.Image> Function(Uint8List)>((
  ref,
) {
  return defaultDecodeUiImage;
});
