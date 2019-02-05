local skynet = require "skynet"
local snax = require "snax"
local cluster = require "skynet.cluster"
local sharedata = require "sharedata"
require "skynet.manager"

local bootstrap = {}
-- 本文件的CMD 会被requireFile的CMD覆盖
local CMD = {}
-- 本文件的GM 对requireFile中的GM接口进行覆盖
local GM = {}
local SUBCMD = {
	[".bootstrap"]=bootstrap,
	["gm"]=GM
}

local sourceFile = nil
local NoReturnCMD = {}

-- 用来方便代码注入的gm变量
gm = {}

function bootstrap.requireList(fileList)
	for k, nFile in pairs(fileList) do
		require(nFile)
	end
end

function bootstrap.init(managerFile)
	-- can only init once
	bootstrap.init = false

	sourceFile = managerFile
	local manager = require(managerFile)
	if manager.init then
		manager.init(bootstrap)
	end
	for k,v in pairs(manager) do
		CMD[k] = v
	end
	gm.CMD = CMD
	return nil
end

function CMD.rest(subcmd, ...)
	local rest = SUBCMD["rawrest"]
	if not rest then
		return {
			error = "no rest cmd in this service"
		}
	end
	if not subcmd then
		return {
			error = "subcmd is nil"
		}
	end
	local func = rest[subcmd]
	if not func then
		return {
			error = "rest subcmd not found : "..subcmd
		}
	end
	local nOkay, nRet = pcall(func, ...)
	if not nOkay then
		return {
			error = nRet
		}
	end

	return nRet
end

function bootstrap.registerREST(funcDict)
	SUBCMD["rawrest"] = funcDict
	gm["REST"] = funcDict
end

function bootstrap.registerGM(funcDict)
	for k,v in pairs(funcDict) do
		gm[k] = v
		if not GM[k] then
			GM[k] = v
		end
	end
end

function bootstrap.register(cmd, funcDict)
	if cmd == "gm" then
		bootstrap.registerGM(funcDict)
	elseif cmd == "rest" then
		bootstrap.registerREST(funcDict)
	else
		SUBCMD[cmd] = funcDict
		gm[cmd:upper()] = funcDict
	end
end

function bootstrap.registerNoReturn(cmd, funcDict)
	bootstrap.register(cmd, funcDict)
	NoReturnCMD[cmd] = true
end

function bootstrap.setNoReturn(cmd)
	NoReturnCMD[cmd] = true
end

-- 该调用很危险
function GM.rawget(...)
	local argList = table.pack(...)
	local dict = gm.get()
	local cur = dict
	if argList and type(argList)=="table" and #argList > 0 then
		for _, key in ipairs(argList) do
			if type(cur)=="table" then
				cur = cur[key]
			else
				return nil
			end
		end
	end
	return cur
end

-- 屏蔽掉外部对gm.get的直接调用
function GM.get(...)
	local argList = table.pack(...)
	local dict = gm.get()
	local cur = dict
	if argList and type(argList)=="table" and #argList > 0 then
		for _, key in ipairs(argList) do
			if type(cur)=="table" then
				cur = cur[key]
			else
				return nil
			end
		end
	end
	if type(cur) == "table" then
		local keyDict = {}
		for k,v in pairs(cur) do
			if type(v) == "table" then
				local meta = getmetatable(v)
				if meta then
					keyDict[k] = tostring(v).."tablewithmeta"
				else
					keyDict[k] = tostring(v)
				end
			elseif type(v) == "number" then
				keyDict[k] = v
			else
				keyDict[k] = tostring(v)
			end
		end
		return keyDict
	else
		return cur
	end
end

function gm.getupvalue(vFunc, vKey)
	local i = 1
	while true do
		local name, oldvalue = debug.getupvalue(vFunc, i)
		if name == nil then
			return
		elseif name == vKey then
			return oldvalue
		end
		i = i + 1
	end
end

function gm.setupvalue(vFunc, vKey, vValue)
	local i = 1
	while true do
		local name, oldvalue = debug.getupvalue(vFunc, i)
		if name == nil then
			return
		elseif name == vKey then
			debug.setupvalue(vFunc, i, vValue)
			break
		end
		i = i + 1
	end
end

function CMD.startCluster()
end

local begin = nil
local runner = nil

function CMD.luacovForceInit()
	begin = require "luacov.begin"
	runner = require ("luacov")
	runner.init(sourceFile)
end

function CMD.luacovInit(fileName)

	local isFound = false
	local dirTable = require("luacov.config")

	for i, str in pairs(dirTable) do
		if str == fileName then
			isFound = true
			break
		end
	end

	if isFound == true then
        begin = require "luacov.begin"
		runner = require ("luacov")
		runner.init(fileName)
	end
end

function CMD.luacovReport()
	if begin and runner then
		runner.shutdown()
		begin.start(sourceFile)
	end
end

function CMD.exit()
	skynet.exit()
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		local subMap = SUBCMD[cmd]
		if subMap then
			local f = subMap[subcmd]
			if f then
				if NoReturnCMD[cmd] then
					f(...)
				else
					skynet.ret(skynet.pack(f(...)))
				end
			else
				skynet.error("[ERROR] unknown sub cmd", cmd, subcmd)
				skynet.ret(skynet.pack(nil))
			end
		else
			local f=CMD[cmd]
			if f then
				if NoReturnCMD[cmd] then
					f(subcmd, ...)
				else
					skynet.ret(skynet.pack(f(subcmd, ...)))
				end
			else
				skynet.error("[ERROR] unknown cmd", cmd)
				skynet.ret(skynet.pack(nil))
			end
		end
	end)
end)
