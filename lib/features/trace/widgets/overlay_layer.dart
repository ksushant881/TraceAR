import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';

class OverlayLayer extends StatelessWidget {
  const OverlayLayer({
    super.key,
    required this.session,
    required this.fullImage,
    required this.stepImages,
    required this.hideImage,
    required this.showFullPicture,
  });

  final TraceSession session;
  final ui.Image? fullImage;
  final List<ui.Image> stepImages;
  final bool hideImage;
  final bool showFullPicture;

  static const List<double> _invertMatrix = <double>[
    -1, 0, 0, 0, 255, //
    0, -1, 0, 0, 255, //
    0, 0, -1, 0, 255, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    if (hideImage) return const SizedBox.shrink();

    final Widget content;
    if (session.mode == DrawMode.stepByStep && stepImages.isNotEmpty) {
      content = _buildStepStack();
    } else if (fullImage != null) {
      content = _buildFull(fullImage!);
    } else {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: Center(
        child: Transform(
          alignment: Alignment.center,
          transform: session.transform.toMatrix4(),
          child: content,
        ),
      ),
    );
  }

  Widget _buildFull(ui.Image image) {
    Widget imgWidget = RawImage(image: image, fit: BoxFit.contain);
    if (session.inverted) {
      imgWidget = ColorFiltered(
        colorFilter: const ColorFilter.matrix(_invertMatrix),
        child: imgWidget,
      );
    }
    return Opacity(opacity: session.opacity, child: imgWidget);
  }

  Widget _buildStepStack() {
    final current = session.currentStep.clamp(0, stepImages.length - 1);
    final children = <Widget>[];

    for (var i = 0; i < stepImages.length; i++) {
      if (!showFullPicture && i > current) continue;

      Widget layer = RawImage(image: stepImages[i], fit: BoxFit.contain);

      if (showFullPicture) {
        if (session.inverted) {
          layer = ColorFiltered(
            colorFilter: const ColorFilter.matrix(_invertMatrix),
            child: layer,
          );
        }
        children.add(Opacity(opacity: session.opacity, child: layer));
      } else if (i < current) {
        if (session.inverted) {
          layer = ColorFiltered(
            colorFilter: const ColorFilter.matrix(_invertMatrix),
            child: layer,
          );
        }
        children.add(
          Opacity(
            opacity: (session.opacity * 0.35).clamp(0.0, 1.0),
            child: layer,
          ),
        );
      } else {
        // i == current
        layer = ColorFiltered(
          colorFilter: ColorFilter.mode(
            session.highlightColor,
            BlendMode.srcIn,
          ),
          child: layer,
        );
        children.add(Opacity(opacity: session.opacity, child: layer));
      }
    }

    return Stack(alignment: Alignment.center, children: children);
  }
}
