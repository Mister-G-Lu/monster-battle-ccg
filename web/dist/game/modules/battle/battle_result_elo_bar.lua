local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local text_loader = require "manager.text_loader"
local arena_logic = require"logic.arena"
local graphic = require "manager.graphic"
local MVP_OFFSET_Y = 180
local MVO_OFFSET_X = 320
local user_logic = require "logic.user"

local meta = class("battle_result_elo_panel",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/battle/battle_end2/ladder_level_bar.csb")
end)

function meta:ctor()
     ui_helper:BindTimeLine(self, "interface/battle/battle_end2/ladder_level_bar.csb")
end

function meta:Init(cur_dexterity,last_dexterity,node)

    self.last_add_dexterity = cur_dexterity - last_dexterity
    self.node = node
    self.node_height = 720 --奖励 总节点 位置
    self.cur_dexterity = 0  --当前的熟练度
    self.add_dexterity_step = 0 --添加熟练度ADD动画速度
    self.add_add_dexterity_step = 0
    self.last_max_exp = 0
    self.add_bar_step = 0 
    self.cur_bar_percent = 0
    self.last_bar_percent = 0
    local max_level = #data_template.periphery_config
    self.max_exp =  data_template.periphery_config[max_level-(arena_logic:GetLastLevel())+1].req_reward_cup
    self.min_exp = 0
    if arena_logic:GetLastLevel() == max_level then
        self.min_exp = self.max_exp
    else
        self.min_exp = data_template.periphery_config[max_level-(arena_logic:GetLastLevel())+1].req_reward_cup
    end
    self.dexterity_bar = nil
    self.dexterity_node = nil
    self.exp_action_time = 0.5
    self.add_add_dexterity = 0
    self.start_bar_action = false
    self:RegisterEvent()
    self:RegisterWidgetEvent()

    self.head_light = self:getChildByName("panel"):getChildByName("headlight")
    self.dexterity_bar = self:getChildByName("panel"):getChildByName("exp_bar")   

    self.cur_dexterity = cur_dexterity
    self.last_dexterity = last_dexterity
    self.level_up_start = false

    local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
    local dexterity_add_text = self:getChildByName("panel"):getChildByName("update_value")
    self.is_level_down  = false
    dexterity_add_text:setVisible(true)
    ui_helper:SetText(dexterity_bar_text,tostring(last_dexterity).."/"..tostring(self.max_exp))
    ui_helper:SetText(dexterity_add_text,0)
    self.last_bar_percent = last_dexterity/self.max_exp*100
    self.dexterity_bar:setPercent(self.last_bar_percent)
    local level = self:getChildByName("panel"):getChildByName("level")
    ui_helper:SetText(level,tostring(arena_logic:GetLastLevel()))

    local pos_y = self.node_height
    self:setPosition(cc.p(0,pos_y))
    self.last_max_exp = self.max_exp
    self.add_dexterity_step = math.ceil(self.cur_dexterity / (60 * self.exp_action_time))
    self.add_add_dexterity_step = math.ceil(self.last_add_dexterity / (60 * self.exp_action_time))
    self.cur_bar_percent = math.ceil(self.cur_dexterity/self.max_exp*100) 
    if self.cur_bar_percent >100 then
        self.cur_bar_percent = 100
    end
    self.add_bar_step = self.cur_bar_percent / (60 * self.exp_action_time)
    if self.add_add_dexterity_step == 0 and self.last_add_dexterity < 0 then
        self.add_add_dexterity_step = -1
    end

    if cur_dexterity < last_dexterity then
        self.add_bar_step = -self.add_bar_step
        self.add_dexterity_step = -self.add_dexterity_step
    end
    --光条
    local width = self.dexterity_bar:getContentSize().width
    local bar_width = width * self.cur_bar_percent /100
    local bar_pos_width = self.dexterity_bar:getPositionX()
    local light_posX = bar_pos_width + bar_width
    self.head_light:setPositionX(light_posX)
end

