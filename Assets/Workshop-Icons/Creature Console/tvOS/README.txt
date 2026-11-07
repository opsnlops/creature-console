CREATURE CONSOLE — tvOS ICON

Matches Creature Console's original white workshop logo and Lagoon gradient:
#168F97 to #123B62. The original logo curves are preserved.

CreatureConsole.xcassets contains a ready-to-import Creature Console brand
asset with two layers: transparent foreground logo over an opaque color-only
background. Includes Home Screen layers at 400 x 240 (1x) and 800 x 480 (2x),
and App Store layers at 1280 x 768. No corners, shadows or focus highlights
are baked in; tvOS applies those effects and parallax.

The logo occupies about 72 percent of the canvas height and is centered with
about 14 percent vertical margin to accommodate focus motion.

Use the layered catalog for shipping. The Preview PNGs are flat composites
for review only. Creature-Console-tvOS.svg is the editable vector master.
Standalone Background and Foreground PNGs are also provided at each size.

To use in Xcode, add this catalog to the tvOS target and select Creature
Console as its app icon, or copy the two imagestacks into your existing
brand asset, retaining any existing Top Shelf images. This package provides
app icons only; it does not include Top Shelf artwork.

Validation: Xcode actool compiled the catalog successfully for appletvos,
minimum deployment 26.0, with no warnings. Layer order, all image references,
PNG dimensions, transparent foregrounds and opaque backgrounds were checked.
Parallax has not been interactively previewed on a TV or Simulator.

References:
https://developer.apple.com/design/human-interface-guidelines/app-icons

Files are stored in the project's Assets folder. The Creature TV target's
existing assets and build settings have not been changed.
