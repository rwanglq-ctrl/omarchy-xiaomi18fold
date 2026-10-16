# Changelog

## 0.1.0 — 2026-10-16

First public Xiaomi 18 Fold release. Forked from
[omarchy-xiaomipad9pm](https://github.com/rwanglq-ctrl/omarchy-xiaomipad9pm) **v0.2.11**
(same Android 16 Linux Terminal → Debian host → Arch nspawn Omarchy stack).
Fold product versioning starts at 0.1.0.

### Device adaptations

- **SUPER→ALT mirror** (`config/hypr/fold_modifier.lua`): Android soft keyboards have no
  Super/Caps; almost every Super chord is also bound on Alt.
- **No default OSK**: prefer Android IME; `omarchy-osk-toggle` on demand (Alt+Shift+K).
  Opt-in session autostart via `~/.config/omarchy-osk-autostart`.
- **Chinese IME (fcitx5 + Rime)**: TriggerKeys = **Ctrl+Space**, Ctrl+Shift+Space, Shift
  tap. **Does not** bind Alt/Super+Space (conflicts with Omarchy menu). Soft-keyboard
  Shift is often not a real key event — use Ctrl+Space there.
- **Opaque / lean looknfeel**: animations/blur/shadow off; all windows opacity 1 1
  (llvmpipe performance on AVF).
- **Touch + display (fold/unfold)**
  - Host `fold-touch-sync`: rewrite crosvm touch ABS range to live DRM mode.
  - Host `fold-touch-flushd` + container `fold-touch-flush-req`: lift stale MT slots after
    gestures so hyprgrass cannot leave the UI unclickable.
  - Container `fold-display-guard`: recover FALLBACK-only / missing layers after AVF
    connector hot-plug.
- **Clipboard bridge** (`fold-clip-bridge`): hard-link host `wayland-0` to Hyprland socket
  in arch mode so Android Terminal’s wl-copy/wl-paste work.
- **Dock / drawer / window menu**: `fold-dock`, `fold-drawer`, `fold-window-menu` with
  4-finger gestures (3-finger kept as fallback when Android does not swallow them).
- **Installer**: `omarchy-provision-user --first-install` so bare-metal migrations are not
  left “pending” inside nspawn; tmux session renamed to `omarchy-fold-install`.
- Host install ships fold binaries under `/usr/local/bin` and enables systemd units.

### Not included (on purpose)

- API keys, `~/.pi/agent/auth.json`, personal herdr secrets, private emails.
- Optional App installs (WorkBuddy / Feishu / etc.).
- Forced Chromium GPU flags (black-screen risk on this AVF stack).

### Attribution

Upstream Pad work and omarchy-alarm-nspawn contributors; Fold field fixes from live
Xiaomi 18 Fold bring-up (touch sync, display guard, IME hotkeys, clipboard bridge).
