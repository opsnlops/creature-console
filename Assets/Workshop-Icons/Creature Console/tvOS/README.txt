CREATURE CONSOLE — tvOS ICON

Matches Creature Console's original white workshop logo and Lagoon gradient:
#168F97 to #123B62. The original logo curves are preserved.

CreatureConsole.xcassets contains a ready-to-import Creature Console brand
asset with three layers: rabbit and wrench in front, gear in the middle,
and an opaque color-only background behind them. Includes Home Screen layers at 400 x 240 (1x) and 800 x 480 (2x),
and App Store layers at 1280 x 768. No corners, shadows or focus highlights
are baked in; tvOS applies those effects and parallax.

The logo occupies about 72 percent of the canvas height and is centered with
about 14 percent vertical margin to accommodate focus motion.

Use the layered catalog for shipping. The Preview PNGs are flat composites
for review only. Creature-Console-tvOS.svg is the editable vector master.
Standalone Background and Foreground PNGs are also provided at each size.

To use in Xcode, add this catalog to the tvOS target and select Creature
Console as its app icon, or copy the two imagestacks into your existing
brand asset, retaining the included Top Shelf image sets. The Top Shelf subfolder
contains standard and wide artwork at 1x and 2x plus editable SVGs.

Validation: Xcode actool compiled the catalog successfully for appletvos,
minimum deployment 26.0, with no warnings. Layer order, all image references,
PNG dimensions, transparent foregrounds and opaque backgrounds were checked.
Parallax has not been interactively previewed on a TV or Simulator.

References:
https://developer.apple.com/design/human-interface-guidelines/app-icons

Files are stored in the project's Assets folder. Matching Top Shelf
artwork is also installed in the Creature TV target's live asset catalog.
Its existing app icon build setting is unchanged.

GEAR / RABBIT LAYER SEPARATION
Front.imagestacklayer: Rabbit PNG (rabbit, flower and wrench).
Middle.imagestacklayer: Gear PNG (visible gear artwork).
Back.imagestacklayer: opaque Lagoon gradient.
All layers share the same rectangular canvas and original placement.

The supplied vector has a combined outline. The split preserves its visible
curves and uses a small overlap at shared white edges to prevent seams.
Hidden gear geometry has not been invented or reconstructed. The original
combined Foreground PNGs remain here as references; production stacks use
the separate Rabbit and Gear PNGs. Separate editable SVGs are also included.

Updated both the live Creature TV catalog and the reusable catalog in this
folder. Both Home Screen resolutions and the App Store icon use the split.
Xcode actool compiled the live catalog for tvOS 26 without warnings and
still generated TVTopShelfImage.TVTopShelfPrimaryImageWide.

A 1280 x 768 composite comparison against the original gave a mean RGB
channel difference of 0.00494 / 255, limited to edge antialiasing; 57 pixels
had a difference greater than 10 / 255. The split layers and composite
were visually inspected. Interactive focus/parallax was not tested on a TV.
