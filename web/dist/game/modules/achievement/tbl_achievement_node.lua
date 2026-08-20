local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local text_loader = require "manager.text_loader"

local constants = require "common.constants"

local ACHIEVEMENT_CONFIG = data_template.achievement_config
local TASKACHI_STATUS = constants["TASKACHI_STATUS"]

local item = class("item", function (node)
    return node
end)

function item:ctor()
    self.icon_img = self:getChildByName("icon")
    self.name_txt = self:getChildByName("name")
    self.desc_txt = self:getChildByName("desc")
    self.get_btn = self:getChildByName("get_btn")
    self.complete_img = self:getChildByName("complete_img")
    self.complete_img:setVisible(false)
    local reward_container = self:getChildByName("reward_node")
    local reward_node = require("modules.common.material_item").new()
    local size = reward_container:getContentSize()
    reward_node:setPosition(size.width / 2, size.height / 2)
    reward_container:addChild(reward_node)
    self.reward_node = reward_node
end

function item:SetInfo(info)
    local config = ACHIEVEMENT_CONFIG[info.id]

    local message = text_loader:GetText("achievement_name_"..config.achievement_type)
    if info.status == TASKACHI_STATUS.finish then
        self.complete_img:setVisible(true)
    else
        self.complete_img:setVisible(false)
        if info.status == TASKACHI_STATUS.begin then
            message = message .. " (" .. info.progress .. "/" ..config.value .. ")"
        end
    end

    ui_helper:SetTextByKey(self.name_txt, message)
    ui_helper:SetTextByKey(self.desc_txt, "achievement_desc_"..config.achievement_type, config.value, config.reward_points)
    ui_helper:SetImage(self.icon_img, "ui/ui_icon/achievement/achi_icon_"..config.achievement_type..".png")

    local reward_info = config.reward_list[1]
    if reward_info then
        self.reward_node:setVisible(true)
        self.reward_node:ShowReward(reward_info)
    else
        self.reward_node:setVisible(false)
    end


    self:setCascadeColorEnabled(true)
    self:setColor(ui_helper:GetColor3B(0xffffff))
    if info.status == TASKACHI_STATUS["begin"] or info.status == TASKACHI_STATUS["finish"] then
        self.get_btn:setVisible(false)
        if info.status == TASKACHI_STATUS["finish"] then
            self.reward_node:setVisible(false)
            -- self:setColor(ui_helper:GetColor3B(0x7f7f7f))
        end
    elseif info.status == TASKACHI_STATUS["can_award"] then
        self.get_btn:setVisible(true)
        self.reward_node:SetTouchEnabled(false)
    end

    if info.status == TASKACHI_STATUS["begin"] then
        self.reward_node:SetGray(true)
    elseif info.status == TASKACHI_STATUS["finish"] then
        self.reward_node:SetGray(false)
    end
end

function item:AddClick(func)
    ui_helper:AddClick(self.get_btn, func)
end

local meta = ui_helper:NewPanel("tbl_achievement_node", "interface/achievement/achievement_list.csb")

local MAX_ROW = 6
local SUB_PANEL_HEIGHT = 136

function meta:OnInit()
    local ui_root = self:getChildByName("node")

    local template_node =  ui_root:getChildByName("template")
    template_node:setVisible(false)
    -- 列表
    self.list_view_node = ui_helper:ExpandUI(ui_root, "scroll_view", "widget/refine_list_view")

    self.list_view_node:Init(MAX_ROW, SUB_PANEL_HEIGHT, function ()
        return item.new(template_node:clone())
    end)

    self:RegisterWidgetEvent()
end

function meta:Show()
    self:setVisible(true)

    local achievement_logic = require "logic.achievement"
    local list = achievement_logic:GetAchievementList()

    self.list_view_node:Show( #list, function (cur_row, item_node)
        local info = list[cur_row]
        item_node:SetInfo(info)
        item_node:AddClick(function ()
            achievement_logic:ReqAchievementReward(info.id)
        end)
    end)
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()

end

return meta
