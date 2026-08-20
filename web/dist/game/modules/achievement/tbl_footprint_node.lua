local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"

local STATISTIC_CONFIG = data_template.statistic_config

local item = class("item", function (node)
    return node
end)

function item:ctor()
    self.shadow_img = self:getChildByName("shadow")
    self.name_txt = self:getChildByName("name")
    self.value_txt = self:getChildByName("value")
end

function item:SetInfo(idx, info)
    if math.fmod(idx, 2) == 0 then
        self.shadow_img:setVisible(false)
    else
        self.shadow_img:setVisible(true)
    end

    local config = STATISTIC_CONFIG[info.id]

    ui_helper:SetText(self.name_txt, config.desc)
    ui_helper:SetText(self.value_txt, info.progress)
end


local MAX_ROW = 6
local SUB_PANEL_HEIGHT = 60

local meta = ui_helper:NewPanel("tbl_footprint_node", "interface/achievement/achievement_total.csb")

function meta:OnInit()
    local node = self:getChildByName("node")
    local total_node = node:getChildByName("total")

    self.info_desc_txt = total_node:getChildByName("info_desc")

    local template_node =  total_node:getChildByName("template")
    template_node:setVisible(false)

    self.list_view_node = ui_helper:ExpandUI(total_node, "scroll_view", "widget/refine_list_view")
    self.list_view_node:Init(MAX_ROW, SUB_PANEL_HEIGHT, function ()
        return item.new(template_node:clone())
    end)

    self:RegisterWidgetEvent()
end

function meta:OnExit()
end

function meta:Update(elapsed_time)
end

function meta:Show()
    self:setVisible(true)

    local achievement_logic = require "logic.achievement"
    local list = achievement_logic:GetStatisticList()

    self.list_view_node:Show( #list, function (cur_row, item_node)
        local info = list[cur_row]
        item_node:SetInfo(cur_row, info)
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
