-- http://blog.codingnow.com/cloud/LuaOO
local _class={}
function class(super)
    local class_type={}
    class_type.ctor=false
	if _class[super] then
		class_type.super=super
	else
		-- print("[warning!!!] a class's super not exist")
	end
	class_type.static={}
    class_type.new=function(...)
            local obj={}
            setmetatable(obj,{ __index=_class[class_type] })
            do
                local create
                create = function(c,...)
                    if c.super then
                        create(c.super,...)
                    end
                    if c.ctor then
                        c.ctor(obj,...)
                    end
                end

                create(class_type,...)
            end

            -- 加一个标记
            -- obj.mIsClass = true
            return obj
        end
	class_type.bindFunction=function(obj, recursive)
		if recursive then
			function loopBind(tableObj)
				for key,valueObj in pairs(tableObj) do
					if type(valueObj) == "table" then
						local classFile = valueObj.mFileName
						if classFile then
							require(classFile).bindFunction(valueObj, recursive)
						end
						loopBind(valueObj)
					end
				end
			end
			loopBind(obj)
		end
		return setmetatable(obj,{ __index=_class[class_type] })
	end
    local vtbl={}
    _class[class_type]=vtbl

    setmetatable(class_type,{__newindex=
        function(t,k,v)
			if type(v) == "function" then
				vtbl[k]=v
				class_type.static[k]=v
			else
				class_type.static[k]=v
			end
        end,
		__index=class_type.static
    })

    if super then
        setmetatable(vtbl,{__index=
            function(t,k)
                local ret=_class[super][k]
                vtbl[k]=ret
                return ret
            end
        })
    end

    return class_type
end
