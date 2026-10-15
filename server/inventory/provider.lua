--- @module server.inventory.provider
--- Abstract inventory interface every card/ATM operation calls through.
--- No other module in this resource calls `exports.ox_inventory` (or any
--- other inventory's exports) directly, swapping to a different inventory
--- system later means writing one new provider file and changing a single
--- line in server/main.lua, not touching cards.lua or atm.lua at all.

---@class TbInventoryProvider
---@field AddItem fun(source: integer, itemName: string, metadata: table?): boolean, string?
---@field GetItemBySerial fun(source: integer, itemName: string, serial: string): table?
---@field SetMetadata fun(source: integer, itemName: string, serial: string, metadata: table): boolean
---@field RemoveItem fun(source: integer, itemName: string, serial: string): boolean

---@type TbInventoryProvider?
local activeProvider = nil

-- Config.Inventory = 'none': cards exist only in tb_cards, no item is given.
-- Everything is authorised from the database, so nothing else changes.
if Config.Inventory == 'none' then
	activeProvider = {
		AddItem = function() return true, nil end,
		GetItemBySerial = function() return {} end,
		SetMetadata = function() return true end,
		RemoveItem = function() return true end,
	}
end

TbInventoryProvider = {}

--- Registers the active inventory provider implementation. Called once by
--- the matching providers/*.lua file when it loads (see
--- server/inventory/providers/ox_inventory.lua's last line).
---@param provider TbInventoryProvider
function TbInventoryProvider.Register(provider)
	activeProvider = provider
end

--- Grants `itemName` to `source`'s inventory with the given metadata.
--- Returns the item's unique serial on success, which is the value stored
--- in tb_bank_cards.inventory_serial and used for every subsequent
--- SetMetadata/RemoveItem call on that specific physical item.
---@param source integer
---@param itemName string
---@param metadata table?
---@return boolean ok
---@return string? serial
function TbInventoryProvider.AddItem(source, itemName, metadata)
	if not activeProvider then
		TbLogger.Error('inventory', 'no provider registered, is server/inventory/providers/ox_inventory.lua listed in fxmanifest.lua?')
		return false, nil
	end

	local ok, added, serial = pcall(activeProvider.AddItem, source, itemName, metadata)

	if not ok then
		TbLogger.Error('inventory', 'AddItem failed', { item = itemName, source = source, error = added })
		return false, nil
	end

	-- The provider's own answer counts, a clean return of false is a refusal
	-- (inventory full, item not defined), not a success.
	return added == true, serial
end

---@param source integer
---@param itemName string
---@param serial string
---@return table? metadata `nil` if the item isn't found in the player's inventory.
function TbInventoryProvider.GetItemBySerial(source, itemName, serial)
	if not activeProvider then
		return nil
	end

	local ok, result = pcall(activeProvider.GetItemBySerial, source, itemName, serial)

	if not ok then
		TbLogger.Error('inventory', 'GetItemBySerial failed', { item = itemName, source = source, error = result })
		return nil
	end

	return result
end

---@param source integer
---@param itemName string
---@param serial string
---@param metadata table
---@return boolean ok
function TbInventoryProvider.SetMetadata(source, itemName, serial, metadata)
	if not activeProvider then
		return false
	end

	local ok, result = pcall(activeProvider.SetMetadata, source, itemName, serial, metadata)

	if not ok then
		TbLogger.Error('inventory', 'SetMetadata failed', { item = itemName, source = source, error = result })
		return false
	end

	return result == true
end

---@param source integer
---@param itemName string
---@param serial string
---@return boolean ok
function TbInventoryProvider.RemoveItem(source, itemName, serial)
	if not activeProvider then
		return false
	end

	local ok, result = pcall(activeProvider.RemoveItem, source, itemName, serial)

	if not ok then
		TbLogger.Error('inventory', 'RemoveItem failed', { item = itemName, source = source, error = result })
		return false
	end

	return result == true
end
