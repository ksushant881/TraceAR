# TraceAR — Spec (Flutter, Android + iOS)

An app for tracing pictures onto paper. The camera shows the paper live, and a see-through copy of a chosen image sits on top of it. The user lines the image up with the paper and traces it with a pencil. It works like the paid "AR Drawing" apps, without ads or a paywall. There are two drawing modes: **Full drawing** and **Step-by-step**.

---

## 1. Scope

| Phase | What | Status |
|---|---|---|
| **MVP** | "Tripod mode": the phone is held still (on a stand, a glass or a stack of books) above the paper, and the image overlay is fixed to the screen. Both drawing modes, line art, recording. Android and iOS. | Must ship this week |
| **Phase 2** | "AR anchor mode": the image is pinned to the paper surface using ARCore (Android) or ARKit (iOS), so it stays in place when the phone moves. | Stretch goal; only after the MVP works on real devices |

Development order: build and test on **Android first** (it can be built from any laptop), then build for iOS on a Mac. iOS builds need macOS with Xcode.

---

## 2. Tech stack

### 2.1 Toolchain
- Flutter stable (latest), Dart 3 with null safety
- Android: minSdk 24, targetSdk = latest stable, Kotlin for native code
- iOS: deployment target 14.0, Swift for native code
- Lints: `flutter_lints` (or `very_good_analysis`), and `flutter analyze` must pass with zero warnings

### 2.2 Packages
> **Check every package on pub.dev before adding it.** It must be actively maintained, support both Android and iOS, and work with the current Flutter stable. Use the latest compatible version. If a package is abandoned, pick the best maintained alternative and write the choice down in `DECISIONS.md`.

| Purpose | Package |
|---|---|
| Camera preview, torch, focus, photo and video capture | `camera` |
| Pick images from the gallery (Android Photo Picker / iOS PHPicker; no storage permission needed) | `image_picker` |
| State management | `flutter_riverpod` (with `riverpod_annotation` + `riverpod_generator` if codegen is wanted; plain Notifier is fine) |
| Routing | `go_router` |
| Immutable models + JSON | `freezed` + `json_serializable` (or hand-written `copyWith` if you want to avoid codegen) |
| Files and paths | `path_provider`, `path` |
| Settings | `shared_preferences` |
| Image decode, encode and resize | `image` (pure Dart) |
| Keep the screen awake | `wakelock_plus` |
| Runtime permissions and the "open settings" flow | `permission_handler` |
| Save videos and photos to the phone's gallery | `gal` |
| Share | `share_plus` |
| Play videos in the in-app gallery | `video_player` |
| Video thumbnails | `video_thumbnail` (or generate thumbnails in native code) |
| Fallback if Dart image processing is too slow | `opencv_dart` (only if §6.4 performance targets are missed) |

**Don't use** `ffmpeg_kit_flutter`: the project has been retired. Video speed-up and encoding go through a small native platform channel (§7.3).

### 2.3 Native code (platform channels)
Use Flutter code everywhere it is practical. Native code is needed only for:
1. **Timelapse encoding**: turn a list of JPEG frames into an MP4 (§7.3)
2. **Phase 2 AR view**: a native platform view (§9)

Channel name: `com.sushant.tracear/native`. Use a typed `MethodChannel` wrapper in `lib/platform/native_bridge.dart`. Pigeon is also fine.

---

## 3. Architecture

### 3.1 Layers
```
UI (widgets/screens)  →  Controllers (Riverpod Notifiers)  →  Services  →  Platform / storage
```
- Widgets do no work beyond layout and passing gestures to controllers
- Controllers hold immutable state (`freezed`) and expose methods
- Services do the actual work: camera, image processing, storage, recording, native bridge
- Heavy image processing runs in isolates through `Isolate.run`, never on the UI thread

