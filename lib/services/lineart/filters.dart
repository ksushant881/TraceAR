import 'dart:math' as math;
import 'dart:typed_data';

/// Pure typed-array image processing filters for the line-art pipeline.
class LineArtFilters {
  LineArtFilters._();

  /// Converts RGBA bytes (4 bytes per pixel) to a [0.0, 1.0] grayscale buffer
  /// using Rec.601 luma weights: 0.299R + 0.587G + 0.114B.
  static Float32List toGrayscale(Uint8List rgba, int width, int height) {
    final count = width * height;
    final out = Float32List(count);
    for (var i = 0, j = 0; i < count; i++, j += 4) {
      final r = rgba[j];
      final g = rgba[j + 1];
      final b = rgba[j + 2];
      out[i] = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
    }
    return out;
  }

  /// Stretches histogram between the 2nd and 98th percentiles to [0.0, 1.0].
  static Float32List normalizeContrast(
    Float32List gray,
    int width,
    int height,
  ) {
    final count = width * height;
    if (count == 0) return Float32List(0);

    final hist = Int32List(256);
    for (var i = 0; i < count; i++) {
      final bin = (gray[i] * 255.0).round().clamp(0, 255);
      hist[bin]++;
    }

    final lowTarget = (count * 0.02).floor();
    final highTarget = (count * 0.98).floor();

    var cumulative = 0;
    var lowBin = 0;
    for (var b = 0; b < 256; b++) {
      cumulative += hist[b];
      if (cumulative >= lowTarget) {
        lowBin = b;
        break;
      }
    }

    cumulative = 0;
    var highBin = 255;
    for (var b = 0; b < 256; b++) {
      cumulative += hist[b];
      if (cumulative >= highTarget) {
        highBin = b;
        break;
      }
    }

    final low = lowBin / 255.0;
    final high = highBin / 255.0;
    final range = high - low;
    final out = Float32List(count);

    if (range < 1e-5) {
      out.setAll(0, gray);
      return out;
    }

    final invRange = 1.0 / range;
    for (var i = 0; i < count; i++) {
      out[i] = ((gray[i] - low) * invRange).clamp(0.0, 1.0);
    }
    return out;
  }

