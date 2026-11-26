import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracear/providers/app_providers.dart';
import 'package:tracear/services/recording_service.dart';

class GalleryController extends AsyncNotifier<List<RecordingItem>> {
  @override
  Future<List<RecordingItem>> build() async {
    return ref.read(recordingServiceProvider).listRecordings();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = AsyncData(
      await ref.read(recordingServiceProvider).listRecordings(),
    );
  }

  Future<void> delete(String path) async {
    await ref.read(recordingServiceProvider).deleteRecording(path);
    await refresh();
  }

  Future<Uint8List?> thumbnailFor(String videoPath) {
    return ref.read(recordingServiceProvider).getVideoThumbnail(videoPath);
  }
}

final galleryControllerProvider =
    AsyncNotifierProvider<GalleryController, List<RecordingItem>>(
      GalleryController.new,
    );
