# D&D Player Tracker

Offline Flutter desktop app for tracking D&D 5e characters: stats, HP, spells, weapons, items, notes and a bio. Each character is one JSON file in `Documents\DnDPlayerTracker\characters\`, auto-saved on every change. No network access.

## Run

```
flutter pub get
flutter run -d windows
```

## Test

```
flutter analyze
flutter test
```

## Build & release (Windows)

1. Install [Inno Setup 6](https://jrsoftware.org/isdl.php) (one time).
2. Bump `version:` in `pubspec.yaml`.
3. Run `.\build_release.ps1`.
4. Send `installer_output\DnDTracker_Setup_<version>.exe` to your friend.

Updates install over the old version, and saved characters are never touched. Don't change the `AppId` in `installer.iss`.
