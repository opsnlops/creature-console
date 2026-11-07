CREATURE CONSOLE — TOP SHELF

Original white workshop logo over an abstract teal ribbon design with orbital
linework, a soft glow and the Creature Console title. Artwork uses colors
and vector geometry only. All original logo curves are preserved.

Wide: 2320 x 720 (1x), 4640 x 1440 (2x).
Standard: 1920 x 720 (1x), 3840 x 1440 (2x).
PNG files are opaque RGB in sRGB. No pre-rounded corners or simulated UI.
SVG files provide editable artwork and live text; font rendering may vary.

Installed into Creature TV/Assets.xcassets/App Icon & Top Shelf Image.brandassets,
and included in the reusable CreatureConsole.xcassets package beside this folder.
The existing Creature TV app icon build setting selects this brand asset.

Validation: Xcode actool compiled the actual Creature TV asset catalog for
appletvos, minimum deployment 26.0, without warnings. Its generated plist
contains both entries under TVTopShelfImage:
  TVTopShelfPrimaryImageWide = Top Shelf Image Wide
  TVTopShelfPrimaryImage = Top Shelf Image

Do not manually insert these keys into the source Info.plist. Xcode merges
these generated asset-catalog entries when rebuilding the app. A new build
and archive are needed; an existing archive will not contain this artwork.
An App Store upload was not performed.

https://developer.apple.com/design/human-interface-guidelines/top-shelf
