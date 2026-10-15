-- Who counts as an admin for the commands and the update notice.
-- Either the framework group from Config.Admin.Group (default 'admin'), or the
-- tiltann_banking.admin ace. Neither is required on its own.

TbAdmin = {}

---@param source integer
---@return boolean
function TbAdmin.Is(source)
	if source == 0 then
		return true -- server console
	end

	if IsPlayerAceAllowed(source, 'tiltann_banking.admin') then
		return true
	end

	local group = Config.Admin and Config.Admin.Group

	if group and group ~= '' then
		local ok, inGroup = pcall(TbFramework.HasGroup, source, group)
		return ok and inGroup == true
	end

	return false
end
