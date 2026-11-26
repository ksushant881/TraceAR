# TraceAR Manual Testing Checklist

Run these checks on real Android and iOS devices before shipping:

## Permissions
- [ ] Camera permission denied permanently -> explanation screen appears with "Open settings" button (`openAppSettings()`).
- [ ] Camera permission granted -> live camera preview appears without stretching.
- [ ] Microphone permission is NOT requested until "Record audio" is enabled in the Record sheet.

## Trace Screen Controls
- [ ] Pinch zoom, two-finger rotation, and drag move the overlay smoothly at 60 fps; zoom/rotation pivot around the fingers.
- [ ] Camera zoom: the slider on the right zooms the camera smoothly (1× up to the phone's max, capped at 8×); tapping the "1.0×" label resets it. Pinching still resizes only the overlay.
- [ ] Camera zoom is hidden while locked, survives leaving/returning to the app and starting a video with audio, and is restored when reopening the same image.
- [ ] Photos, videos and timelapses are captured at the zoom shown on screen.
- [ ] Gesture hints appear on entering Trace and after unlocking, and are hidden while locked.
- [ ] Leaving Trace (back button and system back) turns the camera off (privacy indicator disappears).
- [ ] Double-tap resets transform when unlocked.
- [ ] Tap on camera area focuses and meters when unlocked.
- [ ] Lock button locks overlay gestures and shows "Locked" badge; tapping does not unlock, long-press unlocks.
- [ ] Flip horizontally mirrors the overlay.
- [ ] Flashlight toggles the rear torch on/off.
- [ ] Invert colors inverts the overlay image.
- [ ] Grid toggles the grid overlay using the configured grid size.
- [ ] Hold "Hide image" hides the overlay until released.
- [ ] App switch (background -> foreground) while on Trace cleanly disposes and re-initializes the camera.
- [ ] App switch while recording a video: the clip is saved to the gallery; recording indicator clears.
- [ ] App switch while recording a timelapse: capture pauses and resumes; final video is complete.
- [ ] First video with "Record audio" on: mic permission dialog appears, recording starts, preview keeps working.

## Line Art & Step-by-Step
- [ ] Compare XDoG vs Sobel (`LineArtPipeline.defaultEdgeMethod`) on a face photo and an object photo; record the winner in `DECISIONS.md`.
- [ ] Line art on a face photo completes in < 1.5 s (release/profile build) and produces clean outlines.
- [ ] Step generation on a face photo (5 steps) completes in < 3 s, progressing from coarse silhouette to fine details.
- [ ] Step mode on a bundled template uses its hand-made steps; earlier steps are faded (35% opacity), current step is highlighted, future steps are hidden.
- [ ] Holding "Show full picture" reveals all steps at full opacity until released.

## Recording & Gallery
- [ ] Video recording saves to `recordings/` and appears in the device gallery ("TraceAR" album) without the overlay.
- [ ] Timelapse video is upright (not sideways/stretched) on both Android and iPhone, held in portrait.
- [ ] Timelapse recording captures frames at the configured interval, shows frame count, encodes via native `encodeTimelapse` with progress dialog, and saves MP4 to gallery.
- [ ] In-app Gallery plays videos, views result photos, shares, and deletes.
