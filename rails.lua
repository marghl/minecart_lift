-- Node, rail, visual, sound, placement, and cleanup registrations.

-- Translator supplied by init.lua for all player-visible English names.
local S = minecart_lift.S

-- Rope nodes reuse one quiet, short-range creak sound definition.
local rope_sounds = {
   footstep = {
      name = "minecart_lift_rope_creak",
      gain = 0.8,
      max_hear_distance = 6,
   },
}

-- Elevator Bottom deliberately has the same four rail variants as a normal
-- Minetest Game rail so junctions retain their expected appearance.
local rail_tiles = {
   "carts_rail_straight.png",
   "carts_rail_curved.png",
   "carts_rail_t_junction.png",
   "carts_rail_crossing.png",
}

local bottom_name = "minecart_lift:lift_bottom"

-- The bottom station is both a visible normal rail and a lift endpoint.
carts:register_rail(bottom_name, {
   description = S("Elevator Bottom"),
   tiles = rail_tiles,
   inventory_image = rail_tiles[1],
   wield_image = rail_tiles[1],
   groups = carts:get_rail_groups({
      not_in_creative_inventory = 1,
      not_in_craft_guide = 1,
   }),
   on_destruct = minecart_lift.remove_bottom,
   after_destruct = minecart.delete_waypoint,
}, {})

-- carts:register_rail alone does not add third-party rails to minecart's
-- private lookup collections, so register the endpoint with its public tables.
minecart.tRails[bottom_name] = true
minecart.tRailsExt[bottom_name] = true
table.insert(minecart.lRails, bottom_name)
table.insert(minecart.lRailsExt, bottom_name)

local upper_rail_name = "minecart_lift:upper_rail"

-- This functional rail is rendered as part of the rope. It remains climbable
-- but cannot be selected, dug, or obtained by players.
carts:register_rail(upper_rail_name, {
   description = S("Elevator Upper Rail"),
   drawtype = "nodebox",
   tiles = {"minecart_lift_rope.png"},
   inventory_image = "blank.png",
   wield_image = "blank.png",
   groups = carts:get_rail_groups({not_in_creative_inventory = 1}),
   paramtype = "light",
   sunlight_propagates = true,
   walkable = false,
   climbable = true,
   diggable = false,
   pointable = false,
   buildable_to = false,
   drop = "",
   sounds = rope_sounds,
   selection_box = {
      type = "fixed",
      fixed = {0, 0, 0, 0, 0, 0},
   },
   node_box = {
      type = "fixed",
      fixed = {-1 / 16, -0.5, -1 / 16, 1 / 16, 0.5, 1 / 16},
   },
   after_destruct = minecart.delete_waypoint,
}, {})

-- Make the upper endpoint visible to minecart's path and rail detection.
minecart.tRails[upper_rail_name] = true
minecart.tRailsExt[upper_rail_name] = true
table.insert(minecart.lRails, upper_rail_name)
table.insert(minecart.lRailsExt, upper_rail_name)

-- Ceiling-mounted winch. Placement asynchronously builds the complete lift.
minetest.register_node("minecart_lift:lift_top", {
   description = S("Elevator Top"),
   drawtype = "nodebox",
   tiles = {"minecart_lift_winch.png"},
   inventory_image = "minecart_lift_winch.png",
   wield_image = "minecart_lift_winch.png",
   paramtype = "light",
   is_ground_content = false,
   groups = {cracky = 2, oddly_breakable_by_hand = 2},
   node_box = {
      type = "fixed",
      fixed = {
         {-0.5, 0.375, -0.5, 0.5, 0.5, 0.5},       -- ceiling plate
         {-0.4375, -0.125, -0.3125, 0.4375, 0.375, 0.3125}, -- housing
         {-0.3125, -0.375, -0.25, 0.3125, -0.125, 0.25},   -- cable drum
         {-0.0625, -0.5, -0.0625, 0.0625, -0.375, 0.0625}, -- rope outlet
      },
   },
   after_place_node = function(pos, placer)
      -- Copy position and player name because the emerge callback runs later.
      local player_name = placer and placer:get_player_name() or ""
      local placed_pos = vector.new(pos)

      if player_name ~= "" then
         minetest.chat_send_player(player_name,
            "[minecart_lift] Loading and checking the lift shaft...")
      end
      minetest.get_meta(pos):set_string("infotext", "Minecart Lift: checking shaft")

      -- Deployment starts only after every possible shaft mapblock is loaded.
      minecart_lift.emerge_shaft(placed_pos, function()
         -- The player may remove the winch while loading is in progress.
         if minetest.get_node(placed_pos).name ~= "minecart_lift:lift_top" then
            return
         end

         local success, result = minecart_lift.deploy(placed_pos, player_name)
         if success then
            if player_name ~= "" then
               minetest.chat_send_player(player_name,
                  "[minecart_lift] Lift ready. Elevator Bottom was placed at "
                  .. minetest.pos_to_string(result) .. ".")
            end
            return
         end

         -- Roll back a failed placement and return the item outside creative
         -- mode. If the player disconnected, leave the item in the world.
         minetest.remove_node(placed_pos)
         local player = player_name ~= "" and minetest.get_player_by_name(player_name)
         if player and not minetest.is_creative_enabled(player_name) then
            local leftover = player:get_inventory():add_item("main", "minecart_lift:lift_top")
            if not leftover:is_empty() then
               minetest.add_item(placed_pos, leftover)
            end
         elseif not player and player_name ~= "" then
            minetest.add_item(placed_pos, "minecart_lift:lift_top")
         end
         if player_name ~= "" then
            minetest.chat_send_player(player_name,
               "[minecart_lift] Lift construction failed: " .. result .. ".")
         end
      end)
   end,
   on_destruct = minecart_lift.remove_top,
})