### 3.2 Folder structure
```
lib/
  main.dart
  app.dart                      # MaterialApp.router, theme (dark by default)
  router.dart                   # go_router routes
  core/
    theme.dart
    constants.dart
    result.dart                 # simple Result/Either type for errors
  models/
    trace_image.dart            # one saved image (user photo or template)
    trace_session.dart          # transform, opacity, mode, step, etc.
    step_set.dart               # generated or bundled steps for an image
    app_settings.dart
  services/
    camera_service.dart
    image_library_service.dart  # import, copy, list, delete images
    lineart/
      lineart_pipeline.dart     # public API, runs in an isolate
      filters.dart              # grayscale, blur, Sobel, DoG, threshold, morphology
      step_generator.dart       # §6.3
      connected_components.dart
    step_cache_service.dart
    recording_service.dart      # video + timelapse
    session_store.dart          # saves TraceSession per image
    settings_service.dart
  platform/
    native_bridge.dart
  features/
    home/        home_screen.dart, home_controller.dart
    prepare/     prepare_screen.dart, prepare_controller.dart
    trace/       trace_screen.dart, trace_controller.dart,
                 widgets/overlay_layer.dart, widgets/step_bar.dart,
                 widgets/toolbar.dart, widgets/grid_painter.dart
    gallery/     gallery_screen.dart, gallery_controller.dart
    settings/    settings_screen.dart
    ar/          (Phase 2) ar_screen.dart
assets/
  templates/
    index.json
    <template_id>/full.png, step_1.png … step_N.png, thumb.png
android/app/src/main/kotlin/.../TimelapseEncoder.kt
ios/Runner/TimelapseEncoder.swift
test/  integration_test/
```

### 3.3 Data models
```dart
enum DrawMode { full, stepByStep }
enum ImageSource { userPhoto, template }

class TraceImage {            // freezed
  String id;                  // uuid
  ImageSource source;
  String originalPath;        // app-private copy (user) or asset path (template)
  String? lineArtPath;        // cached line-art PNG (transparent background)
  int width, height;
  DateTime lastUsedAt;
}

class LineArtParams {         // freezed; used as part of the cache key
  double strength;            // 0..1 → threshold
  int thickness;              // 0..3 → dilation radius
  int stepCount;              // 3..8
  bool includeShading;
}

class StepSet {
  String imageId;
  String paramsHash;          // hash of LineArtParams, or "bundled" for templates
  List<String> stepPaths;     // transparent PNGs, in order
}

class OverlayTransform {      // freezed, JSON
  double dx, dy;              // offset in logical pixels, relative to center
  double scale;               // 0.1..10
  double rotation;            // radians
  bool flipH;
}

class TraceSession {          // freezed, JSON; one per image
  String imageId;
  DrawMode mode;
  bool useLineArt;
  OverlayTransform transform;
  double opacity;             // 0..1
  bool locked;
  bool inverted;
  bool gridOn;
  int currentStep;            // 0-based; used only in step mode
  Color highlightColor;       // stored as an int
}

class AppSettings {
  double defaultOpacity;      // 0.5
  int gridSize;               // 3
  int timelapseIntervalSec;   // 2
  int timelapseFps;           // 24
  bool defaultLineArt;        // true
  int defaultStepCount;       // 5
  bool landscapeAllowed;      // false
}
```

### 3.4 Storage
- `getApplicationDocumentsDirectory()/images/<id>/original.jpg`, `lineart.png`, `steps/<paramsHash>/step_N.png`
- Sessions: `documents/sessions/<imageId>.json`
- Image index: `documents/images/index.json`, written atomically (write to a temp file, then rename)
- Recordings: kept in `documents/recordings/` and also saved to the phone's gallery with `gal` (album "TraceAR")
- Settings: `shared_preferences`
- When the user deletes an image, remove its whole folder and its session

---

## 4. Screens and behavior

