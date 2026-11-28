import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tracear/features/trace/trace_controller.dart';
import 'package:tracear/features/trace/trace_screen.dart';
import 'package:tracear/features/trace/widgets/overlay_layer.dart';
import 'package:tracear/features/trace/widgets/toolbar.dart';
import 'package:tracear/features/trace/widgets/zoom_control.dart';
import 'package:tracear/models/trace_image.dart';
import 'package:tracear/models/trace_session.dart';
import 'package:tracear/providers/app_providers.dart';
import 'package:tracear/services/camera_service.dart';

class FakeCameraService implements CameraService {
  bool initialized = false;
  bool flash = false;

  @override
  bool get isInitialized => initialized;

  @override
  Size? get previewSize => const Size(1280, 720);

  @override
  bool get isFlashOn => flash;

  @override
  bool get isRecordingVideo => false;

  @override
  Future<void> initialize({bool enableAudio = false}) async {
    initialized = true;
  }

  @override
  Future<void> dispose() async {
    initialized = false;
  }

  @override
  Future<void> setFlashOn(bool on) async {
    flash = on;
  }

  @override
  Future<void> setFocusAndExposurePoint(Offset normalizedPoint) async {}

  double zoom = 1.0;

  @override
  double get minZoom => 1.0;

  @override
  double get maxZoom => 8.0;

  @override
  Future<void> setZoom(double value) async {
    zoom = value.clamp(minZoom, maxZoom);
  }

  @override
  Future<void> lockCaptureOrientation(DeviceOrientation orientation) async {}

  @override
  Future<void> unlockCaptureOrientation() async {}

  @override
  Future<void> startVideoRecording() async {}

  @override
  Future<String> stopVideoRecording() async => '';

  @override
  Future<String> takePicture() async => '';

  @override
  Widget buildPreview() => const ColoredBox(color: Colors.grey);
}

class FakeTraceController extends TraceController {
  FakeTraceController(super.imageId, this._initial);
  final TraceState _initial;

  @override
  Future<TraceState> build() async => _initial;

  @override
  Future<void> saveSessionNow() async {}
}

