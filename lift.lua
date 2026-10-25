-- Lift construction, persistent endpoint links, removal, and data migration.

-- Node names used by the generated lift structure.
local BOTTOM_NODE = "minecart_lift:lift_bottom"
local TOP_NODE = "minecart_lift:lift_top"
local ROPE_NODE = "minecart_lift:rope"
local ROPE_KNOT_NODE = "minecart_lift:rope_knot"
local UPPER_RAIL_NODE = "minecart_lift:upper_rail"
local MAX_DISTANCE = 256
local BOTTOM_KEY = "minecart_lift:bottom"
local TOP_KEY = "minecart_lift:top"
local PEER_KEY = "minecart_lift:peer"
local LANDMARK_NODE = "minecart:landmark"
local LANDMARK_RANGE = 8

-- Return an independent position table so callers cannot mutate the source.
local function copy_position(pos)
   return {x = pos.x, y = pos.y, z = pos.z}
end

-- Read a position serialized with minetest.pos_to_string from node metadata.
local function read_position(meta, key)
   local value = meta:get_string(key)
   return value ~= "" and minetest.string_to_pos(value) or nil
end

-- Extend the normal protection query to empty shaft nodes. Minecart's
-- minetest.is_protected wrapper checks landmarks only when the node at the
-- queried position was registered with register_protected_node; empty nodes
-- therefore need an explicit landmark lookup while a lift is being built.
function minecart_lift.is_protected(pos, player_name)
   if minetest.is_protected(pos, player_name) then
      return true
   end
   if minetest.check_player_privs(player_name, "minecart") then
      return false
   end

   local min_pos = vector.subtract(pos, LANDMARK_RANGE)
   local max_pos = vector.add(pos, LANDMARK_RANGE)
   for _, landmark_pos in ipairs(minetest.find_nodes_in_area(
         min_pos, max_pos, {LANDMARK_NODE})) do
      local owner = minetest.get_meta(landmark_pos):get_string("owner")
      if owner ~= player_name then
         return true
      end
   end
   return false
end

-- Test a loaded node without treating an unloaded mapblock as air.
local function is_node(pos, name)
   local node = minetest.get_node_or_nil(pos)
   return node and node.name == name
end

-- Elevator Top is a winch; its functional rail is two nodes below it.
local function upper_rail_position(top_pos)
   return {x = top_pos.x, y = top_pos.y - 2, z = top_pos.z}
end

-- Remove the hidden functional rail only if it still belongs to this mod.
local function remove_upper_rail(top_pos)
   local pos = upper_rail_position(top_pos)
   if is_node(pos, UPPER_RAIL_NODE) then
      minetest.remove_node(pos)
   end
end

-- Public lookup used by movement.lua. Connections live in node metadata just
-- like minecart waypoints, so they survive restarts without a runtime cache.
function minecart.get_lift_path(pos)
   local node = minecart.get_node_lvm(pos)
   if not node or (node.name ~= UPPER_RAIL_NODE and node.name ~= BOTTOM_NODE) then
      return nil
   end
   return read_position(minetest.get_meta(pos), PEER_KEY)
end

-- Remove only rope nodes whose ownership metadata points at this winch.
local function remove_rope(top_pos, bottom_pos)
   for y = bottom_pos.y + 1, top_pos.y - 1 do
      local pos = {x = top_pos.x, y = y, z = top_pos.z}
      if is_node(pos, ROPE_NODE) or is_node(pos, ROPE_KNOT_NODE) then
         local owner = read_position(minetest.get_meta(pos), TOP_KEY)
         if owner and vector.equals(owner, top_pos) then
            minetest.remove_node(pos)
         end
      end
   end
end

-- Clear both directions of the persistent endpoint connection.
local function unregister_lift(top_pos, bottom_pos)
   minetest.get_meta(upper_rail_position(top_pos)):set_string(PEER_KEY, "")
   minetest.get_meta(bottom_pos):set_string(PEER_KEY, "")
end

