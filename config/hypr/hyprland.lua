
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")


-- Fold: mirror SUPER bindings onto Alt (Android keyboard has no Super/Caps). Must load first.
require("hypr.fold_modifier")

require("default.hypr.omarchy")

require("hypr.envs")
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
-- Fold: touch gestures (hyprgrass plugin). Disable: touch ~/.config/hypr/hyprgrass-disabled
require("hypr.touch")

require("default.hypr.toggles")




o.window({ tag = "floating-window", class = "^org.omarchy.btop$" }, { size = { 1200, 800 } })
o.window("org.omarchy.about", { size = { 1200, 800 } })

-- LocalSend changed its Wayland application ID.
o.window("^(localsend|org.localsend.localsend_app)$", { float = true })
