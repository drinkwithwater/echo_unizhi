local zlib = require "zlib"
local crypt = require "client.crypt"
local lpeg = require "lpeg"
local cjson = require "cjson"

local url_key_base = skynet.getenv("url_key_base") or "yesyesyes"
local function combine(rootToUrlDict)
	local reDict = {}
	for urlRoot, dict in pairs(rootToUrlDict) do
		for urlNode, resFile in pairs(dict) do
			reDict[urlRoot..urlNode] = resFile
		end
	end
	return reDict
end
local urlDict = combine({
	[""] = {
	},
	-- for gmserver and payserver and debug
	[url_key_base] = {

		["/soa"] = "web/soaResource",
		["/soa/<String>"] = "web/soaResource",
		["/soa/<String>/<String>"] = "web/soaResource",
		["/soa/<Number>"] = "web/soaResource",
		["/soa/<Number>/<String>"] = "web/soaResource",

		-- /rest/module/method?key=value
		["/rest/<String>/<String>"] = "web/restResource",
	},
})

local TypePatternDict = {
	["<Number>"] = function ()
		return lpeg.C(
			lpeg.R("09")^1 +
			( lpeg.S"0" * lpeg.S"xX" * lpeg.R"09" ^ 1)
		)/tonumber
	end,
	["<String>"] = function()
		return lpeg.C(
			(lpeg.S"_" + lpeg.R"az" + lpeg.R"AZ")*
			(lpeg.P(1) - lpeg.S"/")^0
		)/tostring
	end,
}

local GlobalPattern = nil


local function createGlobalPattern()
	GlobalPattern = nil
	for nUrl, nResource in pairs(urlDict) do
		local nThisPattern = lpeg.P(true)
		for nTypeOrStr in string.gmatch(nUrl, "[^/]+") do
			if nTypeOrStr ~= "" then
				nThisPattern = nThisPattern*lpeg.S("/")
				if TypePatternDict[nTypeOrStr] then
					nThisPattern = nThisPattern * TypePatternDict[nTypeOrStr]()
				else
					nThisPattern = nThisPattern * lpeg.P(nTypeOrStr)
				end
			end
		end
		local function withResource(...)
			return nResource, ...
		end
		nThisPattern = lpeg.C(nThisPattern)/withResource * lpeg.P(-1)
		if not GlobalPattern then
			GlobalPattern = nThisPattern
		else
			GlobalPattern = GlobalPattern + nThisPattern
		end
	end

	return GlobalPattern
end

GlobalPattern = createGlobalPattern()

local function serialize(obj)
    local getIndent, quoteStr, wrapKey, wrapVal, dumpObj
    getIndent = function(level)
        return string.rep(" ", level)
    end
    quoteStr = function(str)
        return '"' .. string.gsub(str, '"', '\\"') .. '"'
    end
    wrapKey = function(val)
        if type(val) == "number" then
            return "[" .. val .. "]"
        elseif type(val) == "string" then
            return "[" .. quoteStr(val) .. "]"
        else
            return "[" .. tostring(val) .. "]"
        end
    end
    wrapVal = function(val, level)
        if type(val) == "table" then
            return dumpObj(val, level)
        elseif type(val) == "number" then
            return val
        elseif type(val) == "string" then
            return quoteStr(val)
        else
            return tostring(val)
        end
    end
    dumpObj = function(obj, level)
        if type(obj) ~= "table" then
            return wrapVal(obj)
        end
        level = level + 1
        local tokens = {}
        tokens[#tokens + 1] = "{"
        for k, v in pairs(obj) do
            tokens[#tokens + 1] = getIndent(level) .. wrapKey(k) .. " = " .. wrapVal(v, level) .. ","
        end
        tokens[#tokens + 1] = getIndent(level - 1) .. "}"
        return table.concat(tokens, "\n")
    end
    return dumpObj(obj, 0)
end

local template = require "web.template"
local function htmlFormat(buffer)
	--buffer = buffer:gsub("{[\n]*","{<input type=\"button\" value=\"...\"></input><span>\n")
	--buffer = buffer:gsub("}[,]*[\n]*","</span>},\n")
	--buffer = buffer:gsub("\n","<br/>")
	buffer = buffer:gsub("\n","|")
	buffer = buffer:gsub(" ","?")

	local temp = zlib.deflate(8)(buffer, "finish")
	buffer = "}"..crypt.base64encode(temp)

	return template:format("<div id=\"info\">"..buffer.."</div>")
end

local function recordInject(vUrl, queryObj)
	if queryObj and queryObj.inject then
		local fileName = "inject/"..os.date("%y-%m-%d")..".lua"
		local fileOpen = io.open(fileName,"a")
		fileOpen:write("--")
		fileOpen:write(vUrl)
		fileOpen:write(os.date(" [%H:%M:%S]"))
		fileOpen:write("\n")
		fileOpen:write(queryObj.inject)
		fileOpen:write("\n")
		fileOpen:flush()
		fileOpen:close()
	end
end

local router = setmetatable({serialize = serialize}, {__index=function(t, vUrl)
	return function(queryObj, method, postBody)
		recordInject(vUrl, queryObj)

		local urlResource, urlValue, arg1, arg2, arg3 = lpeg.match(GlobalPattern, vUrl)

		-- sg.logError(urlResource, urlValue, arg1, arg2, arg3)

		-- 定位到对应resource并处理&返回
		if urlResource then
			local nPackage = require(urlResource)
			if type(nPackage)=="function" then
				local nOkay, nResult
				if method == "POST" then
					local nPost = nPackage(arg1, arg2, arg3).post
					if nPost then
						nOkay, nResult = nPost(queryObj, postBody)
					else
						nOkay, nResult = false, cjson.encode({
							error="405 method not allow"
						})
					end
				else
					nOkay, nResult = nPackage(arg1, arg2, arg3).get(queryObj)
				end
				-- table类格式化，其它类直接tostring
				if nOkay and type(nResult)=="table" then
					return nOkay, htmlFormat(serialize(nResult))
				else
					return nOkay, tostring(nResult)
				end
			elseif type(nPackage) == "string" then
				return true, nPackage
			else
				return false, cjson.encode({
					error = "500 resource logic error : ".. urlResource
				})
			end
		else
			return false, "{\"error\"=\"404 not found\"}"
		end
	end
end})

return router
