import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/lineart/filters.dart';
import 'package:tracear/services/lineart/lineart_pipeline.dart';
import 'package:tracear/services/lineart/step_generator.dart';

void main() {
  group('StepGenerator invariants (§6.3)', () {
    final fixtureFiles = [
      'test/fixtures/sample_1.png',
      'test/fixtures/sample_2.png',
      'test/fixtures/sample_3.png',
    ];

    for (final path in fixtureFiles) {
      test('invariants hold for $path', () async {
        final bytes = await File(path).readAsBytes();
        const params = LineArtParams(
          strength: 0.6,
          thickness: 1,
          stepCount: 5,
          includeShading: false,
        );

        final decoded = img.decodeImage(bytes)!;
        final width = decoded.width;
        final height = decoded.height;
        final rgba = decoded.getBytes(order: img.ChannelOrder.rgba);
        final gray = LineArtFilters.toGrayscale(rgba, width, height);
        final norm = LineArtFilters.normalizeContrast(gray, width, height);

        // Full line-art mask (same as LineArtPipeline)
        final fullBase = LineArtPipeline.lineStrokes(
          norm,
          width,
          height,
          params,
        );
        final fullDilated = LineArtFilters.dilateMask(
          fullBase,
          width,
          height,
          params.thickness,
        );

        // Step masks
        final stepMasks = StepGenerator.generateStepMasksSync(
          norm,
          width,
          height,
          params,
        );
        expect(stepMasks.length, equals(params.stepCount));

        final dilatedSteps = StepGenerator.dilateAndDeduplicate(
          stepMasks,
          width,
          height,
          params.thickness,
        );

        // Invariant 3: Every step is non-empty
        for (var i = 0; i < dilatedSteps.length; i++) {
          final count = dilatedSteps[i].where((v) => v != 0).length;
          expect(count, greaterThan(0), reason: 'Step $i is empty');
        }

        // Invariant 1: Union of all steps covers >= 95% of full line-art mask
        final union = Uint8List(width * height);
        for (final step in dilatedSteps) {
          for (var p = 0; p < union.length; p++) {
            if (step[p] != 0) union[p] = 1;
          }
        }
        var fullCount = 0;
        var coveredCount = 0;
        for (var p = 0; p < fullDilated.length; p++) {
          if (fullDilated[p] != 0) {
            fullCount++;
            if (union[p] != 0) coveredCount++;
          }
        }
        if (fullCount > 0) {
          final coverage = coveredCount / fullCount;
          expect(
            coverage,
            greaterThanOrEqualTo(0.95),
            reason: 'Coverage $coverage < 0.95 for $path',
          );
        }

        // Invariant 2: Any two steps overlap by at most 2% of their pixels
        for (var i = 0; i < dilatedSteps.length; i++) {
          for (var j = i + 1; j < dilatedSteps.length; j++) {
            final a = dilatedSteps[i];
            final b = dilatedSteps[j];
            var aCount = 0;
            var bCount = 0;
            var overlap = 0;
            for (var p = 0; p < a.length; p++) {
              if (a[p] != 0) aCount++;
              if (b[p] != 0) bCount++;
              if (a[p] != 0 && b[p] != 0) overlap++;
            }
            final minCount = math.min(aCount, bCount);
            if (minCount > 0) {
              expect(
                overlap / minCount,
                lessThanOrEqualTo(0.02),
                reason: 'Steps $i and $j overlap > 2%',
              );
            }
          }
        }
      });
    }
  });
}
