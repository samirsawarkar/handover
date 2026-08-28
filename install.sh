#!/usr/bin/env bash
# Keybridge -- use your Mac keyboard and trackpad on an Android device.
#   curl -fsSL https://raw.githubusercontent.com/YOUR-NAME/keybridge/main/install.sh | bash
set -u

CONF="$HOME/.keybridge.conf"
HS_DIR="$HOME/.hammerspoon"

# When piped into bash, stdin is the script -- so ask the human via the terminal.
TTY=/dev/tty
[ -r $TTY ] || TTY=/dev/null
ask()  { printf '%s' "$1" >&2; read -r REPLY < $TTY 2>/dev/null || REPLY=""; }
say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
bad()  { printf '\n\033[31m%s\033[0m\n' "$*" >&2; }
die()  { bad "$*"; exit 1; }

printf '\n\033[1m  Keybridge\033[0m\n  Type on your Android tablet with your Mac keyboard.\n'

# ------------------------------------------------------------------ 1. install
command -v brew >/dev/null || die "  First install Homebrew, then run this again:
    https://brew.sh"

command -v scrcpy >/dev/null 2>&1 || { say "Installing (1 of 2)..."; brew install scrcpy >/dev/null || die "  Could not install scrcpy"; }
[ -d /Applications/Hammerspoon.app ] || { say "Installing (2 of 2)..."; brew install --cask hammerspoon >/dev/null || die "  Could not install Hammerspoon"; }

SCRCPY_BIN="$(command -v scrcpy)"
ADB_BIN="$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")"

# ------------------------------------------------------- 2. find the device
# Android USB vendor IDs (Samsung, Google, Motorola, Xiaomi, OnePlus, Oppo,
# Huawei, HTC, LG, ZTE, MediaTek, Qualcomm).
VENDORS='04e8|18d1|22b8|2717|2a70|22d9|12d1|0bb4|1004|19d2|0e8d|05c6'

find_usb() {
  timeout 10 scrcpy --otg 2>&1 \
    | grep -oE '\-\-> +[A-Za-z0-9]+ +\(([0-9a-f]{4}):[0-9a-f]{4}\).*' \
    | grep -iE "\(($VENDORS):|android"
}

say "Plug your tablet into this Mac with a USB cable."
note "Use a cable that can carry data -- charging-only cables will not work."
ask  "
   Press Enter when it is plugged in (or type W for Wi-Fi instead): "

MODE=usb; DEVICE=; TABLET=

if printf '%s' "$REPLY" | grep -qi '^w'; then
  MODE=wifi
else
  FOUND="$(find_usb)"
  if [ -z "$FOUND" ]; then
    bad "  Could not see your tablet."
    note "Try these, then press Enter:"
    note "  * plug straight into the Mac, not into a hub or dock"
    note "  * System Settings > Privacy & Security > Allow accessories to connect"
    note "  * try a different cable (the one from a charger is often power-only)"
    ask  "
   Press Enter to look again (or type W for Wi-Fi): "
    if printf '%s' "$REPLY" | grep -qi '^w'; then MODE=wifi; else FOUND="$(find_usb)"; fi
  fi

  if [ "$MODE" = usb ]; then
    [ -n "$FOUND" ] || die "  Still no tablet found. Wi-Fi setup: run this again and type W."
    if [ "$(printf '%s\n' "$FOUND" | grep -c .)" -gt 1 ]; then
      say "More than one device found:"
      printf '%s\n' "$FOUND" | nl -w3 -s'. '
      ask "
   Which number? "
      DEVICE="$(printf '%s\n' "$FOUND" | sed -n "${REPLY}p" | awk '{print $2}')"
    else
      DEVICE="$(printf '%s\n' "$FOUND" | awk '{print $2}')"
    fi
    note "Found your tablet."
  fi
fi

if [ "$MODE" = wifi ]; then
  say "Wi-Fi setup"
  note "Wi-Fi needs Developer options switched on, and Android turns it back"
  note "off after every restart. A cable is easier if you have one."
  note ""
  note "On the tablet: Settings > Developer options > Wireless debugging = ON"
  note "Then plug the tablet in with a cable, just for this setup step."
  ask  "
   Press Enter when both are done: "
  [ -x "$ADB_BIN" ] || { brew install --cask android-platform-tools >/dev/null 2>&1; ADB_BIN="$(command -v adb)"; }
  [ -x "$ADB_BIN" ] || die "  Could not install the Android tools."
  "$ADB_BIN" tcpip 5555 >/dev/null 2>&1; sleep 2
  IP="$("$ADB_BIN" shell ip route 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' | head -1)"
  [ -n "$IP" ] || die "  Could not reach the tablet. Check that you allowed USB debugging on it."
  TABLET="$IP:5555"
  "$ADB_BIN" connect "$TABLET" >/dev/null 2>&1
  note "Connected over Wi-Fi. You can unplug the cable."
