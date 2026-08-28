-- Keybridge -- use your Mac keyboard and trackpad on an Android device.
-- Loaded by Hammerspoon. Settings live in ~/.keybridge.conf (written by setup.sh).

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
local MODE   = conf.MODE   or "usb"          -- "usb" (cable) or "wifi"
local DEVICE = conf.DEVICE                   -- usb serial
local TABLET = conf.TABLET                   -- ip:port for wifi
local SCRCPY = conf.SCRCPY or "/opt/homebrew/bin/scrcpy"
local ADB    = conf.ADB    or (os.getenv("HOME") .. "/Library/Android/sdk/platform-tools/adb")

-- Wi-Fi mode mirrors video (that is how scrcpy delivers input over adb), so the
-- window is borderless and gets parked off-screen the moment capture engages.
-- USB/OTG mode has no video at all -- the window is blank and only catches input.
local WIFI_FLAGS = " --keyboard=uhid --mouse=uhid --no-audio --window-borderless"
                .. " --window-width=300 --window-height=600 --window-x=100 --window-y=100"

local OFFSCREEN_X = -6000
local savedPos

local function launchCmd()
  if MODE == "wifi" then
    if not TABLET then return nil end
    return ADB .. " connect " .. TABLET .. " && " .. SCRCPY ..
           " -s " .. TABLET .. WIFI_FLAGS .. " >/tmp/keybridge.log 2>&1 &"
  end
  local target = DEVICE and (" -s " .. DEVICE) or ""
  return SCRCPY .. " --otg" .. target .. " >/tmp/keybridge.log 2>&1 &"
end

-- macOS will not focus a window that is too small, and SDL will not capture the
-- mouse until a real window is clicked. So: click it, then move it off-screen.
-- Capture survives the move, and re-engages on focus alone from then on.
local function engageCapture()
  local app = hs.application.get("scrcpy")
  if not app then
    hs.alert.show("No device found -- check the cable")
    return
  end
  savedPos = hs.mouse.absolutePosition()
  app:activate()                                   -- focus first, always:
                                                   -- keyboard works even if
                                                   -- the click path fails
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
    if not cmd then hs.alert.show("Run setup.sh first") return end
    hs.execute(cmd)
    hs.alert.show("Connecting...")
    hs.timer.doAfter(MODE == "wifi" and 3.5 or 2.5, engageCapture)
  elseif app:isFrontmost() then
    app:hide()
    if savedPos then hs.mouse.absolutePosition(savedPos) end
    hs.alert.show("Back on Mac")
  else
    app:activate()                                 -- SDL re-grabs on focus
    hs.alert.show("Typing on Android")
  end
end)

hs.alert.show("Keybridge ready -- press cmd+alt+T")
