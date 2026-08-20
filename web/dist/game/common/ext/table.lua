
-- 拓展元数据
table.extend = function(src_table, metadata, update_event)
    setmetatable(src_table,{
        __index = function (t, k)
            return metadata[k]
        end,
        __newindex = function (t, k, v)
            if type(v) == "function" then
                rawset(t, k, v)
            else
                metadata[k] = v
                if update_event then
                    update_event(k,v)
                end
            end
        end,
        __pairs = function (t) return pairs(metadata) end
    })
end

-- 创建新的对象并且拓展元表
table.new = function (src_table, metadata, update_event)
    local new_data = {}
    table.extend(new_data, metadata, update_event)
    local base = {src_table, new_data}
    return setmetatable({}, {
        __index = function (t,k)
            for i,supper in ipairs(base) do
                local ret = supper[k]
                if ret then
                    return ret
                end
            end
            return rawget(t, k)
        end,
        __newindex = function (t, k, v)
            for i,supper in ipairs(base) do
                local ret = supper[k]
                if ret then
                    new_data[k] = v
                    return
                end
            end
            rawset(t, k, v)
        end
    })
end

-- table追加
-- @dest 追到哪里
-- @src 谁追加
table.append = function (dest, src)
    -- print(">>xxxxxxxxxxxxxxx<<<")
    -- print("dest = "..tostring(dest))
    -- print("src = "..tostring(src))
    for k,v in pairs(src) do
        table.insert(dest, v)
    end
    -- print("dest = "..tostring(dest))

end

-- 返回table大小
-- @t tabel
table.size = function(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- 删除这个值
table.remove_arrays = function (t, value)
    -- list结果。删除必须从后向前删除
    for i = #t, 1, -1 do
        local v = t[i]
        if v == value then
            table.remove(t, i)
        end
    end
end

-- 判断table是否为空
table.empty = function(t)
    return not next(t)
end

-- 返回table索引列表
table.indices = function(t)
    local result = {}
    for k, v in pairs(t) do
        table.insert(result, k)
    end
    return result
end

-- 返回table值列表
table.values = function(t)
    local result = {}
    for k, v in pairs(t) do
        table.insert(result, v)
    end
    return result
end

-- 浅拷贝
table.clone = function(t)
    local result = {}

    for k, v in pairs (t) do
        result[k] = v
    end
    return result
end

-- 深拷贝
table.copy = function(t)
    local result = {}

    for k, v in pairs(t) do
        if type(v) == "table" then
            result[k] = table.copy(v)
        else
            result[k] = v
        end
    end
    return result
end

-- 合并
-- @dest 目标
-- @src 源
table.merge = function(dest, src)
    if not dest or not src then
        return
    end
    for k, v in pairs(src) do
        dest[k] = v
    end
end
