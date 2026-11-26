# Architecture & Package Decisions

## State Management & Models
- **Plain `Notifier` / `AsyncNotifier` (`flutter_riverpod` 3.x)** instead of `riverpod_generator`, and **hand-written immutable models with `copyWith` / `toJson` / `fromJson`** instead of `freezed` + `build_runner`. This avoids codegen build times and keeps the codebase straightforward to modify and test while preserving full immutability.

## Packages Verified on pub.dev
All packages from `SPEC.md` §2.2 were verified on pub.dev as active (not discontinued) and supporting both Android and iOS:
- `camera: ^0.12.2`
- `image_picker: ^1.2.4`
- `flutter_riverpod: ^3.5.0`
- `go_router: ^18.1.4`
- `path_provider: ^2.1.6`
- `path: ^1.9.1`
- `shared_preferences: ^2.5.6`
- `image: ^4.13.1`
- `wakelock_plus: ^1.8.2`
- `permission_handler: ^13.0.2`
- `gal: ^3.0.1`
- `share_plus: ^13.3.1`
- `video_player: ^2.14.1`
- `material_ui: ^1.11.1` — the official Material library, which has been decoupled from the Flutter SDK into its own package. All widgets import `package:material_ui/material_ui.dart` instead of `package:flutter/material.dart`.
- Added `crypto: ^3.0.8` (for SHA-1 step cache keys in §6.3) and `uuid: ^4.6.0` (for image/recording IDs in §3.3).

## Video Thumbnails (§2.2)
- `video_thumbnail: ^0.5.6` failed to build under Gradle 9 / Flutter 3.50.1 (`jcenter()` removed). Replaced with native `getVideoThumbnail` on `com.sushant.tracear/native` using `MediaMetadataRetriever` (Android) and `AVAssetImageGenerator` (iOS), as permitted by §2.2.

## iOS Deployment Target (§2.1)
- The spec asks for iOS 14.0, but the project uses **15.0**: `image_picker_ios` and `video_player_avfoundation` (current versions) declare iOS 15.0 as their minimum, so 14.0 cannot build with them.

## Line-Art Edge Detection (§6.1)
- **XDoG** is the default (`D = G(σ) - k * G(1.6σ)`, `k = 0.98`, soft threshold with `tanh`); Sobel is still selectable via `LineArtPipeline.defaultEdgeMethod`.
- **Two changes were needed for real camera photos** (the first version found almost no lines on phone photos, while crisp stock images worked):
  - **σ scales with resolution:** `σ = 1.0 × max(1, longSide / 600)`. Edges in a photo span more pixels at higher resolution; a fixed 1 px blur missed them. The step generator's sigmas scale the same way.
  - **Contrast-normalized response:** D is divided by the 97th percentile of the dark-side response `max(0, -D)` (floor 0.004), and `ε = 0`, `φ = 0.9`. The strength slider (threshold `lerp(0.6, 0.05, strength)`, unchanged) is therefore relative to each photo's own strongest edges and spans "main contours only" to "lots of detail".
- **Speck removal:** `minArea = max(12, 0.00002 × w × h) × scale²`, because lines and texture specks (fur, grain) get wider with σ.
- **Processing size is 1024 px** (§6.2 fallback 1) instead of 1500 px. On a desktop in the test runner, 1500 px took 1.2–2.2 s for line art and 2.8–4.7 s for 5 steps; 1024 px takes 0.8–1.3 s and 1.6–2.5 s. Phones show the overlay at about 1080 px wide, so little is lost. Measure on a real phone in a profile build.
- Tuned by eye on public-domain test photos (portrait, cat, cup, motorbike, rocket) with `tool/lineart_bench_test.dart`. XDoG vs Sobel on a face photo is still on the manual checklist.
- `AppConstants.lineArtAlgorithmVersion` is part of the step-cache hash and the line-art file name (`lineart_v2.png`), so results cached by an older algorithm are regenerated.

## Step Generation (§6.3)
- **Steps are made of the line-art strokes themselves.** Thresholding edges at the coarse sigmas (8 and 5, ×2.5 at full resolution) gave wide blobs, not lines. Instead, each connected stroke of the line art is assigned to the coarsest level whose edge mask covers at least half of it (with a small tolerance). Silhouette strokes survive heavy blur and come first; strokes only found at fine scales are details and come later. Strokes never repeat across steps, and the steps together cover 100% of the line art.
- The level masks only decide the order, so on images over 400k px they are computed at half resolution.
- Splitting a step (when there are too few levels) is only kept if both halves hold at least 3% of all line pixels. A lopsided component split falls back to a top/bottom split by pixel count. If no step can be split, the image gets fewer than `stepCount` steps instead of steps that break the 3% rule.
- The step cache writes a `complete.json` manifest (with the real step count) after all PNGs are written; a cache without it is treated as missing.
- Prepare reuses the steps it generated for the preview strip when the user taps "Start tracing" with unchanged parameters, instead of generating them again.

## Timelapse Frame Capture (§7.2)
- Uses `controller.takePicture()` on a periodic timer with an in-flight capture guard so overlapping captures never occur. Stopping waits for a capture in progress before encoding. Audio/shutter is muted where supported and flash is kept off during timelapse capture.
- Both native encoders apply each JPEG's EXIF orientation (camera JPEGs store unrotated sensor pixels plus an orientation tag), so the video is upright.

## Camera Lifecycle (§4.3)
- The Trace and Prepare controllers are `autoDispose`, so leaving Trace releases the camera.
- On `inactive`, a running video is stopped and saved and a timelapse is paused; both resume normally after `resumed`. `inactive` events caused by our own permission dialogs are ignored. All camera-controller calls are serialized.
