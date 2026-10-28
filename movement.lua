-- Vertical movement integration for both carts:cart and minecart entities.

-- Default speed in nodes per second; server configuration may override it.
local DEFAULT_SPEED = 3

-- Hash a rounded object position for stable arrival-station comparisons.
local function position_key(pos)
   return minetest.hash_node_position(vector.round(pos))
end

-- Reject missing, non-numeric, zero, and negative configuration values.
local configured_speed = tonumber(minetest.settings:get("minecart_lift_speed"))
if not configured_speed or configured_speed <= 0 then
   configured_speed = DEFAULT_SPEED
end

minecart_lift.speed = configured_speed

-- Return a stable key and representative node position for a mapblock.
local function mapblock(pos)
   local block = {
      x = math.floor(pos.x / 16),
      y = math.floor(pos.y / 16),
      z = math.floor(pos.z / 16),
   }
   return block.x .. ":" .. block.y .. ":" .. block.z, {
      x = block.x * 16,
      y = block.y * 16,
      z = block.z * 16,
   }
end

-- Keep only the cart's current and destination mapblocks active. Locks are
-- transient, so an unclean shutdown cannot leave permanent forceload entries.
local function update_forceload(entity, current_pos, target_pos)
   local desired = {}
   for _, pos in ipairs({current_pos, target_pos}) do
      local key, block_pos = mapblock(pos)
      desired[key] = block_pos
   end

   local held = entity._minecart_lift_forceload or {}
   for key, block_pos in pairs(desired) do
      if not held[key] and minetest.forceload_block(block_pos, true) then
         held[key] = block_pos
      end
   end
   for key, block_pos in pairs(held) do
      if not desired[key] then
         minetest.forceload_free_block(block_pos, true)
         held[key] = nil
      end
   end
   entity._minecart_lift_forceload = held
end

-- Release every transient mapblock lock owned by one cart.
local function release_forceload(entity)
   for _, block_pos in pairs(entity._minecart_lift_forceload or {}) do
      minetest.forceload_free_block(block_pos, true)
   end
   entity._minecart_lift_forceload = nil
end

-- Return the existing minecart monitoring record for an autonomous cart.
local function monitoring_data(entity)
   if entity.owner and entity.userID then
      return minecart.get_cart_monitoring_data(entity.owner, entity.userID)
   end
end

-- Store lift-specific state inside minecart.CartsOnRail. Minecart already
-- serializes this table on changes and shutdown, so no second database is
-- required by this mod.
local function store_monitoring_travel(entity, travel, pos)
   if travel.is_carts_cart then
      return
   end
   local data = monitoring_data(entity)
   if not data then
      return
   end
   -- While the entity is outside a player's active-object range, minecart
   -- turns it into a "zombie" and recreates it from the next checkpoint. A
   -- vertical lift therefore needs a live checkpoint of its own. Preserve the
   -- buffer route so it can continue towards the recorded destination later.
   if travel.had_checkpoints == nil then
      travel.had_checkpoints = data.checkpoints ~= nil
      travel.original_checkpoints = data.checkpoints
      travel.original_checkpoint_index = data.idx
   end
   data.last_pos = vector.round(pos)
   data.minecart_lift_travel = {
      target = vector.new(travel.target),
      direction = travel.direction,
      resume_direction = vector.new(travel.resume_direction),
      resume_speed = travel.resume_speed,
      last_pos = vector.round(pos),
      had_checkpoints = travel.had_checkpoints,
      original_checkpoints = travel.original_checkpoints,
      original_checkpoint_index = travel.original_checkpoint_index,
   }
   data.checkpoints = {{
      minetest.hash_node_position(vector.round(pos)),
      minetest.hash_node_position(travel.target),
      math.floor(minecart_lift.speed + 0.5),
      1,
      "minecart_lift",
      vector.new(travel.resume_direction),
   }}
   data.idx = 0
   minecart.store_carts()
end

