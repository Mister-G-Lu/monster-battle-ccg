local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"

local constants = require "common.constants"

local meta = class("property_template",function (node)
    return node
end)

function meta:ctor()
    local skill_template = self:getChildByName("skill_template")
    local icon_img = skill_template
    local num_txt = skill_template:getChildByName("value")

    self.icon_img = icon_img
    self.num_txt = num_txt
    self.skill_template = skill_template

    self.init_value = 0
    self.cur_value = 0

    ui_helper:BindTimeLine(self, "interface/battle/card_battlefield_skill1_template.csb")
end

-- 设置图标
function meta:SetIcon(icon_name)
    -- self.icon_img:loadTexture(resource:GetMainPowerImage(icon_name))
    if icon_name == "armor" then
        self.icon_img:loadTexture("ui/pic_card/armor_bg.png", ccui.TextureResType.plistType)
    else
        self.icon_img:loadTexture("ui/pic_card/hp_bg.png", ccui.TextureResType.plistType)
    end
end

-- 初始化数值
function meta:InitValue(attr_value)
    self.init_value = attr_value
    self.cur_value = attr_value
    if attr_value == 0 then
        self:setVisible(false)
    else
        self:setVisible(true)
        self:PlayAnimation("enter")
        self:UpdateValue(0)
    end
end

-- 设置数值
function meta:SetValue(new_value)
    self.cur_value = new_value
    if self.init_value < self.cur_value then
        -- 如果初始值>当前值，就改变颜色
        self.num_txt:setColor(ui_helper:GetColor4B(0xc6ff00))
    elseif self.init_value == self.cur_value then
        -- 如果初始值=当前值，就改变颜色
        self.num_txt:setColor(ui_helper:GetColor4B(0xFFFFFF))
    else
        -- 如果初始值<当前值，就改变颜色
        self.num_txt:setColor(ui_helper:GetColor4B(0xFC4444))
    end
    ui_helper:SetText(self.num_txt, self.cur_value * constants.BATTLE_VALUE_SCALE)
end

-- 更新数值
function meta:UpdateValue(new_value, is_overflow)
    local cur_value = self.cur_value + new_value
    if new_value > 0 and cur_value > self.init_value and not is_overflow then
        cur_value = self.init_value
    end

    self:SetValue(cur_value)

    if new_value < 0 then
        self:PlayAnimation("num_down")
    elseif new_value > 0 then
        self:PlayAnimation("num_up")
    end

    return cur_value <= 0
end

-- 设置数量
function meta:SetNum(num)
    num = num * constants.BATTLE_VALUE_SCALE
    if num > 0 then
        ui_helper:SetText(self.num_txt, num)
        self:PlayAnimation("enter")
        self:setVisible(true)
    else
        self:setVisible(false)
    end
end

-- 数值增加
function meta:AddNum(num)
    num = num * constants.BATTLE_VALUE_SCALE
    ui_helper:SetText(self.num_txt, num)
    self:PlayAnimation("num_up")
end

-- 数值减少
function meta:DelNum(num)
    num = num * constants.BATTLE_VALUE_SCALE
    ui_helper:SetText(self.num_txt, num)
    self:PlayAnimation("num_down")
end
return meta
