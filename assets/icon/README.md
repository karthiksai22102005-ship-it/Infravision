# InfraVision Custom App Icon

Place your custom designed app icon file here:
- **Filename**: `app_icon.png`
- **Format**: PNG (32-bit with transparency or solid background)
- **Recommended Resolution**: 1024 x 1024 px

## How to generate all icons automatically:
Once you save your `app_icon.png` in this folder (`assets/icon/app_icon.png`), open the terminal in the project root and run:

```bash
flutter pub get
dart run flutter_launcher_icons
```

This will automatically generate:
1. Android adaptive launcher icons (all screen densities: mdpi, hdpi, xhdpi, xxhdpi, xxxhdpi).
2. Windows `.ico` desktop icon and taskbar branding.
3. iOS and Web icons.
