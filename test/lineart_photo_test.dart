import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/lineart/lineart_pipeline.dart';

/// Regression test: soft, camera-like photos must still produce traceable
/// line art. (The first pipeline found almost no lines on them because its
/// blur scale and threshold were fixed; the synthetic fixtures didn't catch
/// it.) Fixture: public-domain NASA portrait, upscaled to 1024 px so its
/// edges are soft like a phone photo.
double _lineCoverage(LineArtResult res) {
  final decoded = img.decodePng(res.pngBytes)!;
  var lines = 0;
  for (final px in decoded) {
    if (px.a > 0) lines++;
  }
  return lines / (decoded.width * decoded.height);
}

void main() {
  final bytes = File('test/fixtures/photo_soft_portrait.jpg').readAsBytesSync();

  test('soft photo produces a usable amount of line art', () {
    final res = LineArtPipeline.generateSync(
      bytes,
      const LineArtParams(strength: 0.55, thickness: 1),
    );
    final coverage = _lineCoverage(res);
    expect(coverage, greaterThan(0.04), reason: 'too few lines: $coverage');
    expect(coverage, lessThan(0.30), reason: 'too many lines: $coverage');
  });

  test('strength slider controls the amount of detail', () {
    final low = _lineCoverage(
      LineArtPipeline.generateSync(
        bytes,
        const LineArtParams(strength: 0.1, thickness: 1),
      ),
    );
    final high = _lineCoverage(
      LineArtPipeline.generateSync(
        bytes,
        const LineArtParams(strength: 0.9, thickness: 1),
      ),
    );
    expect(low, greaterThan(0.01), reason: 'low strength found no lines');
    expect(high, greaterThan(low * 1.5), reason: 'slider has little effect');
  });
}
