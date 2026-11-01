# Privacy

Whoa Type observes physical virtual-key codes, press/release phase, repeat flags, modifier state, and mouse/trackpad button number and press/release phase only to produce transient audio commands. It does not translate typed characters, inspect foreground applications, retain CGEvents, store keystrokes, or send data over a network. There is no analytics or microphone capture. Cursor position, pressure, scroll and gesture data are not read.

Held-key/button state and audio commands live in fixed transient memory, are cleared on discontinuities, and are never persisted or included in diagnostics. UserDefaults stores only the settings schema version, desired Sound state, volume, selected pack ID, and keyboard geometry. Permission and audio readiness are queried rather than saved. Launch-at-login status comes from macOS.

Input Monitoring is requested only through the explicit enable action. Accessibility is not requested. Secure Input boundaries are respected.
