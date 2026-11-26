import 'package:flutter/services.dart';
import 'package:tracear/core/constants.dart';
import 'package:tracear/core/result.dart';

class NativeBridge {
  NativeBridge({MethodChannel? methodChannel, EventChannel? progressChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel(AppConstants.nativeChannelName),
      _progressChannel =
          progressChannel ??
          const EventChannel(AppConstants.timelapseProgressChannelName);

  final MethodChannel _methodChannel;
  final EventChannel _progressChannel;

  /// Stream of encoding progress values in [0.0, 1.0].
  Stream<double> get timelapseProgressStream => _progressChannel
      .receiveBroadcastStream()
      .map((event) => (event as num).toDouble().clamp(0.0, 1.0));

  /// Encodes JPEG frames in [frameDir] into an H.264 MP4 at [outPath] at [fps].
  Future<Result<String>> encodeTimelapse({
    required String frameDir,
    required String outPath,
    required int fps,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<String>(
        'encodeTimelapse',
        {'frameDir': frameDir, 'outPath': outPath, 'fps': fps},
      );
      if (result == null || result.isEmpty) {
        return const Err('Timelapse encoder returned an empty path.');
      }
      return Ok(result);
    } on PlatformException catch (e) {
      return Err(
        e.message ?? 'Native timelapse encoding failed (${e.code}).',
        e,
      );
    } catch (e) {
      return Err('Unexpected error during timelapse encoding: $e', e);
    }
  }

  /// Generates a JPEG thumbnail for [videoPath] using native media APIs.
  Future<Uint8List?> getVideoThumbnail(String videoPath) async {
    try {
      return await _methodChannel.invokeMethod<Uint8List>('getVideoThumbnail', {
        'videoPath': videoPath,
      });
    } catch (_) {
      return null;
    }
  }
}
