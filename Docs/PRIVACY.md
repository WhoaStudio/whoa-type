# Privacy

Whoa Type observes physical virtual-key codes, press/release phase, repeat flags, modifier state, and mouse/trackpad button number and press/release phase only to produce transient audio commands. It does not translate typed characters, inspect foreground applications, retain CGEvents, store keystrokes, or send data over a network. There is no analytics or microphone capture. Cursor position, pressure, scroll and gesture data are not read.

Held-key/button state and audio commands live in fixed transient memory, are cleared on discontinuities, and are never persisted or included in diagnostics. UserDefaults stores only these settings: schema version, onboarding completion, desired Sound state, volume, effects volume, mouse-sound and Return-ding toggles, selected pack ID, keyboard geometry, and the global shortcut choice (`hotkey.enabled`, `hotkey.modifiers`, `hotkey.key`). Permission and audio readiness are queried rather than saved. Launch-at-login status comes from macOS.

The optional global shortcut is registered with Carbon `RegisterEventHotKey`, which delivers only that one combination and does not monitor other keystrokes. Input Monitoring is requested only through the explicit enable action. Accessibility is not requested. Secure Input boundaries are respected.
