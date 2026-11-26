import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tracear/core/constants.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/lineart/connected_components.dart';
import 'package:tracear/services/lineart/filters.dart';
import 'package:tracear/services/lineart/lineart_pipeline.dart';

class StepGenerationResult {
  const StepGenerationResult({
    required this.stepPngs,
    required this.width,
    required this.height,
  });

  final List<Uint8List> stepPngs;
  final int width;
  final int height;
}

class StepGenerator {
  StepGenerator._();

  static const List<double> _sigmas = [8.0, 5.0, 3.0, 2.0, 1.2, 0.8];

  /// Generates [LineArtParams.stepCount] transparent PNG steps in an isolate.
  static Future<StepGenerationResult> generate(
    Uint8List imageBytes,
    LineArtParams params,
  ) {
    return Isolate.run(() => generateSync(imageBytes, params));
  }

  /// Synchronous version (safe for unit tests and isolates).
  static StepGenerationResult generateSync(
    Uint8List imageBytes,
    LineArtParams params,
  ) {
    final sw = Stopwatch()..start();

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError('Failed to decode image bytes.');
    }

    final scaled = LineArtPipeline.scaleDownIfNeeded(
      decoded,
      AppConstants.maxLineArtDimension,
    );
    final width = scaled.width;
    final height = scaled.height;
    final rgba = scaled.getBytes(order: img.ChannelOrder.rgba);

    final gray = LineArtFilters.toGrayscale(rgba, width, height);
    final norm = LineArtFilters.normalizeContrast(gray, width, height);

    final masks = generateStepMasksSync(norm, width, height, params);
    final dilatedOutlines = dilateAndDeduplicate(
      params.includeShading ? masks.sublist(0, masks.length - 1) : masks,
      width,
      height,
      params.thickness,
    );
    final pngs = <Uint8List>[];

    for (final dilated in dilatedOutlines) {
      pngs.add(LineArtPipeline.encodeMaskAsPng(dilated, width, height));
    }

    if (params.includeShading) {
      // §6.3.6: every step, shading included, is dilated by thickness.
      final shading = LineArtFilters.dilateMask(
        masks.last,
        width,
        height,
        params.thickness,
      );
      pngs.add(_encodeAlphaMaskAsPng(shading, width, height, alpha: 153));
    }

    sw.stop();
    if (kDebugMode) {
      debugPrint(
        '[StepGenerator] ${width}x$height (${pngs.length} steps) in '
        '${sw.elapsedMilliseconds} ms',
      );
    }

