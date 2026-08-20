local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local graphic = require "manager.graphic"
local defines = require "manager.defines"

local battle_logic = require "logic.battle"
local text_loader = require "manager.text_loader"
local data_template = require "manager.data_template"
local POWER_CONFIG_MAP = data_template.power_config
local card_hand_item = require "modules.common.card_hand_item"
local TAB_TYPE = defines.DECK_TAB_TYPE

local skill_item = class("card_detail_item", function (node)
    return node
end)

function skill_item:ctor()

    self.icon_img = self:getChildByName("icon")
    self.name_txt = self:getChildByName("name")
    self.detail_txt = self:getChildByName("detail")

    self.src_desc_size = self.detail_txt:getContentSize()
    local render = self.detail_txt:getVirtualRenderer()
    render:setDimensions(self.src_desc_size.width, 0)
end

function skill_item:Show(power)

    self.src_desc_size = self.detail_txt:getContentSize()
    local render = self.detail_txt:getVirtualRenderer()
    render:setDimensions(self.src_desc_size.width, 0)
    self:setVisible(true)
    local height = 0
    local config = POWER_CONFIG_MAP[power.name]
    self.icon_img:loadTexture(resource:GetSkillIcon(power.name))
    ui_helper:SetText(self.name_txt, config.name_desc)
    local new_size = self.icon_img:getContentSize()
    height = new_size.height

    local render = self.detail_txt:getVirtualRenderer()
    ui_helper:SetText(self.detail_txt, config.info_desc)
    local new_size = render:getContentSize()
    self.detail_txt:setContentSize(new_size)
    height = height + new_size.height
    return height
end
function skill_item:Hide()
    self:setVisible(false)
end

function skill_item:GetHeight()
    return self.height
end

local meta = class("pve_card_detail_panel",function (node)
    ui_helper:BindTimeLine(node, "interface/battle/battle_ui_handcard_detail_panel.csb")
    return node
end)


-- 延迟出现时间
local DELAY_TIME = 0.3
local font_height = 24
local old_transform = {}
function meta:ctor()

    self:setVisible(false)
    self.is_show = false
    self.time_count = DELAY_TIME
    --卡牌信息
    -- 技能信息
    local skill_info = self:getChildByName("skill_info")
    local card = self:getChildByName("card")
    card:setVisible(false)
    skill_info:setVisible(false)
    local power_item_node_list = {}
    for i = 1, 3 do
        local item = skill_item.new(skill_info:getChildByName("skill_template"..i))
        item:setVisible(false)
        power_item_node_list[i] = item
    end
    self.skill_info = skill_info
    self.power_item_node_list = power_item_node_list

    self.card = self:getChildByName("card")
    ui_helper:BindTimeLine(self.card, "interface/battle/battle_hand_card.csb")

    self:RegisterEvent()
end

function meta:Show()
    if not self.show_info then
        return
    end
    local power_list = self.show_info.power_list
    if power_list then

        local height = 0
        local index = 0
        for i = 1, 3 do
            local power = power_list[i]
            local item = self.power_item_node_list[i]
            if power then
                height = height + item:Show(power)
                item:setPositionY(height)
                index = index + 1
            else
                item:Hide()
            end
        end
        self.skill_info:setContentSize({width = 620, height = height + index * 4 +20})

        if index ~= 0 then
            local function callback()
                self.skill_info:setVisible(true)
               self:PlayAnimation("enter_detail")
            end
            local delay = cc.DelayTime:create(self.time_count)
            local sequence = cc.Sequence:create(delay, cc.CallFunc:create(callback))
            self:runAction(sequence)
        else
            self.skill_info:setVisible(false)
        end
    end
end

function meta:Update(elapsed_time)
    if self.is_show then
        self.time_count = self.time_count - elapsed_time
        if self.time_count <= 0 then
            self:Show()
            self.is_show = false
        end
    end
end

function meta:Hide()
    self.is_show = false
    self:setVisible(false)
    self.skill_info:setVisible(false)
end
function meta:ShowCard(info,idx)
    if info  then
        local config = {}
        config = info

        if not config then
            return
        end

        local handcard =  self.card:getChildByName("handcard")
        local demo_node = ui_helper:ExpandUI(handcard, "template", "modules.common.card_hand_item")
        demo_node:setScale(1)
        local posX = 0
        local posY = 0
        if idx < 3 then
            posX = 155
        elseif idx > 6 then
            posX = 490
        else
            posX = 70*idx
        end
        if config.type == TAB_TYPE.monster then
            posY = 250
        else
            posY = 150
        end
        self:setPosition(0,posY)
        self.card:setPosition(cc.p(posX,350))
        self.card:setVisible(true)
        local id = config.uid

        demo_node:SetCardInfo(config)
    end
end

function meta:RegisterEvent()

    graphic:RegisterEvent("show_hand_card_detail", function (info,idx)
        self.is_show = true
        self.time_count = DELAY_TIME
        self.show_info = info
        self:setVisible(true)
        self.skill_info:setVisible(false)
        self.card:PlayAnimation("enter_press")
        self:ShowCard(info,idx)
        self:Show()

    end)

    graphic:RegisterEvent("hide_hand_card_detail", function ()
        self:Hide()
    end)
end

return meta
