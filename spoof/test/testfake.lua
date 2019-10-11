

local udp = require "udp"


local spoof = require "spoof"

local spoofFd = spoof.create()


local src = udp.addr("127.0.0.1", 8080)
local dst = udp.addr("127.0.0.1", 12306)

print(spoofFd, src, dst)

spoof.sendspoof(spoofFd, src, dst, "fdsfds")

spoof.close(spoofFd)

--[[

local serverFd = udp.create_server(12306)
while true do
	udp.usleep(10000)
	local addr, data = udp.recvfrom(serverFd)
	if addr then
		spoof.send(spoofFd,)
	end
end

]]
