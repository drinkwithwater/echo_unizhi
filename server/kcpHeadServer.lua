-- @author Chen Ze
local skynet = require "skynet"
-- use testudp.so instead of udp socket in skynet
local socket = require "testudp"
local KcpHeadConnection = require "kcpHeadConnection"
local UdpMessage = require "UdpMessage"

local socket_type = 2	-- 1 for tcp, 2 for kcp

local CMD = {}
local UDP_CMD = {}

-------------------------------------------------------------
-- 0 < fd < 2^30 -- TODO: deal with fd when fd >= 2^30
-------------------------------------------------------------
-- 0 <= oper < TOKEN_RANGE_MIN <= token <= TOKEN_RANGE_MAX --
-------------------------------------------------------------

-----------------------------------------
-- 客户端发送的消息格式 --
-----------------------------------------
-- syn  : | 0  | helloworld |
-----------------------------------------
-- oper : | fd | oper       |
-----------------------------------------
-- kcp  : | fd | token      |
-----------------------------------------

-----------------------------------------
-- 服务器端发送的消息格式 --
-----------------------------------------
-- oper : | oper       |
-----------------------------------------
-- kcp  : | token      |
-----------------------------------------

local TOKEN_RANGE_MIN = 0x10000000
local TOKEN_RANGE_MAX = 0x7fffffff

local MIN_PACKET_LEN = 12 -- length by bytes, drop smaller udp packet

local mUDPSocket -- udp server socket

local mFdToConn = {}  -- tcpfd -> connection

local mWatchdog = nil

local udpFdCounter = 1
local genFd=function()
	udpFdCounter = (udpFdCounter+1) % (1<<28)
	while(udpFdCounter==0 or mFdToConn[udpFdCounter]) do
		udpFdCounter = (udpFdCounter+1) % (1<<28)
	end
	return udpFdCounter
end

local UDP_WATCHDOG = nil

local mBodyServerList = {}
local BODY_SERVER_NUM = 4
local function getBodyServer(vFd)
	return mBodyServerList[vFd % BODY_SERVER_NUM + 1]
end

local LOOP_INTERVAL = 1					-- udp socket 以非阻塞方式recv message的间隔
local LOOP_UPDATE_INTERVAL = 50			-- 遍历mFdToConn检查是否连接成功或者pingtimeout的间隔

local mToughTime = 0 -- update when loop update, in order to reducing calling skynet.now()

skynet.register_protocol {
	name = "socket",
	id = skynet.PTYPE_SOCKET,
}

-- 使用skynet_malloc生成指针，减少拷贝次数
local SYN_I1, SYN_I2, SYN_I3 = string.unpack("<III", UdpMessage.c2sSyn())
local function udpdispatch_ptr(vLen, vPtr, vFrom)
	local nDoRedirect = false
	if vLen >= MIN_PACKET_LEN then
		local nFd, nParam1, nParam2 = socket.ptrunpack_littleIII(vPtr)
		local nConn = mFdToConn[nFd]
		-- 如果连接存在，直接让它处理message
		if nConn and nConn:checkFrom(vFrom) then
			if nParam1>= TOKEN_RANGE_MIN then
				nDoRedirect = nConn:onInput(nParam1, vPtr, vLen)
			elseif nParam1>=0 then
				nConn:onUdpOper(nParam1, nParam2, vFrom)
			end
		-- 如果连接不存在，并且是syn报文，直接新建连接
		elseif nFd == 0 then
			if nParam1 == SYN_I2 and nParam2 == SYN_I3 then
				local nNewFd = genFd()
				local nToken = math.random(TOKEN_RANGE_MIN, TOKEN_RANGE_MAX)
				local nNewConn = KcpHeadConnection.new(mUDPSocket, mWatchdog)
				nNewConn:onOpen(nNewFd, nToken, vFrom, getBodyServer(nNewFd))
				mFdToConn[nNewFd] = nNewConn
			end
		-- 如果连接不存在，且发送的是ping，则返回rst
		elseif nParam1 == UdpMessage.C2S_PING or nParam1 >= TOKEN_RANGE_MIN then
			socket.sendto(mUDPSocket, vFrom, UdpMessage.s2cRst(nFd))
		end
	end

	if not nDoRedirect then
		skynet.trash(vPtr, vLen);
	end
end

-- module init
function CMD.open(conf)
	local address = conf.address or "0.0.0.0"
	local port = assert(conf.port)

	mWatchdog = conf.watchdog
	mUDPSocket = socket.lcreate(port)
	for i=1, BODY_SERVER_NUM do
		local nBodyServer = skynet.newservice("kcpBodyServer")
		mBodyServerList[i] = nBodyServer
		skynet.call(nBodyServer, "lua", "start", skynet.self(), mUDPSocket, mWatchdog)
		if conf.clusterMode then
			skynet.call(nBodyServer, "lua", "useClusterMode")
		end
	end
	mToughTime = skynet.now()

	skynet.fork(function()
		local nUpdateRestTime = 0
		while(true) do
			local len, buffer, addr = socket.recvfrom_ptr(mUDPSocket)
			if len>0 then
				udpdispatch_ptr(len, buffer, addr)
			elseif len<=0 then
				if nUpdateRestTime <= 0 then
					mToughTime = skynet.now()
					local nRemoveFdList={}
					for nFd, nConn in pairs(mFdToConn) do
						if not nConn then
							nRemoveFdList[#nRemoveFdList + 1] = nFd
						elseif nConn:onCheckClose(mToughTime) then
							nRemoveFdList[#nRemoveFdList + 1] = nFd
						end
					end
					for _, fd in pairs(nRemoveFdList) do
						UDP_CMD.close(fd)
					end
					nUpdateRestTime = LOOP_UPDATE_INTERVAL
				else
					nUpdateRestTime = nUpdateRestTime - LOOP_INTERVAL
					skynet.sleep(LOOP_INTERVAL)
				end
			end
		end
	end)
end

function CMD.exit()
	if mUDPSocket then
		socket.close(mUDPSocket)
		mUDPSocket = nil
	end
end

function UDP_CMD.redirect(vFd, vPayload)
	local nBodyServer = getBodyServer(vFd)
	skynet.redirect(nBodyServer, vFd, "socket", 0, vPayload)
end

-- kcptimeout close
function UDP_CMD.close(vFd)
	local nConn = mFdToConn[vFd]
	if nConn then
		mFdToConn[vFd] = nil
		if nConn:isEstablished() then
			nConn:doClose()
			local nBodyServer = getBodyServer(vFd)
			skynet.send(nBodyServer, "lua", "kcp", "close", vFd)
			skynet.send(mWatchdog, "lua", "socket", "close", vFd, socket_type)
		end
	end
end

-- watchdog close
function CMD.kick(vFd)
	local nConn = mFdToConn[vFd]
	if nConn then
		mFdToConn[vFd] = nil
		nConn:doClose()
		local nBodyServer = getBodyServer(vFd)
		skynet.send(nBodyServer, "lua", "kcp", "close", vFd)
	end
end

function CMD.forward(vFd, vAgent)
	local nBodyServer = getBodyServer(vFd)
	skynet.send(nBodyServer, "lua", "forward", vFd, vAgent)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd=="udp" or cmd=="kcp" or cmd=="UDP" or cmd=="KCP" then
			local f = UDP_CMD[subcmd]
			if f then
				f(...)
			else
				skynet.error("error! unknown cmd:", cmd, subcmd, ...)
			end
			-- udp cmd not need ret
			-- skynet.ret(skynet.pack(f(...)))
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)
end)
