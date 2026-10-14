
local omarchy_gdk_scale = 1
local omarchy_monitor_scale = 1

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
-- Android Terminal exposes its connected virtio_gpu display as Virtual-1.
hl.monitor({ output = "Virtual-1", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
hl.config({ cursor = { no_hardware_cursors = true } })
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })



hl.env("XCURSOR_SIZE", "28")
hl.env("HYPRCURSOR_SIZE", "28")
