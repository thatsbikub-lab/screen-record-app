# CaptureNest

CaptureNest is a private, no-ad screen recorder for Android and iOS. It is designed around a simple principle: recordings remain on the device unless the person using the app explicitly shares or exports one.

## Product choices

- **Name:** CaptureNest
- **Android application ID / iOS bundle ID:** `com.thatsbikublab.capturenest`
- **Targets:** Android 8.0 (API 26)+ and iOS 15+
- **Business model:** free, no accounts, no ads, no watermark, no telemetry
- **Storage:** local by default. The post-recording share sheet provides opt-in export to Drive, iCloud Drive, Dropbox, and any installed provider; no cloud credentials are held by the app.

## Included MVP

- Screen capture with Android's MediaProjection and Apple's ReplayKit APIs.
- Optional microphone capture, a device-audio preference, front-camera preference, countdown, pause/resume controls, and selectable quality.
- A local recording library with playback, rename, delete, share/export, save-to-gallery, and non-destructive trim/export.
- A compact dark UI built for one-handed use.

## Platform notes

The operating systems control capture permission and may prohibit protected/DRM video from appearing in recordings. Android's device-audio capture is available only on Android 10+ when the recorded app permits playback capture. On iOS, the record button opens the system "Start Broadcast" sheet for the bundled `CaptureNestBroadcast` upload extension (sources in `ios_broadcast/`, added to the generated runner by `tool/add_broadcast_extension.rb`). It records the whole screen, including other apps, and saves the finished video to Photos. The front-camera preference is passed to ReplayKit on iOS and is presented as a recording option on Android; production camera compositing across third-party apps requires a separate compositor service and is intentionally kept behind the platform capability boundary.

## Local development

Install Flutter stable, then create the native runner projects once:

```bash
bash tool/bootstrap_platforms.sh all
flutter pub get
flutter run
```

The repository deliberately versions the Flutter UI and native recorder plugin. The generated `android/` and `ios/` runners are reproducible and ignored, so developers do not commit machine-generated Xcode/Gradle noise. CI runs the same bootstrap step before building.

## Builds

GitHub Actions publishes these artifacts:

- `capturenest-android-apk`: installable release APK (unsigned).
- `capturenest-android-aab`: Play Console upload bundle (unsigned).
- `capturenest-ios-unsigned-ipa`: an unsigned IPA. Use Sideloadly to sign it with your Apple ID before installing it on a test device.

No Apple signing certificates or secrets are stored in this repository.
