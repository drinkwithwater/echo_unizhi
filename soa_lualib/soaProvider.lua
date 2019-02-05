local skynet = require "skynet"
require "skynet.manager"

local CMD = {}
local CLUSTER = {}
local LOCAL = {}

local soaInitServiceSet = {}
local soaUniqueServiceDict = {}
local soaMultiServiceFileDict = {}

local mServiceName = nil			-- 给一些service命名
local mCommonRequire = nil			-- 共用的require的文件

function CMD.setServiceNameDict(vDict)
	mServiceName = vDict
end

function CMD.setCommonRequireList(vList)
	mCommonRequire = vList
end

function CMD.initservice(fileName)
	local address = CMD.uniqueservice(fileName)
	soaInitServiceSet[address] = true
	return address
end

function CMD.uniqueservice(fileName)
	fileName = fileName:gsub("/",".")
	local coList = soaUniqueServiceDict[fileName]
	local valueType = type(coList)
	if valueType == "number" then
		return coList
	elseif valueType == "table" then
		local co = coroutine.running()
		coList[#coList + 1] = co
		skynet.wait(co)
		local address = soaUniqueServiceDict[fileName]
		assert(type(address) == "number")
		return address
	elseif coList == nil then
		-- 如果service未创建，则新建一个coroutine list保存等待的coroutine
		coList = {}
		soaUniqueServiceDict[fileName] = coList
		local service = skynet.newservice("soaService", fileName)
		-- 给service命名
		if mServiceName then
			for keyname, rename in pairs(mServiceName) do
				local b,e = fileName:find(keyname)
				if e==#fileName then
					skynet.name(rename, service)
				end
			end
		end

		-- 让soaService require一些通用的文件
		if mCommonRequire then
			skynet.call(service, "lua", ".bootstrap", "requireList", mCommonRequire)
		end

		-- 是否开启覆盖率检测
		if skynet.getenv("luacov") then
			skynet.call(service, "lua", "luacovInit", fileName)
		end
		-- 初始化
		skynet.call(service, "lua", ".bootstrap", "init", fileName)
		-- 恢复等待的coroutine
		soaUniqueServiceDict[fileName] = service
		if #coList > 0 then
			for i, co in pairs(coList) do
				skynet.wakeup(co)
			end
		end
		return service
	else
		skynet.error("[ERROR] unexcept if branch when soa.uniqueservice")
		return nil
	end
end

function CMD.reportLuacov()
	if skynet.getenv("luacov") then
		for fileName, service in pairs(soaUniqueServiceDict) do
			skynet.send(service, "lua", "luacovReport")
		end
		for service, fileName in pairs(soaMultiServiceFileDict) do
			skynet.send(service, "lua", "luacovReport")
		end
	end
end

function CMD.multiservice(fileName)
	fileName = fileName:gsub("/",".")
	local address = skynet.newservice("soaService", fileName)
	skynet.call(address, "lua", ".bootstrap", "init", fileName)
	soaMultiServiceFileDict[address] = fileName
	return address
end

function CMD.queryservice(fileName)
	local address = soaUniqueServiceDict[fileName]
	if address then
		return address
	else
		return nil
	end
end

function CMD.ismultiservice(address)
	return soaMultiServiceFileDict[address]
end

function CMD.start(context)
	for service,v in pairs(soaInitServiceSet) do
		skynet.call(service, "lua", "start", context)
	end
end

function CMD.startCluster()
	for service,v in pairs(soaInitServiceSet) do
		skynet.call(service, "lua", "startCluster")
	end
end

function CMD.list()
	return soaUniqueServiceDict
end

function CMD.listMulti()
	return soaMultiServiceFileDict
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		skynet.ret(skynet.pack(f(...)))
	end)
end)
