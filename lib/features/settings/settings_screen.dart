import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracear/providers/app_providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const List<Color> _highlightSwatches = [
    Color(0xFF00E5FF),
    Color(0xFFFFB74D),
    Color(0xFFFF5252),
    Color(0xFF69F0AE),
    Color(0xFFE040FB),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionSlider(
            title: 'Default overlay opacity',
            valueLabel: '${(settings.defaultOpacity * 100).round()}%',
            value: settings.defaultOpacity,
            min: 0.1,
            max: 1.0,
            onChanged: (v) =>
                controller.update(settings.copyWith(defaultOpacity: v)),
          ),
          _SectionSlider(
            title: 'Grid size',
            valueLabel: '${settings.gridSize} x ${settings.gridSize}',
            value: settings.gridSize.toDouble(),
            min: 2,
            max: 8,
            divisions: 6,
            onChanged: (v) =>
                controller.update(settings.copyWith(gridSize: v.round())),
          ),
          _SectionSlider(
            title: 'Timelapse capture interval',
            valueLabel: '${settings.timelapseIntervalSec} s',
            value: settings.timelapseIntervalSec.toDouble(),
            min: 1,
            max: 15,
            divisions: 14,
            onChanged: (v) => controller.update(
              settings.copyWith(timelapseIntervalSec: v.round()),
            ),
          ),
          _SectionSlider(
            title: 'Timelapse output FPS',
            valueLabel: '${settings.timelapseFps} fps',
            value: settings.timelapseFps.toDouble(),
            min: 12,
            max: 60,
            divisions: 8,
            onChanged: (v) =>
                controller.update(settings.copyWith(timelapseFps: v.round())),
          ),
          _SectionSlider(
            title: 'Default step count',
            valueLabel: '${settings.defaultStepCount}',
            value: settings.defaultStepCount.toDouble(),
            min: 3,
            max: 8,
            divisions: 5,
            onChanged: (v) => controller.update(
              settings.copyWith(defaultStepCount: v.round()),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Default to line art'),
            value: settings.defaultLineArt,
            onChanged: (v) =>
                controller.update(settings.copyWith(defaultLineArt: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow landscape orientation on Trace'),
            value: settings.landscapeAllowed,
            onChanged: (v) =>
                controller.update(settings.copyWith(landscapeAllowed: v)),
          ),
          const SizedBox(height: 12),
          const Text(
            'Step highlight color',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children: _highlightSwatches.map((color) {
              final selected =
                  settings.highlightColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () =>
                    controller.update(settings.copyWith(highlightColor: color)),
                child: Semantics(
                  label: 'Highlight color swatch',
                  button: true,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.black)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 36),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('About TraceAR'),
            subtitle: Text(
              'Offline AR-style paper tracing with full and step-by-step modes. No ads, no analytics, no network calls.',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Open-source licenses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'TraceAR',
              applicationVersion: '1.0.0',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionSlider extends StatelessWidget {
  const _SectionSlider({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
  });

  final String title;
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
          children: [Text(title), Text(valueLabel)],
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
