
local udp = require "udp"

local addr1 = udp.addr("127.0.0.1", 8000)

local addr2 = udp.addr("127.0.0.1", 8000)


local sth = {}

sth[addr1] = 1
sth[addr2] = 2
print(sth[addr1])
print(sth[addr2])

