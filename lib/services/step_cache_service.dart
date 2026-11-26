import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tracear/core/constants.dart';
import 'package:tracear/models/step_set.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/lineart/step_generator.dart';

class StepCacheService {
  StepCacheService({Future<Directory> Function()? docsDirProvider})
    : _docsDirProvider = docsDirProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _docsDirProvider;

  /// Written after every step PNG is on disk. Holds the real step count,
  /// which can be lower than `stepCount` for images with very few lines.
  static const String _manifestName = 'complete.json';

  Future<Directory> _stepsDir(String imageId, String paramsHash) async {
    final docs = await _docsDirProvider();
    return Directory(
      p.join(
        docs.path,
        AppConstants.imagesDirName,
        imageId,
        'steps',
        paramsHash,
      ),
    );
  }

  /// Returns the cached [StepSet] if a complete cache exists, otherwise null.
  Future<StepSet?> getCached({
    required TraceImage image,
    required LineArtParams params,
  }) async {
    final hash = params.computeHash(image.id);
    final dir = await _stepsDir(image.id, hash);
    final manifest = File(p.join(dir.path, _manifestName));
    if (!await manifest.exists()) return null;
    try {
      final json =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final count = json['count'] as int;
      if (count <= 0) return null;
      final paths = List.generate(
        count,
        (i) => p.join(dir.path, 'step_${i + 1}.png'),
      );
      for (final path in paths) {
        if (!await File(path).exists()) return null;
      }
      return StepSet(imageId: image.id, paramsHash: hash, stepPaths: paths);
    } catch (_) {
      return null;
    }
  }

  /// Writes [stepPngs] to the cache for [image] + [params].
  Future<StepSet> store({
    required TraceImage image,
    required LineArtParams params,
    required List<Uint8List> stepPngs,
  }) async {
    final hash = params.computeHash(image.id);
    final dir = await _stepsDir(image.id, hash);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    final paths = <String>[];
    for (var i = 0; i < stepPngs.length; i++) {
      final stepPath = p.join(dir.path, 'step_${i + 1}.png');
      await File(stepPath).writeAsBytes(stepPngs[i], flush: true);
      paths.add(stepPath);
    }
    await File(p.join(dir.path, _manifestName))
        .writeAsString(jsonEncode({'count': stepPngs.length}), flush: true);
    return StepSet(imageId: image.id, paramsHash: hash, stepPaths: paths);
  }

  /// Returns the cached [StepSet], or generates and caches it.
  Future<StepSet> getOrGenerate({
    required TraceImage image,
    required LineArtParams params,
  }) async {
    final cached = await getCached(image: image, params: params);
    if (cached != null) return cached;

    final bytes = await File(image.originalPath).readAsBytes();
    final result = await StepGenerator.generate(bytes, params);
    return store(image: image, params: params, stepPngs: result.stepPngs);
  }

  Future<List<Uint8List>> previewGenerate({
    required Uint8List imageBytes,
    required LineArtParams params,
  }) async {
    final result = await StepGenerator.generate(imageBytes, params);
    return result.stepPngs;
  }
}
