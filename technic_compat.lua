-- Minecart Hopper compatibility for every Technic chest variant.

-- Apply the access rules of locked and protected Technic chests to automated
-- transfers. The Minecart Hopper passes its owner name instead of a player.
local function chest_access_allowed(pos, stack, player_name)
   local node_name = minetest.get_node(pos).name

   -- Locked chests may only exchange cargo with a hopper of the same owner.
   if node_name:find("_locked_chest", 1, true) then
      return minetest.get_meta(pos):get_string("owner") == player_name
   end

   -- Protected chests rely on their surrounding protection for placement,
   -- manual access, and removal. Automated transfers have no player object,
   -- so they use the same direct inventory access as pipe-based automation.
   if node_name:find("_protected_chest", 1, true) then
      return true
   end

   return true
end

-- Technic registers material, ownership, and colored chest variants before
-- this callback runs. Their shared group lets future variants work as well.
minetest.register_on_mods_loaded(function()
   if minetest.registered_nodes["protector:chest"] then
      -- Protector controls who may place, open, or remove the installation.
      -- Automated inventory transfers themselves have no player object and
      -- therefore use Minecart's established direct inventory connection.
      minecart.register_inventory({"protector:chest"}, {
         put = {
            listname = "main",
         },
         take = {
            listname = "main",
         },
      })
      minetest.log("action", "[minecart_lift] Minecart Hopper support enabled for "
         .. "protector:chest")
   end

   local chest_names = {}
   for node_name, definition in pairs(minetest.registered_nodes) do
      if definition.groups and (definition.groups.technic_chest or 0) > 0 then
         chest_names[#chest_names + 1] = node_name
      end
   end

   if #chest_names == 0 then
      return
   end

   minecart.register_inventory(chest_names, {
      put = {
         allow_inventory_put = chest_access_allowed,
         listname = "main",
      },
      take = {
         allow_inventory_take = chest_access_allowed,
         listname = "main",
      },
   })

   minetest.log("action", "[minecart_lift] Minecart Hopper support enabled for "
      .. #chest_names .. " Technic chest variants")
end)
