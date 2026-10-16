-- fcitx5-autostart is launched by the patched default autostart.
o.launch_on_start("portal-autostart")
o.launch_on_start("lock-ime-reset-autostart")
-- Remote access, VNC and upgrade-all are intentionally not autostarted.

-- Wayland on-screen keyboard (wvkbd): OFF by default on the fold, the Android keyboard is used.
-- Start manually: Alt+Shift+K (Super+Shift+K), launcher "虚拟键盘", or `omarchy-osk-toggle start`.
-- To start it with every session again: touch ~/.config/omarchy-osk-autostart
local osk_flag = io.open((os.getenv("HOME") or "") .. "/.config/omarchy-osk-autostart", "r")
if osk_flag then
  osk_flag:close()
  o.launch_on_start("omarchy-osk-toggle start")
end

-- Fold/AVF: repair display-hotplug fallout (FALLBACK-only output, OSK only if opted in,
-- missing shell layers, DPMS with stay-awake). Log: ~/.local/state/omarchy-alarm/fold-display-guard.log
o.launch_on_start("fold-display-guard")

-- Fold: persistent bottom dock (nwg-dock-hyprland, 52 px icons, launcher button -> fold-drawer),
-- respawned by the wrapper if it exits. Off: touch ~/.config/fold-dock-disabled; pkill -f bin/fold-dock; pkill -f nwg-dock-hyprland
o.launch_on_start("fold-dock")

-- fold-ux4: keep the app drawer resident (opens in ~0.1 s instead of ~0.9 s). The guard restarts it
-- if it dies. Off: touch ~/.config/fold-drawer-no-resident; fold-drawer restart
-- fold-ux5: resident drawer DISABLED (was auto-covering / trapping touch).
-- Open on demand: dock grid / fold-drawer toggle. Re-enable only after spawn-stays-hidden verified.
-- o.launch_on_start("fold-drawer daemon")
