WORKSHOP APP ICONS

Creature Console: Lagoon (teal to deep blue), for server administration.
Flock Communicator: Copper (warm orange to wine), for talking to the birds.
World Viewer: Iris (violet to deep purple), for Creature World administration.

FOR iOS 26 / macOS 26 AND LATER — RECOMMENDED
Each app folder contains AppIcon.icon. Open it in Apple's Icon Composer to
edit the background gradient, logo placement, or material settings. Add it
to that app's Xcode target, then select AppIcon as its app icon. If an existing
asset catalog already contains an AppIcon set, replace that icon resource
or use a distinct name and update the target's App Icon setting accordingly.
Use one icon resource per target, not the .icon and fallback set together.

These are shared iOS/macOS layered icons with a 1024 x 1024 design canvas.
The background is a native, opaque, full-bleed two-color gradient. The
foreground is the original rabbit, gear and wrench in white, with its
original Bezier curves preserved. No extra symbols, photos, lettering,
or imagery have been added to the backgrounds.

The logo occupies approximately 680 x 764 points, with a 130-point vertical
margin. The .icon artwork has no baked-in corner mask, shadow, or highlights;
Apple supplies the enclosure and material effects. Dark mode uses a quieter
version of each app's hue. The system derives clear and tinted appearances.

OTHER INCLUDED FORMATS
- iOS/AppIcon.appiconset: opaque 1024-pixel PNGs for default, dark and tinted
  appearances, with an Xcode Contents.json. Corners are not rounded.
- macOS/AppIcon.appiconset: all ten conventional Mac icon slots (16, 32, 128,
  256 and 512 points, at 1x and 2x), with transparent outer margins.
- macOS/<App Name>.icns: conventional multi-resolution Mac icon.
- macOS/Workshop.iconset: source images for the .icns.
- Masters: editable composite SVGs, opaque 1024-pixel PNG masters, and
  color-only PNG background layers. The SVGs contain vector geometry.
- Apple Previews: actual Apple-rendered iOS and macOS icons in Default,
  Dark, ClearLight, ClearDark, TintedLight and TintedDark, at 1024 pixels.
  These previews include system masking; use the .icon for shipping.
- Source: original SVG found alongside your EPS files, original path data,
  the positioned white SVG/transparent PNG layer, and palette values.
- Preview.png: overview using Apple's iOS Default and Dark rendered icons.

VALIDATION
All three .icon packages compiled successfully with Xcode's asset compiler
for both iphoneos and macosx, targeting version 26.0. All six appearances
rendered successfully for each platform using Apple's Icon Composer renderer
with design generation 26. See Validation.txt. PNG asset sizes, alpha modes,
and Contents.json references were checked separately.

The artwork was visually inspected at large and small sizes. Your logo has
fine details that naturally become less distinct at notification sizes.
The production apps and project settings have not been changed.

REFERENCES
https://developer.apple.com/design/human-interface-guidelines/app-icons
https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
https://developer.apple.com/icon-composer/
