
local skynet = require "skynet"
local tcp = require "socket"
local KcpUdpClient = require "kcpUdpClient"

local SOCKET_TCP = 1
local SOCKET_KCP = 2

local CMD = {}
local GM = {}
local KCP = {}
local SOCKET = {}
local gate

local kcpAgent = {}
local tcpAgent = {}

local TOKEN_RANGE_MIN = 0x10000000
local TOKEN_RANGE_MAX = 0x7fffffff

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local kcp_ip = skynet.getenv("middle_kcp_ip")
local kcp_port = tonumber(skynet.getenv("middle_kcp_port"))

local kcpCounter = 1

-- 关闭agent, fromAgent表示该命令是由agent触发
local function close_agent(tcpfd)
	local agent = tcpAgent[tcpfd]
	if agent then
		agent.kcpClient:destroy()
		tcpAgent[tcpfd] = nil
		kcpAgent[agent.kcpfd] = nil
	end
end

function KCP.onClose(kcpfd)
	local agent = kcpAgent[kcpfd]
	if agent then
		skynet.send(gate, "lua", "kick", agent.tcp_fd)
		close_agent(agent.tcp_fd)
	end
end

function KCP.onMessage(kcpfd, source, data)
	local agent = kcpAgent[kcpfd]
	if agent then
		tcp.write(agent.tcpfd, data)
	end
end

------------ socket 接口，由gate service调用 f{{{ -----------------
function SOCKET.open(tcpfd, addr)
	skynet.error("New tcp client from : " .. addr.." fd="..tcpfd)
	-- add kcp
	kcpCounter = kcpCounter + 1
	local kcpfd = kcpCounter
	local agent = {
		kcpfd = kcpfd,
		tcpfd = tcpfd,
		addr = addr,
		buffer_list = {},
		kcpClient = KcpUdpClient.new(kcpfd, 0, KCP.onMessage, KCP.onClose),
	}
	agent.kcpClient:connect(kcp_ip, kcp_port)
	tcpAgent[tcpfd] = agent
	kcpAgent[kcpfd] = agent
end

function SOCKET.close(fd)
	skynet.error("tcp socket close",fd)
	close_agent(fd)
end

function SOCKET.error(fd, msg, socket_type)
	skynet.error("tcp socket error", fd, msg)
	close_agent(fd)
end

function SOCKET.warning(fd, size)
	skynet.error("tcp socket warning", fd, msg)
end

function SOCKET.data(tcpfd, msg)
	local agent = tcpAgent[tcpfd]
	if agent then
		msg = string.pack(">s2", msg)
		agent.kcpClient:kcpSend(msg)
	end
end

---------------------- f}}} ----------------------------

function CMD.start()
	gate = skynet.newservice("naivegate")
	skynet.call(gate, "lua", "open" , {
		port = tonumber(skynet.getenv("client_tcp_port")),
	})
	skynet.fork(function()
		while(true) do
			for k, agent in pairs(kcpAgent) do
				agent.kcpClient:update()
			end
			skynet.sleep(1)
		end
	end)
end

function CMD.init(bootstrap)
	bootstrap.registerNoReturn("socket", SOCKET)
	bootstrap.register("gm", GM)
end

function GM.get()
	return {
		kcpAgent = kcpAgent,
		tcpAgent = tcpAgent,
	}
end

return CMD
