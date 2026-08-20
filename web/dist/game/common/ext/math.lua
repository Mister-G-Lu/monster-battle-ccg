-- 取整数，四舍五入
function math.round(num)
    return math.floor(num + 0.5)
end

-- 随机种子
function math.randseed()
    math.randomseed(os.time())
end

-- 随机list
function math.randlist(list)
    local len = #list
    if len == 0 then
        return nil
    end
    return list[math.random(len)]
end
