-- modified from skynet/service/gate.lua
local skynet = require "skynet"
local netpack = require "skynet.netpack"
local socketdriver = require "skynet.socketdriver"


local mServerDict = {}	-- server fd
local mClientDict = {}	-- client fd, fd -> { fd , client, agent , ip, mode }

local queue					-- message queue
local CMD = {}
local GM = {}

local MAX_CLIENT = 1024		-- max client
local mClientNum = 0
local nodelay = true
local mWatchdog = nil

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local handler = setmetatable({}, {__gc = function() netpack.clear(queue) end })

function handler.message(fd, msg, sz)
	-- recv a package, forward it
	local c = mClientDict[fd]
	local agent = c.agent
	if agent then
		skynet.redirect(agent, c.client, "client", 1, msg, sz)
	else
		skynet.send(mWatchdog, "lua", "socket", "data", fd, netpack.tostring(msg, sz))
	end
end

function handler.connect(fd, addr)
	skynet.send(mWatchdog, "lua", "socket", "open", fd, addr, skynet.self())
end

function handler.disconnect(fd)
	skynet.send(mWatchdog, "lua", "socket", "close", fd)
end

function handler.error(fd, msg)
	skynet.send(mWatchdog, "lua", "socket", "error", fd, msg)
end

function handler.warning(fd, size)
	skynet.send(mWatchdog, "lua", "socket", "warning", fd, size)
end

function CMD.accept(fd)
	local c = mClientDict[fd]
	if c then
		socketdriver.start(fd)
	end
end

function CMD.kick(fd)
	local c = mClientDict[fd]
	if c then
		mClientDict[fd] = false
		socketdriver.close(fd)
	end
end

function CMD.open(conf)
	local address = conf.address or "0.0.0.0"
	local port = assert(conf.port)
	skynet.error(string.format("Listen on %s:%d", address, port))

	local listenSocket = socketdriver.listen(address, port)
	mServerDict[listenSocket] = {
		address = address,
		port = port,
	}
	socketdriver.start(listenSocket)

	return listenSocket
end

function CMD.close(listenSocket)
	if mServerDict[listenSocket] then
		socketdriver.close(listenSocket)
	end
end

local MSG = {}

local function dispatch_msg(fd, msg, sz)
	if mClientDict[fd] then
		handler.message(fd, msg, sz)
	else
		skynet.error(string.format("Drop message from fd (%d) : %s", fd, netpack.tostring(msg,sz)))
	end
end

MSG.data = dispatch_msg

local function dispatch_queue()
	local fd, msg, sz = netpack.pop(queue)
	if fd then
		-- may dispatch even the handler.message blocked
		-- If the handler.message never block, the queue should be empty, so only fork once and then exit.
		skynet.fork(dispatch_queue)
		dispatch_msg(fd, msg, sz)

		for fd, msg, sz in netpack.pop, queue do
			dispatch_msg(fd, msg, sz)
		end
	end
end

MSG.more = dispatch_queue

function MSG.open(fd, msg)
	if mClientNum >= MAX_CLIENT then
		socketdriver.close(fd)
		return
	end
	if nodelay then
		socketdriver.nodelay(fd)
	end
	mClientDict[fd] = {
		fd = fd,
		ip = msg,
	}
	mClientNum = mClientNum + 1
	handler.connect(fd, msg)
end

local function close_fd(fd)
	local c = mClientDict[fd]
	if c ~= nil then
		mClientDict[fd] = nil
		mClientNum = mClientNum - 1
	end
end

function MSG.close(fd)
	if not mServerDict[fd] then
		handler.disconnect(fd)
		close_fd(fd)
	else
		mServerDict[fd] = nil
	end
end

function MSG.error(fd, msg)
	if mServerDict[fd] then
		socketdriver.close(fd)
		skynet.error("gateserver close listen socket, accpet error:", msg)
	else
		handler.error(fd, msg)
		close_fd(fd)
	end
end

function MSG.warning(fd, size)
	if handler.warning then
		handler.warning(fd, size)
	end
end

skynet.register_protocol {
	name = "socket",
	id = skynet.PTYPE_SOCKET,	-- PTYPE_SOCKET = 6
	unpack = function ( msg, sz )
		return netpack.filter( queue, msg, sz)
	end,
	dispatch = function (_, _, q, type, ...)
		queue = q
		if type then
			MSG[type](...)
		end
	end
}

function CMD.init(bootstrap)
	bootstrap.register("gm", GM)
end

function CMD.start(vWatchdog)
	mWatchdog = vWatchdog
end

function GM.get()
	return {
		mServerDict = mServerDict,
		mClientDict = mClientDict,
		mClientNum = mClientNum,
	}
end

return CMD