### 4.1 Home (`/`)
- "Pick image" uses `image_picker` `pickImage(source: gallery)`, then copies the file into app storage and scales it down to at most 2048 px on the long side
- "Take photo" uses `image_picker` with `source: camera`
- "Recent" grid sorted by `lastUsedAt`. Long-press to delete, with a confirmation dialog.
- "Templates" horizontal list, read from `assets/templates/index.json`:
  ```json
  [{"id":"cat","title":"Cat","steps":5,"difficulty":"easy"}]
  ```
- Ship about 20 original, simple line-art templates (animals, flowers, faces, letters, a house, a car). **Make them yourself as SVG, then export to PNG at 2048 px. Don't use copyrighted characters or artwork.** Each template needs hand-made steps in a real drawing order: guide shapes or outline → main features → details → optional shading.

### 4.2 Prepare (`/prepare/:imageId`)
- Preview of the image, switchable between Original and Line art (shown on a checkerboard background when transparent)
- Sliders: line-art **strength** and **thickness** (debounced 250 ms; re-run the pipeline in an isolate; show a small progress indicator)
- Rotate 90° buttons, and a simple crop (drag a rectangle; build it yourself to avoid adding a dependency)
- **Mode picker**: two large cards, **Full drawing** and **Step-by-step**
  - Step-by-step shows a "Number of steps" slider (3–8) and a "Include shading step" switch
  - Shows a horizontal preview strip of the generated steps (each thumbnail shows the earlier steps faded and the new step highlighted)
  - Templates use their bundled steps, and the slider is hidden
- "Start tracing" saves the session and opens Trace

### 4.3 Trace (`/trace/:imageId`)

**Layer stack (bottom to top):**
1. `CameraPreview`, covering the whole screen. Wrap it in `FittedBox(fit: BoxFit.cover)` inside a `SizedBox` with the preview's real aspect ratio (`controller.value.previewSize`, swapped for portrait), so it isn't stretched.
2. **Overlay layer**: the image or steps (see the rendering rules below)
3. Grid (`CustomPainter`), if on
4. Step bar at the top (step mode only)
5. Toolbar at the bottom, with recording indicator

**Gestures:**
- One `GestureDetector` with `onScaleStart` / `onScaleUpdate` handles pinch zoom, two-finger rotation and drag together. Apply `details.scale`, `details.rotation` and `details.focalPointDelta` relative to the values at gesture start, so moving the image feels natural (zoom and rotate around the fingers).
- Build the transform as `Matrix4` translate → rotateZ → scale → (flip: scale x by -1), and apply it with the `Transform` widget
- When **locked**: wrap the overlay in `IgnorePointer`, hide the gesture hints, and show a small lock badge. Unlock needs a **long-press** on the lock button, so it can't be undone by accident while drawing.
- Double-tap (only when unlocked) resets the transform

**Overlay rendering rules:**
- Full mode: `Opacity(opacity)` → (optional invert via `ColorFiltered` with an invert matrix) → `Image.file(...)`. Use line art or the original depending on the session.
- Step mode (all steps are transparent PNGs, all the same size, stacked in a `Stack`):
  - Steps `< currentStep`: shown with opacity `opacity * 0.35`, in their original color
  - Step `== currentStep`: opacity `opacity`, tinted with the highlight color using `ColorFiltered(ColorFilter.mode(highlight, BlendMode.srcIn))`
  - Steps `> currentStep`: not rendered
  - "Show full picture" (press and hold) renders all steps at `opacity` until released
- Wrap the overlay in a `RepaintBoundary`. Load and decode the images once and keep them in state, so changing steps or the slider never reloads files.

**Toolbar:**
Opacity slider · Lock · Flip · Flashlight (`controller.setFlashMode(FlashMode.torch / off)`) · Grid · Invert · Hide image (press and hold) · Record (tap to choose Video or Timelapse) · Mode switch (Full ⇄ Step) · Reset · Take a photo of the result

