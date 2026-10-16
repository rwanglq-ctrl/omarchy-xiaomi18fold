





hl.config({
  decoration = {
    shadow = { enabled = false },
    blur = { enabled = false },
  },
  animations = {
    enabled = false,
  },
})

o.window({ tag = "default-opacity" }, { opacity = "1 1" })
-- fold-ux4: every window fully opaque (performance on the llvmpipe renderer), including apps
-- that drop Omarchy's default-opacity tag and bring their own translucent rule
-- (Chromium/Firefox: "1.0 0.985" = slightly see-through when inactive). Last rule wins.
o.window(".*", { opacity = "1 1" })

hl.config({
  render = { cm_enabled = false },
  misc = { render_unfocused_fps = 5 },
})

hl.config({
  debug = {
    fifo_pending_workaround = true,
  },
})

hl.config({
  decoration = {
    rounding = 0,
    dim_inactive = false,
  },
})
