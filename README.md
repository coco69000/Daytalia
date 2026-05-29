# daytalia

A new Flutter project.

## iOS build

The GitHub Actions workflow in `.github/workflows/ios-build.yml` builds iOS in release mode, packages `build/ios/iphoneos/Runner.app` into `Daytalia-unsigned.ipa`, and uploads that artifact.
Download the artifact from Actions, then import the IPA into Sideloadly on Windows to sign and install it on your iPhone.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