-- Connect the endpoint rails and invalidate cached minecart waypoints nearby.
local function activate_lift(top_pos, bottom_pos)
   local rail_pos = upper_rail_position(top_pos)
   minecart.delete_waypoint(rail_pos)
   minecart.delete_waypoint(bottom_pos)
   minetest.get_meta(rail_pos):set_string(PEER_KEY, minetest.pos_to_string(bottom_pos))
   minetest.get_meta(bottom_pos):set_string(PEER_KEY, minetest.pos_to_string(rail_pos))
   minetest.get_meta(top_pos):set_string("infotext",
      "Minecart Lift connected to " .. minetest.pos_to_string(bottom_pos))
   minetest.get_meta(bottom_pos):set_string("infotext",
      "Minecart Lift connected to " .. minetest.pos_to_string(rail_pos))
end

-- Rope deployment may use only loaded, empty, and unprotected nodes.
local function can_replace_with_rope(pos, player_name)
   local node = minetest.get_node_or_nil(pos)
   if not node or node.name ~= "air" then
      return false
   end
   return not minecart_lift.is_protected(pos, player_name)
end

-- Scan downward until the first solid node and return the last air node above
-- it. That air node becomes Elevator Bottom.
local function find_bottom(top_pos, player_name)
   local rope_start = {x = top_pos.x, y = top_pos.y - 1, z = top_pos.z}
   if not can_replace_with_rope(rope_start, player_name) then
      return nil, "The space below Elevator Top is blocked or protected"
   end

   -- The first two nodes below the winch are handled separately: one rope
   -- segment and the functional upper rail.
   local last_air
   for offset = 3, MAX_DISTANCE + 2 do
      local pos = {x = top_pos.x, y = top_pos.y - offset, z = top_pos.z}
      local node = minetest.get_node_or_nil(pos)
      if not node then
         return nil, "The lift shaft is not fully loaded"
      end
      if node.name == "air" then
         if minecart_lift.is_protected(pos, player_name) then
            return nil, "The lift shaft crosses protected space"
         end
         last_air = copy_position(pos)
      else
         if not last_air then
            return nil, "There is no room below the upper rail"
         end
         return last_air
      end
   end
   return nil, "No floor found within " .. MAX_DISTANCE .. " nodes"
end

-- Place a rope variant and record the winch that owns it for safe cleanup.
local function set_rope(pos, top_pos, node_name)
   minetest.set_node(pos, {name = node_name or ROPE_NODE})
   minetest.get_meta(pos):set_string(TOP_KEY, minetest.pos_to_string(top_pos))
end

-- Build a complete lift after emerge_shaft has loaded the vertical column.
-- Returns true and the bottom position, or false and an English error message.
function minecart_lift.deploy(top_pos, player_name)
   player_name = player_name or ""
   if minecart_lift.is_protected(top_pos, player_name) then
      return false, "Elevator Top is protected by a Minecart Landmark"
   end
   local rail_pos = upper_rail_position(top_pos)
   if not can_replace_with_rope(rail_pos, player_name) then
      return false, "Elevator Top needs two empty nodes below it"
   end

   local bottom_pos, error_message = find_bottom(top_pos, player_name)
   if not bottom_pos then
      return false, error_message
   end
   if minecart_lift.is_protected(bottom_pos, player_name) then
      return false, "The bottom endpoint is protected"
   end

   -- Fill the shaft with rope, using a knot for its final visible segment.
   set_rope({x = top_pos.x, y = top_pos.y - 1, z = top_pos.z}, top_pos)
   for y = top_pos.y - 3, bottom_pos.y + 1, -1 do
      local node_name = y == bottom_pos.y + 1 and ROPE_KNOT_NODE or ROPE_NODE
      set_rope({x = top_pos.x, y = y, z = top_pos.z}, top_pos, node_name)
   end

   -- Create both functional rails before writing their reciprocal metadata.
   minetest.set_node(bottom_pos, {name = BOTTOM_NODE})
   minetest.set_node(rail_pos, {name = UPPER_RAIL_NODE})
   minetest.get_meta(top_pos):set_string(BOTTOM_KEY, minetest.pos_to_string(bottom_pos))
   minetest.get_meta(bottom_pos):set_string(TOP_KEY, minetest.pos_to_string(top_pos))
   activate_lift(top_pos, bottom_pos)
   minetest.log("action", "[minecart_lift] Deployed lift from "
      .. minetest.pos_to_string(top_pos) .. " to " .. minetest.pos_to_string(bottom_pos))
   return true, bottom_pos
