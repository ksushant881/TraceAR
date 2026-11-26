import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';

void main() {
  group('OverlayTransform math', () {
    test('pure drag translates by the focal point movement', () {
      const start = OverlayTransform(dx: 10, dy: 20, scale: 2.0, rotation: 0.5);
      final updated = start.applyFocalGesture(
        startFocal: const Offset(50, 50),
        focal: const Offset(55, 40),
        scaleFactor: 1.0,
        rotationDelta: 0.0,
      );

      expect(updated.dx, closeTo(15.0, 1e-6));
      expect(updated.dy, closeTo(10.0, 1e-6));
      expect(updated.scale, closeTo(2.0, 1e-6));
      expect(updated.rotation, closeTo(0.5, 1e-6));
    });

    test('zoom and rotation pivot around the fingers', () {
      const start = OverlayTransform(
        dx: 10,
        dy: 20,
        scale: 2.0,
        rotation: 0.5,
        flipH: true,
      );
      const startFocal = Offset(80, -30);
      const focal = Offset(95, -10);

      // Image-local point under the finger at gesture start.
      final inverse = Matrix4.inverted(start.toMatrix4());
      final local = MatrixUtils.transformPoint(inverse, startFocal);

      final updated = start.applyFocalGesture(
        startFocal: startFocal,
        focal: focal,
        scaleFactor: 1.5,
        rotationDelta: 0.25,
      );

      expect(updated.scale, closeTo(3.0, 1e-6));
      expect(updated.rotation, closeTo(0.75, 1e-6));
      final mapped = MatrixUtils.transformPoint(updated.toMatrix4(), local);
      expect(mapped.dx, closeTo(focal.dx, 1e-4));
      expect(mapped.dy, closeTo(focal.dy, 1e-4));
    });

    test('scale is clamped to [0.1, 10.0]', () {
      const start = OverlayTransform(scale: 1.0);
      final tooSmall = start.applyFocalGesture(
        startFocal: Offset.zero,
        focal: Offset.zero,
        scaleFactor: 0.01,
        rotationDelta: 0.0,
      );
      expect(tooSmall.scale, equals(0.1));

      final tooLarge = start.applyFocalGesture(
        startFocal: Offset.zero,
        focal: Offset.zero,
        scaleFactor: 50.0,
        rotationDelta: 0.0,
      );
      expect(tooLarge.scale, equals(10.0));
    });

    test('toMatrix4 builds translate -> rotateZ -> scale -> flip', () {
      const t = OverlayTransform(
        dx: 100,
        dy: -50,
        scale: 2.0,
        rotation: math.pi / 2,
        flipH: true,
      );
      final m = t.toMatrix4();
      final p = MatrixUtils.transformPoint(m, const Offset(1, 0));
      // (1,0) -> flip (-1,0) -> scale (-2,0) -> rotate +90deg (0,-2) -> translate (100, -52)
      expect(p.dx, closeTo(100.0, 1e-4));
      expect(p.dy, closeTo(-52.0, 1e-4));
    });
  });

  group('TraceSession JSON round-trip', () {
    test('round-trips all fields accurately', () {
      const session = TraceSession(
        imageId: 'img-123',
        mode: DrawMode.stepByStep,
        useLineArt: false,
        transform: OverlayTransform(
          dx: 12.5,
          dy: -34.0,
          scale: 1.75,
          rotation: 0.4,
          flipH: true,
        ),
        opacity: 0.72,
        locked: true,
        inverted: true,
        gridOn: true,
        currentStep: 3,
        highlightColor: Color(0xFFFFB74D),
        lineArtParams: LineArtParams(
          strength: 0.8,
          thickness: 2,
          stepCount: 6,
          includeShading: true,
        ),
      );

      final encoded = jsonEncode(session.toJson());
      final decoded = TraceSession.fromJson(
        jsonDecode(encoded) as Map<String, dynamic>,
      );

      expect(decoded, equals(session));
    });
  });
}
