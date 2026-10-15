-- Keep Caps as Compose; upstream both_capslock_cancel swallows fcitx5 Shift.
hl.config({ input = { kb_options = "compose:caps", touchpad = { tap_to_click = true } } })
-- AVF translates touchpad scrolling into oversized wheel events.
hl.device({ name = "crosvm-virtio-mouse-0", scroll_factor = 0.01 })
