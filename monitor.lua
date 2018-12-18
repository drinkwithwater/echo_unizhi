#!/bin/bash ./boot.sh
-- #!/data/data/com.termux/files/usr/bin/bash ./boot.sh

local skynet = require "skynet"

skynet.start(function()
	local redis = require "skynet.db.redis"
	mRedis = redis.connect({
		host = "192.168.5.126",
		port = 6379 ,
		db = 0,
		auth = nil,
	})
	mRedis:zadd("wom_servers", 0.0, "192.168.5.201")
	mRedis:disconnect()
end)
