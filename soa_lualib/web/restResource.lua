local skynet = require "skynet"
local urllib = require "http.url"
local snax = require "snax"
local soa = require "soa"
local cjson = require "cjson"

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
	else
		return false, getSkynetDict()[module]
	end
end

return function (module, method) -- url param
	local get=function(query)
		local isSoa, address = queryModule(module)
		if not address then
			return false, cjson.encode({
				error="404 service not found"
			})
		end

		if isSoa then
			local nOkay, nResult = pcall(soa.call, address, "rest", method, query)
			if nOkay then
				return true, cjson.encode(nResult)
			else
				return true, cjson.encode({
					error = tostring(nResult)
				})
			end
		else
			return true, {
				["error"] = "not a good service for rest"
			}
		end
	end
	return {
		get=get,
		post=function(queryObj, postBody)
			local nObj = urllib.parse_query(postBody or "")
			return get(nObj)
		end,
	}
end

