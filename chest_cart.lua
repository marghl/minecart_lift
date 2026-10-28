-- Fixed-inventory minecart based on minecart's cart lifecycle and the
-- 32-slot layout of a standard Minetest Game chest.

local S = minecart_lift.S
local cart_name = "minecart_lift:chest_cart"
local entity_name = "minecart_lift:chest_cart_entity"
local inventory_size = 32
local chest_top = "minecart_lift_chest_top.png"
local chest_side = "minecart_lift_chest_side.png"
local chest_front = "minecart_lift_chest_front.png"

-- Present the same 8 by 4 storage area as a standard chest. The original
-- layout is shifted down uniformly to make room for the assigned cart number.
local function get_formspec(pos, inventory_location)
   local number = minetest.get_meta(pos):get_int("userID")
   inventory_location = inventory_location or "context"
   return "size[8,9.35]"
      .. "label[0,0;"
      .. minetest.formspec_escape(S("Cart number: @1", number)) .. "]"
      .. "list[" .. inventory_location .. ";main;0,0.65;8,4;]"
      .. "list[current_player;main;0,5.2;8,1;]"
      .. "list[current_player;main;0,6.43;8,3;8]"
      .. "listring[" .. inventory_location .. ";main]"
      .. "listring[current_player;main]"
      .. default.get_hotbar_bg(0, 5.2)
end

-- Initialize metadata both for newly placed carts and carts restored after a
-- trip. Resizing an existing inventory to the same size preserves its stacks.
local function initialize_inventory(pos)
   local meta = minetest.get_meta(pos)
   meta:get_inventory():set_size("main", inventory_size)
   meta:set_string("formspec", get_formspec(pos))
   meta:set_string("infotext", S("Chest Cart"))
end

-- Only the owner or a player with the minecart privilege may edit the cargo.
local function inventory_access(pos, player)
   if not minecart.is_owner(player, minetest.get_meta(pos):get_string("owner")) then
      return 0
   end
   return nil
end

-- Convert every slot to a plain string. Plain Lua data survives minecart's
-- monitoring storage, server restarts, and the elevator checkpoint handling.
local function get_cargo(pos)
   local inventory = minetest.get_meta(pos):get_inventory()
   local cargo = {}
   for index = 1, inventory_size do
      cargo[index] = inventory:get_stack("main", index):to_string()
   end
   inventory:set_list("main", {})
   return cargo
end

-- Restore stacks into their original slots instead of spawning item entities.
local function set_cargo(pos, cargo)
   local inventory = minetest.get_meta(pos):get_inventory()
   inventory:set_size("main", inventory_size)
   for index = 1, inventory_size do
      inventory:set_stack("main", index, ItemStack(cargo and cargo[index] or ""))
   end
end

-- Prevent pickup while the fixed inventory still contains cargo.
local function has_cargo(pos)
   return not minetest.get_meta(pos):get_inventory():is_empty("main")
end

minetest.register_node(cart_name, {
   description = S("Chest Cart"),
   drawtype = "nodebox",
   tiles = {
      chest_top,
      "carts_cart_top.png",
      chest_side,
      chest_side,
      chest_side,
      chest_front,
   },
   -- Without flat inventory overrides, Minetest uses this same nodebox model
   -- for the inventory item and for the moving wielditem entity below.
   paramtype = "light",
   paramtype2 = "facedir",
   sunlight_propagates = true,
   is_ground_content = false,
   node_placement_prediction = "",
   diggable = false,
   groups = {cracky = 2, oddly_breakable_by_hand = 2},
   sounds = default.node_sound_metal_defaults(),
   node_box = {
      type = "fixed",
      fixed = {
         -- The lower cart occupies 6 of the total 16 vertical texture pixels.
         {-0.5, -0.5, -0.5, 0.5, -0.375, 0.5},
         {-0.5, -0.5, -0.5, -0.375, -0.125, 0.5},
         {0.375, -0.5, -0.5, 0.5, -0.125, 0.5},
         {-0.5, -0.5, -0.5, 0.5, -0.125, -0.375},
         {-0.5, -0.5, 0.375, 0.5, -0.125, 0.5},
         -- The inset chest uses the remaining 10 vertical pixels.
         {-0.375, -0.125, -0.375, 0.375, 0.5, 0.375},
      },
   },
   selection_box = {
      type = "fixed",
      fixed = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
   },
   on_place = minecart.on_nodecart_place,
   on_punch = minecart.on_nodecart_punch,
   on_rightclick = function(pos, node, clicker, itemstack)
      local meta = minetest.get_meta(pos)
      if meta:get_int("userID") == 0 then
         minecart.show_formspec(pos, clicker)
         return itemstack
      end
      if inventory_access(pos, clicker) == 0 then
         return itemstack
      end
      local location = "nodemeta:" .. pos.x .. "," .. pos.y .. "," .. pos.z
      minetest.show_formspec(clicker:get_player_name(),
         "minecart_lift:chest_cart", get_formspec(pos, location))
      return itemstack
   end,
   after_place_node = initialize_inventory,
   set_cargo = set_cargo,
   get_cargo = get_cargo,
   has_cargo = has_cargo,
   allow_metadata_inventory_move = function(pos, from_list, from_index,
         to_list, to_index, count, player)
      return inventory_access(pos, player) or count
   end,
   allow_metadata_inventory_put = function(pos, listname, index, stack, player)
      return inventory_access(pos, player) or stack:get_count()
   end,
   allow_metadata_inventory_take = function(pos, listname, index, stack, player)
      return inventory_access(pos, player) or stack:get_count()
   end,
})

-- The moving entity carries the serialized inventory in its cargo field. It
-- cannot be opened while moving and cannot be removed while it contains items.
minecart.register_cart_entity(entity_name, cart_name, "chest", {
   initial_properties = {
      physical = false,
      collisionbox = {-0.5, -0.5, -0.5, 0.5, 0.5, 0.5},
      visual = "wielditem",
      textures = {cart_name},
      visual_size = {x = 0.66, y = 0.66},
      static_save = false,
   },
   driver_allowed = false,
   only_dig_if_empty = true,
})

-- Let the existing Minecart Hopper load and unload the fixed inventory
-- directly while the cart is standing on a rail.
minecart.register_inventory({cart_name}, {
   put = {listname = "main"},
   take = {listname = "main"},
})

-- Give landmarks the same control over the Chest Cart as over standard carts.
minecart.register_protected_node(cart_name)

-- Combine the two standard components that define the cart.
minetest.register_craft({
   output = cart_name,
   recipe = {
      {"default:chest"},
      {"minecart:cart"},
   },
})
