local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local network = require "manager.network"

local battle_logic = require "logic.battle"
    local constants = require "common.constants"
local meta = ui_helper:NewPanel("battle_result_reward_panel", "interface/battle/battle_end2/reward_template.csb")
function meta:OnEnter()

end

function meta:Init(have_mvp,reward_list)

    self.item_height = 80
    self.max_item_count = 0
    self.pos_y = 0
    self:getChildByName("panel"):getChildByName("template"):setVisible(false)
    if have_mvp then
        self.pos_y=645-267-62
    else
        self.pos_y=645-62
    end
    self:setPosition(cc.p(0,self.pos_y))
    self:PlayAnimation("enter", false, function ()
        self:DispatchGraphicEvent("reward_action_over")
    end)
    local item_index = 0
    for k,v in pairs(reward_list) do
        if v.type == constants["REWARD_TYPE"].resource then
            self.max_item_count = self.max_item_count + 1
        elseif v.type == constants["REWARD_TYPE"].chest then
            self.max_item_count = self.max_item_count + 1
        end
    end

    for k,v in pairs(reward_list) do
        if v.type == constants["REWARD_TYPE"].resource then
            self:showItem(v,item_index,self.max_item_count,self)
            item_index = item_index +1
        elseif v.type == constants["REWARD_TYPE"].card then

        elseif v.type == constants["REWARD_TYPE"].chest then
            self:showChest(v,item_index,self.max_item_count,self)
            item_index = item_index + 1
        end
    end


    local reward_node = require("modules.common.reward_tips").new()
    self:addChild(reward_node, 100)

    self.reward_tips_panel = reward_node
    -- self:getChildByName("template_reward"):getChildByName("icon"):setVisible(false)
    self:RegisterWidgetEvent()
end

function meta:showItem(material_info,index,max,node)

    local item_id = tonumber(material_info.attr_id)
    local item_node = node:getChildByName("panel")
    -- local item = item_node:getChildByName("icon")
    -- local bg = item:clone()
    local reward_item = ui_helper:LoadCocosUI("interface/battle/battle_end2/reward_item_template.csb")
    reward_item:setName("reward_resource"..index)
    item_node:addChild(reward_item,100)
    -- item_node:addChild(bg,1)
    reward_item:setScale(0.95)
    local reward_node = ui_helper:ExpandUI(item_node,"reward_resource"..index, "modules.common.pve_material_item")
    reward_node:setVisible(true)
    
    local block = cc.CallFunc:create(function()
        reward_node:ShowReward(material_info)
    end)
    self:runAction(cc.Sequence:create(cc.DelayTime:create(0.3*index), block))

    reward_item:setPosition(cc.p( 320-100*(max-1) + 200*index ,self.item_height))
    -- bg:setPosition(reward_item:getPosition())
end

function meta:showChest(material_info,index,max,node)

    local item_id = tonumber(material_info.attr_id)
    local item_node = node:getChildByName("panel")
    -- local item = item_node:getChildByName("icon")
    -- local bg = item:clone()
    local reward_item = ui_helper:LoadCocosUI("interface/battle/battle_end2/reward_item_template.csb")
    reward_item:setName("reward_chest"..index)
    item_node:addChild(reward_item,100)
    reward_item:setScale(0.95)
    -- item_node:addChild(bg,1)
    local reward_node = ui_helper:ExpandUI(item_node,"reward_chest"..index, "modules.common.pve_material_item")
    reward_node:setVisible(true)
    reward_node:ShowReward(material_info)
    reward_item:setPosition(cc.p( 320-100*(max-1) + 200*index ,self.item_height))
    -- bg:setPosition(reward_item:getPosition())
end

function meta:RegisterWidgetEvent()

    self:RegisterGraphic("show_pve_reward_tips", function (reward_info, pos)
        if not reward_info then return end
        pos.y = 0
        self.reward_tips_panel:Show(reward_info,pos)
    end)

    self:RegisterGraphic("hide_pve_reward_tips", function ()
        self.reward_tips_panel:Hide()
    end)

end

function meta:Show()

end

function meta:Hide()

end


return meta
