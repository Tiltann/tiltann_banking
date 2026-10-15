-- Qbox implementation of the framework layer. NOT TESTED, see the warning
-- TbFramework prints when it is selected. The shared logic is in qb.lua.

TbQbLike.Build('qbox', {
	ready = function()
		local deadline = GetGameTimer() + 15000

		while GetResourceState('qbx_core') ~= 'started' do
			if GetGameTimer() >= deadline then
				error('qbx_core did not start, is it ensured before tiltann_banking?', 0)
			end

			Wait(100)
		end
	end,
	player = function(source)
		return exports.qbx_core:GetPlayer(source)
	end,
	players = function()
		return exports.qbx_core:GetQBPlayers()
	end,
	byCitizenId = function(citizenId)
		return exports.qbx_core:GetPlayerByCitizenId(citizenId)
	end,
	jobs = function()
		return exports.qbx_core:GetJobs()
	end,
	hasPermission = function(source, group)
		return exports.qbx_core:HasPermission(source, group)
	end,
})
