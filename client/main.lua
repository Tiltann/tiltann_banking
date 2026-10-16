-- Client entry point. Makes sure the framework is reachable and wires the
-- live balance updates.

CreateThread(function()
	TbSafe.Run('startup:client', function()
		TbFramework.Ready()
		TbLogger.Debug('startup', 'client ready', { version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) })

		-- The framework tells the client when the bank balance changes (another
		-- script, an admin command). The server re-reads it, so the client never
		-- gets to say what the balance is.
		TbFramework.OnBankChanged(function()
			TriggerServerEvent('tiltann_banking:bankChanged')
		end)
	end)
end)

RegisterNetEvent('tiltann_banking:setDebug', function(enabled)
	TbLogger.SetDebug(enabled)
end)

CreateThread(function()
	Wait(2000)
	TriggerServerEvent('tiltann_banking:requestDebug')
end)

RegisterNetEvent('tiltann_banking:refresh', function()
	TbRefreshUI()
end)

-- Billing menu on a key (rebindable in the GTA key settings).
if Config.Billing.Enabled then
	RegisterCommand('tb_billing', function()
		TbOpenBilling()
	end, false)

	RegisterKeyMapping('tb_billing', locale('billing_keybind'), 'keyboard', Config.Billing.Key or 'F7')
end

RegisterNetEvent('tiltann_banking:invoiceReceived', function()
	lib.notify({ type = 'inform', description = locale('invoice_received') })
end)
