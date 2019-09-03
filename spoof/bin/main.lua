
local udp = require "udp"
local spoof = require "spoof"

local mSpoofSocket = spoof.create()

local mLocalSocket = udp.create_server(12306)

local mRemoteAddr = udp.addr("54.180.49.100", 10085)
-- local mSpoofAddr = udp.addr("39.105.154.204", 10086)
local mSpoofAddr = udp.addr("127.0.0.1", 10000)

local TIME_OUT = 10

--[[
interface Pair
	client_addr = Addr
	spoof_addr = Addr
	fd = integer
	time = 0
end
]]

local mClientToPair = {} --
local mFdToPair = {}

local function accept()
	local nNow = os.time()
	while true do
		local nAddr, nBuffer = udp.recvfrom(mLocalSocket)
		if not nAddr then
			break
		end
		local nAddrStr = tostring(nAddr)
		local nPair = mClientToPair[nAddrStr]
		if not nPair then
			local nFd = udp.create_client()
			nPair = {
				client_addr = nAddr,
				spoof_addr = mSpoofAddr,
				--spoof_addr = udp.addr(mRemoteAddr.ip, mRemoteAddr.port),
				fd = nFd,
				time = nNow
			}
			mClientToPair[nAddrStr] = nPair
			mFdToPair[nFd] = nPair
			print("spoof", nAddrStr, nFd)
		else
			nPair.time = nNow
		end
		-- print("from client:", #nBuffer)
		udp.sendto(nPair.fd, mRemoteAddr, nBuffer)
	end
end

local function update()
	local nNow = os.time()
	local nDeletePairList = {}
	for nFd, nPair in pairs(mFdToPair) do
		while true do
			local nAddr, nBuffer = udp.recvfrom(nFd)
			if nAddr then
				-- print("from server:", #nBuffer)
				spoof.sendspoof(mSpoofSocket, nPair.spoof_addr, nPair.client_addr, nBuffer)
				nPair.time = nNow
			else
				-- TODO check timeout
				if nNow - nPair.time >= TIME_OUT then
					nDeletePairList[#nDeletePairList + 1] = nPair
				end
				break
			end
		end
	end
	for i=1, #nDeletePairList do
		local nPair = nDeletePairList[i]
		udp.close(nPair.fd)
		mFdToPair[nPair.fd] = nil
		mClientToPair[tostring(nPair.client_addr)] = nil
	end
end

print("spoof", mSpoofAddr)
while true do
	accept()
	update()
	udp.usleep(5000)
end