fi

# ---------------------------------------------------------------- 3. settings
cat > "$CONF" <<EOF
# Keybridge settings
MODE=$MODE
DEVICE=$DEVICE
TABLET=$TABLET
SCRCPY=$SCRCPY_BIN
ADB=$ADB_BIN
EOF

# ------------------------------------------------------------ 4. the shortcut
mkdir -p "$HS_DIR"
if [ -f "$HS_DIR/init.lua" ] && ! grep -q Keybridge "$HS_DIR/init.lua"; then
  cp "$HS_DIR/init.lua" "$HS_DIR/init.lua.backup-$(date +%s)"
  note "Your existing Hammerspoon settings were saved alongside."
fi

cat > "$HS_DIR/init.lua" <<'LUA'
-- Keybridge -- Mac keyboard and trackpad on an Android device.
local CONF = os.getenv("HOME") .. "/.keybridge.conf"

local function readConf()
  local c, f = {}, io.open(CONF, "r")
  if not f then return c end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k and not line:match("^%s*#") then c[k] = v end
  end
  f:close()
  return c
end

local conf   = readConf()
local MODE   = conf.MODE or "usb"
local DEVICE = conf.DEVICE
local TABLET = conf.TABLET
local SCRCPY = conf.SCRCPY or "/opt/homebrew/bin/scrcpy"
local ADB    = conf.ADB or (os.getenv("HOME") .. "/Library/Android/sdk/platform-tools/adb")

-- Wi-Fi delivers input through adb, which requires video; the window is
-- borderless and parked off-screen once the trackpad is captured.
-- USB (OTG) has no video at all -- its window is blank and only catches input.
local WIFI_FLAGS = " --keyboard=uhid --mouse=uhid --no-audio --window-borderless"
                .. " --window-width=300 --window-height=600 --window-x=100 --window-y=100"

local OFFSCREEN_X = -6000
local savedPos

local function launchCmd()
  if MODE == "wifi" then
    if not TABLET or TABLET == "" then return nil end
    return ADB .. " connect " .. TABLET .. " && " .. SCRCPY ..
           " -s " .. TABLET .. WIFI_FLAGS .. " >/tmp/keybridge.log 2>&1 &"
  end
  local target = (DEVICE and DEVICE ~= "") and (" -s " .. DEVICE) or ""
  return SCRCPY .. " --otg" .. target .. " >/tmp/keybridge.log 2>&1 &"
end

-- macOS will not focus a window too small to be real, and scrcpy will not
-- capture the trackpad until a real window is clicked. So: click it, then move
-- it off-screen. Capture survives the move and re-engages on focus after that.
local function engageCapture()
  local app = hs.application.get("scrcpy")
  if not app then hs.alert.show("No device -- check the cable") return end
  savedPos = hs.mouse.absolutePosition()
  app:activate()                                  -- focus first, always
  hs.timer.doAfter(0.4, function()
    local win = app:mainWindow()
    local f   = win and win:frame()
    if not f or f.w < 10 then
      hs.alert.show("Connected (keyboard only)")
      return
    end
    hs.eventtap.leftClick({ x = f.x + f.w / 2, y = f.y + f.h / 2 })
    hs.timer.doAfter(0.3, function()
      win:setTopLeft({ x = OFFSCREEN_X, y = 0 })
      hs.alert.show("Typing on Android")
    end)
  end)
end

hs.hotkey.bind({"cmd", "alt"}, "T", function()
  local app = hs.application.get("scrcpy")
  if not app then
    local cmd = launchCmd()
    if not cmd then hs.alert.show("Run the installer again") return end
    hs.execute(cmd)
    hs.alert.show("Connecting...")
    hs.timer.doAfter(MODE == "wifi" and 3.5 or 2.5, engageCapture)
  elseif app:isFrontmost() then
    app:hide()
    if savedPos then hs.mouse.absolutePosition(savedPos) end
    hs.alert.show("Back on Mac")
  else
    app:activate()
    hs.alert.show("Typing on Android")
  end
end)

hs.alert.show("Keybridge ready -- press cmd+alt+T")
LUA

# -------------------------------------------------------------- 5. permission
say "Last step: macOS needs your permission"
note "A settings window is opening. Switch \033[1mHammerspoon\033[0m ON in the list."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null
ask  "
   Press Enter once you have switched it on: "

pkill -f Hammerspoon 2>/dev/null; sleep 2; open -a Hammerspoon

say "All done."
printf '   Press \033[1mcommand + option + T\033[0m to type on your tablet.\n'
printf '   Press it again to come back to your Mac.\n\n'
