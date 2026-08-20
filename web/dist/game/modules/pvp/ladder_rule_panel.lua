local ui_helper = require "manager.ui_helper"
local arena_logic = require "logic.arena"
local REWARD_NUM = 6
local meta = ui_helper:NewPanel("ladder_rule_panel","interface/ladder/intro_list_panel.csb")

function meta:OnInit()
    self.rule_scroll_view = self:getChildByName("scroll_view")
    local template = self:getChildByName("template")
       --奖励位置
    self.rule_list = {}
    local max_row = #arena_logic.periphery_config
    for i = max_row, 1, -1  do
        local info = arena_logic.periphery_config[i]
        table.insert(self.rule_list,info)
    end
    self.reward_list_node = ui_helper:ExpandUI(self, "scroll_view", "widget/refine_list_view")
    self.reward_list_node:Init(3,template:getContentSize().height,function()
        local rule= require("modules.pvp.ladder_rule_template").new(template:clone())
        return rule
    end)
    template:setVisible(false)
    self.ladder_close_btn = self:getChildByName("close_btn")
    self:setVisible(false)
end

function meta:Show()
    local rule_list = self.rule_list
    local max_row = #rule_list
    self.reward_list_node:Show(max_row,function(cur_row,item_node)
        if cur_row > max_row then
            cur_row = max_row
        end
        local rule_info = rule_list[cur_row]
        local reward_list = {}
        local info = rule_list[cur_row]
        local template = self:getChildByName("template")
        for i = 1,REWARD_NUM do
            if info and info["season_reward_type"..i] and info["season_reward_type"..i] ~= "" then
                local reward = {}
                reward.type = info["season_reward_type"..i]
                reward.attr_id = info["season_reward_id"..i]
                reward.value = info["season_reward_num"..i]
                table.insert(reward_list,reward)
            end
        end
        local table_row = #rule_list - cur_row + 1
        item_node:SetLadderRuleInfo(rule_info,cur_row,table_row)
        item_node:initReward(reward_list,template:getContentSize().width/2)
    end)
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
    --显示当前阶段的 对应listview 位置
    self:RegisterGraphic("find_cur_ladder_level",function()
        self.reward_list_node:SetHeadRow(arena_logic.ladder_lv)
    end)

    ui_helper:AddClick(self.ladder_close_btn,function()
        self:Hide()
    end)
end

return meta