-- Clear persistent lift state once minecart can resume normal rail handling.
local function clear_monitoring_travel(entity, travel, pos)
   local data = monitoring_data(entity)
   if data then
      data.last_pos = vector.round(pos)
      if travel.had_checkpoints then
         data.checkpoints = travel.original_checkpoints
         data.idx = travel.original_checkpoint_index or 0
      else
         data.checkpoints = nil
         data.idx = 0
      end
      data.minecart_lift_travel = nil
      minecart.store_carts()
   end
end

-- Record a vertical checkpoint in the format used by minecart monitoring.
-- Extra fields are ignored by minecart itself and identify lift re-entry.
local function record_lift_checkpoint(entity, travel, pos)
   if not entity.is_recording or not entity.checkpoints or not entity.rec_time
         or entity.rec_time > entity.timebase then
      return
   end
   entity.curr_speed = minecart_lift.speed
   entity.sum_speed = (entity.sum_speed or 0) + minecart_lift.speed
   entity.checkpoints[#entity.checkpoints + 1] = {
      minetest.hash_node_position(vector.round(pos)),
      minetest.hash_node_position(travel.target),
      math.floor(minecart_lift.speed + 0.5),
      1,
      "minecart_lift",
      vector.new(travel.resume_direction),
   }
   entity.rec_time = entity.rec_time + 2
end

-- Return the rounded rail position only when it is a connected lift endpoint.
local function get_rail_position(object_pos)
   local rail_pos = vector.round(object_pos)
   if minecart.get_lift_path(rail_pos) then
      return rail_pos
   end
   return nil
end

-- Preserve the direction and speed of a Minetest Game cart before vertical
-- movement temporarily replaces its normal rail physics.
local function horizontal_state(entity)
   local velocity = entity.object:get_velocity()
   if entity.punched and entity.velocity then
      velocity = entity.velocity
   end

   local direction = entity.old_dir and vector.new(entity.old_dir)
      or carts:velocity_to_dir(velocity)
   direction.y = 0
   local speed = math.sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
   if speed < 0.1 and entity.velocity then
      speed = math.sqrt(entity.velocity.x * entity.velocity.x
         + entity.velocity.z * entity.velocity.z)
   end
   return direction, math.max(speed, 2)
end

-- Obtain a horizontal travel direction from either supported cart system.
local function entity_direction(entity, is_carts_cart)
   if is_carts_cart then
      local direction = entity.old_dir and vector.new(entity.old_dir)
         or carts:velocity_to_dir(entity.object:get_velocity())
      direction.y = 0
      return vector.round(direction)
   end

   local rotation = entity.object:get_rotation()
   local direction = minetest.yaw_to_dir(rotation.y)
   direction.y = 0
   return vector.round(direction)
end

-- Accept flat rails as well as a one-node rise or drop next to the station.
local function has_rail_ahead(pos, direction)
   if direction.x == 0 and direction.z == 0 then
      return false
   end
   for vertical_offset = -1, 1 do
      local next_pos = {
         x = pos.x + direction.x,
         y = pos.y + vertical_offset,
         z = pos.z + direction.z,
      }
      if minecart.is_rail(next_pos) then
         return true
      end
   end
   return false
end