**Step bar (step mode):** "Step 2 of 5", Previous and Next buttons, progress dots (tap to jump to a step), a "Show full picture" button. On the last step, Next becomes "Finish", which shows the completion sheet: stop recording if active, take a photo of the result, share, and go back home.

**Screen behavior:**
- Turn `WakelockPlus.enable()` on when entering this screen and off when leaving
- Lock to portrait with `SystemChrome.setPreferredOrientations` and `controller.lockCaptureOrientation()`, unless landscape is allowed in Settings
- Tap the camera area while unlocked to focus and meter there: `setFocusPoint` / `setExposurePoint`, using normalized coordinates
- Save the session (debounced 500 ms) on every change, and in `AppLifecycleState.paused`
- App lifecycle: dispose the camera controller on `inactive` and create it again on `resumed`. This is required on both platforms; without it the camera breaks after switching apps.

### 4.4 Gallery (`/gallery`)
- Grid of recordings and result photos, with thumbnails. Tap to play (`video_player`) or view. Share and delete.

### 4.5 Settings (`/settings`)
- Every field of `AppSettings`, plus the highlight color, an About section and `showLicensePage`

---

## 5. Camera setup details
- `availableCameras()`: choose the back camera
- `CameraController(back, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg on iOS / yuv420 on Android)`
- Turn audio on only if the user switches on "Record audio" in the Record sheet. Request the microphone permission only at that moment.
- If the camera permission is permanently denied, show a screen explaining why the app needs the camera, with an "Open settings" button (`openAppSettings()`)
- iOS `Info.plist`:
  - `NSCameraUsageDescription`: "TraceAR shows your paper through the camera so you can trace."
  - `NSMicrophoneUsageDescription`: "Only used if you record audio with your drawing video."
  - `NSPhotoLibraryUsageDescription`: "Pick a picture to trace."
  - `NSPhotoLibraryAddUsageDescription`: "Save your drawing videos to Photos."
- Android `AndroidManifest.xml`: `CAMERA`, `RECORD_AUDIO`. For saving to the gallery on Android 9 and older, follow the `gal` package's README. Don't add the `INTERNET` permission.

---

## 6. Image processing

All processing runs inside `Isolate.run`. Send the data in as `Uint8List` plus width and height, never as `ui.Image`. Work on a single-channel `Uint8List` or `Float32List` grayscale buffer, not on `image` package `Pixel` objects (they are too slow in loops). Use the `image` package only to decode, resize and encode.

### 6.1 Line-art pipeline (`lineart_pipeline.dart`)
1. Decode and scale down so the long side is at most 1500 px
2. Grayscale: `0.299R + 0.587G + 0.114B`
3. Contrast normalization: stretch the histogram between the 2nd and 98th percentiles
4. Gaussian blur, σ ≈ 1.0. Use **separable** blurs (horizontal pass then vertical pass). For σ > 3, use 3 passes of a box blur as an approximation.
5. **Edges** (two methods; choose with a constant, test both on sample faces and objects, default to the better one):
   - **XDoG / DoG** (default candidate): `D = G(σ) − k·G(1.6σ)` with k ≈ 0.98, then a soft threshold `out = D > ε ? 1 : 1 + tanh(φ·(D − ε))`
   - **Sobel**: magnitude `sqrt(gx² + gy²)` normalized to 0..1
6. Threshold the edge map with `t = lerp(0.6, 0.05, strength)`, giving a binary mask
7. Dilate the mask with radius `thickness` (0–3, square kernel, separable max filter)
8. Remove noise: drop 8-connected components smaller than `minArea = 0.00002 × w × h` (at least 12 px)
9. Output an RGBA PNG: line pixels black (`#000`, alpha 255), every other pixel fully transparent

