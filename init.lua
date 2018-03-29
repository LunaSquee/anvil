anvil = rawget(_G, "anvil") or {}

local modpath = minetest.get_modpath("anvil")
anvil.modpath = modpath

-- Sets the colors and images for the anvil GUI when it is clicked
anvil.gui_bg = "bgcolor[#080808BB;true]"
anvil.gui_bg_img = "background[5,5;1,1;anvil_gui_formbg.png;true]"
anvil.gui_slots = "listcolors[#00000069;#5A5A5A;#141318;#30434C;#FFF]"

function anvil.get_formspec()
	-- What does this function do
	return "size[8,8.5]"..
			anvil.gui_bg..
			anvil.gui_bg_img..
			anvil.gui_slots..
			"list[context;src;1.5,1.5;1,1;]"..
			"image[2.4,1.5;1,1;anvil_gui_plus.png]"..
			"list[context;dst;3.3,1.5;1,1;]"..
			"image[4.4,1.5;1,1;anvil_gui_arrow.png]"..
			"list[context;res;5.5,1.5;1,1;]"..
			"list[current_player;main;0,4.25;8,1;]"..
			"list[current_player;main;0,5.5;8,3;8]"..
			"listring[context;dst]"..
			"listring[current_player;main]"..
			"listring[context;src]"..
			"listring[current_player;main]"..
			"listring[context;res]"..
			"listring[current_player;main]"
end

local function allow_metadata_inventory_put(pos, listname, index, stack, player)
	-- What does this function do
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end

	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()

	if listname == "res" then
		return 0
	end

	return stack:get_count()
end

local function allow_metadata_inventory_move(pos, from_list, from_index, to_list, to_index, count, player)
	-- What does this function do
	local meta = minetest.get_meta(pos)
	local inv = meta:get_inventory()
	local stack = inv:get_stack(from_list, from_index)
	return allow_metadata_inventory_put(pos, to_list, to_index, stack, player)
end

local function allow_metadata_inventory_take(pos, listname, index, stack, player)
	-- What does this function do
	if minetest.is_protected(pos, player:get_player_name()) then
		return 0
	end

	return stack:get_count()
end

local function take_from_stack(stack, count)
	-- What does this function do
	local newcount = stack:get_count() - count
	if newcount <= 0 then
		return nil
	end

	stack:set_count(newcount)
	return stack
end

function anvil.on_take(pos, listname, index, stack, player)
	-- What does this function do
	local inv = minetest.get_meta(pos):get_inventory()
	local src = inv:get_stack("src", 1)
	local dst = inv:get_stack("dst", 1)

	if listname == "src" or listname == "dst" then
		anvil:set_output(inv, src, dst)
	elseif listname == "res" then
		inv:set_stack("src", 1, take_from_stack(src, 1))
		inv:set_stack("dst", 1, take_from_stack(dst, 1))

		-- TODO: Multiple component repair

		minetest.sound_play("anvil_smith", {
			pos = pos,
			max_hear_distance = 10,
			gain = 1.0,
		})
	end
end

function anvil:set_output(inv, src, dst, name)
	-- What does this function do
	local srcname = src:get_name()
	local dstname = dst:get_name()
	local result = nil

	if src:is_empty() or dst:is_empty() then
		inv:set_list("res", {})
		return
	end

	-- TODO: Repair penalty

	-- Combination
	if srcname == dstname then
		local meta = src:get_meta()
		local meta2 = dst:get_meta()
		local repair_count = math.max(meta:get_int("repairs"), meta2:get_int("repairs"))

		local minwear = 65535 - src:get_wear()
		local maxwear = 65535 - dst:get_wear()

		if minwear ~= 65535 or maxwear ~= 65535 then
			local wear = 65535 - (minwear + maxwear)

			if wear < 0 then
				wear = 0
			end

			result = ItemStack(dstname)
			result:get_meta():set_int("repairs", repair_count + 1)
			result:set_wear(wear)
		end
	-- Tool repair by item
	elseif src:get_wear() ~= 0 and dst:get_wear() == 0 then
		local is_supported_tool = string.find(srcname, "axe") ~= nil or string.find(srcname, "sword") ~= nil or
			string.find(srcname, "shovel") ~= nil or string.find(srcname, "pick") ~= nil

		local meta = src:get_meta()
		local repair_count = 0
		if meta then
			repair_count = meta:get_int("repairs")
		end

		if is_supported_tool then
			local recipe = minetest.get_craft_recipe(srcname)
			if recipe.items ~= nil then
				if recipe.type == "normal" then
					local item_instances = 0
					for i, v in ipairs(recipe.items) do
						if v ~= "default:stick" then
							local is_group = string.find(v, "group:") ~= nil
							if is_group then
								local grp = string.sub(v, 7)
								if minetest.get_item_group(dstname, grp) > 0 then
									item_instances = item_instances + 1
								end
							elseif v == dstname then
								item_instances = item_instances + 1
							end
						end
					end

					if item_instances > 0 then
						local percentile = item_instances / #recipe.items
						local repair_amount = 65535 * percentile
						local wear = 65535 - src:get_wear()

						local endwear = 65535 - (wear + repair_amount)
						if endwear < 0 then
							endwear = 0
						end

						result = ItemStack(srcname)
						result:get_meta():set_int("repairs", repair_count + 1)
						result:set_wear(endwear)
					end
				end
			end
		end
	end

	if result then
		if inv:room_for_item("res", result) then
			inv:add_item("res", result)
		end
	else
		inv:set_list("res", {})
	end
end

function anvil.on_put(pos, listname, _, stack)
	-- What does this function do
	local inv = minetest.get_meta(pos):get_inventory()
	local src = inv:get_stack("src", 1)
	local dst = inv:get_stack("dst", 1)

	anvil:set_output(inv, src, dst)
end

minetest.register_node("anvil:anvil", {
	-- Creates the block called Anvil
	description = "Anvil",
	paramtype = "light",
	paramtype2 = "facedir",
	legacy_facedir_simple = true,
	drawtype = "nodebox",
	node_box = {
		type = "fixed",
		fixed = {
			{-1/4,  0.1, -1/2,  1/4,  1/2,  1/2},
			{-1/5, -1/4, -1/4,  1/5,  0.1,  1/4},
			{-1/3, -1/2, -1/3,  1/3, -1/4,  1/3},
		},
	},
	sunlight_propagates = true,
	is_ground_content = false,
	groups = {cracky = 1, falling_node = 1},
	tiles = {"anvil_node.png"},

	on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("formspec", anvil.get_formspec())
		local inv = meta:get_inventory()
		inv:set_size('src', 1)
		inv:set_size('dst', 1)
		inv:set_size('res', 1)
	end,

	allow_metadata_inventory_put = allow_metadata_inventory_put,
	allow_metadata_inventory_move = allow_metadata_inventory_move,
	allow_metadata_inventory_take = allow_metadata_inventory_take,

	on_metadata_inventory_move = anvil.on_put,
	on_metadata_inventory_put = anvil.on_put,
	on_metadata_inventory_take = anvil.on_take
})

minetest.register_craft({
	-- Creates the recipe for the anvil
	output = "anvil:anvil",
	recipe = {
		{ "default:steelblock"  , "default:steelblock"  , "default:steelblock"  },
		{ ""                    , "default:steel_ingot" , ""                    },
		{ "default:steel_ingot" , "default:steel_ingot" , "default:steel_ingot" }
	}
})
