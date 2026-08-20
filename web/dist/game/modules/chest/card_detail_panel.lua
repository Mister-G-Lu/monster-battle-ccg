local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local data_template = require "manager.data_template"
local POWER_CONFIG_MAP = data_template.power_config
local CARD_CONFIG = data_template.card_config


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
    local height
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


local meta = ui_helper:NewPanel("chest_card_detail", "interface/chest/card_detail_panel.csb")


-- 延迟出现时间
local DELAY_TIME = 0
function meta:OnInit()
    self:PlayAnimation("normal")
    self:setVisible(false)

    self.is_show = false
    -- 技能信息
    local skill_info = self:getChildByName("skill_info")
    skill_info:setVisible(false)
    local power_item_node_list = {}
    for i = 1, 3 do
        local item = skill_item.new(skill_info:getChildByName("skill_template"..i))
        item:setVisible(false)
        power_item_node_list[i] = item
    end
    self.skill_info = skill_info
    self.power_item_node_list = power_item_node_list

    self.time_count = DELAY_TIME
end

function meta:Update(elapsed_time)
    if not self.is_show then
        return
    end
    self.time_count = self.time_count - elapsed_time
    if self.time_count < 0 then
        self.is_show = false
        self.skill_info:setVisible(true)
        self:PlayAnimation("enter_detail")
    end
end

function meta:Show(card_id)
    self:setVisible(true)
    self.skill_info:setVisible(false)

    -- self:PlayAnimation("enter_detail")
    self.time_count = DELAY_TIME
    local card_info = CARD_CONFIG[tostring(card_id)]
    if not card_info then
        self:setVisible(false)
        return
    end
    local power_list = card_info.power_list

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
        self.is_show = true

    end


end

function meta:Hide()
    self:setVisible(false)
    self.is_show = false
end


return meta
