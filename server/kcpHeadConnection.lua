-- @author Chen Ze
require "oo"
local skynet = require "skynet"
local socket = require "testudp"
local UdpMessage = require "UdpMessage"

local KcpHeadConnection = class()

local socket_type = 2  -- type = 2 for kcp, type = 1 for tcp

local STATE_SYN_RCVD = 1
local STATE_ESTABLISHED = 2
local STATE_CLOSE = 3

local KCP_TIME_COE = 10 -- convert skynet.now() to kcp time (xxx ms)
local OFFLINE_TIMEOUT = 2000 -- 20s, no msg (include ping) for 60s will cause connection close..
local CONN_TIMEOUT = 300 -- 6s

local function udp_address(vFrom)
	--local _1, vPort = socket.udp_address(vFrom)
	local _, nPort, a,b,c,d= string.unpack(">HHBBBB", vFrom)
	local nIP = table.concat({a,b,c,d}, ".")
	local nAddr = nIP..":"..nPort
	return nAddr
end

-- [public]
function KcpHeadConnection:ctor(vUDPSocket, vWatchdog)
	self.mUDPSocket	=	vUDPSocket	-- udp socket
	self.mWatchdog  =	vWatchdog

	self.mFd		=	nil			-- the first tcp bind with, used as a udp fd
	self.mToken		=	nil			-- authorized token, also used as conv segments in kcp
	self.mFrom		=	nil			-- client's udp address

	self.mState		=	nil			-- wait/established/close

	self.mLastMsgTime	=	skynet.now()	-- time when receive latest message
	self.mStartTime	=	skynet.now()-- start time
end

-- [public], called after new()
function KcpHeadConnection:onOpen(vFd, vToken, vFrom, vBodyServer)
	self.mFd		=	vFd
	self.mToken		=	vToken
	self.mFrom		=	vFrom
	self.mBodyServer = vBodyServer

	self.mState		=	STATE_SYN_RCVD
	self:doUdpSend(UdpMessage.s2cSyn(vFd, vToken))
end

-- [private]
function KcpHeadConnection:onConnected()
	local nFd = self.mFd
	local nToken = self.mToken
	local nFrom = self.mFrom
	local nBodyServer = self.mBodyServer
	local nAddrStr = udp_address(nFrom)
	skynet.error("kcp connected:", nFd, nAddrStr)
	skynet.send(nBodyServer, "lua", "kcp", "open", nFd, nToken, nFrom)
	skynet.send(self.mWatchdog, "lua", "socket", "open", nFd, nAddrStr, nToken, nBodyServer)
end


-- [public], control message
function KcpHeadConnection:onUdpOper(vOper, vToken, vFrom)
	if self.mToken ~= vToken then
		skynet.error("udp:", self.mFd, " operudp with unexcept token")
		return
	end
	if self.mState == STATE_SYN_RCVD then
		if vOper == UdpMessage.C2S_ACK then -- client handshake ACK
			if self.mState==STATE_SYN_RCVD then
				self.mState = STATE_ESTABLISHED
				self:onConnected()
			end
			self:doUdpSend(UdpMessage.s2cAck(self.mFd, self.mToken))
		end
	elseif self.mState == STATE_ESTABLISHED then
		if vOper == UdpMessage.C2S_ACK then -- client handshake ACK
			self:doUdpSend(UdpMessage.s2cAck(self.mFd, self.mToken))
		elseif vOper == UdpMessage.C2S_PING then -- client ping
			-- TODO ping do not update msg time for vpn
			-- self.mLastMsgTime = skynet.now()
		end
	end
end

function KcpHeadConnection:checkFrom(vFrom)
	return self.mFrom == vFrom
end

-- [public], kcp input
function KcpHeadConnection:onInput(vToken, vPayload, vLen)
	if self.mToken == vToken and self.mState == STATE_ESTABLISHED then
		self.mLastMsgTime = skynet.now()
		skynet.redirect(self.mBodyServer, self.mFd, "socket", 0, vPayload, vLen)
		return true
	else
		local nAddr = udp_address(self.mFrom)
		skynet.error("udp:", self.mFd, " send with unexcept token")
		return false
	end
end

-- [public], send by udp
function KcpHeadConnection:doUdpSend(vBuf)
	socket.sendto(self.mUDPSocket, self.mFrom, vBuf)
end

-- [public]
function KcpHeadConnection:doClose()
	self.mState = STATE_CLOSE
end

-- [public], the functions below are called in update in udpserver
function KcpHeadConnection:onCheckClose(vTime)
	local nCurTime = vTime
	if self.mState == STATE_SYN_RCVD then
		local nConnTime = nCurTime-self.mStartTime
		if nConnTime>=CONN_TIMEOUT then
			-- close
			local nAddr = udp_address(self.mFrom)
			skynet.error("kcp client ", nAddr, " connect-timeout in fd=",self.mFd)
			return true
		else
			return false
		end
	elseif self.mState == STATE_ESTABLISHED then
		if nCurTime - self.mLastMsgTime > OFFLINE_TIMEOUT then
			local nAddr = udp_address(self.mFrom)
			skynet.error("kcp client from ", nAddr, " ping-timeout")
			return true
		else
			return false
		end
	elseif self.mState == STATE_CLOSE then
		return true
	end
end

function KcpHeadConnection:isEstablished()
	return self.mState == STATE_ESTABLISHED
end

function KcpHeadConnection.parseAddr(vFrom)
	return udp_address(vFrom)
end

return KcpHeadConnection