Future<ui.Image> _createTestImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 64, 64),
    Paint()..color = Colors.black,
  );
  final picture = recorder.endRecording();
  return picture.toImage(64, 64);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Lock blocks gestures and step navigation updates layers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final testImg = (await tester.runAsync(_createTestImage))!;
    final fakeCam = FakeCameraService()..initialized = true;

    final initial = TraceState(
      image: TraceImage(
        id: 'test-img',
        source: ImageSource.userPhoto,
        originalPath: 'orig.png',
        width: 64,
        height: 64,
        lastUsedAt: DateTime(2026),
      ),
      session: const TraceSession(
        imageId: 'test-img',
        mode: DrawMode.stepByStep,
        currentStep: 0,
      ),
      fullImage: testImg,
      stepImages: [testImg, testImg, testImg],
      cameraReady: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          cameraServiceProvider.overrideWithValue(fakeCam),
          traceControllerProvider('test-img')
              .overrideWith(() => FakeTraceController('test-img', initial)),
        ],
        child: const MaterialApp(home: TraceScreen(imageId: 'test-img')),
      ),
    );

    await tester.pump();
    expect(find.text('Step 1 of 3'), findsOneWidget);

    var overlay = tester.widget<OverlayLayer>(find.byType(OverlayLayer));
    expect(overlay.session.currentStep, equals(0));
    expect(
      find.descendant(
        of: find.byType(OverlayLayer),
        matching: find.byType(RawImage),
      ),
      findsNWidgets(1),
    );

    // Tap Next step -> Step 2 of 3 -> 2 RawImages rendered
    await tester.tap(find.byTooltip('Next step'));
    await tester.pump();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(OverlayLayer),
        matching: find.byType(RawImage),
      ),
      findsNWidgets(2),
    );

    // Dragging overlay while unlocked changes dx
    await tester.drag(find.byType(OverlayLayer), const Offset(40, 0));
    await tester.pump();
    overlay = tester.widget<OverlayLayer>(find.byType(OverlayLayer));
    final dxAfterDrag = overlay.session.transform.dx;
    expect(dxAfterDrag, isNot(equals(0.0)));

    // Lock overlay -> IgnorePointer ignores overlay gestures
    await tester.tap(find.byTooltip('Lock overlay'));
    await tester.pump();
    expect(find.text('Locked'), findsOneWidget);

    await tester.drag(
      find.byType(OverlayLayer),
      const Offset(80, 0),
      warnIfMissed: false,
    );
    await tester.pump();
    overlay = tester.widget<OverlayLayer>(find.byType(OverlayLayer));
    expect(overlay.session.transform.dx, equals(dxAfterDrag));

    // A plain tap on the lock explains how to unlock and stays locked.
    final unlock = find.descendant(
      of: find.byType(TraceToolbar),
      matching: find.byIcon(Icons.lock),
    );
    await tester.tap(unlock);
    await tester.pump();
    expect(find.text('Press and hold the lock to unlock'), findsOneWidget);
    expect(find.text('Locked'), findsOneWidget);

    // Long-press unlocks, and gestures move the overlay again.
    await tester.longPress(unlock);
    await tester.pump();
    expect(find.text('Locked'), findsNothing);
    await tester.drag(find.byType(OverlayLayer), const Offset(30, 0));
    await tester.pump();
    overlay = tester.widget<OverlayLayer>(find.byType(OverlayLayer));
    expect(overlay.session.transform.dx, isNot(equals(dxAfterDrag)));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Camera zoom slider zooms, resets, and hides when locked', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final testImg = (await tester.runAsync(_createTestImage))!;
    final fakeCam = FakeCameraService()..initialized = true;

    final initial = TraceState(
      image: TraceImage(
        id: 'zoom-img',
        source: ImageSource.userPhoto,
        originalPath: 'orig.png',
        width: 64,
        height: 64,
        lastUsedAt: DateTime(2026),
      ),
      session: const TraceSession(imageId: 'zoom-img'),
      fullImage: testImg,
      cameraReady: true,
      zoomMin: 1.0,
      zoomMax: 8.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          cameraServiceProvider.overrideWithValue(fakeCam),
          traceControllerProvider('zoom-img')
              .overrideWith(() => FakeTraceController('zoom-img', initial)),
        ],
        child: const MaterialApp(home: TraceScreen(imageId: 'zoom-img')),
      ),
    );
    await tester.pump();

    expect(find.byType(ZoomControl), findsOneWidget);
    expect(find.text('1.0×'), findsOneWidget);

    // Drag the (vertical) slider upward -> zoom in.
    final slider = find.descendant(
      of: find.byType(ZoomControl),
      matching: find.byType(Slider),
    );
    await tester.drag(slider, const Offset(0, -60));
    await tester.pump();

    ZoomControl control() =>
        tester.widget<ZoomControl>(find.byType(ZoomControl));
    expect(control().zoom, greaterThan(1.2));
    expect(fakeCam.zoom, closeTo(control().zoom, 1e-6));

    // Overlay pinch/drag does not change camera zoom and vice versa.
    final overlay = tester.widget<OverlayLayer>(find.byType(OverlayLayer));
    expect(overlay.session.transform.scale, equals(1.0));

    // Tap the label -> back to 1×.
    await tester.tap(find.textContaining('×'));
    await tester.pump();
    expect(control().zoom, equals(1.0));
    expect(fakeCam.zoom, equals(1.0));

    // Locking hides the zoom control.
    await tester.tap(find.byTooltip('Lock overlay'));
    await tester.pump();
    expect(find.byType(ZoomControl), findsNothing);

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('OverlayLayer renders exact step count for currentStep', (
    tester,
  ) async {
    final imgs = (await tester.runAsync(
      () => Future.wait([
        _createTestImage(),
        _createTestImage(),
        _createTestImage(),
      ]),
    ))!;

    await tester.pumpWidget(
      MaterialApp(
        home: OverlayLayer(
          session: const TraceSession(
            imageId: 'x',
            mode: DrawMode.stepByStep,
            currentStep: 1,
          ),
          fullImage: null,
          stepImages: imgs,
          hideImage: false,
          showFullPicture: false,
        ),
      ),
    );

    expect(find.byType(RawImage), findsNWidgets(2));
  });
}
