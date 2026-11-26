import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tracear/core/constants.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/lineart/connected_components.dart';
import 'package:tracear/services/lineart/filters.dart';

enum EdgeMethod { xdog, sobel }

class LineArtResult {
  const LineArtResult({
    required this.pngBytes,
    required this.width,
    required this.height,
  });

  final Uint8List pngBytes;
  final int width;
  final int height;
}

class LineArtPipeline {
  LineArtPipeline._();

  /// Default edge detection method (§6.1).
  static const EdgeMethod defaultEdgeMethod = EdgeMethod.xdog;

  /// Base blur (§6.1 step 4) at [referenceSide] px. Edges in a photo get
  /// wider in pixels as resolution grows, so a fixed 1 px sigma finds almost
  /// nothing on a 1500 px camera photo. Sigmas scale with the long side.
  static const double baseSigma = 1.0;
  static const int referenceSide = 600;

  /// Noise cleanup threshold (§6.1 step 8): `0.00002 x w x h`, at least
  /// 12 px, multiplied by [sigmaScaleFor] squared. Lines (and texture specks
  /// such as fur or grain) get wider as sigma grows, so a fixed area would
  /// keep specks on large photos.
  static int minComponentArea(int width, int height) {
    final scale = sigmaScaleFor(width, height);
    return (math.max(12, (0.00002 * width * height).round()) * scale * scale)
        .round();
  }

  /// Factor (>= 1) to multiply blur sigmas by for a [width]x[height] image.
  static double sigmaScaleFor(int width, int height) =>
      math.max(1.0, math.max(width, height) / referenceSide);

  /// Generates a transparent-background black line-art PNG in an isolate.
  static Future<LineArtResult> generate(
    Uint8List imageBytes,
    LineArtParams params,
  ) {
    return Isolate.run(() => generateSync(imageBytes, params));
  }

  /// Synchronous version (safe to call from inside an isolate or unit test).
  static LineArtResult generateSync(
    Uint8List imageBytes,
    LineArtParams params,
  ) {
    final sw = Stopwatch()..start();

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw ArgumentError('Failed to decode image bytes.');
    }

    final scaled = scaleDownIfNeeded(decoded, AppConstants.maxLineArtDimension);
    final width = scaled.width;
    final height = scaled.height;
    final rgba = scaled.getBytes(order: img.ChannelOrder.rgba);

    final gray = LineArtFilters.toGrayscale(rgba, width, height);
    final norm = LineArtFilters.normalizeContrast(gray, width, height);

    final lines = lineStrokes(norm, width, height, params);
    final cleaned = LineArtFilters.dilateMask(
      lines,
      width,
      height,
      params.thickness,
    );

    final pngBytes = encodeMaskAsPng(cleaned, width, height);

    sw.stop();
    if (kDebugMode) {
      debugPrint(
        '[LineArtPipeline] ${width}x$height in ${sw.elapsedMilliseconds} ms',
      );
    }

    return LineArtResult(pngBytes: pngBytes, width: width, height: height);
  }

  /// The line-art strokes before they are thickened (§6.1 steps 4-8).
  ///
  /// `dilate(lineStrokes(...), thickness)` is exactly the line-art output:
  /// noise is removed on the dilated mask (steps 7-8, as the spec orders
  /// them), then only the stroke pixels inside kept components remain.
  /// The step generator splits these same strokes into steps.
  static Uint8List lineStrokes(
    Float32List normGray,
    int width,
    int height,
    LineArtParams params,
  ) {
    final mask = computeEdgeMask(
      normGray,
      width,
      height,
      sigma: baseSigma * sigmaScaleFor(width, height),
      strength: params.strength,
    );
    final dilated = LineArtFilters.dilateMask(
      mask,
      width,
      height,
      params.thickness,
    );
    final kept = ConnectedComponents.removeSmall(
      dilated,
      width,
      height,
      minComponentArea(width, height),
    );
    for (var i = 0; i < mask.length; i++) {
      if (kept[i] == 0) mask[i] = 0;
    }
    return mask;
  }

  /// Computes a binary edge mask for a normalized grayscale buffer.
  static Uint8List computeEdgeMask(
    Float32List normGray,
    int width,
    int height, {
    required double sigma,
    required double strength,
    EdgeMethod method = defaultEdgeMethod,
  }) {
    final Float32List edges;
    switch (method) {
      case EdgeMethod.xdog:
        edges = LineArtFilters.xdogEdges(normGray, width, height, sigma: sigma);
      case EdgeMethod.sobel:
        final blurred = LineArtFilters.gaussianBlur(
          normGray,
          width,
          height,
          sigma,
        );
        edges = LineArtFilters.sobelEdges(blurred, width, height);
    }
    return LineArtFilters.thresholdMask(edges, strength);
  }

  static img.Image scaleDownIfNeeded(img.Image src, int maxSide) {
    final longSide = math.max(src.width, src.height);
    if (longSide <= maxSide) return src;
    final scale = maxSide / longSide;
    final targetW = math.max(1, (src.width * scale).round());
    final targetH = math.max(1, (src.height * scale).round());
    return img.copyResize(
      src,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Encodes a binary mask (non-zero = black line, 0 = transparent) as RGBA PNG.
  static Uint8List encodeMaskAsPng(Uint8List mask, int width, int height) {
    final count = width * height;
    final rgba = Uint8List(count * 4);
    for (var i = 0, j = 0; i < count; i++, j += 4) {
      if (mask[i] != 0) {
        rgba[j] = 0;
        rgba[j + 1] = 0;
        rgba[j + 2] = 0;
        rgba[j + 3] = 255;
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
}
