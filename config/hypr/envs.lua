-- No user systemd manager; keep host dconf/tmux isolated from the container.
hl.env("GSETTINGS_BACKEND", "keyfile")
hl.env("TMUX_TMPDIR", os.getenv("HOME") .. "/.local/state")
hl.env("TERMINAL", "xdg-terminal-exec")
hl.env("EDITOR", "omarchy-launch-editor --inline")
hl.env("INPUT_METHOD", "fcitx")
hl.env("QT_IM_MODULE", "fcitx")
hl.env("XMODIFIERS", "@im=fcitx")
hl.env("SDL_IM_MODULE", "fcitx")
hl.env("OMARCHY_OCR_LANGS", "chi_sim+eng")

-- fold-ux11: GTK3/XWayland apps need this; Wayland text-input still works for Chromium/GTK4
hl.env("GTK_IM_MODULE", "fcitx")
