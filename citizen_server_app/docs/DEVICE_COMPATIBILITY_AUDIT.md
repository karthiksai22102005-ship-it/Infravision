# Device Compatibility Audit

**Status: BLOCKED (no Flutter/Android SDK, no device).**
Declared by patch script: minSdk 24, applicationId com.infravision.citizen. Targets/AGP/Java come from `flutter create` and were not inspected (folder absent).
Proposed support: Android 7.0 (API 24) to current. Test matrix (to fill after build): emulator API 24/29/34; physical: one low-RAM Android 8-10, one Android 13+ (notification permission), one with a single camera. Nothing has been tested.