  /// Separable Gaussian blur.
  /// For [sigma] > 3, uses 3 passes of separable box blur as an approximation.
  static Float32List gaussianBlur(
    Float32List src,
    int width,
    int height,
    double sigma,
  ) {
    if (sigma <= 0.05) {
      return Float32List.fromList(src);
    }

    if (sigma > 3.0) {
      final wIdeal = math.sqrt((12.0 * sigma * sigma / 3.0) + 1.0);
      var wl = wIdeal.floor();
      if (wl.isEven) wl--;
      final radius = ((wl - 1) ~/ 2).clamp(1, 64);

      var buf = Float32List.fromList(src);
      final tmp = Float32List(width * height);
      for (var pass = 0; pass < 3; pass++) {
        _boxBlurHorizontal(buf, tmp, width, height, radius);
        _boxBlurVertical(tmp, buf, width, height, radius);
      }
      return buf;
    }

    final radius = (sigma * 3.0).ceil().clamp(1, 32);
    final kernel = Float32List(radius * 2 + 1);
    final twoSigmaSq = 2.0 * sigma * sigma;
    var sum = 0.0;
    for (var i = -radius; i <= radius; i++) {
      final v = math.exp(-(i * i) / twoSigmaSq);
      kernel[i + radius] = v;
      sum += v;
    }
    for (var i = 0; i < kernel.length; i++) {
      kernel[i] /= sum;
    }

    final tmp = Float32List(width * height);
    final out = Float32List(width * height);

    // Horizontal pass
    for (var y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (var x = 0; x < width; x++) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k++) {
          final sx = (x + k).clamp(0, width - 1);
          acc += src[rowOffset + sx] * kernel[k + radius];
        }
        tmp[rowOffset + x] = acc;
      }
    }

    // Vertical pass
    for (var y = 0; y < height; y++) {
      final rowOffset = y * width;
      for (var x = 0; x < width; x++) {
        var acc = 0.0;
        for (var k = -radius; k <= radius; k++) {
          final sy = (y + k).clamp(0, height - 1);
          acc += tmp[sy * width + x] * kernel[k + radius];
        }
        out[rowOffset + x] = acc;
      }
    }

    return out;
  }

  static void _boxBlurHorizontal(
    Float32List src,
    Float32List dst,
    int width,
    int height,
    int radius,
  ) {
    final windowSize = radius * 2 + 1;
    final inv = 1.0 / windowSize;
    for (var y = 0; y < height; y++) {
      final rowOffset = y * width;
      var acc = 0.0;
      for (var k = -radius; k <= radius; k++) {
        acc += src[rowOffset + k.clamp(0, width - 1)];
      }
      dst[rowOffset] = acc * inv;
      for (var x = 1; x < width; x++) {
        final addIdx = (x + radius).clamp(0, width - 1);
        final remIdx = (x - radius - 1).clamp(0, width - 1);
        acc += src[rowOffset + addIdx] - src[rowOffset + remIdx];
        dst[rowOffset + x] = acc * inv;
      }
    }
  }

  static void _boxBlurVertical(
    Float32List src,
    Float32List dst,
    int width,
    int height,
    int radius,
  ) {
    final windowSize = radius * 2 + 1;
    final inv = 1.0 / windowSize;
    for (var x = 0; x < width; x++) {
      var acc = 0.0;
      for (var k = -radius; k <= radius; k++) {
        acc += src[k.clamp(0, height - 1) * width + x];
      }
      dst[x] = acc * inv;
      for (var y = 1; y < height; y++) {
        final addIdx = (y + radius).clamp(0, height - 1);
        final remIdx = (y - radius - 1).clamp(0, height - 1);
        acc += src[addIdx * width + x] - src[remIdx * width + x];
        dst[y * width + x] = acc * inv;
      }
    }
  }

  /// XDoG edge detector:
  /// D = G(sigma) - k * G(1.6 * sigma), k ~ 0.98
  /// out = D > epsilon ? 1 : 1 + tanh(phi * (D - epsilon))
  ///
  /// D is first divided by a robust, per-image scale: the [scalePercentile]
  /// of the dark-side response `max(0, -D)` (floored at [minScale]). Fixed,
  /// absolute epsilon/phi only suited crisp, high-contrast images; soft
  /// camera photos produced almost no lines. With the normalization, D is
  /// measured relative to this image's own strong edges.
  ///
  /// Returns edge strength in [0.0, 1.0] where 1.0 is a strong dark line
  /// (i.e. `1 - out`, so the threshold in [thresholdMask] picks lines).
  static Float32List xdogEdges(
    Float32List gray,
    int width,
    int height, {
    double sigma = 1.0,
    double k = 0.98,
    double phi = 0.9,
    double epsilon = 0.0,
    double scalePercentile = 0.97,
    double minScale = 0.004,
  }) {
    final g1 = gaussianBlur(gray, width, height, sigma);
    final g2 = gaussianBlur(gray, width, height, 1.6 * sigma);
    final count = width * height;
    final d = Float32List(count);
    var maxNeg = 0.0;
    for (var i = 0; i < count; i++) {
      final v = g1[i] - k * g2[i];
      d[i] = v;
      if (-v > maxNeg) maxNeg = -v;
    }

    final scale = math.max(
      minScale,
      _percentileOfNegative(d, maxNeg, scalePercentile),
    );
    final invScale = 1.0 / scale;

    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      final dn = d[i] * invScale;
      if (dn > epsilon) {
        out[i] = 0.0;
      } else {
        final x = phi * (dn - epsilon);
        // tanh(x) = (e^2x - 1) / (e^2x + 1), safe for x <= 0
        final e2x = math.exp(2.0 * x.clamp(-20.0, 0.0));
        final tanhVal = (e2x - 1.0) / (e2x + 1.0);
        final soft = 1.0 + tanhVal; // in (0, 1]
        out[i] = (1.0 - soft).clamp(0.0, 1.0);
      }
    }
    return out;
  }

  /// The [p]-quantile of `max(0, -d)` over all pixels, via a histogram.
  static double _percentileOfNegative(Float32List d, double maxNeg, double p) {
    if (maxNeg <= 0) return 0.0;
    const bins = 2048;
    final hist = Int32List(bins);
    final toBin = (bins - 1) / maxNeg;
    for (var i = 0; i < d.length; i++) {
      final neg = -d[i];
      hist[neg > 0 ? (neg * toBin).floor() : 0]++;
    }
    final target = (d.length * p).ceil();
    var cumulative = 0;
    for (var b = 0; b < bins; b++) {
      cumulative += hist[b];
      if (cumulative >= target) return (b + 0.5) / toBin;
    }
    return maxNeg;
  }

  /// Sobel edge magnitude normalized to [0.0, 1.0].
  static Float32List sobelEdges(Float32List gray, int width, int height) {
    final count = width * height;
    final mag = Float32List(count);
    var maxMag = 0.0;

    for (var y = 1; y < height - 1; y++) {
      final rowPrev = (y - 1) * width;
      final rowCurr = y * width;
      final rowNext = (y + 1) * width;
      for (var x = 1; x < width - 1; x++) {
        final tl = gray[rowPrev + x - 1];
        final tc = gray[rowPrev + x];
        final tr = gray[rowPrev + x + 1];
        final ml = gray[rowCurr + x - 1];
        final mr = gray[rowCurr + x + 1];
        final bl = gray[rowNext + x - 1];
        final bc = gray[rowNext + x];
        final br = gray[rowNext + x + 1];

        final gx = (-tl + tr) + (-2.0 * ml + 2.0 * mr) + (-bl + br);
        final gy = (-tl - 2.0 * tc - tr) + (bl + 2.0 * bc + br);
        final m = math.sqrt(gx * gx + gy * gy);
        mag[rowCurr + x] = m;
        if (m > maxMag) maxMag = m;
      }
    }

    if (maxMag > 1e-6) {
      final inv = 1.0 / maxMag;
      for (var i = 0; i < count; i++) {
        mag[i] = (mag[i] * inv).clamp(0.0, 1.0);
      }
    }
    return mag;
  }

  /// Thresholds [edgeMap] with t = lerp(0.6, 0.05, strength).
  static Uint8List thresholdMask(Float32List edgeMap, double strength) {
    final t = 0.6 + (0.05 - 0.6) * strength.clamp(0.0, 1.0);
    final out = Uint8List(edgeMap.length);
    for (var i = 0; i < edgeMap.length; i++) {
      out[i] = edgeMap[i] >= t ? 1 : 0;
    }
    return out;
  }

  /// Separable square dilation with [radius] (0..3).
  static Uint8List dilateMask(
    Uint8List mask,
    int width,
    int height,
    int radius,
  ) {
    if (radius <= 0) return Uint8List.fromList(mask);

    final tmp = Uint8List(width * height);
    final out = Uint8List(width * height);

    // Horizontal max filter
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        var found = 0;
        final xStart = (x - radius).clamp(0, width - 1);
        final xEnd = (x + radius).clamp(0, width - 1);
        for (var kx = xStart; kx <= xEnd; kx++) {
          if (mask[row + kx] != 0) {
            found = 1;
            break;
          }
        }
        tmp[row + x] = found;
      }
    }

    // Vertical max filter
    for (var y = 0; y < height; y++) {
      final yStart = (y - radius).clamp(0, height - 1);
      final yEnd = (y + radius).clamp(0, height - 1);
      final row = y * width;
      for (var x = 0; x < width; x++) {
        var found = 0;
        for (var ky = yStart; ky <= yEnd; ky++) {
          if (tmp[ky * width + x] != 0) {
            found = 1;
            break;
          }
        }
        out[row + x] = found;
      }
    }

    return out;
  }
}
