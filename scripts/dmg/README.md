# DMG window

`scripts/build-dmg.sh <version>` calls `scripts/package-dmg.sh` after the app
build and app notarization, before DMG signing and notarization. Packaging uses
only macOS tools: `hdiutil`, `tiffutil`, and Finder via `osascript`. It requires
a logged-in GUI session with permission to automate Finder; layout failures
abort packaging rather than producing an unstyled release.

The window bounds are `{160, 120, 800, 560}` (640 × 440 points). Icons are
96 points, centered at `{160, 207}` and `{480, 207}`, with labels below.
The toolbar, sidebar, path bar, and status bar are hidden.

The backgrounds are `background.png` (640 × 440, 72 dpi) and
`background@2x.png` (1280 × 880, 144 dpi). Packaging combines them into a
multi-resolution TIFF inside the image's hidden `.background` directory.
Keep both PNGs aligned when changing the artwork or icon positions.

To test packaging independently using an existing app:

```sh
scripts/package-dmg.sh 'build/release/DerivedData/Build/Products/Release/Whoa Type.app' 1.2 build/release/WhoaType-1.2-preview.dmg
```

Artwork was generated with the built-in imagegen tool, then resized for both
resolutions. Prompt: a predominantly warm beige, landscape 16:11 installer
background inspired by retro nested contour bands; red/orange/ochre at upper
left, blue at lower left, charcoal at lower right; charcoal Whoa Type title,
drag-to-Applications instruction, and a right-pointing arrow in the center;
leave clear space for real Finder icons at 25% and 75% width; no painted app
or folder icons, window frames, or mockups.

Follow-up imagegen edit prompt: change only the bottom-center text from
"Whoa Type" to "Whoa Studio", preserving the font, size, color, centering,
top instruction, arrow, beige background, and contour shapes.
