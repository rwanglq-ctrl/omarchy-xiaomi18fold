
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
-- Crosvm connector numbering changes: configure whichever output is connected.
hl.config({ cursor = { no_hardware_cursors = true } })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })



hl.env("XCURSOR_SIZE", "28")
hl.env("HYPRCURSOR_SIZE", "28")
