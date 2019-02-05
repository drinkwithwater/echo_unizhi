local skynet = require "skynet"
require "skynet.manager"

local soa = {}
local cache = {}
local provider = nil

local function get_provider()
	provider = provider or  skynet.uniqueservice("soaProvider")
	return provider
end


soa.call = function(service, cmd, ...)
	return skynet.call(service, "lua", cmd, ...)
end
soa.send = function(service, cmd, ...)
	skynet.send(service, "lua", cmd, ...)
end

-- 包裹一下由snax模块临时改造成的soa的调用接口
soa.snaxuniqueservice = function(fileName, ...)
	local handle = soa.uniqueservice(fileName)
	local obj = {handle=handle}
	obj.post = setmetatable({}, {
		__index = function(t,k)
			return function(...)
				return skynet.send(obj.handle, "lua", "post", k, ...)
			end
		end
	})
	obj.req = setmetatable({}, {
		__index = function(t,k)
			return function(...)
				return skynet.call(obj.handle, "lua", "req", k, ...)
			end
		end
	})
	return obj
end

-- 以初始化方式启动的service
-- 该部分service会在soa.start时统一调用CMD.start，同时在soa.startCluster时统一调用CMD.startCluster
function soa.initservice(name, ...)
	local address = cache[name]
	if not address then
		address = skynet.call(get_provider(), "lua", "initservice", name, ...)
		cache[name] = address
	end
	return address
end

function soa.uniqueservice(name, ...)
	local address = cache[name]
	if not address then
		address = skynet.call(get_provider(), "lua", "uniqueservice", name, ...)
		cache[name] = address
	end
	return address
end

function soa.queryservice(name)
	local address = cache[name] or skynet.call(get_provider(), "lua", "queryservice", name)
	return address
end

function soa.wrapper(subcmd)
	return {
		call=function(service, ...)
			return skynet.call(service, "lua", subcmd, ...)
		end,
		send=function(service, ...)
			skynet.send(service, "lua", subcmd, ...)
		end
	}
end

-- cluster api
local cluster = {}
local soaClusterd = nil

function soa.newgate(name)
	local address = skynet.call(cluster.getClusterd(), "lua", "get", name)
	local addr, port = string.match(address, "([^:]+):(.*)$")
	local gate = skynet.newservice("gate")
	skynet.call(gate, "lua", "open", {
		address = addr,
		port = port,
		nodelay = true,
	})
	return gate
end

function cluster.getClusterd()
	soaClusterd = soaClusterd or soa.uniqueservice("soaClusterd")
	return soaClusterd
end

function cluster.getNodeAddress()
	return skynet.call(cluster.getClusterd(), "lua", "get")
end

-- 监听clusterd的node_address变化
function cluster.monitorNodeAddress(vSetter)
	local nInitDict = cluster.getNodeAddress()
	for k, v in pairs(nInitDict) do
		vSetter(k,v)
	end
	skynet.fork(function()
		while(true) do
			local nDict = skynet.call(cluster.getClusterd(), "lua", "addressWaitUpdate")
			for k, v in pairs(nDict) do
				vSetter(k,v)
			end
		end
	end)
end

soa.cluster = cluster

-- 除了以上api，其他api直接调用soaProvider的接口
soa = setmetatable(soa, {
	__index = function(t, cmd)
		local api = function(...)
			return skynet.call(get_provider(), "lua", cmd, ...)
		end
		t[cmd] = api
		return api
	end
})


return soa
