# LanBridge GitHub Actions build setup

This bundle adds a GitHub Actions workflow that builds a Flutter app for Windows and Android.

## Files
- `.github/workflows/build.yml` — builds a Windows release ZIP and an Android release APK.

## Important
This is a CI workflow bundle, not a complete LanBridge application. The repository must contain a real Flutter project at its root, including `pubspec.yaml`, `lib/`, `windows/`, and `android/`. This workflow does not invent the app's transfer features or generate missing app source.

## Install the workflow
1. Download and extract this ZIP.
2. Copy the `.github` folder into the root of your existing `LanBridge` repository.
3. Commit and push the folder to the `main` or `master` branch.
4. On GitHub, open **Actions → Build LanBridge → Run workflow**.

The workflow also runs automatically on pushes to `main` or `master`.

## If you do not yet have Windows and Android platform folders
On a computer with Flutter installed, open a terminal at the Flutter project's root and run:

```bash
flutter create --platforms=windows,android .
flutter pub get
```

Review the generated changes before committing them. This command expects an existing Flutter project and should not be run over unrelated source files without checking the changes.

## Download the build outputs
When the workflow completes successfully:
1. Open the completed workflow run in GitHub Actions.
2. Scroll to **Artifacts**.
3. Download `LanBridge-Windows` (ZIP containing the Windows executable and runtime files) and/or `LanBridge-Android-APK` (APK).

The APK built by this workflow is an unsigned-for-store/testing release unless release signing is configured. Do not publish it to an app store without setting up secure release signing. The Windows ZIP is a portable build package, not an installer.

## Troubleshooting
- `pubspec.yaml` missing: the Flutter project is not at the repository root.
- `windows/` or `android/` missing: generate the platform folders as described above.
- Build errors after dependencies resolve: review the workflow log; application source, plugin compatibility, and Android Gradle settings may need project-specific changes.
