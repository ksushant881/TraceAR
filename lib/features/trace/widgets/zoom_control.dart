import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Vertical camera-zoom slider shown at the right edge of the trace screen.
///
/// The slider is logarithmic so 1×→2× gets as much travel as 4×→8×, which
/// matches how zoom feels. Tapping the label resets to [minZoom].
class ZoomControl extends StatelessWidget {
  const ZoomControl({
    super.key,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    required this.onChanged,
  });

  final double zoom;
  final double minZoom;
  final double maxZoom;
  final ValueChanged<double> onChanged;

  static const double _maxSliderLength = 180;
  static const double _minSliderLength = 80;

  String get _label {
    final z = zoom;
    return z < 9.95 ? '${z.toStringAsFixed(1)}×' : '${z.round()}×';
  }

  @override
  Widget build(BuildContext context) {
    final logMin = math.log(minZoom);
    final logMax = math.log(maxZoom);
    final logValue = math.log(zoom.clamp(minZoom, maxZoom));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Label + padding take ~64 px; the rest is for the slider.
        final available = constraints.maxHeight.isFinite
            ? constraints.maxHeight - 64
            : _maxSliderLength;
        if (available < _minSliderLength) return const SizedBox.shrink();
        final length = math.min(_maxSliderLength, available);

        return Container(
          width: 48,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: 'Camera zoom $_label. Tap to reset.',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(minZoom),
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: Text(
                        _label,
                        style: TextStyle(
                          color: zoom > minZoom + 0.05
                              ? Colors.amber
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: length,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Slider(
                    value: logValue,
                    min: logMin,
                    max: logMax,
                    onChanged: (v) => onChanged(math.exp(v)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
