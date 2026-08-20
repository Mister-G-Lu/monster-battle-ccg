local ui_helper = require "manager.ui_helper"

local meta = ui_helper:NewPanel("achievement_panel", "interface/achievement/achievement_panel.csb")

local achievement_logic = require "logic.achievement"

local TAB_NAME = achievement_logic.TAB_NAME

local ACHIEVEMENT_LIST_MAP = {
    ["page_btn1"] = TAB_NAME.achievement,
    ["page_btn2"] = TAB_NAME.footprint,
}


function meta:OnInit()
    local ui_root = self:getChildByName("msgbox")
    self.ui_root = ui_root

    self.container_node = ui_root:getChildByName("node")

    local player_info_node = ui_root:getChildByName("player_info")
    self.achievement_value_txt = player_info_node:getChildByName("value")

    self.tips_node = nil
    self.tbl_node_list = {}
    for k,v in pairs(ACHIEVEMENT_LIST_MAP) do
        self.tbl_node_list[v] = ui_root:getChildByName(k)
        if k == "page_btn1" then
            self.tips_node = self.tbl_node_list[v]:getChildByName("tip")
        end
    end
    ui_helper:BindTimeLine(self.tips_node, "interface/world/newtip.csb")
    self.tips_node:PlayAnimation("loop", true)

    self.cur_container_node = nil
    self.tbl_container_node = {}

    self:RegisterWidgetEvent()
end

function meta:Update()
end

function meta:Show()
    self:setVisible(true)
    local cur_tbl_name = self:ChangeAllButtonStyle()

    ui_helper:SetText(self.achievement_value_txt, achievement_logic.achi_points)

    if self.cur_container_node then
        self.cur_container_node:Hide()
    end

    local container_node = self.tbl_container_node[cur_tbl_name]
    if container_node == nil then
        container_node = require("modules.achievement.tbl_"..cur_tbl_name.."_node").new()
        self.tbl_container_node[cur_tbl_name] = container_node
        self.container_node:addChild(container_node)
    end
    container_node:Show()
    self.cur_container_node = container_node
    self.tips_node:setVisible(achievement_logic:CheckHaveReward())
end

function meta:ChangeAllButtonStyle()
    local button_name
    local achievement_type = achievement_logic:GetType()

    for _, v in pairs(ACHIEVEMENT_LIST_MAP) do
        if achievement_type == v then
            button_name = v
        end
    end

    for _, v in pairs(ACHIEVEMENT_LIST_MAP) do
        local button_node = self.tbl_node_list[v]
        if v == button_name then
            local button_desc = button_node:getChildByName("desc")
            button_desc:setTextColor(ui_helper:GetColor3B(0x6D5527))
            button_node:setTouchEnabled(false)
            button_node:setBrightStyle(0)
            button_node:setLocalZOrder(1)
        else
            local button_desc = button_node:getChildByName("desc")
            button_desc:setTextColor(ui_helper:GetColor3B(0x3A2E19))
            button_node:setTouchEnabled(true)
            button_node:setBrightStyle(1)
            button_node:setLocalZOrder(0)
        end
    end
    return button_name
end


function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()

    self:RegisterGraphic("achievement_refresh_panel", function ()
        self:Show()
    end)
end

function meta:RegisterWidgetEvent()
    local ui_root = self.ui_root

    local close_btn = ui_root:getChildByName("close_btn")
    ui_helper:AddClick(close_btn, function ()
        self:DispatchGraphicEvent("pop_world_panel")
    end)

    for k, v in pairs(self.tbl_node_list) do
        ui_helper:AddClick(v, function ()
            achievement_logic:SetType(k)
            self:Show()
        end)
    end
end

return meta
