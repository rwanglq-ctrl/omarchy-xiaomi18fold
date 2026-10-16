-- ARM replacements for unavailable Omarchy packages.
hl.unbind("SUPER + CTRL + Q")
hl.unbind("XF86Calculator")
o.bind("SUPER + CTRL + Q", "Calculator", "qalculate-gtk")
o.bind("XF86Calculator", "Calculator", "qalculate-gtk")
hl.unbind("SUPER + CTRL + RETURN")
o.bind("SUPER + CTRL + RETURN", "Herdr", "xdg-terminal-exec herdr")

-- On-screen keyboard (wvkbd) is off by default on the fold; the Android keyboard is used.
-- SUPER + K stays Omarchy's keybindings menu (it used to fire both).
-- Mirrored to ALT + SHIFT + K / ALT + CTRL + SHIFT + K by hypr/fold_modifier.lua.
o.bind("SUPER + SHIFT + K", "Toggle on-screen keyboard", "omarchy-osk-toggle toggle")
o.bind("SUPER + CTRL + SHIFT + K", "Stop on-screen keyboard", "omarchy-osk-toggle stop")

-- Fold: SUPER + ALT chords are not mirrored automatically; pick the useful ones.
fold.bind("ALT + D", "Apps menu", "omarchy-menu toggle apps")

-- Touch window-management popup (close / float / fullscreen / move to workspace).
-- Mirrored to ALT + SHIFT + U; also 3-finger long-press (touch.lua) and the dock.
o.bind("SUPER + SHIFT + U", "Window manage popup", "fold-window-menu toggle")

-- fold-ime-fix: no IME binds here. SUPER/ALT + SPACE stay Omarchy's menu and
-- SUPER/ALT + CTRL + SPACE the background switcher. Toggle Chinese/English with
-- Ctrl+Space (or Ctrl+Shift+Space, or a lone Shift tap), handled by fcitx5 itself:
-- see ~/.config/fcitx5/config [Hotkey/TriggerKeys].