-- Craft one complete lift winch. Elevator Bottom and the rope are generated
-- automatically when Elevator Top is placed and therefore have no recipes.
minetest.register_craft({
   output = "minecart_lift:lift_top",
   recipe = {
      {"default:steel_ingot", "default:steel_ingot", "default:steel_ingot"},
      {"default:steel_ingot", "default:copper_ingot", "default:steel_ingot"},
      {"default:steel_ingot", "carts:rail", "default:steel_ingot"},
   },
})

-- Standard shaft rope. Ownership metadata is added by lift.lua on placement.
minetest.register_node("minecart_lift:rope", {
   description = S("Elevator Rope"),
   drawtype = "nodebox",
   tiles = {"minecart_lift_rope.png"},
   use_texture_alpha = "clip",
   paramtype = "light",
   sunlight_propagates = true,
   walkable = false,
   climbable = true,
   -- Axes cut the rope quickly; an empty hand can still remove it, but slowly.
   diggable = true,
   pointable = true,
   drop = "",
   is_ground_content = false,
   groups = {
      choppy = 3,
      oddly_breakable_by_hand = 1,
      not_in_creative_inventory = 1,
   },
   sounds = rope_sounds,
   node_box = {
      type = "fixed",
      fixed = {-1 / 16, -0.5, -1 / 16, 1 / 16, 0.5, 1 / 16},
   },
   selection_box = {
      type = "fixed",
      fixed = {-2 / 16, -0.5, -2 / 16, 2 / 16, 0.5, 2 / 16},
   },
})

-- Final rope segment; the second node box forms the visible bottom knot.
minetest.register_node("minecart_lift:rope_knot", {
   description = S("Elevator Rope Knot"),
   drawtype = "nodebox",
   tiles = {"minecart_lift_rope.png"},
   use_texture_alpha = "clip",
   paramtype = "light",
   sunlight_propagates = true,
   walkable = false,
   climbable = true,
   -- The knotted final section uses the same removal rules as the rope above it.
   diggable = true,
   pointable = true,
   drop = "",
   is_ground_content = false,
   groups = {
      choppy = 3,
      oddly_breakable_by_hand = 1,
      not_in_creative_inventory = 1,
   },
   sounds = rope_sounds,
   node_box = {
      type = "fixed",
      fixed = {
         {-1 / 16, -0.5, -1 / 16, 1 / 16, 0.5, 1 / 16},
         {-3 / 16, -0.375, -3 / 16, 3 / 16, -0.0625, 3 / 16},
      },
   },
   selection_box = {
      type = "fixed",
      fixed = {-3 / 16, -0.5, -3 / 16, 3 / 16, 0.5, 3 / 16},
   },
})

-- Minecart Landmarks protect only explicitly registered node types. Register
-- every generated lift component so protected-area aware tools and dig logic
-- treat the complete installation like the rest of the rail network.
for _, node_name in ipairs({
      bottom_name,
      upper_rail_name,
      "minecart_lift:lift_top",
      "minecart_lift:rope",
      "minecart_lift:rope_knot",
   }) do
   minecart.register_protected_node(node_name)
end
