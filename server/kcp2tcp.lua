local skynet = require "skynet"
local tcp = require "socket"

local SOCKET_TCP = 1
local SOCKET_KCP = 2

local CMD = {}
local SOCKET = {}
local udpserver					-- Actually, this is udp gate

local kcpAgent = {}
local tcpAgent = {}

local TOKEN_RANGE_MIN = 0x10000000
local TOKEN_RANGE_MAX = 0x7fffffff

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
}

local tcp_ip = skynet.getenv("server_tcp_ip")
local tcp_port = tonumber(skynet.getenv("server_tcp_port"))

-- 关闭agent, fromAgent表示该命令是由agent触发
local function close_agent(kcpfd)
	local agent = kcpAgent[kcpfd]
	if agent then
		local tcpfd = agent.tcpfd
		if tcpfd then
			tcp.close(tcpfd)
			tcpAgent[tcpfd] = nil
		end
		kcpAgent[kcpfd] = nil
	end
end

------------ socket 接口，由gate service调用 f{{{ -----------------
function SOCKET.open(kcpfd, addr, token, kcp_sender)
	skynet.error("New kcp client from : " .. addr.." fd="..kcpfd)
	local agent = {
		token = token,
		kcpfd = kcpfd,
		tcpfd = nil,
		addr = addr,
		kcp_sender = kcp_sender,
		buffer_list = {},
	}
	kcpAgent[kcpfd] = agent
	local tcpfd = tcp.open(tcp_ip, tcp_port)
	agent.tcpfd = tcpfd
	tcpAgent[tcpfd] = agent
	for k, buffer in ipairs(agent.buffer_list) do
		tcp.write(tcpfd, buffer)
	end
	while true do
		local ret, err = tcp.read(tcpfd)
		if not ret then
			break
		else
			local buffer = string.pack(">s2", ret)
			skynet.redirect(agent.kcp_sender, kcpfd, "client", 0, buffer)
		end
	end
end

function SOCKET.close(kcpfd)
	skynet.error("kcp socket close",kcpfd)
	close_agent(kcpfd)
end

function SOCKET.error(kcpfd, msg, socket_type)
	skynet.error("kcp socket error", kcpfd, msg)
	close_agent(kcpfd)
end

function SOCKET.warning(kcpfd, size)
	skynet.error("kcp socket warning", kcpfd, size)
end

function SOCKET.data(kcpfd, msg, socket_type)
	local agent = kcpAgent[kcpfd]
	if agent then
		local tcpfd = agent.tcpfd
		if tcpfd then
			tcp.write(tcpfd, msg)
		else
			table.insert(agent.buffer_list, msg)
		end
	end
end

---------------------- f}}} ----------------------------

function CMD.start(conf)
	-- udpserver do not get watchdog's address by dispatch... set it in conf
	conf.watchdog = skynet.self()
	skynet.call(udpserver, "lua", "open" , conf)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
			-- socket api don't need return
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	udpserver = skynet.newservice("kcpHeadServer")
end)
