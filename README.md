# Keybridge

Use your MacBook keyboard and trackpad on an Android phone or tablet.

Press **⌘ + ⌥ + T** and your typing goes to the tablet. Press it again and you are
back on your Mac. You look at the tablet's own screen the whole time — nothing is
mirrored on your Mac.

Think of it as Universal Control, but for Android.

## Install

1. Install [Homebrew](https://brew.sh) if you do not have it.
2. Download this folder, open Terminal in it, and run:

```bash
./setup.sh
```

The setup asks how your tablet is connected, finds it, and sets everything up.

## Two ways to connect

**USB cable (recommended).** Nothing to enable on the tablet. Plug it in, tap
"OK" on the prompt that appears on the tablet, done. Keeps working after a
reboot.

**Wi-Fi.** No cable, but the tablet needs *Developer options → Wireless
debugging* switched on, and on most Android versions that switch turns itself
off every time the tablet reboots. Choose this only if a cable is impossible.

|                        | USB cable | Wi-Fi |
|------------------------|-----------|-------|
| Developer options      | not needed | required, always |
| Survives a reboot      | yes       | no, switch it on again |
| Setup                  | plug in   | pairing, IP address |
| Cable                  | required  | none |

## If it does not work

**"No Android device on USB"**
- Use a **data** cable. Cables that came with a charger are often power-only and
  cannot carry data — there is no software fix for that.
- macOS blocks new USB devices until you approve them: System Settings →
  Privacy & Security → **Allow accessories to connect**.
- Plug straight into the Mac. USB hubs and docks stop this from working.

**The shortcut does nothing**
- System Settings → Privacy & Security → **Accessibility** → Hammerspoon must be
  switched on. If it already is, switch it off and on again, then restart
  Hammerspoon.

**Typing works but the trackpad does not**
- Press the shortcut again to reconnect. The trackpad is captured when the
  connection starts; if it did not catch the first time, a reconnect fixes it.

**Wi-Fi mode stopped working after a reboot**
- Turn *Wireless debugging* back on in Developer options. This is Android's
  behaviour, not something this tool can prevent.

## How it works

Android does not let an ordinary app inject keystrokes — that needs a
system-level permission no installable app can hold. There are exactly two ways
in, and Keybridge uses both:

- **USB:** [scrcpy](https://github.com/Genymobile/scrcpy)'s OTG mode speaks the
  AOAv2 protocol, so your Mac registers as a genuine USB keyboard and mouse. The
  tablet just thinks hardware got plugged in. No debugging, no permissions.
- **Wi-Fi:** scrcpy's normal mode over adb, which is why Developer options are
  unavoidable there.

[Hammerspoon](https://www.hammerspoon.org) provides the global shortcut and
handles the window juggling.

### Why there is a window at all

scrcpy captures your trackpad only while one of its windows has focus, and macOS
will not give focus to a window too small to be real. So Keybridge lets a small
window exist for a moment, clicks it to capture the mouse, then moves it far
off-screen. The capture survives the move, so you see nothing afterwards.

This was arrived at the hard way: a 1-pixel window receives neither focus nor
clicks, and no scrcpy flag forces mouse capture.

## Limitations

- Apple Silicon and Intel Macs; macOS 13+.
- USB mode needs a real USB data connection — no hubs, no charge-only cables.
- Wi-Fi mode needs both devices on the same network, with AP isolation off.
- The tablet's IP is stored at setup. If your router hands it a new one, run
  `./setup.sh` again.

## License

MIT — see [LICENSE](LICENSE).
