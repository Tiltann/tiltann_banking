-- Client exports for other resources.
--
--   exports.tiltann_banking:OpenBank()      bank terminal (tablet)
--   exports.tiltann_banking:OpenAtm()       ATM screen
--   exports.tiltann_banking:OpenBilling()   billing menu
--   exports.tiltann_banking:CloseUi()       closes whatever is open
--   exports.tiltann_banking:IsUiOpen()      true while a bank screen is open
--   exports.tiltann_banking:RefreshUi()     reloads the open screen's data

local function ClientExport(name, fn)
	exports(name, function(...)
		local ok, result = TbSafe.Run(('export:%s'):format(name), fn, ...)

		if not ok then
			return false
		end

		return result
	end)
end

ClientExport('OpenBank', function()
	TbOpenTerminal()
	return true
end)

ClientExport('OpenAtm', function()
	TbOpenAtm()
	return true
end)

ClientExport('OpenBilling', function()
	TbOpenBilling()
	return true
end)

ClientExport('CloseUi', function()
	TbCloseUi()
	return true
end)

ClientExport('IsUiOpen', function()
	return TbIsUiOpen()
end)

ClientExport('RefreshUi', function()
	TbRefreshUI()
	return true
end)
