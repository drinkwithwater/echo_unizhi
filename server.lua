#!/data/data/com.termux/files/usr/bin/bash ./boot.sh
-- #!/bin/bash ./boot.sh

local skynet = require "skynet"

skynet.start(function()
	local kcp2tcp = skynet.newservice("kcp2tcp")
	skynet.call(kcp2tcp, "lua", "start", {
		port = tonumber(skynet.getenv("middle_kcp_port"))
	})
	skynet.exit()
end)
