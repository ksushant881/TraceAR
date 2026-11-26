import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tracear/services/lineart/connected_components.dart';
import 'package:tracear/services/lineart/filters.dart';

void main() {
  group('LineArtFilters', () {
    test('gaussianBlur preserves constant image and smooths impulse', () {
      const w = 5;
      const h = 5;
      final constant = Float32List.fromList(List<double>.filled(w * h, 0.5));
      final blurredConst = LineArtFilters.gaussianBlur(constant, w, h, 1.0);
      for (final v in blurredConst) {
        expect(v, closeTo(0.5, 1e-4));
      }

      final impulse = Float32List(w * h);
      impulse[2 * w + 2] = 1.0;
      final blurredImpulse = LineArtFilters.gaussianBlur(impulse, w, h, 1.0);
      expect(blurredImpulse[2 * w + 2], lessThan(1.0));
      expect(blurredImpulse[2 * w + 2], greaterThan(blurredImpulse[0]));
    });

    test('sobelEdges detects vertical edge on step array', () {
      const w = 5;
      const h = 5;
      final src = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          src[y * w + x] = x >= 2 ? 1.0 : 0.0;
        }
      }
      final edges = LineArtFilters.sobelEdges(src, w, h);
      // Center column (x=2) has strong gradient, x=0 and x=4 have 0
      expect(edges[2 * w + 2], greaterThan(0.5));
      expect(edges[2 * w + 0], equals(0.0));
    });

    test('thresholdMask applies lerp(0.6, 0.05, strength)', () {
      final edges = Float32List.fromList([0.04, 0.1, 0.4, 0.7]);
      // strength = 0.0 -> t = 0.6 -> only 0.7 passes
      final low = LineArtFilters.thresholdMask(edges, 0.0);
      expect(low, orderedEquals([0, 0, 0, 1]));

      // strength = 1.0 -> t = 0.05 -> 0.1, 0.4, 0.7 pass
      final high = LineArtFilters.thresholdMask(edges, 1.0);
      expect(high, orderedEquals([0, 1, 1, 1]));
    });

    test('dilateMask expands single pixel by radius 1 into 3x3 square', () {
      const w = 5;
      const h = 5;
      final mask = Uint8List(w * h);
      mask[2 * w + 2] = 1;
      final dilated = LineArtFilters.dilateMask(mask, w, h, 1);
      var count = 0;
      for (final v in dilated) {
        if (v != 0) count++;
      }
      expect(count, equals(9));
      expect(dilated[1 * w + 1], equals(1));
      expect(dilated[0], equals(0));
    });
  });

  group('ConnectedComponents', () {
    test('finds 8-connected components and removes small noise', () {
      const w = 6;
      const h = 6;
      final mask = Uint8List(w * h);
      // Component 1: diagonal 4 pixels (8-connected)
      mask[0 * w + 0] = 1;
      mask[1 * w + 1] = 1;
      mask[2 * w + 2] = 1;
      mask[3 * w + 3] = 1;
      // Component 2: isolated 2-pixel noise
      mask[5 * w + 0] = 1;
      mask[5 * w + 1] = 1;

      final comps = ConnectedComponents.find(mask, w, h);
      expect(comps.length, equals(2));
      expect(comps.map((c) => c.area).toList()..sort(), equals([2, 4]));

      final cleaned = ConnectedComponents.removeSmall(mask, w, h, 3);
      expect(cleaned[0], equals(1));
      expect(cleaned[5 * w + 0], equals(0));
    });
  });
}
