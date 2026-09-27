# Branding sources

Source images for the launcher icon and native splash. Not bundled into the app
(in-app logo lives in `assets/brand/`).

| File | Use |
| --- | --- |
| `app_icon.png` | iOS + legacy Android icon (opaque; OS applies the mask). The mark is scaled to 80% on the `#09121E` tile for breathing room in the launcher. |
| `app_icon_foreground.png` | Android adaptive icon foreground, on `#09121E` (mark at 80%, as above; the generator insets it a further 16%) |
| `splash_logo.png` | Native splash mark on `#060A10` |
| `splash_android12.png` | Android 12+ splash icon, on `#09121E` (icon at 80% so the ball fits the circular mask) |

All are cut from `D:\SkorX\favicon.png` (tile colour `#09121E`). After changing them:

```
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