    return StepGenerationResult(stepPngs: pngs, width: width, height: height);
  }

  /// Generates binary masks for each step (outline steps + optional shading).
  /// Exposed for invariant unit testing (§6.3, §10).
  static List<Uint8List> generateStepMasksSync(
    Float32List normGray,
    int width,
    int height,
    LineArtParams params,
  ) {
    final count = width * height;

    // The strokes of the full line art: steps are made of exactly these
    // lines, so every step looks like the line art the user sees in Full
    // mode (detecting edges at sigma 8-20 directly gives blurry blobs).
    final strokes = LineArtPipeline.lineStrokes(
      normGray,
      width,
      height,
      params,
    );
    final comps = ConnectedComponents.find(strokes, width, height);

    // 1-3. Multi-scale edges decide the drawing order. A stroke belongs to
    // the coarsest level whose edge mask E_i covers most of it: strokes on
    // the main silhouette survive heavy blur and come first; strokes only
    // found at fine scales are details and come later. Each stroke is in
    // exactly one level, so lines are never repeated across steps.
    final sigmaScale = LineArtPipeline.sigmaScaleFor(width, height);
    // The level masks only decide ordering, so on large images compute them
    // at half resolution (about 4x less work; step generation must stay
    // under ~3 s, §6.2).
    final half = width * height > 400000;
    final lw = half ? width ~/ 2 : width;
    final lh = half ? height ~/ 2 : height;
    final levelGray = half ? _downsample2(normGray, width, height) : normGray;
    final levelSigmaScale = half ? sigmaScale / 2 : sigmaScale;
    // Index into the level grid for each full-resolution pixel.
    int levelIndex(int idx) {
      if (!half) return idx;
      final x = math.min((idx % width) >> 1, lw - 1);
      final y = math.min((idx ~/ width) >> 1, lh - 1);
      return y * lw + x;
    }

    final levelOf = List<int>.filled(comps.length, -1);
    var unassigned = comps.length;
    for (var li = 0; li < _sigmas.length && unassigned > 0; li++) {
      final edges = LineArtPipeline.computeEdgeMask(
        levelGray,
        lw,
        lh,
        sigma: _sigmas[li] * levelSigmaScale,
        strength: params.strength,
      );
      // Small tolerance: a fine stroke sits next to, not exactly on, the
      // centre of a coarse edge band.
      final near = LineArtFilters.dilateMask(
        edges,
        lw,
        lh,
        math.max(1, levelSigmaScale.round()),
      );
      for (var c = 0; c < comps.length; c++) {
        if (levelOf[c] != -1) continue;
        var hits = 0;
        for (final idx in comps[c].pixels) {
          if (near[levelIndex(idx)] != 0) hits++;
        }
        if (hits * 2 >= comps[c].area) {
          levelOf[c] = li;
          unassigned--;
        }
      }
    }

    final levelCount = _sigmas.length + 1; // + "finest" for the rest
    final byLevel = List.generate(levelCount, (_) => Uint8List(count));
    for (var c = 0; c < comps.length; c++) {
      final li = levelOf[c] == -1 ? levelCount - 1 : levelOf[c];
      final target = byLevel[li];
      for (final idx in comps[c].pixels) {
        target[idx] = 1;
      }
    }
    final levels = byLevel.where((l) => _countPixels(l) > 0).toList();

    // Fallback if image is completely blank/flat
    if (levels.isEmpty) {
      final fallback = Uint8List(count);
      fallback[count ~/ 2] = 1;
      levels.add(fallback);
    }

    // 4. Adjust to exact N outline steps
    final targetOutlines = math.max(
      1,
      params.includeShading ? params.stepCount - 1 : params.stepCount,
    );

    // Steps are disjoint, so the total line-pixel count stays the same
    // through every merge and split below.
    var totalPixels = 0;
    for (final l in levels) {
      totalPixels += _countPixels(l);
    }
    final minStepPixels = (totalPixels * 0.03).ceil();

    // Each step must hold >= 3% of all line pixels: merge smaller steps
    // into their neighbor.
    _mergeTinySteps(levels, minStepPixels);

    // Too many levels -> merge the level with fewest pixels into the next one.
    while (levels.length > targetOutlines) {
      var minIdx = 0;
      var minPx = _countPixels(levels[0]);
      for (var i = 1; i < levels.length; i++) {
        final px = _countPixels(levels[i]);
        if (px < minPx) {
          minPx = px;
          minIdx = i;
        }
      }
      final targetIdx = (minIdx + 1 < levels.length) ? minIdx + 1 : minIdx - 1;
      _orInto(levels[targetIdx], levels[minIdx]);
      levels.removeAt(minIdx);
    }

    // Too few levels -> split the level with the most pixels into two.
    // A split is only kept if both halves still meet the 3% minimum; if the
    // biggest level can't be split that way, try the next biggest. If none
    // can, the image simply gets fewer steps.
    final minHalf = math.max(1, minStepPixels);
    while (levels.length < targetOutlines) {
      final order = List.generate(levels.length, (i) => i)
        ..sort(
          (a, b) => _countPixels(levels[b]).compareTo(_countPixels(levels[a])),
        );
      var didSplit = false;
      for (final idx in order) {
        if (_countPixels(levels[idx]) < 2 * minHalf) break;
        final split = _splitStep(levels[idx], width, height, minHalf);
        if (split == null) continue;
        levels[idx] = split.$1;
        levels.insert(idx + 1, split.$2);
        didSplit = true;
        break;
      }
      if (!didSplit) break;
    }

    if (params.includeShading) {
      levels.add(_generateShadingMask(normGray, width, height));
    }

    return levels;
  }

  /// Dilates each outline step by [thickness] and removes pixels already
  /// covered by earlier steps so steps remain disjoint (<=2% overlap invariant).
  static List<Uint8List> dilateAndDeduplicate(
    List<Uint8List> outlineMasks,
    int width,
    int height,
    int thickness,
  ) {
    final count = width * height;
    final union = Uint8List(count);
    final out = <Uint8List>[];

    for (final mask in outlineMasks) {
      final dilated = LineArtFilters.dilateMask(mask, width, height, thickness);
      final deduped = Uint8List(count);
      var kept = 0;
      for (var p = 0; p < count; p++) {
        if (dilated[p] != 0 && union[p] == 0) {
          deduped[p] = 1;
          kept++;
        }
      }
      final chosen = kept > 0 ? deduped : dilated;
      for (var p = 0; p < count; p++) {
        if (chosen[p] != 0) union[p] = 1;
      }
      out.add(chosen);
    }
    return out;
  }

  /// Splits [mask] into an earlier and a later step, each with at least
  /// [minHalf] pixels, or returns null if that isn't possible.
  ///
  /// First by connected component (biggest first; the bigger half goes into
  /// the earlier step). If that is lopsided, e.g. one big component, split
  /// spatially into top and bottom halves.
  static (Uint8List, Uint8List)? _splitStep(
    Uint8List mask,
    int width,
    int height,
    int minHalf,
  ) {
    final count = width * height;
    final comps = ConnectedComponents.find(mask, width, height);

    if (comps.length >= 2) {
      final first = Uint8List(count);
      final second = Uint8List(count);
      comps.sort((a, b) => b.area.compareTo(a.area));
      final total = comps.fold<int>(0, (sum, c) => sum + c.area);
      var firstSum = 0;
      var secondSum = 0;
      for (var i = 0; i < comps.length; i++) {
        final comp = comps[i];
        final toFirst =
            i == 0 || (firstSum < total / 2 && i < comps.length - 1);
        final target = toFirst ? first : second;
        if (toFirst) {
          firstSum += comp.area;
        } else {
          secondSum += comp.area;
        }
        for (final idx in comp.pixels) {
          target[idx] = 1;
        }
      }
      if (firstSum >= minHalf && secondSum >= minHalf) {
        return (first, second);
      }
    }

    // Spatial split: top half / bottom half by pixel count.
    final total = _countPixels(mask);
    final first = Uint8List(count);
    final second = Uint8List(count);
    var seen = 0;
    var firstSum = 0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      final toFirst = seen < total / 2;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] != 0) {
          seen++;
          if (toFirst) {
            first[row + x] = 1;
            firstSum++;
          } else {
            second[row + x] = 1;
          }
        }
      }
    }
    final secondSum = total - firstSum;
    if (firstSum >= minHalf && secondSum >= minHalf) {
      return (first, second);
    }
    return null;
  }

  /// Shading step (§6.3.5):
  /// Blur at sigma=3, quantize to 4 tone levels, take darkest 2 levels as regions,
  /// draw their outlines + 45° hatching inside the darkest level (every 8 px, 1 px wide).
  static Uint8List _generateShadingMask(
    Float32List normGray,
    int width,
    int height,
  ) {
    final blurred = LineArtFilters.gaussianBlur(normGray, width, height, 3.0);
    final count = width * height;
    final dark2 = Uint8List(count);
    final darkest = Uint8List(count);

    for (var i = 0; i < count; i++) {
      // 4 tone levels: 0 (<0.25), 1 (<0.5), 2 (<0.75), 3 (>=0.75)
      final v = blurred[i];
      if (v < 0.5) {
        dark2[i] = 1;
        if (v < 0.25) {
          darkest[i] = 1;
        }
      }
    }

    final out = Uint8List(count);

    // Outlines of the darkest 2 region masks (4-neighbor boundary)
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final idx = row + x;
        if (dark2[idx] != 0) {
          final isBoundary =
              x == 0 ||
              x == width - 1 ||
              y == 0 ||
              y == height - 1 ||
              dark2[idx - 1] == 0 ||
              dark2[idx + 1] == 0 ||
              dark2[idx - width] == 0 ||
              dark2[idx + width] == 0;
          if (isBoundary) {
            out[idx] = 1;
          }
        }
        // 45-degree hatching inside the darkest level (lines every 8 px, 1 px wide)
        if (darkest[idx] != 0 && ((x + y) % 8 == 0)) {
          out[idx] = 1;
        }
      }
    }

    // Ensure non-empty if image has no dark regions
    if (_countPixels(out) == 0 && count > 0) {
      out[0] = 1;
    }
    return out;
  }

  static Uint8List _encodeAlphaMaskAsPng(
    Uint8List mask,
    int width,
    int height, {
    required int alpha,
  }) {
    final count = width * height;
    final rgba = Uint8List(count * 4);
    for (var i = 0, j = 0; i < count; i++, j += 4) {
      if (mask[i] != 0) {
        rgba[j] = 0;
        rgba[j + 1] = 0;
        rgba[j + 2] = 0;
        rgba[j + 3] = alpha;
      }
    }
    final outImg = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(outImg));
  }

  /// 2x2 box downsample of a grayscale buffer.
  static Float32List _downsample2(Float32List src, int width, int height) {
    final w2 = width ~/ 2;
    final h2 = height ~/ 2;
    final out = Float32List(w2 * h2);
    for (var y = 0; y < h2; y++) {
      final r0 = (2 * y) * width;
      final r1 = r0 + width;
      for (var x = 0; x < w2; x++) {
        final x0 = 2 * x;
        out[y * w2 + x] =
            (src[r0 + x0] +
                src[r0 + x0 + 1] +
                src[r1 + x0] +
                src[r1 + x0 + 1]) *
            0.25;
      }
    }
    return out;
  }

  static void _mergeTinySteps(List<Uint8List> levels, int minStepPixels) {
    var changed = true;
    while (changed && levels.length > 1) {
      changed = false;
      for (var i = 0; i < levels.length; i++) {
        if (_countPixels(levels[i]) < minStepPixels) {
          final mergeInto = (i + 1 < levels.length) ? i + 1 : i - 1;
          _orInto(levels[mergeInto], levels[i]);
          levels.removeAt(i);
          changed = true;
          break;
        }
      }
    }
  }

  static int _countPixels(Uint8List mask) {
    var c = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 0) c++;
    }
    return c;
  }

  static void _orInto(Uint8List dst, Uint8List src) {
    for (var i = 0; i < dst.length; i++) {
      if (src[i] != 0) dst[i] = 1;
    }
  }
}
