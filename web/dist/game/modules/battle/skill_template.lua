local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"

local constants = require "common.constants"

local MAIN_POWER = constants.MAIN_POWER

local meta = class("skill_template",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/battle/card_battlefield_skill2_template.csb")
end)

function meta:ctor()
    local skill_template = self:getChildByName("skill_template")
    local icon_img = skill_template:getChildByName("icon")
    local num_txt = skill_template:getChildByName("value")
    local against_img = skill_template:getChildByName("against_icon")
    ui_helper:BindTimeLine(against_img, "interface/battle/skill1_against_tip.csb")


    if not icon_img then
        icon_img = skill_template
    end

    self.icon_img = icon_img
    self.num_txt = num_txt
    self.against_img = against_img

    against_img:setVisible(false)

    self.init_value = 0
    self.cur_value = 0

    self.value_map = {}
end

-- 设置禁用
function meta:SetAgainst(is_visible)
    if is_visible then
        self.against_img:setVisible(is_visible)
        self.against_img:PlayAnimation("enter")
    else
        self.against_img:PlayAnimation("exit", false, function()
            self.against_img:setVisible(false)
        end)
    end
end

-- 设置图标
function meta:SetIcon(icon_name)
    self.power_name = icon_name
    -- if MAIN_POWER[icon_name] == 1 then
    --     self.icon_img:loadTexture(resource:GetSkillIcon(icon_name))
    -- else
    self.icon_img:loadTexture(resource:GetSkillIcon(icon_name))
    -- end
end

-- 初始化数值
function meta:InitValue(attr_value)
    self.init_value = attr_value
    self.cur_value = attr_value
    self.value_map = {}
    self:PlayAnimation("enter")
    if attr_value == 0 then
        self.num_txt:setVisible(false)
    else
        self:setVisible(true)
        self.num_txt:setVisible(true)
        ui_helper:SetText(self.num_txt, attr_value * constants.BATTLE_VALUE_SCALE)
        self.num_txt:setColor(ui_helper:GetColor4B(0xFFFFFF))
    end
end

function meta:GetValue()
    local value = 0
    for k,v in pairs(self.value_map) do
        value = value + v
    end
    value = value + self.cur_value
    if value < 0 then
        value = 0
    end
    return value
end

-- 更新数值
function meta:PushValue(power_name, value)

    self.value_map[power_name] = value
    local cur_value = self:GetValue()

    if self.init_value < cur_value then
        -- 如果初始值>当前值，就改变颜色
        self.num_txt:setColor(ui_helper:GetColor4B(0xc6ff00))
    elseif self.init_value == cur_value then
        -- 如果初始值=当前值，就改变颜色
        self.num_txt:setColor(ui_helper:GetColor4B(0xFFFFFF))
    else
        -- 如果初始值<当前值，就改变颜色
        self.num_txt:setColor(ui_helper:GetColor4B(0xFC4444))
    end
    if not value then
        self.num_txt:setVisible(false)
        return
    end

    self.num_txt:setVisible(true)
    if value < 0 then
        self:PlayAnimation("num_down")
    elseif value > 0 then
        self:PlayAnimation("num_up")
    end

    ui_helper:SetText(self.num_txt, cur_value * constants.BATTLE_VALUE_SCALE)
end

return meta
