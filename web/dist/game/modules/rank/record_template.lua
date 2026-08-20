local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"
local user_logic = require "logic.user"
local rank_logic = require "logic.rank"

local RANK_ELO_NAME = text_loader:GetText("rank_elo_name")


local constants = require "common.constants"
local data_template = require "manager.data_template"

local DEFAULT_HEADIMAG_FILE = "ui/ui_bg/paper_head2.png"
local RANKING_HEADIMG_MAP = {
    [1] = "ui/ui_bg/paper_head.png",
    [2] = "ui/ui_bg/paper_head.png",
    [3] = "ui/ui_bg/paper_head.png",
}

local meta = class("record_template",function (node)
    return node
end)

function meta:ctor()
    self.ladder_value = self:getChildByName("ladder_value")
    self.head = self:getChildByName("head")    
    self.name = self:getChildByName("name")
    self.elo_value = self:getChildByName("elo_value")
    self.win_lose = self:getChildByName("win_lose")
    self.country_icon = self:getChildByName("country_icon")
    self.country = self.country_icon:getChildByName("country")
end

function meta:SetRecordInfo(cur_row, info)
    local first_icon_node = self:getChildByName("first_icon")    
    if cur_row == 1 then
        first_icon_node:setVisible(true)
        self.ladder_value:setVisible(false)
    else
        first_icon_node:setVisible(false)
        self.ladder_value:setVisible(true)        
    end

    ui_helper:SetText(self.ladder_value, cur_row)
    ui_helper:SetText(self.name, info.user_name)

    local rank_elo_value = info.elo_value or 0
    ui_helper:SetText(self.elo_value, rank_elo_value)

    -- for interface overload: src/widget/refine_list_view.lua 
    local img_path = RANKING_HEADIMG_MAP[cur_row]
    if img_path then
        ui_helper:SetImage(self.head, img_path, ccui.TextureResType.plistType)
    else
        ui_helper:SetImage(self.head, DEFAULT_HEADIMAG_FILE, ccui.TextureResType.plistType)
    end

    ui_helper:SetTextByKey(self.win_lose, "rank_win_lose_value", info.win_count, info.loss_count)

    -- ui_helper:SetText(self.country_icon, info.country_icon)
    local extra_info     
    local region_info = text_loader:GetText("user_country_empty")
    if info.global_rank then

        local rank_in_global_value = info.global_rank
        if rank_in_global_value ~= 0 then
            local rank_in_global_info = text_loader:GetText("user_world_rank_number", rank_in_global_value)                    
            extra_info = region_info .. rank_in_global_info
        else
            extra_info = region_info        
        end

    else
        extra_info = region_info
    end

    ui_helper:SetText(self.country, extra_info)    
end

function meta:AddClick(func)
    ui_helper:AddClick(self, func)
end

return meta
