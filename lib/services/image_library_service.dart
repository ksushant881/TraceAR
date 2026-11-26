import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tracear/core/constants.dart';
import 'package:tracear/models/template_item.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/session_store.dart';
import 'package:uuid/uuid.dart';

class ImageLibraryService {
  ImageLibraryService({
    required this.sessionStore,
    Future<Directory> Function()? docsDirProvider,
  }) : _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory;

  final SessionStore sessionStore;
  final Future<Directory> Function() _docsDirProvider;
  static const _uuid = Uuid();

  Future<Directory> _imagesDir() async {
    final docs = await _docsDirProvider();
    final dir = Directory(p.join(docs.path, AppConstants.imagesDirName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _imagesDir();
    return File(p.join(dir.path, AppConstants.imageIndexFileName));
  }

  Future<List<TraceImage>> _readIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];
    try {
      final raw = await file.readAsString();
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => _dropStaleLineArt(
              TraceImage.fromJson(e as Map<String, dynamic>),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Line art made by an older algorithm version is treated as missing, so
  /// Prepare regenerates it.
  static TraceImage _dropStaleLineArt(TraceImage image) {
    final path = image.lineArtPath;
    if (image.source == ImageSource.userPhoto &&
        path != null &&
        p.basename(path) != AppConstants.lineArtFileName) {
      return image.copyWith(clearLineArtPath: true);
    }
    return image;
  }

  /// Deletes every line-art PNG (any version) in an image folder.
  static Future<void> _deleteLineArtFiles(Directory itemDir) async {
    if (!await itemDir.exists()) return;
    await for (final e in itemDir.list()) {
      final name = p.basename(e.path);
      if (e is File && name.startsWith('lineart') && name.endsWith('.png')) {
        await e.delete();
      }
    }
  }

  Future<void> _writeIndexAtomically(List<TraceImage> items) async {
    final file = await _indexFile();
    final tmp = File('${file.path}.tmp');
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await tmp.writeAsString(encoded, flush: true);
    // rename() atomically replaces the target on Android/iOS (POSIX).
    // Windows (tests/desktop) can't rename over an existing file.
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  Future<List<TraceImage>> listRecent() async {
    final items = await _readIndex();
    items.sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return items;
  }

  Future<List<TemplateItem>> loadTemplates() async {
    final raw = await rootBundle.loadString('assets/templates/index.json');
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => TemplateItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<TraceImage?> getById(String id) async {
    if (id.startsWith('template:')) {
      final templateId = id.substring('template:'.length);
      final templates = await loadTemplates();
      final match = templates.where((t) => t.id == templateId).firstOrNull;
      if (match == null) return null;
      return TraceImage(
        id: id,
        source: ImageSource.template,
        originalPath: match.fullAssetPath,
        lineArtPath: match.fullAssetPath,
        width: 2048,
        height: 2048,
        lastUsedAt: DateTime.now(),
      );
    }
    final items = await _readIndex();
    return items.where((e) => e.id == id).firstOrNull;
  }

  Future<TemplateItem?> getTemplateForImageId(String id) async {
    if (!id.startsWith('template:')) return null;
    final templateId = id.substring('template:'.length);
    final templates = await loadTemplates();
    return templates.where((t) => t.id == templateId).firstOrNull;
  }

  /// Copies & scales down an imported image to <= 2048 px on the long side.
  Future<TraceImage> importImage(String sourcePath) async {
    final rawBytes = await File(sourcePath).readAsBytes();
    final processed = await Isolate.run(() {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) {
        throw ArgumentError('Unable to decode selected image.');
      }
      final baked = img.bakeOrientation(decoded);
      final longSide = math.max(baked.width, baked.height);
      final img.Image resized;
      if (longSide > AppConstants.maxImportDimension) {
        final scale = AppConstants.maxImportDimension / longSide;
        resized = img.copyResize(
          baked,
          width: math.max(1, (baked.width * scale).round()),
          height: math.max(1, (baked.height * scale).round()),
          interpolation: img.Interpolation.linear,
        );
      } else {
        resized = baked;
      }
      final jpg = Uint8List.fromList(img.encodeJpg(resized, quality: 92));
      return (jpg: jpg, width: resized.width, height: resized.height);
    });

    final id = _uuid.v4();
    final imagesDir = await _imagesDir();
    final itemDir = Directory(p.join(imagesDir.path, id));
    await itemDir.create(recursive: true);

    final outPath = p.join(itemDir.path, 'original.jpg');
    await File(outPath).writeAsBytes(processed.jpg, flush: true);

    final traceImage = TraceImage(
      id: id,
      source: ImageSource.userPhoto,
      originalPath: outPath,
      width: processed.width,
      height: processed.height,
      lastUsedAt: DateTime.now(),
    );

    final items = await _readIndex();
    items.add(traceImage);
    await _writeIndexAtomically(items);
    return traceImage;
  }

  Future<TraceImage> saveLineArt(String imageId, Uint8List pngBytes) async {
    final imagesDir = await _imagesDir();
    final itemDir = Directory(p.join(imagesDir.path, imageId));
    await itemDir.create(recursive: true);

    final lineArtPath = p.join(itemDir.path, AppConstants.lineArtFileName);
    await _deleteLineArtFiles(itemDir);
    await File(lineArtPath).writeAsBytes(pngBytes, flush: true);

    final items = await _readIndex();
    final idx = items.indexWhere((e) => e.id == imageId);
    if (idx == -1) {
      throw StateError('Image $imageId not found in index.');
    }
    final updated = items[idx].copyWith(
      lineArtPath: lineArtPath,
      lastUsedAt: DateTime.now(),
    );
    items[idx] = updated;
    await _writeIndexAtomically(items);
    return updated;
  }

  Future<TraceImage> rotate90(String imageId, {bool clockwise = true}) async {
    final items = await _readIndex();
    final idx = items.indexWhere((e) => e.id == imageId);
    if (idx == -1) throw StateError('Image $imageId not found.');
    final item = items[idx];

    final bytes = await File(item.originalPath).readAsBytes();
    final rotated = await Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw StateError('Failed to decode original image.');
      final r = img.copyRotate(decoded, angle: clockwise ? 90 : -90);
      return (
        jpg: Uint8List.fromList(img.encodeJpg(r, quality: 92)),
        width: r.width,
        height: r.height,
      );
    });

    await File(item.originalPath).writeAsBytes(rotated.jpg, flush: true);
    await _clearDerivedFiles(imageId);

    final updated = item.copyWith(
      width: rotated.width,
      height: rotated.height,
      clearLineArtPath: true,
      lastUsedAt: DateTime.now(),
    );
    items[idx] = updated;
    await _writeIndexAtomically(items);
    return updated;
  }

  /// Crops [imageId] using normalized [0..1] coordinates.
  Future<TraceImage> cropNormalized(String imageId, Rect normRect) async {
    final items = await _readIndex();
    final idx = items.indexWhere((e) => e.id == imageId);
    if (idx == -1) throw StateError('Image $imageId not found.');
    final item = items[idx];

    final bytes = await File(item.originalPath).readAsBytes();
    final cropped = await Isolate.run(() {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw StateError('Failed to decode original image.');
      final x = (normRect.left.clamp(0.0, 1.0) * decoded.width).round();
      final y = (normRect.top.clamp(0.0, 1.0) * decoded.height).round();
      final w = math.max(
        16,
        (normRect.width.clamp(0.05, 1.0) * decoded.width).round(),
      );
      final h = math.max(
        16,
        (normRect.height.clamp(0.05, 1.0) * decoded.height).round(),
      );
      final c = img.copyCrop(
        decoded,
        x: x.clamp(0, decoded.width - 16),
        y: y.clamp(0, decoded.height - 16),
        width: math.min(w, decoded.width - x.clamp(0, decoded.width - 16)),
        height: math.min(h, decoded.height - y.clamp(0, decoded.height - 16)),
      );
      return (
        jpg: Uint8List.fromList(img.encodeJpg(c, quality: 92)),
        width: c.width,
        height: c.height,
      );
    });

    await File(item.originalPath).writeAsBytes(cropped.jpg, flush: true);
    await _clearDerivedFiles(imageId);

    final updated = item.copyWith(
      width: cropped.width,
      height: cropped.height,
      clearLineArtPath: true,
      lastUsedAt: DateTime.now(),
    );
    items[idx] = updated;
    await _writeIndexAtomically(items);
    return updated;
  }

  Future<void> _clearDerivedFiles(String imageId) async {
    final imagesDir = await _imagesDir();
    await _deleteLineArtFiles(Directory(p.join(imagesDir.path, imageId)));
    final stepsDir = Directory(p.join(imagesDir.path, imageId, 'steps'));
    if (await stepsDir.exists()) await stepsDir.delete(recursive: true);
  }

  Future<void> touchLastUsed(String imageId) async {
    if (imageId.startsWith('template:')) return;
    final items = await _readIndex();
    final idx = items.indexWhere((e) => e.id == imageId);
    if (idx == -1) return;
    items[idx] = items[idx].copyWith(lastUsedAt: DateTime.now());
    await _writeIndexAtomically(items);
  }

  Future<void> deleteImage(String imageId) async {
    final imagesDir = await _imagesDir();
    final itemDir = Directory(p.join(imagesDir.path, imageId));
    if (await itemDir.exists()) {
      await itemDir.delete(recursive: true);
    }
    final items = await _readIndex();
    items.removeWhere((e) => e.id == imageId);
    await _writeIndexAtomically(items);
    await sessionStore.delete(imageId);
  }
}