end

-- Load the entire possible shaft asynchronously before inspecting its nodes.
function minecart_lift.emerge_shaft(top_pos, callback)
   local min_pos = {
      x = top_pos.x - LANDMARK_RANGE,
      y = top_pos.y - MAX_DISTANCE - 2,
      z = top_pos.z - LANDMARK_RANGE,
   }
   local max_pos = {
      x = top_pos.x + LANDMARK_RANGE,
      y = top_pos.y + LANDMARK_RANGE,
      z = top_pos.z + LANDMARK_RANGE,
   }

   -- emerge_area invokes the callback once per mapblock operation. Defer the
   -- user callback until the final operation has completed.
   minetest.emerge_area(min_pos, max_pos, function(_, _, calls_remaining)
      if calls_remaining == 0 then
         minetest.after(0, callback)
      end
   end)
end

-- Removing the winch removes every generated part of its lift.
function minecart_lift.remove_top(top_pos)
   local bottom_pos = read_position(minetest.get_meta(top_pos), BOTTOM_KEY)
   if not bottom_pos then
      return
   end
   unregister_lift(top_pos, bottom_pos)
   remove_rope(top_pos, bottom_pos)
   remove_upper_rail(top_pos)
   if is_node(bottom_pos, BOTTOM_NODE) then
      minetest.remove_node(bottom_pos)
   end
end

-- Removing Elevator Bottom disconnects the winch and removes generated parts.
function minecart_lift.remove_bottom(bottom_pos)
   local top_pos = read_position(minetest.get_meta(bottom_pos), TOP_KEY)
   if not top_pos then
      minetest.get_meta(bottom_pos):set_string(PEER_KEY, "")
      return
   end
   unregister_lift(top_pos, bottom_pos)
   remove_rope(top_pos, bottom_pos)
   remove_upper_rail(top_pos)
   if is_node(top_pos, TOP_NODE) then
      local meta = minetest.get_meta(top_pos)
      meta:set_string(BOTTOM_KEY, "")
      meta:set_string("infotext", "Minecart Lift not connected")
   end
end

-- Migrate lifts built before endpoint connections were stored like minecart
-- waypoints. Each loaded endpoint can restore its own metadata independently.
minetest.register_lbm({
   label = "Migrate Minecart Lift endpoint metadata",
   name = "minecart_lift:migrate_endpoint_metadata_v2",
   nodenames = {TOP_NODE, BOTTOM_NODE},
   run_at_every_load = false,
   action = function(pos, node)
      if node.name == TOP_NODE then
         local bottom_pos = read_position(minetest.get_meta(pos), BOTTOM_KEY)
         local rail_pos = upper_rail_position(pos)
         local rail_node = minecart.get_node_lvm(rail_pos)
         if bottom_pos and bottom_pos.x == pos.x and bottom_pos.z == pos.z
               and bottom_pos.y < rail_pos.y
               and rail_node and rail_node.name == UPPER_RAIL_NODE then
            minetest.get_meta(rail_pos):set_string(
               PEER_KEY, minetest.pos_to_string(bottom_pos))
         end
         return
      end

      local top_pos = read_position(minetest.get_meta(pos), TOP_KEY)
      if top_pos and top_pos.x == pos.x and top_pos.z == pos.z
            and pos.y < top_pos.y - 2 then
         minetest.get_meta(pos):set_string(
            PEER_KEY, minetest.pos_to_string(upper_rail_position(top_pos)))
      end
   end,
})
