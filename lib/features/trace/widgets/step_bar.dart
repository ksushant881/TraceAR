import 'package:material_ui/material_ui.dart';

class StepBar extends StatelessWidget {
  const StepBar({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.onPrevious,
    required this.onNext,
    required this.onFinish,
    required this.onSelectStep,
    required this.onShowFullStart,
    required this.onShowFullEnd,
  });

  final int currentStep;
  final int totalSteps;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onFinish;
  final ValueChanged<int> onSelectStep;
  final VoidCallback onShowFullStart;
  final VoidCallback onShowFullEnd;

  @override
  Widget build(BuildContext context) {
    if (totalSteps == 0) return const SizedBox.shrink();
    final isFirst = currentStep <= 0;
    final isLast = currentStep >= totalSteps - 1;
    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: isFirst ? null : onPrevious,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous step',
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Step ${currentStep + 1} of $totalSteps',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      alignment: WrapAlignment.center,
                      children: List.generate(totalSteps, (i) {
                        final active = i == currentStep;
                        final done = i < currentStep;
                        return GestureDetector(
                          onTap: () => onSelectStep(i),
                          child: Semantics(
                            label: 'Step ${i + 1}',
                            button: true,
                            child: Container(
                              width: active ? 18 : 10,
                              height: 10,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(5),
                                color: active
                                    ? cs.primary
                                    : done
                                    ? cs.primary.withValues(alpha: 0.45)
                                    : Colors.white30,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTapDown: (_) => onShowFullStart(),
                onTapUp: (_) => onShowFullEnd(),
                onTapCancel: onShowFullEnd,
                child: Semantics(
                  label: 'Hold to show full picture',
                  button: true,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    child: const Icon(Icons.visibility_outlined),
                  ),
                ),
              ),
              if (isLast)
                FilledButton(onPressed: onFinish, child: const Text('Finish'))
              else
                IconButton(
                  onPressed: onNext,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next step',
                ),
            ],
          ),
        ],
      ),
    );
  }
}
