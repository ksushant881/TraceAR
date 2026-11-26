import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracear/features/prepare/prepare_controller.dart';
import 'package:tracear/models/trace_image.dart';

class PrepareScreen extends ConsumerStatefulWidget {
  const PrepareScreen({super.key, required this.imageId});

  final String imageId;

  @override
  ConsumerState<PrepareScreen> createState() => _PrepareScreenState();
}

class _PrepareScreenState extends ConsumerState<PrepareScreen> {
  Rect _cropRect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);

  @override
  Widget build(BuildContext context) {
    final asyncState = ref.watch(prepareControllerProvider(widget.imageId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prepare'),
        actions: [
          asyncState.maybeWhen(
            data: (s) => s.isTemplate
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.rotate_right),
                        tooltip: 'Rotate 90 degrees',
                        onPressed: () => ref
                            .read(
                              prepareControllerProvider(widget.imageId)
                                  .notifier,
                            )
                            .rotate90(),
                      ),
                      IconButton(
                        icon: Icon(s.isCropping ? Icons.check : Icons.crop),
                        tooltip: s.isCropping ? 'Apply crop' : 'Crop image',
                        onPressed: () {
                          final notifier = ref.read(
                            prepareControllerProvider(widget.imageId).notifier,
                          );
                          if (s.isCropping) {
                            notifier.applyCrop(_cropRect);
                          } else {
                            setState(() {
                              _cropRect = const Rect.fromLTWH(
                                0.1,
                                0.1,
                                0.8,
                                0.8,
                              );
                            });
                            notifier.setCropping(true);
                          }
                        },
                      ),
                      if (s.isCropping)
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel crop',
                          onPressed: () => ref
                              .read(
                                prepareControllerProvider(widget.imageId)
                                    .notifier,
                              )
                              .setCropping(false),
                        ),
                    ],
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: asyncState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (state) {
          final controller = ref.read(
            prepareControllerProvider(widget.imageId).notifier,
          );
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!state.isTemplate && !state.isCropping)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: true,
                              label: Text('Line art'),
                              icon: Icon(Icons.brush),
                            ),
                            ButtonSegment(
                              value: false,
                              label: Text('Original'),
                              icon: Icon(Icons.image),
                            ),
                          ],
                          selected: {state.showLineArt},
                          onSelectionChanged: (sel) =>
                              controller.togglePreview(sel.first),
                        ),
                      ),
                    AspectRatio(
                      aspectRatio: state.image.width / state.image.height,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const CustomPaint(painter: _CheckerboardPainter()),
                            if (state.isCropping)
                              _CropOverlay(
                                imagePath: state.image.originalPath,
                                cropRect: _cropRect,
                                onChanged: (r) => setState(() => _cropRect = r),
                              )
                            else if (state.showLineArt &&
                                state.lineArtBytes != null)
                              Image.memory(
                                state.lineArtBytes!,
                                fit: BoxFit.contain,
                              )
                            else if (state.isTemplate)
                              Image.asset(
                                state.image.originalPath,
                                fit: BoxFit.contain,
                              )
                            else
                              Image.file(
                                File(state.image.originalPath),
                                fit: BoxFit.contain,
                              ),
                            if (state.isProcessingLineArt)
                              const Positioned(
                                top: 12,
                                right: 12,
                                child: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Colors.black54,
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!state.isTemplate && state.showLineArt) ...[
                      const SizedBox(height: 16),
                      _SliderRow(
                        label: 'Line strength',
                        valueLabel:
                            '${(state.session.lineArtParams.strength * 100).round()}%',
                        value: state.session.lineArtParams.strength,
                        min: 0.0,
                        max: 1.0,
                        onChanged: (v) =>
                            controller.updateLineArtParams(strength: v),
                      ),
                      _SliderRow(
                        label: 'Line thickness',
                        valueLabel: '${state.session.lineArtParams.thickness}',
                        value: state.session.lineArtParams.thickness.toDouble(),
                        min: 0,
                        max: 3,
                        divisions: 3,
                        onChanged: (v) => controller.updateLineArtParams(
                          thickness: v.round(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Drawing mode',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _ModeCard(
                            title: 'Full drawing',
                            subtitle: 'Trace the whole picture freely',
                            icon: Icons.layers_outlined,
                            selected: state.session.mode == DrawMode.full,
                            onTap: () => controller.setMode(DrawMode.full),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ModeCard(
                            title: 'Step-by-step',
                            subtitle: 'Outline to details in stages',
                            icon: Icons.format_list_numbered,
                            selected: state.session.mode == DrawMode.stepByStep,
                            onTap: () =>
                                controller.setMode(DrawMode.stepByStep),
                          ),
                        ),
                      ],
                    ),
                    if (state.session.mode == DrawMode.stepByStep) ...[
                      const SizedBox(height: 16),
                      if (!state.isTemplate) ...[
                        _SliderRow(
                          label: 'Number of steps',
                          valueLabel:
                              '${state.session.lineArtParams.stepCount}',
                          value: state.session.lineArtParams.stepCount
                              .toDouble(),
                          min: 3,
                          max: 8,
                          divisions: 5,
                          onChanged: (v) =>
                              controller.updateStepParams(stepCount: v.round()),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Include shading step'),
                          value: state.session.lineArtParams.includeShading,
                          onChanged: (v) =>
                              controller.updateStepParams(includeShading: v),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            'Step preview',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          if (state.isProcessingSteps)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: state.stepPreviewPngs.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            return _StepPreviewThumb(
                              stepIndex: idx,
                              allSteps: state.stepPreviewPngs,
                              highlightColor: state.session.highlightColor,
                            );
                          },
                        ),
                      ),
                    ],
                    if (state.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          state.errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: state.isStarting
                          ? null
                          : () async {
                              final ok = await controller.startTracing();
                              if (ok && context.mounted) {
                                context.push('/trace/${widget.imageId}');
                              }
                            },
                      icon: state.isStarting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: const Text('Start tracing'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(valueLabel)],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? cs.primary.withValues(alpha: 0.16)
              : cs.surfaceContainerHighest,
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? cs.primary : null),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _StepPreviewThumb extends StatelessWidget {
  const _StepPreviewThumb({
    required this.stepIndex,
    required this.allSteps,
    required this.highlightColor,
  });

  final int stepIndex;
  final List<Uint8List> allSteps;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (var i = 0; i < stepIndex; i++)
                Opacity(
                  opacity: 0.35,
                  child: Image.memory(allSteps[i], fit: BoxFit.contain),
                ),
              ColorFiltered(
                colorFilter: ColorFilter.mode(highlightColor, BlendMode.srcIn),
                child: Image.memory(allSteps[stepIndex], fit: BoxFit.contain),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Step ${stepIndex + 1}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _CropOverlay extends StatelessWidget {
  const _CropOverlay({
    required this.imagePath,
    required this.cropRect,
    required this.onChanged,
  });

  final String imagePath;
  final Rect cropRect;
  final ValueChanged<Rect> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final rectPx = Rect.fromLTWH(
          cropRect.left * w,
          cropRect.top * h,
          cropRect.width * w,
          cropRect.height * h,
        );
        return GestureDetector(
          onPanUpdate: (details) {
            final dx = details.delta.dx / w;
            final dy = details.delta.dy / h;
            final nextLeft = (cropRect.left + dx).clamp(
              0.0,
              1.0 - cropRect.width,
            );
            final nextTop = (cropRect.top + dy).clamp(
              0.0,
              1.0 - cropRect.height,
            );
            onChanged(
              Rect.fromLTWH(nextLeft, nextTop, cropRect.width, cropRect.height),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(imagePath), fit: BoxFit.contain),
              CustomPaint(painter: _CropRectPainter(rectPx)),
            ],
          ),
        );
      },
    );
  }
}

class _CropRectPainter extends CustomPainter {
  _CropRectPainter(this.rect);
  final Rect rect;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black54;
    final full = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(rect);
    canvas.drawPath(
      Path.combine(PathOperation.difference, full, hole),
      dimPaint,
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropRectPainter oldDelegate) =>
      oldDelegate.rect != rect;
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 12.0;
    final light = Paint()..color = const Color(0xFFCCCCCC);
    final dark = Paint()..color = const Color(0xFF999999);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        final isEven = ((x ~/ cell) + (y ~/ cell)).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isEven ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
