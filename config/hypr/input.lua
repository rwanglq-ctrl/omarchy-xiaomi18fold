-- Caps Lock is Super; Right Alt is Compose. Leave Shift available to fcitx5.
hl.config({ input = { kb_options = "caps:super,compose:ralt", touchpad = { tap_to_click = true } } })
-- AVF translates touchpad scrolling into oversized wheel events.
hl.device({ name = "crosvm-virtio-mouse-0", scroll_factor = 0.01 })
