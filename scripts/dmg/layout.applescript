-- Coordinates are in points, matching the 640 x 440 background at both scales.
on run argv
  set volumeFolder to POSIX file (item 1 of argv) as alias
  tell application "Finder"
    set volumeFolder to folder (volumeFolder as text)
    open volumeFolder
    tell container window of volumeFolder
      set current view to icon view
      set toolbar visible to false
      set statusbar visible to false
      set pathbar visible to false
      set sidebar width to 0
      set bounds to {160, 120, 800, 560}
      set viewOptions to icon view options of container window of volumeFolder
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 96
      set text size of viewOptions to 13
      set label position of viewOptions to bottom
      set shows item info of viewOptions to false
      set shows icon preview of viewOptions to true
      set background picture of viewOptions to file ".background:background.tiff" of volumeFolder
    end tell
    set position of item "Whoa Type.app" of volumeFolder to {160, 207}
    set position of item "Applications" of volumeFolder to {480, 207}
    update volumeFolder without registering applications
    delay 2
    close container window of volumeFolder
    -- Reopening and closing flushes the layout before the volume is detached.
    open volumeFolder
    delay 2
    close container window of volumeFolder
  end tell
end run
