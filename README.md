# InfraVision — Level 1

A real, on-device Flutter computer-vision foundation. Local camera →
local object detection → local tracking → live overlay → real performance
metrics. No cloud AI, no API keys, no fake data.

This is **Level 1 only**: a reusable CV pipeline using pretrained COCO
classes (person, car, bicycle, etc.) as test objects — not yet infrastructure
defect detection. See "Future Architecture" below for what's intentionally
deferred.

## Build status

Built incrementally across sessions. Progress:

- [x] Day 1 — Project scaffold, config, app shell, CI build pipeline
- [ ] Day 2 — Camera module (camera_service, frame_controller)
- [ ] Day 3 — Vision module (TFLite YOLO model, pre/post-processing)
- [ ] Day 4 — Detection models + object tracking
- [ ] Day 5 — Full UI (overlay, performance panel, settings)
- [ ] Day 6 — Tests, analyze, first verified release APK

## How this gets built (important — read this)

This project is built with no local Flutter/Android toolchain available to
the assistant writing the code. Instead, every push to `main` triggers
`.github/workflows/build.yml`, which:

1. Installs Flutter + a JDK on a free GitHub Actions runner
2. Runs `flutter analyze` and `flutter test`
3. Runs `flutter build apk --release`
4. Uploads `app-release.apk` as a downloadable build artifact

To get the APK: push code → open the **Actions** tab on GitHub → open the
latest run → download the `infravision-release-apk` artifact → install on
your phone.

## Architecture (target, being filled in session by session)

```
Android Camera
  -> Live Camera Preview
  -> Camera Frame Stream
  -> Dynamic Frame Sampling (independent camera FPS vs AI FPS)
  -> Local Model (TFLite, on-device)
  -> Object Detection
  -> Object Tracking (persistent IDs across frames)
  -> Live Bounding Box Overlay
  -> Confidence + FPS + Latency Monitoring
```

```
lib/
  main.dart                     # thin entry point
  app/app.dart                  # MaterialApp shell, theme, routing
  config/app_config.dart        # single source of truth for constants
  camera/                       # Day 2
  vision/                       # Day 3
  tracking/                     # Day 4
  models/                       # Day 4
  performance/                  # Day 4/5
  presentation/screens/         # Day 5
  presentation/widgets/         # Day 5
```

## AI model

- Runtime: **tflite_flutter** (TensorFlow Lite), chosen over ONNX Runtime
  for more mature/stable Flutter plugin support on Android.
- Model: a lightweight YOLO-family detector (YOLOv5n or YOLOv8n exported to
  `.tflite`), pretrained on COCO (80 classes). Added in Day 3.
- Runs **entirely on-device** after install. No network calls, no API keys.

## Replacing the model later (Level 3 readiness)

`VisionService` is the only interface the rest of the app depends on.
`LocalModelRunner` is the concrete TFLite implementation behind it. A
future custom InfraVision defect-detection model can replace
`LocalModelRunner` (different `.tflite` file + label list + input size in
`AppConfig`) without changing camera, tracking, UI, or the overlay.

## Running locally (if you do have Flutter installed)

```
flutter pub get
flutter run
```

## Building the APK locally (if you do have the Android toolchain)

```
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Known limitations (Level 1, intentional)

- No GPS, no maps, no database, no backend, no infrastructure defect
  classes yet — see project spec.
- Model asset not yet bundled (arrives Day 3).
- UI is a placeholder screen until Day 5.

## Future architecture (not implemented yet, on purpose)

- Level 2: GPS + spatial/depth information
- Level 3: Infrastructure defect model (pothole, road_crack, etc.)
- Level 4: Map + database + backend
- Level 5: Maintenance assignment + repair verification
