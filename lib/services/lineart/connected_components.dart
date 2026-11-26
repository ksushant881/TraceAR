import 'dart:collection';
import 'dart:typed_data';

class ComponentInfo {
  const ComponentInfo({
    required this.label,
    required this.area,
    required this.pixels,
  });

  final int label;
  final int area;
  final List<int> pixels;
}

class ConnectedComponents {
  ConnectedComponents._();

  static const List<int> _dx = [-1, 0, 1, -1, 1, -1, 0, 1];
  static const List<int> _dy = [-1, -1, -1, 0, 0, 1, 1, 1];

  /// Finds 8-connected components in a binary [mask] (non-zero = foreground).
  static List<ComponentInfo> find(Uint8List mask, int width, int height) {
    final count = width * height;
    final visited = Uint8List(count);
    final components = <ComponentInfo>[];
    final queue = Queue<int>();
    var nextLabel = 1;

    for (var start = 0; start < count; start++) {
      if (mask[start] == 0 || visited[start] != 0) continue;

      final label = nextLabel++;
      final pixels = <int>[];
      visited[start] = 1;
      queue.add(start);

      while (queue.isNotEmpty) {
        final idx = queue.removeFirst();
        pixels.add(idx);
        final x = idx % width;
        final y = idx ~/ width;

        for (var d = 0; d < 8; d++) {
          final nx = x + _dx[d];
          final ny = y + _dy[d];
          if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
          final nIdx = ny * width + nx;
          if (mask[nIdx] != 0 && visited[nIdx] == 0) {
            visited[nIdx] = 1;
            queue.add(nIdx);
          }
        }
      }

      components.add(
        ComponentInfo(label: label, area: pixels.length, pixels: pixels),
      );
    }

    return components;
  }

  /// Drops 8-connected components smaller than [minArea].
  static Uint8List removeSmall(
    Uint8List mask,
    int width,
    int height,
    int minArea,
  ) {
    final components = find(mask, width, height);
    final out = Uint8List(width * height);
    for (final comp in components) {
      if (comp.area >= minArea) {
        for (final idx in comp.pixels) {
          out[idx] = 1;
        }
      }
    }
    return out;
  }
}
