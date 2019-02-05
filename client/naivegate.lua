local skynet = require "skynet"
local netpack = require "skynet.netpack"
local socketdriver = require "skynet.socketdriver"

local gateserver = {}

local socket	-- listen socket
local client_number = 0
local CMD = {}
local nodelay = false

local connection = {}

local maxclient

local watchdog

function CMD.open( source, conf )
	assert(not socket)
	local address = conf.address or "0.0.0.0"
	local port = assert(conf.port)
	maxclient = conf.maxclient or 1024
	nodelay = conf.nodelay
	skynet.error(string.format("Listen on %s:%d", address, port))
	socket = socketdriver.listen(address, port)
	socketdriver.start(socket)
	watchdog = source
end

function CMD.close()
	assert(socket)
	socketdriver.close(socket)
end

-- defined in skynet_socket.h
local toType = {
	[1]="data",
	[3]="close",
	[4]="accept",
	[5]="error",
	[7]="warning",
}

skynet.register_protocol {
	name = "socket",
	id = skynet.PTYPE_SOCKET,	-- PTYPE_SOCKET = 6
	unpack = function ( msg, sz )
		-- local typeid, fd, ud, data = socketdriver.unpack(msg, sz)
		return socketdriver.unpack(msg,sz)
	end,
	dispatch = function (_, _, typeid, fd, ud, data, ...)
		if typeid then
			local typeStr = toType[typeid]
			if typeStr=="accept" then
				socketdriver.start(ud)
				connection[ud] = true
				skynet.send(watchdog, "lua", "socket", "open", ud, data)
			elseif typeStr=="data" then
				if connection[fd] then
					local strData = netpack.tostring(data, ud)
					skynet.send(watchdog, "lua", "socket", "data", fd, strData)
				end
			elseif typeStr then
				if connection[fd] then
					socketdriver.close(fd)
					skynet.send(watchdog, "lua", "socket", "close", fd)
					connection[fd] = nil
				end
			else
				skynet.error("gate msg type:", typeid)
			end
		end
	end
}

skynet.start(function()
	skynet.dispatch("lua", function (_, address, cmd, ...)
		local f = assert(CMD[cmd])
		if f then
			skynet.ret(skynet.pack(f(address, ...)))
		end
	end)
end)
