#!/usr/bin/env bash
# Handover -- your Mac keyboard, on your Android.
#   curl -fsSL https://raw.githubusercontent.com/samirsawarkar/handover/main/install.sh | bash
set -u

CONF="$HOME/.handover.conf"
HS_DIR="$HOME/.hammerspoon"

# When piped into bash, stdin is the script -- so ask the human via the terminal.
TTY=/dev/tty
[ -r "$TTY" ] || TTY=/dev/null
ask()  { printf '%s' "$1" >&2; read -r REPLY < "$TTY" 2>/dev/null || REPLY=""; }
say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }
bad()  { printf '\n\033[31m%s\033[0m\n' "$*" >&2; }
die()  { bad "$*"; exit 1; }

printf '\n\033[1m  Handover\033[0m\n  Your Mac keyboard, on your Android.\n'

# ------------------------------------------------------------------ 1. install
command -v brew >/dev/null || die "  First install Homebrew, then run this again:
    https://brew.sh"

command -v scrcpy >/dev/null 2>&1 || { say "Installing (1 of 2)..."; brew install scrcpy || die "  Could not install scrcpy"; }
# Cask installs can ask for a password -- never hide their output.
[ -d /Applications/Hammerspoon.app ] || { say "Installing (2 of 2)..."; brew install --cask hammerspoon || die "  Could not install Hammerspoon"; }

SCRCPY_BIN="$(command -v scrcpy)"
ADB_BIN="$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")"

# ------------------------------------------------------- 2. find the device
# Android USB vendor IDs, as decimals -- ioreg reports them that way.
# Samsung 04e8, Google 18d1, Motorola 22b8, Xiaomi 2717, OnePlus 2a70,
# Oppo 22d9, Huawei 12d1, HTC 0bb4, LG 1004, ZTE 19d2, MediaTek 0e8d,
# Qualcomm 05c6, Sony 0fce, Asus 0b05, Lenovo 17ef, Nokia 2e04.
VENDORS="1256 6353 8888 10007 10864 8921 4817 3000 4100 6610 3725 1478 4046 2821 6127 11780"

# Enumerate USB devices with ioreg: instant, read-only, and it never touches
# the device. (Do not use `scrcpy --otg` to scan -- with a single device it
# starts a session instead of listing, seizing the keyboard mid-install.)
find_usb() {
  ioreg -p IOUSB -w0 -l 2>/dev/null | awk -v vendors="$VENDORS" '
    BEGIN { n = split(vendors, v, " "); for (i = 1; i <= n; i++) want[v[i]] = 1 }
    function val(line) { sub(/.*= /, "", line); gsub(/"/, "", line); return line }
    /"USB Product Name"/ { product = val($0) }
    /"idVendor"/         { vend    = val($0); gsub(/[^0-9]/, "", vend) }
    /"USB Serial Number"/ {
      serial = val($0)
      if (vend in want && serial != "")
        print serial "\t" (product == "" ? "Android device" : product)
      product = ""; vend = ""
    }'
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
    [ -n "$FOUND" ] || die "  Still no tablet found. For Wi-Fi setup, run this again and type W."
    COUNT="$(printf '%s\n' "$FOUND" | grep -c .)"
    if [ "$COUNT" -gt 1 ]; then
      say "More than one device found:"
      printf '%s\n' "$FOUND" | awk -F'\t' '{printf "   %d. %s\n", NR, $2}'
      PICK=
      while [ -z "$PICK" ]; do
        ask "
   Which number? "
        # reject anything that is not a number in range
        case "$REPLY" in
          ''|*[!0-9]*) bad "  Please type one of the numbers above." ;;
          *) [ "$REPLY" -ge 1 ] && [ "$REPLY" -le "$COUNT" ] && PICK="$REPLY" \
               || bad "  Please type a number between 1 and $COUNT." ;;
        esac
      done
      DEVICE="$(printf '%s\n' "$FOUND" | sed -n "${PICK}p" | cut -f1)"
    else
      DEVICE="$(printf '%s\n' "$FOUND" | cut -f1)"
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
  [ -x "$ADB_BIN" ] || { brew install --cask android-platform-tools; ADB_BIN="$(command -v adb)"; }
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
# Handover settings
MODE=$MODE
DEVICE=$DEVICE
TABLET=$TABLET
SCRCPY=$SCRCPY_BIN
ADB=$ADB_BIN
EOF

# ------------------------------------------------------------ 4. the shortcut
mkdir -p "$HS_DIR"
if [ -f "$HS_DIR/init.lua" ] && ! grep -q Handover "$HS_DIR/init.lua"; then
  BACKUP="$HS_DIR/init.lua.backup-$(date +%s)"
  cp "$HS_DIR/init.lua" "$BACKUP"
  bad "  You already had a Hammerspoon setup. It has been saved to:"
  note "$BACKUP"
  note "Handover replaces it. To keep both, copy your old lines back in afterwards."
fi

cat > "$HS_DIR/init.lua" <<'LUA'
-- Handover -- your Mac keyboard and trackpad, on an Android device.
local CONF = os.getenv("HOME") .. "/.handover.conf"

local function readConf()
  local c, f = {}, io.open(CONF, "r")
  if not f then return c end
  for line in f:lines() do
    local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if k then c[k] = v end
  end
  f:close()
  return c
end

local conf   = readConf()
local MODE   = conf.MODE or "usb"
local DEVICE = conf.DEVICE
local TABLET = conf.TABLET
-- Homebrew lives in a different place on Intel Macs than on Apple Silicon.
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
           " -s " .. TABLET .. WIFI_FLAGS .. " >/tmp/handover.log 2>&1 &"
  end
  local target = (DEVICE and DEVICE ~= "") and (" -s " .. DEVICE) or ""
  return SCRCPY .. " --otg" .. target .. " >/tmp/handover.log 2>&1 &"
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

hs.alert.show("Handover ready -- press cmd+alt+T")
LUA

# -------------------------------------------------------------- 5. permission
say "Last step: macOS needs your permission"
note "A settings window is opening. Switch Hammerspoon ON in the list."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" 2>/dev/null
ask  "
   Press Enter once you have switched it on: "

pkill -x Hammerspoon 2>/dev/null; sleep 2; open -a Hammerspoon

say "All done."
printf '   Press \033[1mcommand + option + T\033[0m to type on your tablet.\n'
printf '   Press it again to come back to your Mac.\n\n'
