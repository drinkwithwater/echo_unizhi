#!/data/data/com.termux/files/usr/bin/bash ./boot.sh
-- #!/bin/bash ./boot.sh

local skynet = require "skynet"

skynet.start(function()
	local tcp2kcp = skynet.newservice("tcp2kcp")
	skynet.call(tcp2kcp, "lua", "start", {
		port = tonumber(skynet.getenv("port"))
	})
	skynet.exit()
end)