-- Prefer the incoming direction, then try both sides, the reverse direction,
-- and finally all cardinals as a fallback for carts without direction state.
local function find_exit_direction(pos, preferred_direction)
   local directions = {}
   local seen = {}

   local function add_direction(direction)
      direction = vector.round({x = direction.x, y = 0, z = direction.z})
      local key = direction.x .. ":" .. direction.z
      if (direction.x ~= 0 or direction.z ~= 0) and not seen[key] then
         seen[key] = true
         directions[#directions + 1] = direction
      end
   end

   -- Keep travelling straight whenever the rail layout permits it.
   add_direction(preferred_direction)
   if preferred_direction.x ~= 0 or preferred_direction.z ~= 0 then
      add_direction({x = -preferred_direction.z, z = preferred_direction.x})
      add_direction({x = preferred_direction.z, z = -preferred_direction.x})
      add_direction({x = -preferred_direction.x, z = -preferred_direction.z})
   end

   -- Also handle carts without a usable previous direction.
   add_direction({x = 1, z = 0})
   add_direction({x = -1, z = 0})
   add_direction({x = 0, z = 1})
   add_direction({x = 0, z = -1})

   for _, direction in ipairs(directions) do
      if has_rail_ahead(pos, direction) then
         return direction
      end
   end
   return nil
end

-- Suspend normal rail processing and initialize one vertical trip.
local function begin_lift_travel(entity, rail_pos, peer_pos, is_carts_cart)
   local object_pos = entity.object:get_pos()
   local direction = peer_pos.y > rail_pos.y and 1 or -1
   local resume_direction, resume_speed
   if is_carts_cart then
      resume_direction, resume_speed = horizontal_state(entity)
   else
      resume_direction = entity_direction(entity, false)
   end

   -- Private entity state is kept only for the duration of this trip.
   entity._minecart_lift_travel = {
      start_y = object_pos.y,
      target = vector.new(peer_pos),
      direction = direction,
      is_carts_cart = is_carts_cart,
      resume_direction = resume_direction,
      resume_speed = resume_speed,
   }
   update_forceload(entity, object_pos, peer_pos)
   store_monitoring_travel(entity, entity._minecart_lift_travel, object_pos)
   -- Discard the horizontal waypoint and prevent minecart from advancing it.
   entity.waypoint = nil
   entity.arrival_time = math.huge
   entity.object:set_velocity({x = 0, y = direction * minecart_lift.speed, z = 0})
   minetest.log("action", "[minecart_lift] Lift travel started from "
      .. minetest.pos_to_string(rail_pos) .. " to " .. minetest.pos_to_string(peer_pos))
end

-- Place the cart exactly on the destination rail, choose an exit if present,
-- and restore the state expected by the respective cart implementation.
local function finish_lift_travel(entity, travel)
   entity.object:set_pos(travel.target)
   local exit_direction = find_exit_direction(travel.target, travel.resume_direction)
   local can_continue = exit_direction ~= nil
   -- Minetest Game carts resume through velocity and old_dir.
   if travel.is_carts_cart and can_continue then
      local velocity = vector.multiply(exit_direction, travel.resume_speed)
      entity.object:set_velocity(velocity)
      entity.velocity = vector.new(velocity)
      entity.old_dir = vector.new(exit_direction)
      entity.old_pos = vector.new(travel.target)
      entity.punched = false
   else
      entity.object:set_velocity({x = 0, y = 0, z = 0})
      if travel.is_carts_cart then
         entity.velocity = {x = 0, y = 0, z = 0}
         -- Confirm the reached endpoint even when no outgoing rail exists.
         -- Otherwise carts:pathfinder treats the old upper endpoint as the
         -- last valid position and instantly snaps the cart back there.
         entity.old_pos = vector.new(travel.target)
         entity.punched = false
      end
   end
   -- Minecart entities resume through their yaw and is_running flag.
   if not travel.is_carts_cart and can_continue then
      entity.object:set_rotation({x = 0, y = minetest.dir_to_yaw(exit_direction), z = 0})
   end
   entity._minecart_lift_travel = nil
   entity._minecart_lift_cooldown = (entity._minecart_lift_time or 0) + 0.5
   -- Do not interpret the remaining movement state as a new trip in the
   -- opposite direction while the cart is still on the arrival rail.
   entity._minecart_lift_arrival = position_key(travel.target)
   entity._minecart_lift_departing = can_continue
   entity.waypoint = nil
   entity.arrival_time = 0
   entity.is_running = can_continue
   if not can_continue then
      entity.cart_speed = 0
   end
   clear_monitoring_travel(entity, travel, travel.target)
   release_forceload(entity)
   minetest.log("action", "[minecart_lift] Lift travel finished at "
      .. minetest.pos_to_string(travel.target))

   -- Match minecart's native stop_cart behavior at a real route end: detach a
   -- rider, restore the cart node, and let entity_to_node stop monitoring.
   if not travel.is_carts_cart and not can_continue then
      local player = entity.driver and minetest.get_player_by_name(entity.driver)
      if player then
         minecart.manage_attachment(player, entity, false)
         player:set_pos(travel.target)
      end
      minecart.entity_to_node(travel.target, entity)
   end
end

-- Advance at a fixed nodes-per-second rate and clamp the final step to avoid
-- overshooting the destination under a large dtime.
local function continue_lift_travel(entity, dtime)
   local travel = entity._minecart_lift_travel
   if not travel.is_carts_cart then
      entity.timebase = (entity.timebase or 0) + dtime
   end
   local pos = entity.object:get_pos()
   local remaining = math.abs(travel.target.y - pos.y)
   local step = minecart_lift.speed * dtime

   if not travel.is_carts_cart then
      entity.curr_speed = minecart_lift.speed
      record_lift_checkpoint(entity, travel, pos)
      if entity.is_recording then
         minecart.recording_junctions(entity)
      end
   end

   if remaining <= step then
      finish_lift_travel(entity, travel)
      return
   end

   pos.x = travel.target.x
   pos.y = pos.y + travel.direction * step
   pos.z = travel.target.z
   update_forceload(entity, pos, travel.target)
   entity.object:set_pos(pos)
   entity.object:set_velocity({x = 0, y = travel.direction * minecart_lift.speed, z = 0})

   -- Persist at most once per second; shutdown serialization still sees the
   -- latest in-memory value even between these periodic writes.
   local now = entity._minecart_lift_time or 0
   if not travel.is_carts_cart and now >= (travel.next_monitoring_update or 0) then
      store_monitoring_travel(entity, travel, pos)
      travel.next_monitoring_update = now + 1
   end
end

-- Resume a checkpoint created by record_lift_checkpoint after minecart has
-- reconstructed a zombie cart near a player or at the end of a route.
local function resume_checkpoint(entity, checkpoint)
   if type(checkpoint) ~= "table" or checkpoint[5] ~= "minecart_lift" then
      return false
   end
   local target = minetest.get_position_from_hash(checkpoint[2])
   local current = entity.object:get_pos()
   local resume_direction = checkpoint[6] or entity_direction(entity, false)
   local saved = monitoring_data(entity)
   saved = saved and saved.minecart_lift_travel
   entity.reenter = nil
   entity._minecart_lift_travel = {
      start_y = current.y,
      target = vector.new(target),
      direction = target.y > current.y and 1 or -1,
      is_carts_cart = false,
      resume_direction = vector.new(resume_direction),
      resume_speed = saved and saved.resume_speed,
      had_checkpoints = saved and saved.had_checkpoints,
      original_checkpoints = saved and saved.original_checkpoints,
      original_checkpoint_index = saved and saved.original_checkpoint_index,
   }
   entity.arrival_time = math.huge
   entity.is_running = true
   update_forceload(entity, current, target)
   store_monitoring_travel(entity, entity._minecart_lift_travel, current)
   return true
end

-- Decorate an entity's existing on_step callback without replacing the rest
-- of its cart implementation.
local function wrap_entity(entity_name)
   local definition = minetest.registered_entities[entity_name]
   if not definition or definition._minecart_lift_wrapped then
      return
   end

   local original_on_step = definition.on_step
   if not original_on_step then
      return
   end
   local original_on_activate = definition.on_activate
   local original_on_deactivate = definition.on_deactivate
   local original_get_staticdata = definition.get_staticdata

   -- Mark definitions because multiple mods-loaded callbacks must not wrap the
   -- same function repeatedly.
   definition._minecart_lift_wrapped = true

   -- Minetest Game carts are not part of minecart's monitoring database. Add
   -- an extension to their normal static data so a lift trip survives a
   -- singleplayer logout, which shuts down and restarts the local server.
   if entity_name == "carts:cart" then
      definition.get_staticdata = function(entity)
         local staticdata = original_get_staticdata and original_get_staticdata(entity)
         local data = minetest.deserialize(staticdata or "")
         if type(data) ~= "table" then
            data = {}
         end

         local travel = entity._minecart_lift_travel
         if travel then
            data.minecart_lift_travel = {
               target = vector.new(travel.target),
               direction = travel.direction,
               resume_direction = vector.new(travel.resume_direction),
               resume_speed = travel.resume_speed,
            }
         end
         return minetest.serialize(data)
      end

      -- Restore vertical movement before the first entity step. The engine
      -- already restores the entity position, so only the destination and
      -- movement state have to be reconstructed from the static data.
      definition.on_activate = function(entity, staticdata, dtime_s)
         if original_on_activate then
            original_on_activate(entity, staticdata, dtime_s)
         end

         local data = minetest.deserialize(staticdata or "")
         local saved = type(data) == "table" and data.minecart_lift_travel
         if not saved or not saved.target then
            return
         end

         local current = entity.object:get_pos()
         local target = vector.new(saved.target)
         entity._minecart_lift_travel = {
            start_y = current.y,
            target = target,
            direction = saved.direction or (target.y > current.y and 1 or -1),
            is_carts_cart = true,
            resume_direction = saved.resume_direction
               and vector.new(saved.resume_direction) or {x = 1, y = 0, z = 0},
            resume_speed = saved.resume_speed or 2,
         }
         entity.punched = false
         entity.velocity = {x = 0, y = 0, z = 0}
         update_forceload(entity, current, target)
         entity.object:set_velocity({
            x = 0,
            y = entity._minecart_lift_travel.direction * minecart_lift.speed,
            z = 0,
         })
         minetest.log("action", "[minecart_lift] Restored carts:cart in lift at "
            .. minetest.pos_to_string(vector.round(current)))
      end
   end

   definition.on_deactivate = function(entity, removal)
      release_forceload(entity)
      if original_on_deactivate then
         return original_on_deactivate(entity, removal)
      end
   end
   definition.on_step = function(entity, dtime, moveresult)
      entity._minecart_lift_time = (entity._minecart_lift_time or 0) + dtime

      -- Minecart monitoring may recreate a cart from one of our extended
      -- checkpoints. Convert that checkpoint back into vertical movement
      -- before the original entity code interprets it as a normal waypoint.
      if entity.reenter and resume_checkpoint(entity, entity.reenter) then
         continue_lift_travel(entity, dtime)
         return
      end

      -- Lift physics owns the entity exclusively while a trip is active.
      if entity._minecart_lift_travel then
         continue_lift_travel(entity, dtime)
         return
      end

      local object_pos = entity.object:get_pos()
      -- An arrival latch prevents stale velocity or running flags from
      -- immediately starting an unintended return trip.
      if entity._minecart_lift_arrival then
         if position_key(object_pos) ~= entity._minecart_lift_arrival then
            entity._minecart_lift_arrival = nil
            entity._minecart_lift_departing = nil
         else
            local explicitly_restarted = entity_name == "carts:cart"
               and entity.punched
               or entity_name ~= "carts:cart" and entity.is_running
            if entity._minecart_lift_departing or not explicitly_restarted then
               return original_on_step(entity, dtime, moveresult)
            end
            entity._minecart_lift_arrival = nil
            entity._minecart_lift_departing = nil
         end
      end

      -- Enter a connected endpoint only when the cart is actually moving and
      -- the short post-arrival cooldown has expired.
      local cooldown = entity._minecart_lift_cooldown or 0
      local velocity = entity.object:get_velocity()
      local is_moving = entity.is_running or entity.punched
         or not vector.equals(velocity, {x = 0, y = 0, z = 0})
      if is_moving and entity._minecart_lift_time >= cooldown then
         local rail_pos = get_rail_position(object_pos)
         local peer_pos = rail_pos and minecart.get_lift_path(rail_pos)
         if peer_pos then
            begin_lift_travel(entity, rail_pos, peer_pos, entity_name == "carts:cart")
            return
         end
      end

      return original_on_step(entity, dtime, moveresult)
   end
   minetest.log("action", "[minecart_lift] Movement enabled for " .. entity_name)
end

-- Recreate monitored carts whose persisted lift trip survived a server
-- restart. The normal minecart storage callback has populated CartsOnRail by
-- the time this function is scheduled.
local function restore_monitored_lifts()
   for owner, carts_by_id in pairs(minecart.CartsOnRail or {}) do
      for user_id, data in pairs(carts_by_id) do
         local saved = data.minecart_lift_travel
         if saved and saved.target and (saved.last_pos or data.last_pos) then
            local restore_owner = owner
            local restore_user_id = user_id
            local restore_data = data
            local restore_saved = saved
            local pos = vector.new(saved.last_pos or data.last_pos)
            local target = vector.new(saved.target)
            local emerge_min = {
               x = math.min(pos.x, target.x),
               y = math.min(pos.y, target.y),
               z = math.min(pos.z, target.z),
            }
            local emerge_max = {
               x = math.max(pos.x, target.x),
               y = math.max(pos.y, target.y),
               z = math.max(pos.z, target.z),
            }
            restore_data._minecart_lift_recovering = true
            minetest.emerge_area(emerge_min, emerge_max, function(_, _, calls_remaining)
               if calls_remaining ~= 0 or not restore_data._minecart_lift_recovering then
                  return
               end
               restore_data._minecart_lift_recovering = nil

               -- Reuse a statically restored entity when possible; otherwise
               -- create the same cart type from its monitoring record.
               local object
               for _, candidate in ipairs(minetest.get_objects_inside_radius(pos, 1)) do
                  local candidate_entity = candidate:get_luaentity()
                  if candidate_entity and candidate_entity.name == restore_data.entity_name then
                     object = candidate
                     break
                  end
               end
               if not object then
                  object = minecart.add_entitycart(pos, restore_data.node_name,
                     restore_data.entity_name, {x = 0, y = 0, z = 0},
                     restore_data.cargo or {}, restore_owner, restore_user_id)
               end
               if not object then
                  return
               end

               local entity = object:get_luaentity()
               entity.owner = restore_owner
               entity.userID = restore_user_id
               entity.node_name = restore_data.node_name
               entity.entity_name = restore_data.entity_name
               entity.cargo = restore_data.cargo or {}
               entity.objID = minecart.get_object_id(object)
               entity.is_running = true
               entity.arrival_time = math.huge
               entity._minecart_lift_travel = {
                  start_y = pos.y,
                  target = target,
                  direction = restore_saved.direction or (target.y > pos.y and 1 or -1),
                  is_carts_cart = false,
                  resume_direction = restore_saved.resume_direction
                     or {x = 1, y = 0, z = 0},
                  resume_speed = restore_saved.resume_speed,
                  had_checkpoints = restore_saved.had_checkpoints,
                  original_checkpoints = restore_saved.original_checkpoints,
                  original_checkpoint_index = restore_saved.original_checkpoint_index,
               }
               restore_data.objID = entity.objID
               restore_data.last_pos = vector.round(pos)
               update_forceload(entity, pos, target)
               minecart.store_carts()
               minetest.log("action", "[minecart_lift] Restored monitored cart "
                  .. restore_owner .. "/" .. restore_user_id .. " in lift at "
                  .. minetest.pos_to_string(pos))
            end)
         end
      end
   end
end

-- Entity definitions exist only after all dependencies have loaded.
minetest.register_on_mods_loaded(function()
   for entity_name in pairs(minecart.tEntityNames) do
      wrap_entity(entity_name)
   end
   wrap_entity("carts:cart")
   minetest.after(0, restore_monitored_lifts)
end)
