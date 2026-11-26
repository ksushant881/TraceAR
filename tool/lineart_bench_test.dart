// Dev harness: runs the line-art pipeline on real photos.
//   flutter test tool/lineart_bench_test.dart --dart-define=BENCH_IN=<dir> --dart-define=BENCH_OUT=<dir>
// Writes <name>_lines.png (lines on white) and prints line-pixel coverage.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/services/lineart/lineart_pipeline.dart';
import 'package:tracear/services/lineart/step_generator.dart';

const _in = String.fromEnvironment('BENCH_IN');
const _out = String.fromEnvironment('BENCH_OUT');
const _strength = String.fromEnvironment(
  'BENCH_STRENGTH',
  defaultValue: '0.55',
);
const _steps = bool.fromEnvironment('BENCH_STEPS');

img.Image _onWhite(Uint8List png) {
  final src = img.decodePng(png)!;
  final out = img.Image(width: src.width, height: src.height);
  img.fill(out, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(out, src);
}

void main() {
  test('line-art bench', () {
    if (_in.isEmpty || _out.isEmpty) return;
    Directory(_out).createSync(recursive: true);
    final strength = double.parse(_strength);
    final files =
        Directory(_in)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jpg') || f.path.endsWith('.png'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = p.basenameWithoutExtension(f.path);
      final bytes = f.readAsBytesSync();
      final params = LineArtParams(strength: strength, thickness: 1);
      final sw = Stopwatch()..start();
      final res = LineArtPipeline.generateSync(bytes, params);
      final ms = sw.elapsedMilliseconds;
      final decoded = img.decodePng(res.pngBytes)!;
      var lines = 0;
      for (final px in decoded) {
        if (px.a > 0) lines++;
      }
      final pct = 100 * lines / (decoded.width * decoded.height);
      // ignore: avoid_print
      print(
        '$name ${res.width}x${res.height} lines=${pct.toStringAsFixed(2)}% ${ms}ms',
      );
      File(p.join(_out, '${name}_lines.png'))
          .writeAsBytesSync(img.encodePng(_onWhite(res.pngBytes)));
      if (_steps) {
        final steps = StepGenerator.generateSync(
          bytes,
          LineArtParams(strength: strength, thickness: 1, stepCount: 5),
        );
        for (var i = 0; i < steps.stepPngs.length; i++) {
          File(p.join(_out, '${name}_step${i + 1}.png'))
              .writeAsBytesSync(img.encodePng(_onWhite(steps.stepPngs[i])));
        }
      }
    }
  });
}
