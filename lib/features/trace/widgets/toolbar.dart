import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tracear/features/trace/trace_controller.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';

class TraceToolbar extends StatelessWidget {
  const TraceToolbar({
    super.key,
    required this.session,
    required this.flashOn,
    required this.recordingKind,
    required this.timelapseFrames,
    required this.onOpacityChanged,
    required this.onToggleLock,
    required this.onUnlockLongPress,
    required this.onFlip,
    required this.onToggleFlash,
    required this.onToggleGrid,
    required this.onToggleInvert,
    required this.onHideStart,
    required this.onHideEnd,
    required this.onRecordTap,
    required this.onToggleMode,
    required this.onReset,
    required this.onTakeResultPhoto,
  });

  final TraceSession session;
  final bool flashOn;
  final RecordingKind recordingKind;
  final int timelapseFrames;
  final ValueChanged<double> onOpacityChanged;
  final VoidCallback onToggleLock;
  final VoidCallback onUnlockLongPress;
  final VoidCallback onFlip;
  final VoidCallback onToggleFlash;
  final VoidCallback onToggleGrid;
  final VoidCallback onToggleInvert;
  final VoidCallback onHideStart;
  final VoidCallback onHideEnd;
  final VoidCallback onRecordTap;
  final VoidCallback onToggleMode;
  final VoidCallback onReset;
  final VoidCallback onTakeResultPhoto;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRecording = recordingKind != RecordingKind.none;

    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.opacity, size: 18),
                Expanded(
                  child: Slider(
                    value: session.opacity,
                    min: 0.05,
                    max: 1.0,
                    onChanged: onOpacityChanged,
                  ),
                ),
                Text('${(session.opacity * 100).round()}%'),
              ],
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (session.locked)
                    _LockedButton(
                      color: cs.secondary,
                      onUnlock: onUnlockLongPress,
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.lock_open),
                      tooltip: 'Lock overlay',
                      onPressed: onToggleLock,
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.flip,
                      color: session.transform.flipH ? cs.primary : null,
                    ),
                    tooltip: 'Flip horizontally',
                    onPressed: session.locked ? null : onFlip,
                  ),
                  IconButton(
                    icon: Icon(
                      flashOn ? Icons.flash_on : Icons.flash_off,
                      color: flashOn ? cs.secondary : null,
                    ),
                    tooltip: 'Toggle flashlight',
                    onPressed: onToggleFlash,
                  ),
                  IconButton(
                    icon: Icon(
                      session.gridOn ? Icons.grid_on : Icons.grid_off,
                      color: session.gridOn ? cs.primary : null,
                    ),
                    tooltip: 'Toggle grid',
                    onPressed: onToggleGrid,
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.invert_colors,
                      color: session.inverted ? cs.primary : null,
                    ),
                    tooltip: 'Invert colors',
                    onPressed: onToggleInvert,
                  ),
                  GestureDetector(
                    onTapDown: (_) => onHideStart(),
                    onTapUp: (_) => onHideEnd(),
                    onTapCancel: onHideEnd,
                    child: Semantics(
                      label: 'Hold to hide image',
                      button: true,
                      child: Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        child: const Icon(Icons.visibility_off_outlined),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onRecordTap,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isRecording
                                ? Icons.stop_circle
                                : Icons.fiber_manual_record,
                            color: Colors.redAccent,
                          ),
                          if (recordingKind == RecordingKind.timelapse) ...[
                            const SizedBox(width: 4),
                            Text('$timelapseFrames'),
                          ],
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      session.mode == DrawMode.stepByStep
                          ? Icons.format_list_numbered
                          : Icons.layers_outlined,
                      color: cs.primary,
                    ),
                    tooltip: 'Switch drawing mode',
                    onPressed: onToggleMode,
                  ),
                  IconButton(
                    icon: const Icon(Icons.restart_alt),
                    tooltip: 'Reset position',
                    onPressed: session.locked ? null : onReset,
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined),
                    tooltip: 'Take photo of result',
                    onPressed: onTakeResultPhoto,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lock button while locked: long-press unlocks, a tap explains how.
///
/// Deliberately not an [IconButton]: its [Tooltip] claims the long-press on
/// touch screens, so a long-press only showed the tooltip and never unlocked.
class _LockedButton extends StatelessWidget {
  const _LockedButton({required this.color, required this.onUnlock});

  final Color color;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Locked. Long press to unlock',
      onLongPress: onUnlock,
      child: InkResponse(
        key: const ValueKey('unlock-button'),
        radius: 24,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onUnlock();
        },
        onTap: () {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text('Press and hold the lock to unlock'),
                duration: Duration(seconds: 2),
              ),
            );
        },
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.lock, color: color),
        ),
      ),
    );
  }
}
