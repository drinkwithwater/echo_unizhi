-- @author Chen Ze
require "oo"
local PackKcp = require "packkcp"
local skynet = require "skynet"
local socket = require "testudp"
local UdpMessage = require "UdpMessage"

local KcpHeadConnection = class()

local socket_type = 2  -- type = 2 for kcp, type = 1 for tcp

local STATE_SYN_RCVD = 1
local STATE_ESTABLISHED = 2
local STATE_CLOSE = 3

local KCP_TIME_COE = 10 -- convert skynet.now() to kcp time (xxx ms)
local OFFLINE_TIMEOUT = 6000 -- 60s, no msg (include ping) for 60s will cause connection close..
local CONN_TIMEOUT = 600 -- 6s

local function udp_address(vFrom)
	--local _1, vPort = socket.udp_address(vFrom)
	local _, nPort, a,b,c,d= string.unpack(">HHBBBB", vFrom)
	local nIP = table.concat({a,b,c,d}, ".")
	local nAddr = nIP..":"..nPort
	return nAddr
end

-- [public]
function KcpHeadConnection:ctor(vUDPSocket, UDP_CMD)
	self.mUDPSocket	=	vUDPSocket	-- udp socket
	self.mCmd		=	UDP_CMD		-- api in service

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
	self:doUdpSend(vFrom, UdpMessage.s2cSyn(vFd, vToken))
end

-- [public], when udpserver recv message, vParam1 is token when kcp, vParam1&vParam2 are oper&token when udp
function KcpHeadConnection:onMessage(vParam1, vParam2, vStr, vFrom, vToughTime)
	if vParam1>=0 and vParam1<=100 then
		self:onUdpOper(vParam1, vParam2, vStr, vFrom, vToughTime)
	else
		self:onInput(vParam1, vStr, vToughTime)
	end
end

-- [private], udp oper except kcp message
function KcpHeadConnection:onUdpOper(vOper, vToken, vStr, vFrom, vToughTime)
	if self.mState == STATE_SYN_RCVD then
		if vOper == UdpMessage.C2S_ACK then -- client handshake ACK
			-- local _a, _b, _c, nMinrto, nMtu = UdpMessage.serverUnpack(vStr)
			if self.mToken == vToken then
				if self.mState==STATE_SYN_RCVD then
					self.mState = STATE_ESTABLISHED
					self.mCmd.connected(self.mFd, self.mToken, vFrom)
					skynet.error("kcp connected:", self.mFd, udp_address(vFrom))
				end
				self:doUdpSend(vFrom, UdpMessage.s2cAck(self.mFd, self.mToken))
			end
		end
	elseif self.mState == STATE_ESTABLISHED then
		if vOper == UdpMessage.C2S_ACK then -- client handshake ACK
			if self.mToken == vToken then
				self:doUdpSend(vFrom, UdpMessage.s2cAck(self.mFd, self.mToken))
			end
		elseif vOper == UdpMessage.C2S_PING then -- client ping
			if self.mToken == vToken then
				self.mLastMsgTime = vToughTime
			end
		end
	end
end

-- [private], kcp input
function KcpHeadConnection:onInput(vToken, vPayload, vToughTime)
	if self.mToken ~= vToken then
		local nAddr = udp_address(self.mFrom)
		--skynet.error("udp:", nAddr, " send with unexcept token")
	elseif self.mState == STATE_ESTABLISHED then
		self.mLastMsgTime = vToughTime
		self.mCmd.redirect(self.mFd, vPayload)
	end
end

-- [public], send by udp
function KcpHeadConnection:doUdpSend(vFrom, vBuf)
	self.mFrom = vFrom
	socket.sendto(self.mUDPSocket, vFrom, vBuf)
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
