--- @module server.inventory.providers.ox_inventory
--- ox_inventory implementation of TbInventoryProvider. This is v1's only
--- shipped backend (per project requirements), every ox_inventory-specific
--- export call lives in this one file.
---
--- Assumes ox_inventory's standard exports (AddItem, RemoveItem, Search,
--- SetMetadata) and that every item instance gets an auto-assigned
--- `metadata.serial` string, true for all ox_inventory releases at time of
--- writing. If a future ox_inventory version changes this, only this file
--- needs updating.

-- The resource state is checked per call, not once at load: ox_inventory may
-- simply start after this resource.
if Config.Inventory ~= 'ox_inventory' then
	return
end

local Provider = {}

---@param source integer
---@param itemName string
---@param metadata table?
---@return boolean ok
---@return string? serial
function Provider.AddItem(source, itemName, metadata)
	if GetResourceState('ox_inventory') ~= 'started' then
		error('ox_inventory is not started, the card item cannot be given')
	end

	metadata = metadata or {}
	-- ox_inventory only gives weapons a serial, so we stamp our own.
	metadata.serial = metadata.serial or tostring(metadata.cardNumber or ('%d%06d'):format(os.time(), math.random(0, 999999)))

	if not exports.ox_inventory:AddItem(source, itemName, 1, metadata) then
		return false, nil
	end

	return true, metadata.serial
end

---@param source integer
---@param itemName string
---@param serial string
---@return table? metadata
function Provider.GetItemBySerial(source, itemName, serial)
	if GetResourceState('ox_inventory') ~= 'started' then
		error('ox_inventory is not started')
	end

	local items = exports.ox_inventory:Search(source, 'slots', itemName)

	if not items then
		return nil
	end

	for _, item in ipairs(items) do
		if item.metadata and item.metadata.serial == serial then
			return item.metadata
		end
	end

	return nil
end

---@param source integer
---@param itemName string
---@param serial string
---@param metadata table
---@return boolean ok
function Provider.SetMetadata(source, itemName, serial, metadata)
	if GetResourceState('ox_inventory') ~= 'started' then
		error('ox_inventory is not started')
	end

	local items = exports.ox_inventory:Search(source, 'slots', itemName)

	if not items then
		return false
	end

	for _, item in ipairs(items) do
		if item.metadata and item.metadata.serial == serial then
			exports.ox_inventory:SetMetadata(source, item.slot, metadata)
			return true
		end
	end

	return false
end

---@param source integer
---@param itemName string
---@param serial string
---@return boolean ok
function Provider.RemoveItem(source, itemName, serial)
	if GetResourceState('ox_inventory') ~= 'started' then
		error('ox_inventory is not started')
	end

	local items = exports.ox_inventory:Search(source, 'slots', itemName)

	if not items then
		return false
	end

	for _, item in ipairs(items) do
		if item.metadata and item.metadata.serial == serial then
			return exports.ox_inventory:RemoveItem(source, itemName, 1, item.metadata, item.slot) == true
		end
	end

	return false
end

TbInventoryProvider.Register(Provider)
