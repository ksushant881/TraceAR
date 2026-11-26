import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tracear/core/constants.dart';
import 'package:tracear/core/result.dart';
import 'package:tracear/platform/native_bridge.dart';
import 'package:uuid/uuid.dart';

class RecordingItem {
  const RecordingItem({
    required this.path,
    required this.isVideo,
    required this.createdAt,
  });

  final String path;
  final bool isVideo;
  final DateTime createdAt;
}

class RecordingService {
  RecordingService({
    required this.nativeBridge,
    Future<Directory> Function()? docsDirProvider,
  }) : _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory;

  final NativeBridge nativeBridge;
  final Future<Directory> Function() _docsDirProvider;
  static const _uuid = Uuid();

  Future<Directory> _recordingsDir() async {
    final docs = await _docsDirProvider();
    final dir = Directory(p.join(docs.path, AppConstants.recordingsDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> createTempTimelapseDir() async {
    final base = await _recordingsDir();
    final dir = Directory(p.join(base.path, 'tmp_${_uuid.v4()}'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> saveVideoToLibraryAndGallery(String tempVideoPath) async {
    final dir = await _recordingsDir();
    final name = 'tracear_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final destPath = p.join(dir.path, name);
    await File(tempVideoPath).copy(destPath);
    try {
      await File(tempVideoPath).delete();
    } catch (_) {}

    await _saveVideoToGallery(destPath);
    return destPath;
  }

  Future<String> savePhotoToLibraryAndGallery(String tempPhotoPath) async {
    final dir = await _recordingsDir();
    final name = 'tracear_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = p.join(dir.path, name);
    await File(tempPhotoPath).copy(destPath);
    try {
      await File(tempPhotoPath).delete();
    } catch (_) {}

    try {
      await Gal.putImage(destPath, album: AppConstants.galleryAlbumName);
    } catch (_) {}
    return destPath;
  }

  Future<Result<String>> finalizeTimelapse({
    required Directory frameDir,
    required int fps,
  }) async {
    final dir = await _recordingsDir();
    final outPath = p.join(
      dir.path,
      'tracear_timelapse_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    final result = await nativeBridge.encodeTimelapse(
      frameDir: frameDir.path,
      outPath: outPath,
      fps: fps,
    );

    if (result.isOk) {
      await _saveVideoToGallery(outPath);
      try {
        await frameDir.delete(recursive: true);
      } catch (_) {}
    }

    return result;
  }

  Future<void> _saveVideoToGallery(String path) async {
    try {
      await Gal.putVideo(path, album: AppConstants.galleryAlbumName);
    } catch (_) {}
  }

  Future<List<RecordingItem>> listRecordings() async {
    final dir = await _recordingsDir();
    final entities = await dir.list().toList();
    final items = <RecordingItem>[];
    for (final e in entities) {
      if (e is! File) continue;
      final ext = p.extension(e.path).toLowerCase();
      if (ext == '.mp4' || ext == '.jpg' || ext == '.jpeg' || ext == '.png') {
        final stat = await e.stat();
        items.add(
          RecordingItem(
            path: e.path,
            isVideo: ext == '.mp4',
            createdAt: stat.modified,
          ),
        );
      }
    }
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  Future<Uint8List?> getVideoThumbnail(String videoPath) {
    return nativeBridge.getVideoThumbnail(videoPath);
  }

  Future<void> deleteRecording(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
