-- 特殊动作效果

local meta = {}

local action_list = {}

function meta:Init()
    action_list = {}
end

-- 范围随机
local function RangeRand(min, max)
    local rnd = math.random()
    return rnd * (max - min) + min
end

-- 创建震动效果
function meta:CreateShake(name, target, shake_time, shake_margin, callback)
    local action_info = action_list[name]
    if not action_info then
        action_info = {}
    end

    action_info.name = name
    action_info.target = target
    action_info.start_time = 0
    action_info.shake_time = shake_time
    action_info.shake_margin = shake_margin
    action_info.callback = callback
    action_list[name] = action_info
end

function meta:Update(elapsed_time)
    for action_name, action_info in pairs(action_list) do
        local rate = (action_info.shake_time - action_info.start_time) / action_info.shake_time
        if rate < 0 then
            rate = 0
            if action_info.callback then
                action_info.callback()
            end
            action_list[action_name] = nil
        end
        local shake_margin = action_info.shake_margin
        action_info.start_time = action_info.start_time + elapsed_time

        local rand_x = RangeRand(-shake_margin, shake_margin) * rate
        local rand_y = RangeRand(-shake_margin, shake_margin) * rate
        if action_info.target then
            action_info.target:setPosition(rand_x, rand_y)
        end
    end
end

return meta
