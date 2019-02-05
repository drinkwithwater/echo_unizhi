local skynet = require "skynet"
local soa = require "soa"
local sc = require "skynet.socketchannel"
local socket = require "skynet.socket"
local cluster = require "skynet.cluster.core"

local config_name = skynet.getenv "cluster"

local node_address = {}			-- node to ip:port
local node_session = {}			-- node to session id

local CMD = {}
local GM = {}
local REST = {}

local timeout_queue = {}

local mMultiGate = nil

local function read_response(sock)
	local sz = socket.header(sock:read(2))
	local msg = sock:read(sz)
	return cluster.unpackresponse(msg)	-- session, ok, data, padding
end

local function open_channel(t, key)
	local host, port = string.match(node_address[key], "([^:]+):(.*)$")
	local c = sc.channel {
		host = host,
		port = tonumber(port),
		response = read_response,
		nodelay = true,
	}
	t[key] = c
	assert(c:connect(true))
	return c
end

-- 不调用connect的channel打开方式
local function raw_open_channel(t, key)
	local host, port = string.match(node_address[key], "([^:]+):(.*)$")
	local c = sc.channel {
		host = host,
		port = tonumber(port),
		response = read_response,
		nodelay = true,
	}
	t[key] = c
	return c
end

local node_channel = setmetatable({}, { __index = open_channel })

local function loadconfig(tmp)
	if tmp == nil then
		tmp = {}
		if config_name then
			local f = assert(io.open(config_name))
			local source = f:read "*a"
			f:close()
			assert(load(source, "@"..config_name, "t", tmp))()
		end
	end
	for name,address in pairs(tmp) do
		assert(type(address) == "string")
		if node_address[name] ~= address then
			-- address changed
			if rawget(node_channel, name) then
				node_channel[name] = nil	-- reset connection
			end
			node_address[name] = address
		end
	end
end

function CMD.listen(addr, port)
	if port == nil then
		addr, port = string.match(node_address[addr], "([^:]+):(.*)$")
	end
	skynet.call(mMultiGate, "lua", "open", { address = addr, port = port })
	return nil
end

local function send_request(node, addr, msg, sz)
	local session = node_session[node] or 1
	-- msg is a local pointer, cluster.packrequest will free it
	local request, new_session, padding = cluster.packrequest(addr, session, msg, sz)
	node_session[node] = new_session

	-- node_channel[node] may yield or throw error
	local c = node_channel[node]

	return c:request(request, session, padding)
end

function CMD.req(...)
	local ok, msg, sz = pcall(send_request, ...)
	if ok then
		if type(msg) == "table" then
			skynet.ret(cluster.concat(msg))
		else
			skynet.ret(msg)
		end
	else
		-- skynet.error(msg)
		skynet.response()(false)
	end
end

function CMD.push(node, addr, msg, sz)
	local session = node_session[node] or 1
	local request, new_session, padding = cluster.packpush(addr, session, msg, sz)
	if padding then	-- is multi push
		node_session[node] = new_session
	end

	-- node_channel[node] may yield or throw error
	local c = node_channel[node]

	c:request(request, nil, padding)

	-- notice: push may fail where the channel is disconnected or broken.
end

local register_name = {}

function CMD.register(name, addr)
	assert(register_name[name] == nil)
	local old_name = register_name[addr]
	if old_name then
		register_name[old_name] = nil
	end
	register_name[addr] = name
	register_name[name] = addr
	skynet.error(string.format("Register [%s] :%08x", name, addr))
end

local large_request = {}

local SOCKET = {}

function SOCKET.warning(fd, msg)
	large_request[fd] = nil
	skynet.error(string.format("socket %s %d %s", "close", fd, msg or ""))
end
SOCKET.error = SOCKET.warning
SOCKET.close = SOCKET.warning

function SOCKET.data(fd, msg)
	local sz
	local addr, session, msg, padding, is_push = cluster.unpackrequest(msg)
	if padding then
		local requests = large_request[fd]
		if requests == nil then
			requests = {}
			large_request[fd] = requests
		end
		local req = requests[session] or { addr = addr , is_push = is_push }
		requests[session] = req
		table.insert(req, msg)
		return
	else
		local requests = large_request[fd]
		if requests then
			local req = requests[session]
			if req then
				requests[session] = nil
				table.insert(req, msg)
				msg,sz = cluster.concat(req)
				addr = req.addr
				is_push = req.is_push
			end
		end
		if not msg then
			local response = cluster.packresponse(session, false, "Invalid large req")
			socket.write(fd, response)
			return
		end
	end
	local ok, response
	if addr == 0 then
		local name = skynet.unpack(msg, sz)
		local addr = register_name[name]
		if addr then
			ok = true
			msg, sz = skynet.pack(addr)
		else
			ok = false
			msg = "name not found"
		end
	elseif is_push then
		skynet.rawsend(addr, "lua", msg, sz)
		return	-- no response
	else
		ok , msg, sz = pcall(skynet.rawcall, addr, "lua", msg, sz)
	end
	if ok then
		response = cluster.packresponse(session, true, msg, sz)
		if type(response) == "table" then
			for _, v in ipairs(response) do
				socket.lwrite(fd, v)
			end
		else
			socket.write(fd, response)
		end
	else
		response = cluster.packresponse(session, false, msg)
		socket.write(fd, response)
	end
