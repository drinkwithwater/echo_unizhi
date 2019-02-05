local cjson  = require "cjson"
local skynet = require "skynet"
local snax = require "snax"
local soa = require "soa"
local socket = require "socket"
local httpd = require "http.httpd"
local sockethelper = require "http.sockethelper"
local urllib = require "http.url"
local webRouter = require "webRouter"
local table = table
local string = string

DEFAULT_HTTP_HEADER = {
	["Access-Control-Allow-Origin"] = "*"
}

local snaxMailManager = nil
local mode = ...
if mode == "agent" then
	local function response(id, ...)
		local ok, err = httpd.write_response(sockethelper.writefunc(id), ...)
		if not ok then
			-- if err == sockethelper.socket_error , that means socket closed.
			skynet.error(string.format("fd = %d, %s", id, err))
		end
	end

	-- mail
	local function webMail(vJsonParam)
		if vJsonParam == nil then
			return false, "no param"
		end
		local nSuccess, nJsonTable	= pcall(cjson.decode, vJsonParam)
		if nSuccess then
			snaxMailManager = snaxMailManager or soa.snaxuniqueservice("soaSnaxMailManager")
			-- for test...[[
			if nJsonTable.debug == 1 then
				local nResult = snaxMailManager.req.getBroadcastMail(tonumber(nJsonTable.lastQueryTime),tonumber(nJsonTable.thisQueryTime))
				return false, cjson.encode(nResult)
			elseif nJsonTable.debug == 2 then
				local nResult = snaxMailManager.req.getUnicastMail(tonumber(nJsonTable.playerID))
				return false, cjson.encode(nResult)
			end
			-- ]]
			local nOK, nError = snaxMailManager.req.createMail(nJsonTable)
			return nOK, nError
		else
			return false, "json parse error"
		end
	end

	skynet.start(function()
		skynet.dispatch("lua", function (_,_,id)
			socket.start(id)
			-- limit request body size to 8192 (you can pass nil to unlimit)
			local code, url, method, header, body = httpd.read_request(sockethelper.readfunc(id), 65536)
			if code then
				if code ~= 200 then
					response(id, code, nil, DEFAULT_HTTP_HEADER)
				else
					local responseText = "{error=\"nothing\"}"
					local path, query = urllib.parse(url)
					local q = nil
					if query then
						q = urllib.parse_query(query)
					end

					if path then
						local nOkay, nResult = webRouter[path](q, method, body)
						responseText = nResult
					end
					response(id, code, responseText, DEFAULT_HTTP_HEADER)
				end
			else
				if url == sockethelper.socket_error then
					skynet.error("socket closed")
				else
					skynet.error(url)
				end
			end
			socket.close(id)
		end)
	end)
else
	skynet.start(function()
		local agent = {}
		for i= 1, 10 do
			agent[i] = skynet.newservice(SERVICE_NAME, "agent")
		end
		local balance = 1
		local webport = tonumber(skynet.getenv("rest_port") or 9018) -- use a port hard to guess
		local id = socket.listen("0.0.0.0", webport)
		skynet.error("Listen web port "..webport)
		socket.start(id , function(id, addr)
			skynet.error(string.format("%s connected, pass it to agent :%08x", addr, agent[balance]))
			skynet.send(agent[balance], "lua", id)
			balance = balance + 1
			if balance > #agent then
				balance = 1
			end
		end)
	end)
end
