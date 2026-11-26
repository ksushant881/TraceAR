import 'package:material_ui/material_ui.dart';

class GridPainter extends CustomPainter {
  const GridPainter({required this.gridSize});

  final int gridSize;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;

    for (var i = 1; i < gridSize; i++) {
      final x = size.width * (i / gridSize);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);

      final y = size.height * (i / gridSize);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.gridSize != gridSize;
}