### 6.2 Performance targets
- Line art on a 1500 px image: **under 1.5 s** on a mid-range Android phone in a **release/profile build** (debug builds are much slower in Dart; don't measure there)
- Step generation (§6.3) with 5 steps: under 3 s
- If these targets are missed: (1) process at 1024 px, (2) replace loops with typed-array sliding windows, (3) as a last resort, use `opencv_dart`
- Add timing logs with `Stopwatch` in debug builds

### 6.3 Automatic step generation (`step_generator.dart`)
Input: grayscale buffer, `LineArtParams`. Output: N transparent PNGs, ordered from coarse to fine.

1. **Multi-scale edges.** Compute edge masks `E_i` for blur levels σ ∈ {8, 5, 3, 2, 1.2, 0.8}. Use the same edge method and threshold as in §6.1. Heavy blur keeps only the main silhouette; light blur adds detail.
2. **New lines at each level.** `S_1 = E_σ=8`. For each later level, `S_i = E_i AND NOT dilate(S_1 ∪ … ∪ S_{i−1}, r=2)`. This keeps each line in only one step.
3. **Clean up** each `S_i`: remove connected components smaller than `minArea`.
4. **Get exactly N steps** (`N = stepCount`, minus 1 if shading is included):
   - Too many levels: merge the levels with the fewest pixels into the next level
   - Too few: split the level with the most pixels into two, by **connected component**. Sort the components by size (biggest first); the bigger half goes into the earlier step. If there is only one big component, split it spatially into top and bottom halves.
   - Each step must have at least 3% of all line pixels; merge any smaller step into its neighbor
5. **Shading step** (optional, always last): blur at σ = 3, quantize to 4 tone levels, take the darkest 2 levels as regions, draw their outlines (the outlines of the region masks) plus 45° hatching inside the darkest level (lines every 8 px, 1 px wide), clipped to that region. Shading pixels use 60% alpha.
6. Dilate every step by `thickness` and encode as an RGBA PNG (black lines, transparent background)
7. **Cache**: `steps/<sha1(imageId + params JSON)>/step_N.png`. Before generating, check if the cache exists. Delete the cache when the image is deleted.

Invariants (test these):
- The union of all steps covers at least 95% of the full line-art mask's pixels (after the same dilation)
- Any two steps overlap by at most 2% of their pixels
- Every step is non-empty

---

## 7. Recording

### 7.1 Video mode
- `controller.startVideoRecording()` / `stopVideoRecording()`. The camera is recorded **without the overlay** (the video shows only the real paper, which is what people want to share).
- When it stops: move the file into `recordings/`, save it to the gallery with `gal`, and generate a thumbnail

### 7.2 Timelapse mode
- Every `timelapseIntervalSec`, call `controller.takePicture()`. Keep a guard so a new capture never starts while the previous one is still running.
- Turn off sound and flash for these photos where the platform allows. On iOS the shutter sound can't always be turned off in some regions; this is acceptable.
- Save the frames to `recordings/tmp_<id>/frame_00001.jpg`. Show a frame counter in the UI.
- When it stops: call the native method `encodeTimelapse(frameDir, outPath, fps)` (§7.3), then save the result to the gallery and delete the temp folder
- If `takePicture` makes the preview stutter on some device, fall back to grabbing frames from `startImageStream`. Convert YUV to JPEG in an isolate, at most every N seconds. Write down which method was used in `DECISIONS.md`.

### 7.3 Native `encodeTimelapse`
- **Android (Kotlin)**: `MediaCodec` (H.264, `COLOR_FormatSurface`) + `MediaMuxer`. Draw each decoded bitmap onto the input `Surface` with a `Canvas` (`lockCanvas` / `unlockCanvasAndPost`), with presentation time = `index × 1_000_000 / fps`. Resolution: the first frame's size, rounded to even numbers, at most 1920 on the long side. Bitrate about 8 Mbps.
- **iOS (Swift)**: `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`, H.264. Convert each `UIImage` to a `CVPixelBuffer`; time = `CMTime(value: index, timescale: fps)`.
- Run on a background thread. Report progress through an `EventChannel` (0..1), and show a progress dialog in the UI.
- Return the output path, or a typed error

---

## 8. Non-functional requirements
- No ads, no analytics, no network calls, no accounts
- Camera preview runs smoothly (no visible stutter). Gestures move the overlay at 60 fps; check this in profile mode with the Flutter performance overlay.
- Survive app switching (§4.3 lifecycle), rotation (where allowed), and the OS killing the app in the background (the session is saved to disk)
- Dark theme by default, Material 3; touch targets at least 48 dp; the toolbar works with one hand
- Size: under 25 MB per platform for the MVP, including templates (compress template PNGs with `pngquant` or `oxipng`)
- Accessibility: semantic labels on every icon button

---

## 9. Phase 2: AR anchor mode
Flutter AR plugins are poorly maintained, so build this as **native platform views**:
- **Android**: `AndroidView` wrapping a Kotlin view built on ARCore + SceneView (or a GLSurfaceView with a textured quad). Check `ArCoreApk.checkAvailability`.
- **iOS**: `UiKitView` wrapping `ARSCNView` (ARKit, horizontal plane detection). Place an `SCNPlane` with the image as its material at the hit-test point.
- One shared channel API: `placeImage(path)`, `setOpacity`, `setScale`, `setRotation`, `setLocked`, `setStep(paths, current, highlightColor)`, `reset`
- Tap to place the image on a detected plane. Gestures go to native code while unlocked.
- Hide the AR option on devices without ARCore or ARKit
- Show a tip in the UI: plain white paper is hard to track, so put a textured object (a book or a pen) next to it

---

## 10. Testing
- **Unit tests** (`test/`):
  - Filters: blur, Sobel and threshold on small hand-made arrays with known results
  - Connected components, and the step generator invariants (§6.3) on 3–4 sample images in `test/fixtures/`
  - Transform math (gesture deltas → matrix), and session JSON round-trip
- **Widget tests**: the Trace screen with a fake camera service. Lock blocks gestures; step navigation shows and hides the right layers.
- **Integration test** (`integration_test/`): pick a template → step mode → Next ×N → Finish
- Abstract the camera behind `CameraService` so tests can use a fake
- Before each milestone: `dart format .`, `flutter analyze`, `flutter test`, and `flutter build apk --release` must all succeed
- Manual checklist in `TESTING.md`: permissions denied and granted, lock, flip, torch, invert, grid, app switch while on Trace, video and timelapse saved to the gallery, line art on a face photo, steps on a face photo and on a template

---

## 11. Milestones (one week)
| Day | Goal |
|---|---|
| 1 | `flutter create`, packages, folder structure, theme, router. Home with image picker. Trace screen with camera, overlay, opacity. Lifecycle handling. |
| 2 | Gestures, lock (long-press unlock), flip, torch, grid, invert, hide image, wakelock, focus tap, session saving |
| 3 | Line-art pipeline in an isolate + Prepare screen + mode picker. Unit tests for filters. |
| 4 | Step generator + cache + step bar and layered rendering on Trace + completion sheet. Invariant tests. |
| 5 | Recording: video, timelapse, native encoders on Android and iOS. Gallery. Templates with hand-made steps. Settings. |
| 6 | Build and test on iOS (Mac + iPhone), fix platform differences, check performance in profile mode, release APK, iOS build |
| 7 | Optional Phase 2 (AR), or buffer time for bugs |

---

## 12. Definition of done (MVP)
On both an Android phone and an iPhone:
1. I can pick a photo, turn it into line art, put the phone on a glass above an A4 sheet, line the image up, lock it, and trace it in **Full drawing** mode while recording a timelapse that ends up in my gallery.
2. On the same photo I can choose **Step-by-step**, and draw it in about 5 steps from the main outline to the details. Earlier steps are faded, the current step is highlighted, and I can switch between the modes without losing my place.
3. Bundled templates work in both modes using their hand-made steps.
4. `flutter analyze` and `flutter test` pass.
