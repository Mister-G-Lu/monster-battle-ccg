local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"
local friend_logic = require "logic.friend"
local START_ELO = 1000
local constants = require "common.constants"
local data_template = require "manager.data_template"
local FRIEND_STATUS = constants.FRIEND_STATUS
local CHAT_STATUS =constants.CHAT_STATUS
local chat_logic = require "logic.chat"
local arena_logic = require "logic.arena"
local INTERVAL = 90
local ITEM_TAG = 99
local meta = class("ladder_rule_template",function (node)
    return node
end)

function meta:ctor()
    self.ladder_lv = self:getChildByName("value")
    self.elo_value = self:getChildByName("elo")
    self.icon = self:getChildByName("icon")
    self.ladder_desc = self:getChildByName("ladder_desc")
    self:getChildByName("reward_template"):setVisible(false)
    self.pos_y = self:getChildByName("reward_template"):getPositionY()
    self.is_init = false
    self:RegisterEvent()
end
function meta:SetLadderRuleInfo(rule_info,cur_row,table_row)
    self.ladder_lv:setString(tostring(cur_row))
    local elo = 0
    local max = #arena_logic.periphery_config
    if cur_row == max then
        elo = START_ELO
    else
        elo = arena_logic.periphery_config[max - cur_row].req_reward_cup
    end
    self.elo_value:setString(elo)
    self.icon:loadTexture(resource:GetLadderTypeIcon(rule_info.icon))
    self.ladder_desc:setString(arena_logic.periphery_config[table_row].ladder_desc)
end
-- --天梯预览 奖励
function meta:initReward(reward_list,width)
    local reward_node_list = {}
    local max = #reward_list
    local max_item = 0
    for i = 1,6 do
        self:removeChildByTag(ITEM_TAG+i)
    end

    for i = 1, max do
        local reward_node = require("modules.common.material_item").new()
        reward_node:setVisible(false)
        self:addChild(reward_node)
        reward_node:setTag(ITEM_TAG+i)
        reward_node:setPosition(cc.p(width-INTERVAL/2*(max-1) + INTERVAL*max_item ,self.pos_y))
        max_item = max_item +1
        reward_node_list[i] = reward_node
    end
    --显示奖励
    for i = 1, max do
        local reward_node = reward_node_list[i]
        if reward_list[i] then
            reward_node:setVisible(true)
            local reward_info = {}
            reward_info.type = reward_list[i].type
            reward_info.attr_id = reward_list[i].attr_id
            reward_info.value = reward_list[i].value
            reward_node:ShowReward(reward_info)
        else
            reward_node:setVisible(false)
        end
    end
end

function meta:RegisterEvent()

    
end



return meta
