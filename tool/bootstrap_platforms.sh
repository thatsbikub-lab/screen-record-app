#!/usr/bin/env bash
# Creates reproducible Flutter runner projects. Source code lives in lib/ and packages/.
set -euo pipefail

target="${1:-all}"
case "$target" in
  android) platforms="android" ;;
  ios) platforms="ios" ;;
  all) platforms="android,ios" ;;
  *) echo "Usage: bash tool/bootstrap_platforms.sh [android|ios|all]" >&2; exit 64 ;;
esac

flutter create --project-name capturenest --org com.thatsbikublab --platforms="$platforms" .

if [[ "$platforms" == *"android"* ]]; then
  gradle_file="android/app/build.gradle.kts"
  if [[ -f "$gradle_file" ]]; then
    sed -i.bak 's/minSdk = flutter.minSdkVersion/minSdk = 26/' "$gradle_file"
    rm -f "${gradle_file}.bak"
  else
    gradle_file="android/app/build.gradle"
    sed -i.bak 's/minSdkVersion flutter.minSdkVersion/minSdkVersion 26/' "$gradle_file"
    rm -f "${gradle_file}.bak"
  fi
  sed -i.bak 's/android:label="capturenest"/android:label="CaptureNest"/' android/app/src/main/AndroidManifest.xml
  rm -f android/app/src/main/AndroidManifest.xml.bak
fi

if [[ "$platforms" == *"ios"* ]]; then
  plist="ios/Runner/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 'CaptureNest uses the microphone only when you enable narration.'" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :NSMicrophoneUsageDescription 'CaptureNest uses the microphone only when you enable narration.'" "$plist"
  /usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'CaptureNest uses the front camera only when you enable picture-in-picture.'" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :NSCameraUsageDescription 'CaptureNest uses the front camera only when you enable picture-in-picture.'" "$plist"
  /usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryAddUsageDescription string 'CaptureNest needs permission to save your selected recordings to Photos.'" "$plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Set :NSPhotoLibraryAddUsageDescription 'CaptureNest needs permission to save your selected recordings to Photos.'" "$plist"
  sed -i.bak 's/# platform :ios, .*/platform :ios, '\''15.0'\''/' ios/Podfile
  rm -f ios/Podfile.bak
  sed -E -i.bak 's/IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+/IPHONEOS_DEPLOYMENT_TARGET = 15.0/g' ios/Runner.xcodeproj/project.pbxproj
  rm -f ios/Runner.xcodeproj/project.pbxproj.bak
  # Whole-screen recording on iPhone needs a ReplayKit broadcast upload extension.
  ruby tool/add_broadcast_extension.rb
fi