function meta:Update(elapsed_time)
    if self.start_bar_action == true then
        --熟练度动画
        if self.last_dexterity ~= self.cur_dexterity then
            local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
            self.last_dexterity = self.last_dexterity + self.add_dexterity_step
            if  self.last_dexterity > self.cur_dexterity and self.add_dexterity_step > 0 then
                self.last_dexterity = self.cur_dexterity
            elseif self.last_dexterity < self.cur_dexterity and self.add_dexterity_step < 0 then
                self.last_dexterity = self.cur_dexterity
            end
            ui_helper:SetText(dexterity_bar_text,tostring(self.last_dexterity).."/"..tostring(self.max_exp))
        end

        --增加的熟练度动画
        if self.last_add_dexterity ~= 0 then
            local dexterity_add_text = self:getChildByName("panel"):getChildByName("update_value")
            self.add_add_dexterity = self.add_add_dexterity + self.add_add_dexterity_step
            if self.add_add_dexterity > self.last_add_dexterity and self.add_add_dexterity_step >0 then
                self.add_add_dexterity = self.last_add_dexterity
            elseif self.add_add_dexterity < self.last_add_dexterity and self.add_add_dexterity_step < 0 then
                self.add_add_dexterity = self.last_add_dexterity
            end
            local symbol = ""
            if self.add_add_dexterity_step > 0 then
                symbol = "+"
            end
            ui_helper:SetText(dexterity_add_text,symbol.. tostring(self.add_add_dexterity))
        end
        --熟练度条动画
        if self.last_bar_percent ~= self.cur_bar_percent then
            self.min_bar_percent = self.cur_dexterity - self.min_exp
            local num  = self.dexterity_bar:getPercent()+ self.add_bar_step
            self.last_bar_percent = self.last_bar_percent + self.add_bar_step
            if self.last_bar_percent > self.cur_bar_percent and self.add_bar_step >0  then
                num = self.cur_bar_percent
                self.last_bar_percent = self.cur_bar_percent
            elseif self.last_bar_percent >= self.min_bar_percent and self.add_bar_step < 0 and self.is_level_down then
                num = 100
                self.last_bar_percent = self.cur_bar_percent    
            elseif self.last_bar_percent < self.cur_bar_percent and self.add_bar_step < 0 then
                self.last_bar_percent = self.cur_bar_percent
            end

            local width = self.dexterity_bar:getContentSize().width
            local bar_width = width * num /100
            local bar_pos_width = self.dexterity_bar:getPositionX()
            local light_posX = bar_pos_width + bar_width
            self.head_light:setPositionX(light_posX)
            self.dexterity_bar:setPercent(num)
        end
    end
end

--降级
function meta:LevelDown()
    -- self.max_exp = 1500
    local max_level = #data_template.periphery_config
    self.max_exp =  data_template.periphery_config[max_level-(arena_logic:GetLevel())+1].req_reward_cup
    self.level_up_start = true
    self.last_dexterity = self.max_exp
    self.cur_bar_percent = math.ceil(self.cur_dexterity/self.max_exp*100) 
    self.last_bar_percent = 100
    self.add_bar_step = self.cur_bar_percent / (60 * self.exp_action_time)
    self.dexterity_bar:setPercent(self.last_bar_percent)
    local level = self:getChildByName("panel"):getChildByName("level")
    ui_helper:SetText(level,tostring(user_logic.level))
    local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
    ui_helper:SetText(dexterity_bar_text,tostring(self.cur_dexterity).."/"..tostring(self.max_exp))
    self:PlayAnimation("decrease",false,function()
    end)
end

--升级
function meta:LevelUp()
    -- self.max_exp = 2500
    local max_level = #data_template.periphery_config
    self.max_exp =  data_template.periphery_config[max_level-(arena_logic:GetLevel())+1].req_reward_cup
    self.last_dexterity = self.last_max_exp
    self.cur_bar_percent = math.ceil(self.cur_dexterity/self.max_exp*100)
    self.last_bar_percent = 0
    self.dexterity_bar:setPercent(self.last_bar_percent)
    local level = self:getChildByName("panel"):getChildByName("level")
    ui_helper:SetText(level,tostring(user_logic.level))
    local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
    ui_helper:SetText(dexterity_bar_text,tostring(self.cur_dexterity).."/"..tostring(self.max_exp))
    self:PlayAnimation("increase",false,function()
    end)
end

function meta:RegisterWidgetEvent()
   self.handler_id = graphic:RegisterEvent("start_result_elo_bar", function ()
        if arena_logic:GetLastLevel() < arena_logic:GetLevel() then
            self.is_level_down = true
            self:PlayAnimation("decrease_leveldown",false,function()
                self:LevelDown()
            end)
        elseif arena_logic:GetLastLevel() > arena_logic:GetLevel() then
            self:PlayAnimation("increase_levelup",false,function()
                self:LevelUp()
            end)
        else
            if self.cur_dexterity < self.last_dexterity then --输了
                self:PlayAnimation("decrease",false,function() 
                end)
            else
                self:PlayAnimation("increase",false,function() --赢
                end)
            end
        end
        self.start_bar_action = true 
    end)
end

function meta:RegisterEvent()
    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "next" then
            graphic:DispatchEvent("elo_over")
            if self.handler_id ~= nil then
                graphic:UnregisterEvent("start_result_elo_bar", self.handler_id)
            end
        elseif event_name == "increase_animation" then --升级
            graphic:DispatchEvent("level_up_skeleton")
        elseif event_name == "decrease_animation" then --降级
            graphic:DispatchEvent("level_down_skeleton")
        end
    end)
end
  
return meta
