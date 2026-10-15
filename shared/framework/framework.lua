-- Framework layer. This is the only place the rest of the resource talks to
-- the player framework through, nothing outside framework/ may touch
-- ESX, QBCore or qbox directly.
--
-- To support a new framework copy framework/esx.lua, implement the same
-- functions, call TbFramework.Register('name', impl) at the bottom and add
-- the file to fxmanifest.lua. The functions are listed in the README.

TbFramework = {}

local implementations = {}
local active = nil

function TbFramework.Register(name, impl)
	impl.Name = name
	implementations[name] = impl
end

-- Order used when Config.Framework is 'auto'.
local DETECT = {
	{ name = 'qbox', resource = 'qbx_core' },
	{ name = 'qb', resource = 'qb-core' },
	{ name = 'esx', resource = 'es_extended' },
}

local function Resolve()
	if active then
		return active
	end

	local wanted = Config.Framework

	if wanted == nil or wanted == 'auto' then
		for _, entry in ipairs(DETECT) do
			if implementations[entry.name] and GetResourceState(entry.resource) ~= 'missing' then
				wanted = entry.name
				break
			end
		end
	end

	active = implementations[wanted]

	if not active then
		error(('no framework implementation for "%s", see framework/ and Config.Framework'):format(tostring(wanted)), 3)
	end

	if active.Experimental and IsDuplicityVersion() then
		print(('^1[tiltann_banking] WARNING: the %s framework support is not finished and has not been tested. It is not recommended for a live server, ESX is the supported framework.^7'):format(wanted))
	end

	return active
end

-- TbFramework.Anything(...) calls the active implementation.
setmetatable(TbFramework, {
	__index = function(_, key)
		local impl = Resolve()
		local value = impl[key]

		if type(value) == 'function' then
			return function(...)
				return value(...)
			end
		end

		return value
	end,
})
