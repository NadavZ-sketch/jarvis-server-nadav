# Hebrew brand font — Heebo

The app's typography is centralized on **Heebo** (configured in
`lib/theme/jarvis_theme.dart` via `fontFamily` + `fontFamilyFallback`).
Until the font files are bundled here, Heebo resolves through the fallback
chain (Rubik → Assistant → system Hebrew fonts), so the UI still renders
cleanly — it just isn't the exact brand face.

## How to activate Heebo

1. Download the Heebo static TTFs (SIL Open Font License, free) from
   Google Fonts: https://fonts.google.com/specimen/Heebo
2. Place these files in this folder (`jarvis_mobile/assets/fonts/`):
   - `Heebo-Regular.ttf`
   - `Heebo-Medium.ttf`     (weight 500)
   - `Heebo-SemiBold.ttf`   (weight 600)
   - `Heebo-Bold.ttf`       (weight 700)
   - `Heebo-ExtraBold.ttf`  (weight 800)
3. Uncomment the `fonts:` block in `pubspec.yaml` (already scaffolded).
4. Run `flutter pub get` and rebuild.

That's it — every `fontFamily: 'Heebo'` reference (and the theme default)
will then render in true Heebo across the whole app.

## Alternative: google_fonts package

If you prefer runtime fetching instead of bundling, add `google_fonts` to
`pubspec.yaml` and set the theme's `textTheme` via `GoogleFonts.heeboTextTheme(...)`.
Bundling (above) is recommended for offline reliability and no first-paint flash.
