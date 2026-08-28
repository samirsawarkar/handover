# Contributing to Handover

Thanks for helping. Handover is small on purpose — one shell installer and one
Lua file — so it is easy to read end to end before changing anything.

## The project in one minute

- `install.sh` — everything. Installs dependencies, finds the device, writes
  `~/.handover.conf`, and embeds the Hammerspoon config as a heredoc. It is
  designed to be piped into `bash`, so **prompts must read from `/dev/tty`**.
- The Lua inside it becomes `~/.hammerspoon/init.lua` and owns the shortcut.

There is no build step. Edit, run `bash -n install.sh`, run the installer.

## Good first contributions

- **Uninstall script.** Remove the config, restore any backed-up Hammerspoon
  setup, and say what was left behind.
- **Configurable shortcut.** ⌘⌥T is hardcoded; it should come from the config.
- **Test on non-Samsung devices.** Development happened on a Galaxy Tab S6 Lite
  and a Realme phone. Vendor IDs for other brands are in `VENDORS` in
  `install.sh` — if your device is not detected, its ID is probably missing.
- **Intel Mac testing.** Homebrew paths differ (`/usr/local` vs `/opt/homebrew`).
- **Better Wi-Fi reconnection.** The IP is stored once; devices move.

## Things to know before you change the window logic

Several obvious-looking simplifications do not work, and were tried:

- A 1-pixel window is invisible but useless — macOS will not give focus to a
  window that small, and it cannot receive the click that starts mouse capture.
- `--always-on-top` prevents the window from accepting that click.
- Synthetic `LAlt` (scrcpy's documented capture toggle) does not reliably engage
  capture from Hammerspoon.
- scrcpy locks the window to the device's aspect ratio unless you pass
  `--no-window-aspect-ratio-lock`, so small windows silently become large ones.
- There is no scrcpy flag that forces mouse capture.

The current design — real window, click its true frame, move it off-screen —
is the result. Please do not replace it without testing capture on hardware.

## Do not use `scrcpy --otg` to detect devices

It starts a session rather than listing when only one device is attached, which
seizes the user's keyboard mid-install. Device detection uses `ioreg`. Related:
macOS does not ship `timeout`, so scripts must not depend on it.

## Pull requests

1. Keep it small and explain the user-visible effect.
2. Test the real path: run the installer on a clean-ish machine if you can.
3. Say which Mac (Apple Silicon or Intel), macOS version, and Android device you
   tested on. Hardware detail matters more than usual here.
4. `bash -n install.sh` must pass. CI runs ShellCheck.

## Reporting bugs

Include your macOS version, Mac type, Android device and version, whether you
used USB or Wi-Fi, and the output of:

```bash
ioreg -p IOUSB -w0 -l | grep -E '"USB Product Name"|"idVendor"|"USB Serial Number"'
```

That last one is usually enough to diagnose detection problems.
