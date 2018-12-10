#!/bin/bash ./boot.sh
-- #!/data/data/com.termux/files/usr/bin/bash ./boot.sh

local skynet = require "skynet"

skynet.start(function()
	local tcp2kcp = skynet.newservice("tcp2kcp")
	skynet.call(tcp2kcp, "lua", "start", {
		port = tonumber(skynet.getenv("client_tcp_port")),
	})
	skynet.exit()
end)
