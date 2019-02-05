#!/bin/bash ./boot.sh
-- #!/data/data/com.termux/files/usr/bin/bash ./boot.sh

local skynet = require "skynet"
local soa = require "soa"

skynet.start(function()
	skynet.uniqueservice("soaRestServer")
	local tcp2kcp = soa.uniqueservice("tcp2kcp")
	skynet.call(tcp2kcp, "lua", "start")
	skynet.exit()
end)
