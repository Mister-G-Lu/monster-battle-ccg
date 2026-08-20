local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"
local defines = require "manager.defines"

local rank_logic = require "logic.rank"
local user_logic = require "logic.user"
local arena_logic = require "logic.arena"
local constants = require "common.constants"
local MAIL_STAGE = constants["MAIL_STAGE"]
local MAIL_TYPE = constants["MAIL_TYPE"]
local ARENA_STAGE = constants["ARENA_STAGE"]

local data_template = require "manager.data_template"
local WORLD_TIPS_ZORDER = 2500

local RANK_LIST_MAP = {
    ["page_btn1"] = "global_elo",
    ["page_btn2"] = "friend_elo",
}

local meta = class("rank_panel",function (node)
    return ui_helper:LoadCocosUI("interface/world/ladder_panel.csb")
end)

local MAX_ROW = 6
local SUB_PANEL_HEIGHT = 126

function meta:ctor()
    self:setVisible(false)

    local root_node = self:getChildByName("node")
    local help_tips_node = require("modules.common.help_tips").new()
    root_node:addChild(help_tips_node, WORLD_TIPS_ZORDER)

    self.root_node = root_node
    self.info_btn = root_node:getChildByName("info_btn")
    self:SetHelpTipsPos(help_tips_node)

    self:ChangeAllButtonStyle("page_btn1")

    self.ladder_desc = root_node:getChildByName("ladder_desc")
    self.first_icon = root_node:getChildByName("first_icon")
    self.ladder_value_player = root_node:getChildByName("ladder_value_player")

    self.player_elo_value = root_node:getChildByName("player_elo_value")

    self.page_btn1 = root_node:getChildByName("page_btn1")
    self.page_btn2 = root_node:getChildByName("page_btn2")

    self.top_btn_node = root_node:getChildByName("top_btn")
    self.top_btn_node:setVisible(false)
    self.top_btn = self.top_btn_node:getChildByName("bg")

    local record_template = root_node:getChildByName("template")
    record_template:setVisible(false)

    local record_template_size = record_template:getContentSize()

    self.list_view_node = ui_helper:ExpandUI(root_node, "scroll_view", "widget/refine_list_view")
    self.list_view_node:Init(MAX_ROW, SUB_PANEL_HEIGHT, function ()
        local new_record = require("modules.rank.record_template").new(record_template:clone())
        new_record:setVisible(false)
        return new_record
    end)

    local function ScrollCallback(list_view_node)

        -- self.list_view_node.pre_inner_y is Position, minus
        local show_top_btn = (list_view_node.inner_size.height + list_view_node.pre_inner_y) > list_view_node.size.height

        if show_top_btn then
            self.top_btn_node:setVisible(true)
        else
            self.top_btn_node:setVisible(false)
        end
    end

    self.list_view_node:SetScrollCallback(ScrollCallback)

    self.ladder_value_player = root_node:getChildByName("ladder_value_player")
    self.ladder_desc = root_node:getChildByName("ladder_desc")

    self.close_btn = root_node:getChildByName("close_btn")

    self.ladder_value = root_node:getChildByName("ladder_value")

    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

function meta:SetHelpTipsPos(help_tips_node)

    local rank_info_name = text_loader:GetText("rank_info_name")
    local rank_info_desc = text_loader:GetText("rank_info_desc")
    help_tips_node:SetTitle(rank_info_name)
    help_tips_node:SetContext(rank_info_desc)

    local info_btn_x, info_btn_y = self.info_btn:getPosition()

    local help_tips_width = help_tips_node.root_node:getContentSize().width
    local help_tips_x = info_btn_x - help_tips_width / 2
    local help_tips_y = info_btn_y

    help_tips_node:setPosition(help_tips_x, help_tips_y)

    self.help_tips_node = help_tips_node
end

function meta:ChangeAllButtonStyle()
    local button_name
    local rank_type = rank_logic:GetRankType()

    for k, v in pairs(RANK_LIST_MAP) do
        if rank_type == v then
            button_name = k
        end
    end

    for k, v in pairs(RANK_LIST_MAP) do
        local button_node = self.root_node:getChildByName(k)
        if k == button_name then
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
end

function meta:Show()
    self:setVisible(true)
    self.top_btn_node:setVisible(false)
    self:ChangeAllButtonStyle()

    local rank_record_list = rank_logic:GetRankList()

    self.list_view_node:Show( #rank_record_list, function (cur_row, item_node)
        local record_info = rank_record_list[cur_row]
        item_node:SetRecordInfo(cur_row, record_info)
        item_node:AddClick(function ()
        end)
    end)

    local user_rank_info_key
    local rank_type = rank_logic:GetRankType()
    if rank_type == "global_elo" then
        user_rank_info_key = "user_in_world_rank"
    else
        user_rank_info_key = "user_in_friend_rank"
    end

    local cur_user_rank = rank_logic:GetUserRank()
    if cur_user_rank then
        if cur_user_rank == 1 then
            self.ladder_value_player:setVisible(false)
            self.first_icon:setVisible(true)
        else
            self.ladder_value_player:setVisible(true)
            self.first_icon:setVisible(false)
        end
    else
        cur_user_rank = "--"
        self.first_icon:setVisible(false)
        self.ladder_value_player:setVisible(true)
    end

    ui_helper:SetText(self.ladder_value_player, cur_user_rank)
    ui_helper:SetTextByKey(self.ladder_desc, user_rank_info_key)

    if user_logic.arena_stage == ARENA_STAGE.casual then
        ui_helper:SetText(self.player_elo_value, "--")
    else
        ui_helper:SetText(self.player_elo_value, arena_logic.elo_value)
    end
end


function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()

    local function query_rank_func(widget, event_type)
        local button_name = widget:getName()
        rank_logic:SetRankType(RANK_LIST_MAP[button_name])
        rank_logic:QueryRank()
    end

    ui_helper:AddClick(self.close_btn, function ()
        graphic:DispatchEvent("pop_world_panel")
    end)

    ui_helper:AddClick(self.top_btn, function()
        self.list_view_node:scrollToTop(1, true)
    end)

    ui_helper:AddClick(self.page_btn1, query_rank_func)

    ui_helper:AddClick(self.page_btn2, query_rank_func)

    self:AddClick(function(widget)
        self.help_tips_node:Show()
    end,
    function(widget)
        self.help_tips_node:Hide()
    end)
end

function meta:AddClick(click_event, end_event)

    self.info_btn:addTouchEventListener(function(widget, event_type)
        if event_type == ccui.TouchEventType.began then
            if click_event then click_event(widget) end
        end
        if event_type == ccui.TouchEventType.ended or event_type == ccui.TouchEventType.canceled then
            if end_event then end_event(widget) end
        end
    end)
end


return meta
