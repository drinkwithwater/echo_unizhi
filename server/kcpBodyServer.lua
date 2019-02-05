-- @author Chen Ze
local skynet = require "skynet"
-- use testudp.so instead of udp socket in skynet
local socket = require "testudp"
local PollKcp = require "pollkcp"
local UdpMessage = require "UdpMessage"

local socket_type = 2	-- 1 for tcp, 2 for kcp

local CMD = {}
local KCP_CMD = {}
local KCP_LOCAL = {}

local mHeadServer = nil
local mUDPSocket = nil -- udp server socket

local mFdToKcp = {}  -- tcpfd -> connection

local mFdToAgent = {}

local mWatchdog = nil

local mPoll = nil

-- receive from agent, send to kcp socket
skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
		-- return skynet.tostring(msg, sz)
		return msg, sz
	end,
	dispatch = function (vSession, vSource, vMsg, vSize)
		local nKcp = mFdToKcp[vSource]
		if nKcp then
			PollKcp.lkcp_send(nKcp, vMsg, vSize)
		else
			-- skynet.error("kcp connection not found when sending for fd=", vSource)
		end
	end
}

-- receive from socket, send to agent
skynet.register_protocol {
	name = "socket",
	id = skynet.PTYPE_SOCKET,
	unpack = function (msg, sz)
		return msg, sz
	end,
	dispatch = function (vSession, vFd, vMsg, vSize)
		local nKcp = mFdToKcp[vFd]
		if nKcp then
			-- args should be ptr
			PollKcp.lkcp_input_ptr4(nKcp, vMsg, vSize, skynet.now()*10)
			local nLen, nData = PollKcp.lkcp_recv(nKcp)
			while nLen > 0 do
				KCP_LOCAL.redirect(vFd, mFdToAgent[vFd], nData)
				nLen, nData = PollKcp.lkcp_recv(nKcp)
			end
		else
			skynet.error("kcp connection not found when recving for fd=", vFd)
		end
	end
}


-- create new connection
function KCP_CMD.open(vFd, vToken, vFrom)
	local nKcp = mPoll:openKcp(vFd, vToken, vFrom)
	mFdToKcp[vFd] = nKcp
end

function KCP_CMD.setAddr(vFd, vFrom)
	local nKcp = mFdToKcp[vFd]
	if nKcp then
		PollKcp.lkcp_setaddr(nKcp, vFrom)
		skynet.error("[WARNING] client's udp reset addr", vFd)
	end
end

-- kcptimeout close
function KCP_CMD.close(vFd)
	local nKcp = mFdToKcp[vFd]
	if nKcp then
		mPoll:closeKcp(nKcp)
		mFdToKcp[vFd] = nil
		mFdToAgent[vFd] = nil
	end
end

-- 本地kcp调用给agent发送数据
function KCP_LOCAL.redirect(vFd, vAgent, vMsg)
	if vAgent then
		skynet.redirect(vAgent, skynet.self(), "client", 0, vMsg, #vMsg)
	else
		skynet.send(mWatchdog, "lua", "socket", "data", vFd, vMsg, socket_type)
	end
end

-- 本地kcp调用给agent发送数据用户cluster模式
function KCP_LOCAL.send(vFd, vAgent, vMsg)
	if vAgent then
		skynet.send(vAgent, "lua", "recv", socket_type, vFd, vMsg)
	else
		skynet.send(mWatchdog, "lua", "socket", "data", vFd, vMsg, socket_type)
	end
end

-- 本地kcp调用关闭连接
function KCP_LOCAL.close(vFd)
	skynet.send(mHeadServer, "lua", "kcp", "close", vFd)
end

function CMD.forward(fd, agent)
	local nKcp = mFdToKcp[fd]
	if nKcp then
		mFdToAgent[fd] = agent
	else
		skynet.error("kcp connection not found when forwarding for fd=", fd)
	end
end

function CMD.tryForward(fd, agent)
	local nKcp = mFdToKcp[fd]
	if nKcp then
		mFdToAgent[fd] = agent
		return true
	else
		skynet.error("kcp connection not found when forwarding for fd=", fd)
		return false
	end
end

-- redirect的转发一般走 skynet.register_protocol {dispatch = function(...) ...end}
-- 但在该dispatch中调用cluster貌似会出bug？所以改成skynet.send的方式调用
function CMD.useClusterMode()
	KCP_LOCAL.redirect = KCP_LOCAL.send
end

function CMD.start(vHeadServer, vUDPSocket, vWatchdog)
	mHeadServer = vHeadServer
	mWatchdog = vWatchdog

	mPoll = PollKcp.lpoll_create(vUDPSocket)
	if mPoll.setWaitSendInit then
		mPoll:setWaitSendInit(150)
		mPoll:setWaitSendIncr(25)
	end

	skynet.fork(function()
		while(mPoll) do
			local nTime = skynet.now()
			mPoll:update(nTime*10)
			for nKcp, nFd, nEvent in mPoll.select, mPoll, nil do
				if nEvent < 0  then
					mFdToKcp[nFd] = nil
					mFdToAgent[nFd] = nil
					KCP_LOCAL.close(nFd)
				else
					local nLen, nData = PollKcp.lkcp_recv(nKcp)
					while nLen > 0 do
						KCP_LOCAL.redirect(nFd, mFdToAgent[nFd], nData)
						nLen, nData = PollKcp.lkcp_recv(nKcp)
					end
				end
			end
			skynet.sleep(3)
		end
	end)
end

function CMD.exit()
	mPoll = nil
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd=="kcp" then
			local f = assert(KCP_CMD[subcmd])
			f(...)
			-- skynet.ret(skynet.pack(f(...)))
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)
end)
