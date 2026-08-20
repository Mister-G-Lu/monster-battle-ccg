local bit = require "bit"
local bit_lshift = bit.lshift
local bit_rshift = bit.rshift
local bit_band = bit.band
local bit_bor = bit.bor
local bit_bnot = bit.bnot

local bit_extension = {}

-- 设置标记位状态
-- @target 存储值
-- @tag 第几位
-- @flag 状态 true,false
function bit_extension:SetBitNum(target, tag, flag)
    tag = bit_lshift(1, tag)
    if flag then
        target = bit_bor(target, tag)
    else
        tag = bit_bnot(tag)
        target = bit_band(target, tag)
    end
    return target
end

-- 获取标志位置状态
-- @target 存储值
-- @tag 第几位
function bit_extension:GetBitNum(target, tag)
    local shift_value = bit_lshift(1, tag)
    local tag_num = bit_band(target, shift_value)
    return bit_rshift(tag_num, tag)
end


-- 验证标志位 源按位与目标等于目标
-- @src 源
-- @desc 目标
function bit_extension:CheckBitValue(src, desc)
    local value = bit_band(src, desc)
    return value == desc
end

return bit_extension
