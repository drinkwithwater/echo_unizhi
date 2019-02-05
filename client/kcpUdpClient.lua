require "oo"

local LKcp = require "lkcp"
-- local skynet = require "skynet"
local UdpMessage = require "UdpMessage"

local skynet = require "skynet"

local testudp = require "testudp"

local KcpUdpClient = class()

local STATE_DOWN = 0
local STATE_WAIT_SYN = 2
local STATE_WAIT_ACK = 3
local STATE_UP = 4

function KcpUdpClient:ctor(id, source, callback, closecallback)
	self.fd = testudp.lcreateclient()
	self.ip = nil
	self.port = nil
	self.state = STATE_DOWN

	self.serverFd = nil
	self.token = nil

	self.kcp = nil
	self.sendQueue = {}

	self.id = id
	self.source = source
	self.callback = callback
	self.closecallback = closecallback
	self.buffer = ""
	self.nextLen = 0
end

function KcpUdpClient:getFd()
	return self.serverFd,self.token
end

local num = 0
function KcpUdpClient:ping()
	if self.serverFd and self.token then
		num=num+1
		-- print("self.serverFd and self.token",num,self.serverFd , self.token)
		-- local pack = UdpMessage.c2sPing(self.serverFd,self.token)
		-- self:send(pack)
	end
end

function KcpUdpClient:update()
	if self.state == STATE_DOWN then
		return
	end
	local re, buffer = self:recv()
	if re >0 then
		if self.state ~= STATE_UP then
			local oper, serverFd, token = UdpMessage.serverUnpack(buffer)
			if oper == UdpMessage.S2C_SYN and self.state == STATE_WAIT_SYN then
				self.serverFd = serverFd
				self.token = token
				self.state = STATE_WAIT_ACK

				self.kcp = LKcp.lkcp_create(self.token, function(buf)
						self:send(string.pack("<i",self.serverFd)..buf)
					   end)
				self.kcp:lkcp_nodelay(1,10,2,1)
				self.kcp:lkcp_setmtu(1000)
				self.kcp:lkcp_setstream(1)
				self.kcp:lkcp_update(0)

			elseif oper == UdpMessage.S2C_ACK and self.state == STATE_WAIT_ACK then
				self.state = STATE_UP
				skynet.error("kcp connected fd=", self.id)
			elseif oper == UdpMessage.S2C_RST and serverFd == self.serverFd then
				self.closecallback(self.id)
				skynet.error("kcp disconnect connected fd=", self.id)
				return
			end
		end
	end

	if self.state == STATE_WAIT_SYN then
		self:send(UdpMessage.c2sSyn())
	elseif self.state == STATE_WAIT_ACK then
		self:send(UdpMessage.c2sAck(self.serverFd, self.token))
	elseif self.state == STATE_UP then
		for k,v in pairs(self.sendQueue) do
			self.kcp:lkcp_send(v)
		end
		self.sendQueue = {}


		while re>0 do
			self.kcp:lkcp_input(buffer)
			self.kcp:lkcp_update(skynet.now()*10)
			local len, data = self.kcp:lkcp_recv()
			if len > 0 then
				local nOkay, nData = self:unpackMessage(data)
				if self.callback then
					if nOkay then
						self.callback(self.id, self.source, nData)
					end
				else
					skynet.error("kcpUdpClient's callback function not setted...")
				end
			end
			re, buffer = self:recv()
		end
		local len, data = self.kcp:lkcp_recv()
		while len > 0 do
			local nOkay, nData = self:unpackMessage(data)
			if self.callback then
				if nOkay then
					self.callback(self.id, self.source, nData)
				end
			else
				skynet.error("kcpUdpClient's callback function not setted...")
			end
			len, data = self.kcp:lkcp_recv()
		end
		local nOkay, nData = self:unpackMessage("")
		while(nOkay) do
			if self.callback then
				self.callback(self.id, self.source, nData)
			else
				skynet.error("kcpUdpClient's callback function not setted...")
			end
			nOkay, nData = self:unpackMessage("")
		end
		self.kcp:lkcp_update(skynet.now()*10)
		--[[local waitsnd = self.kcp:lkcp_waitsnd()
		if waitsnd > 40 then
			self.closecallback(self.id)
			skynet.error("kcp disconnect connected fd=", self.id)
			return
		end]]
	end

end

function KcpUdpClient:connect(ip, port)
	self.ip = ip
	self.port = port
	self.state = STATE_WAIT_SYN
end

function KcpUdpClient:kcpSend(buffer)
	if self.kcp then
		self.kcp:lkcp_send(buffer)
		self.kcp:lkcp_flush()
	else
		self.sendQueue[#self.sendQueue + 1] = buffer
	end
end

function KcpUdpClient:send(buffer)
	return testudp.sendtoipport(self.fd, buffer, self.ip, self.port)
end

function KcpUdpClient:recv()
	return testudp.recvfrom(self.fd)
end

function KcpUdpClient:unpackMessage(vMsg)
	local buffer = (self.buffer or "")..vMsg
	if #buffer<2 then
		self.buffer = buffer
		return false
	else
		-- skynet use 2 byte to indicate the packat size
		local nLen = string.unpack(">H", buffer)
		if #buffer>=nLen+2 then
			local nRet = buffer:sub(3,nLen+2)
			local nLeft = buffer:sub(nLen+3)
			self.buffer = nLeft
			return true, nRet
		else
			self.buffer = buffer
			return false
		end
	end
end

function KcpUdpClient:destroy()
	testudp.close(self.fd)
end

return KcpUdpClient
