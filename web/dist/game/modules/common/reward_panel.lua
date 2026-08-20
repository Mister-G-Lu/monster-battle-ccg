local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local resource = require "manager.resource"
local graphic = require "manager.graphic"

local resource_logic = require "logic.resource"

local ITEM_CONFIG = data_template.item_config
local MATERIAL_KIND = constants["MATERIAL_KIND"]

local MAX_ITEM_NUM = 4

local meta = class("reward_panel",function (node)
    return ui_helper:LoadCocosUI("interface/common/reward_panel.csb")
end)

function meta:ctor()
    local root = self:getChildByName("node")

    -- 标题
    self.title_txt = root:getChildByName("title")

    -- 明细的背景
    local detailbg = root:getChildByName("detailbg")

    -- 明细文字
    self.desc_txt = detailbg:getChildByName("desc")

    -- 确认
    self.close_btn = root:getChildByName("close_btn")
    self.confirm_btn = detailbg:getChildByName("confirm_btn")

    -- 奖励列表
    local reward_group = detailbg:getChildByName("reward_group")
    self.item_node_list = {}
    for i = 1, MAX_ITEM_NUM do
        local bg = reward_group:getChildByName("bg"..i)
        local item = ui_helper:ExpandUI(reward_group, "reward"..i.."_item", "modules.common.material_item")
        self.item_node_list[i] = { backgroup = bg, item = item }
    end

    self:RegisterWidgetEvent()
end

-- 显示
function meta:Show(reward_list, title, desc)

    self:setVisible(true)
    if title then
        ui_helper:SetText(self.title_txt, title)
    end
    if desc then
        ui_helper:SetText(self.desc_txt, desc)
    end

    for i = 1, MAX_ITEM_NUM do
        local reward = reward_list[i]
        local node = self.item_node_list[i]
        if reward then
            node.backgroup:setVisible(true)
            node.item:setVisible(true)
            node.item:ShowReward(reward)
        else
            node.backgroup:setVisible(false)
            node.item:setVisible(false)
        end
    end
end

-- 隐藏
function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterWidgetEvent()
    local function _on_close_event()
        graphic:DispatchEvent("pop_world_panel")
    end
    ui_helper:AddClick(self.close_btn, _on_close_event)

    ui_helper:AddClick(self.confirm_btn, _on_close_event)
    -- ui_helper:AddClick(self.confirm_btn, function ()

         -- graphic:DispatchEvent("show_reward_animation",self.reward_list)
        --self.root:setVisible(false)
        --deck_logic:ResolveCard(self.card_uid)
    -- end)
end

return meta
