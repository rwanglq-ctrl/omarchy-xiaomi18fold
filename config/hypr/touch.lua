-- Fold: touch-screen gestures via the hyprgrass plugin (built from source, pinned for Hyprland 0.56.2).
-- Plugin: ~/.local/lib/hyprland/plugins/libhyprgrass.so  (source/build: ~/src/hyprgrass, see fold-hyprgrass-build)
-- Disable: touch ~/.config/hypr/hyprgrass-disabled && hyprctl reload   (re-enable: rm the file, reload)
-- Hyprland loads the plugin after parsing, then re-parses the config, so the binds below
-- only register on the second pass (when hl.plugin.hyprgrass exists).

local home = os.getenv("HOME") or ""
local plugin = home .. "/.local/lib/hyprland/plugins/libhyprgrass.so"

local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  return false
end

if exists(home .. "/.config/hypr/hyprgrass-disabled") or not exists(plugin) then
  return
end

hl.plugin.load(plugin)

local hg = hl.plugin.hyprgrass
if not hg then
  return
end

-- fold-ux9: every gesture also asks the phone host (fold-touch-flushd) to lift touch slots whose lift
-- Android swallowed. hyprgrass cancels all touches after a gesture until a touch-down with exactly ONE
-- finger tracked, so one lost lift made the dock / 窗口管理 / every popup dead (fold-ux7 root cause).
-- The request only lifts slots unchanged for >= 1.5 s within 2 s; it never taps (safe with popups open).
local function bind(spec)
  local action = spec.action
  spec.action = function()
    hl.dispatch(action)
    hl.dispatch(hl.dsp.exec_cmd("fold-touch-flush-req gesture"))
  end
  hg.bind(spec)
end

hl.config({
  plugin = {
    hyprgrass = {
      sensitivity = 2.0,
      long_press_delay = 600,
      -- single-finger long-press on window borders would steal ordinary taps; keep it off
      resize_on_border_long_press = false,
      edge_margin = 10,
    },
  },
})

-- fold-ux4: Android (Xiaomi HyperOS) owns 3-finger gestures (3-finger swipe = screenshot, and it can
-- swallow the whole 3-finger touch before the VM sees it), so the *primary* set is now 4 fingers.
-- The 3-finger binds stay as a fallback: they still work whenever Android lets them through.
-- Optional Android-side help: Settings > Additional settings > Gesture shortcuts > Take a screenshot >
-- turn off "Slide 3 fingers down" (not required for the 4-finger set).
--
--   4 fingers  ← / →  next / previous workspace       (recommended; also 3 fingers)
--   4 fingers  ↑      回桌面: close popups; if none open, show the empty desktop (fold-dismiss-overlays)
--   4 fingers  ↓      app drawer toggle                (also 3 fingers ↓)
--   4 fingers  hold   window-management popup          (also 3 fingers hold)
--   3 fingers  ↑      Omarchy menu
-- Direction follows the content, like paging on a phone home screen (same targets as Super+Tab).
local function ws(fingers)
  bind({ pattern = { kind = "swipe", fingers = fingers, direction = "left" }, action = hl.dsp.focus({ workspace = "e+1" }) })
  bind({ pattern = { kind = "swipe", fingers = fingers, direction = "right" }, action = hl.dsp.focus({ workspace = "e-1" }) })
end
ws(4)
ws(3)

bind({ pattern = { kind = "swipe", fingers = 4, direction = "up" }, action = hl.dsp.exec_cmd("fold-dismiss-overlays auto") })

-- App drawer (resident nwg-drawer, toggles).
bind({ pattern = { kind = "swipe", fingers = 4, direction = "down" }, action = hl.dsp.exec_cmd("fold-drawer toggle") })
bind({ pattern = { kind = "swipe", fingers = 3, direction = "down" }, action = hl.dsp.exec_cmd("fold-drawer toggle") })

-- Touch window-management popup (fold-tablet-ref).
bind({ pattern = { kind = "longpress", fingers = 4 }, action = hl.dsp.exec_cmd("fold-window-menu toggle") })
bind({ pattern = { kind = "longpress", fingers = 3 }, action = hl.dsp.exec_cmd("fold-window-menu toggle") })

-- 3-finger swipe up: Omarchy menu (deliberately not "close window").
bind({ pattern = { kind = "swipe", fingers = 3, direction = "up" }, action = hl.dsp.exec_cmd("omarchy-menu toggle") })

-- No edge swipes on purpose (Android owns the screen edges: back / home).