end

function SOCKET.open(fd, addr)
	skynet.error(string.format("socket accept from %s", addr))
	skynet.call(mMultiGate, "lua", "accept", fd)
end

function CMD.reqx(reconn, sleeptime, node, addr, msg, sz)
	local session = node_session[node] or 1
	-- msg is a local pointer, cluster.packrequest will free it
	local request, new_session, padding = cluster.packrequest(addr, session, msg, sz)
	node_session[node] = new_session

	-- node_channel[node] may yield or throw error
	local c = rawget(node_channel, node)
	if not c then
		c = raw_open_channel(node_channel, node)
	end

	local ok, retMsg, retSize = nil, nil, nil
	if reconn then
		ok, retMsg, retSize = pcall(c.sleep_request, c, request, session, padding, sleeptime)
	else
		ok, retMsg, retSize = pcall(c.only_request, c, request, session, padding, sleeptime)
	end
	if ok then
		if type(msg) == "table" then
			skynet.ret(cluster.concat(retMsg))
		else
			skynet.ret(retMsg)
		end
	else
		-- skynet.error(retMsg)
		skynet.response()(false)
	end
end

-- reconn 如果断开了是否重新连接
-- sleeptime 调用等待时间
function CMD.pushx(reconn, sleeptime, node, addr, msg, sz)
	local session = node_session[node] or 1
	local request, new_session, padding = cluster.packpush(addr, session, msg, sz)
	if padding then	-- is multi push
		node_session[node] = new_session
	end

	-- node_channel[node] may yield or throw error
	local c = rawget(node_channel, node)
	if not c then
		c = raw_open_channel(node_channel, node)
	end

	-- c:request(request, nil, padding)

	local ok, ret = nil, nil
	if reconn then
		ok, ret = pcall(c.sleep_request, c, request, nil, padding, sleeptime)
	else
		ok, ret = pcall(c.only_request, c, request, nil, padding, sleeptime)
	end

end

-- for soa.cluster
local mUpdateAddressQueue = {}

function CMD.get(name)
	if not name then
		return node_address
	else
		return node_address[name]
	end
end

function CMD.addressWaitUpdate()
	local co = coroutine.running()
	mUpdateAddressQueue[#mUpdateAddressQueue + 1] = co
	skynet.wait(co)
	return node_address
end

function CMD.addressUpdate()
	for k, co in pairs(mUpdateAddressQueue) do
		skynet.wakeup(co)
	end
	mUpdateAddressQueue = {}
end


function REST.getAddress()
	return node_address
end

-- 添加remote地址
function REST.addAddress(vObj)
	if not vObj.name or not vObj.address then
		return {
			error = "param error"
		}
	end
	local name = vObj.name
	local address = vObj.address
	if not node_address[name] then
		node_address[name] = address
		CMD.addressUpdate()
	end
	return node_address
end

-- (强制)设置remote地址，会把对应的连接断开
function REST.setAddress(vObj)
	if not vObj.name or not vObj.address then
		return {
			error = "param error"
		}
	end
	local name = vObj.name
	local address = vObj.address
	if node_address[name] then
		if node_address[name] ~= address then
			-- address changed
			if rawget(node_channel, name) then
				node_channel[name] = nil	-- reset connection
			end
			CMD.addressUpdate()
		end
	end
	node_address[name] = address
	return node_address
end

function CMD.start()
end

function CMD.init(bootstrap)
	bootstrap.register("gm", GM)
	bootstrap.register("rest", REST)
	bootstrap.registerNoReturn("socket", SOCKET)

	bootstrap.setNoReturn("req")
	bootstrap.setNoReturn("reqx")
	bootstrap.setNoReturn("push")
	bootstrap.setNoReturn("pushx")

	loadconfig()

	mMultiGate = soa.uniqueservice("multigate")
	skynet.call(mMultiGate, "lua", "start", skynet.self())
end

function GM.get()
	local node_channel_data = {}
	for name, channel in pairs(node_channel) do
		if type(channel)=="table" then
			local channel_data = {}
			for k,v in pairs(channel) do
				local typev = type(v)
				if typev=="number" or typev=="boolean" or typev=="string" then
					channel_data[k] = v
				end
			end
			node_channel_data[name] = channel_data
		elseif type(channel) ~= "function" then
			node_channel_data[name] = channel
		end
	end
	return {
		node_address = node_address,
		node_channel_data = node_channel_data,
	}
end

return CMD
