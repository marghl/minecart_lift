-- Minecart Lift
-- Main entry point loaded by Minetest.

-- Resolve this installation instead of assuming a fixed mods directory.
local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

-- Publish the small shared namespace used by the module files.
minecart_lift = rawget(_G, "minecart_lift") or {}
minecart_lift.modname = modname
minecart_lift.modpath = modpath
minecart_lift.S = minetest.get_translator(modname)

-- Load persistent lift data first, node definitions second, and entity hooks
-- last so every referenced API exists when it is used.
dofile(modpath .. "/lift.lua")
dofile(modpath .. "/rails.lua")
dofile(modpath .. "/chest_cart.lua")
dofile(modpath .. "/technic_compat.lua")
dofile(modpath .. "/movement.lua")

minetest.log("action", "[minecart_lift] Mod loaded")
