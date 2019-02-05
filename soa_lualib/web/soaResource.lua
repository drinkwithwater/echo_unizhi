local skynet = require "skynet"
local snax = require "snax"
local soa = require "soa"
local cjson = require "cjson"

local skynetAdapterDict = {
	["snaxd.snaxPlayerEntityManager"] = true,
	["snlua.debugConsole"] = true,
}

local function getSkynetDict()
	local dict = skynet.call("SERVICE", "lua", "LIST")
	local reDict = {}
	for name, coAddr in pairs(dict) do
		local hex = coAddr:gsub(":","0x")
		local address = tonumber(hex)
		if name:find("snaxd.") == 1 then
			reDict[name] = address
		else
			reDict["snlua."..name] = address
		end
	end
	return reDict
end

local function queryModule(module)
	local address = soa.queryservice(module)
	if address then
		return true, address
	elseif soa.ismultiservice(module) then
		return true, module
	else
		return false, getSkynetDict()[module]
	end
end

return function (module, method, argList) -- url param
	return {
		get=function(query)
			if not module then
				return true, {
					soa = soa.list(),
					soaMulti = soa.listMulti(),
					skynet = getSkynetDict(),
				}
			else
				local isSoa, address = queryModule(module)
				if not address then
					return false, "404 service not found"
				end

				if query and query.inject then
					return skynet.call(address, "debug", "RUN", query.inject, nil)
				end

				if isSoa or skynetAdapterDict[module] then
					if not method then
						return pcall(soa.call, address, "gm", "get")
					elseif not argList then
						local argvStr = (query or {}).argv or "[]"
						argList = cjson.decode(argvStr)
						return pcall(soa.call, address, "gm", method, table.unpack(argList))
					else
						return pcall(soa.call, address, "gm", method, table.unpack(argList))
					end
				else
					return true, {
						["nothing"] = "not a good service for web"
					}
				end
			end
		end
	}
end

