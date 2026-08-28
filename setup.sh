#!/usr/bin/env bash
# Keybridge setup -- installs what is needed and finds your Android device.
set -u

CONF="$HOME/.keybridge.conf"
HS_DIR="$HOME/.hammerspoon"
SRC="$(cd "$(dirname "$0")" && pwd)"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die()  { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

say "Keybridge setup"

# ---------------------------------------------------------------- dependencies
command -v brew >/dev/null || die "Homebrew is required: https://brew.sh"

command -v scrcpy >/dev/null || { note "Installing scrcpy..."; brew install scrcpy; }
[ -d /Applications/Hammerspoon.app ] || { note "Installing Hammerspoon..."; brew install --cask hammerspoon; }

SCRCPY_BIN="$(command -v scrcpy)"
ADB_BIN="$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")"

# ---------------------------------------------------------------- pick a mode
say "How is your Android device connected?"
note "1) USB cable   -- recommended: nothing to enable on the tablet"
note "2) Wi-Fi       -- no cable, but needs Developer Options turned on"
printf '\nChoose 1 or 2: '
read -r choice

MODE=usb; DEVICE=; TABLET=

if [ "$choice" = "2" ]; then
  MODE=wifi
  [ -x "$ADB_BIN" ] || die "adb not found. Install it: brew install --cask android-platform-tools"

  say "Wi-Fi setup"
  note "On the tablet: Settings > Developer options > Wireless debugging = ON"
  note "Then connect the tablet to this Mac once with a USB cable."
  printf '\nPress Enter when the cable is plugged in: '
  read -r _

  "$ADB_BIN" tcpip 5555 >/dev/null 2>&1
  sleep 2
  IP="$("$ADB_BIN" shell ip route 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' | head -1)"
  [ -n "$IP" ] || die "Could not read the tablet's IP. Is USB debugging allowed on the tablet?"
  TABLET="$IP:5555"
  "$ADB_BIN" connect "$TABLET" >/dev/null 2>&1
  note "Found tablet at $TABLET -- you can unplug the cable now."
else
  say "USB setup"
  note "Plug the tablet into this Mac with a data USB cable."
  printf '\nPress Enter when it is plugged in: '
  read -r _

  # scrcpy prints the USB devices it can see; keep the Android-looking ones.
  LIST="$(timeout 10 scrcpy --otg 2>&1 | grep -oE '\-\-> +[A-Za-z0-9]+ +\(([0-9a-f]{4}):[0-9a-f]{4}\).*')"
  ANDROID="$(printf '%s\n' "$LIST" | grep -iE '\((04e8|18d1|22b8|2717|2a70|22d9|12d1|0bb4|1004|19d2|0e8d|05c6|2d95|1ebf):' )"
  [ -n "$ANDROID" ] || ANDROID="$(printf '%s\n' "$LIST" | grep -i android)"

  COUNT="$(printf '%s\n' "$ANDROID" | grep -c . )"
  if [ "$COUNT" -eq 0 ]; then
    die "No Android device on USB.
  - Use a DATA cable (charge-only cables will not work)
  - System Settings > Privacy & Security > Allow accessories to connect
  - Plug straight into the Mac, not through a hub"
  elif [ "$COUNT" -eq 1 ]; then
    DEVICE="$(printf '%s\n' "$ANDROID" | awk '{print $2}')"
  else
    say "Several devices found:"
    printf '%s\n' "$ANDROID" | nl -w2 -s') '
    printf '\nWhich number? '
    read -r n
    DEVICE="$(printf '%s\n' "$ANDROID" | sed -n "${n}p" | awk '{print $2}')"
  fi
  note "Using device $DEVICE"
fi

# ---------------------------------------------------------------- write config
cat > "$CONF" <<EOF
# Keybridge settings -- rewritten by setup.sh
MODE=$MODE
DEVICE=$DEVICE
TABLET=$TABLET
SCRCPY=$SCRCPY_BIN
ADB=$ADB_BIN
EOF
note "Saved settings to $CONF"

# ------------------------------------------------------------- install the lua
mkdir -p "$HS_DIR"
if [ -f "$HS_DIR/init.lua" ] && ! grep -q "Keybridge" "$HS_DIR/init.lua"; then
  cp "$HS_DIR/init.lua" "$HS_DIR/init.lua.backup-$(date +%s)"
  note "Existing Hammerspoon config backed up."
fi
cp "$SRC/bridge.lua" "$HS_DIR/init.lua"
note "Installed shortcut into Hammerspoon."

# ------------------------------------------------------------------ permission
say "One last thing -- macOS permission"
note "Hammerspoon needs Accessibility access to send your keystrokes."
note "Opening the settings pane: switch Hammerspoon ON."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null
printf '\nPress Enter once Hammerspoon is switched on: '
read -r _

pkill -f Hammerspoon 2>/dev/null
sleep 2
open -a Hammerspoon

say "Done."
note "Press  cmd + alt + T  to type on your Android device."
note "Press it again to come back to your Mac."
