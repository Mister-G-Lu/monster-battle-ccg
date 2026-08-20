local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local text_loader = require "manager.text_loader"
local MVP_OFFSET_Y = 180
local MVO_OFFSET_X = 320
local user_logic = require "logic.user"

local meta = ui_helper:NewPanel("battle_dexterity_template", "interface/battle/battle_end2/exp_template.csb")

function meta:OnEnter()

end

function meta:Init(cur_dexterity,last_dexterity,node)

    self.last_add_dexterity = cur_dexterity - last_dexterity
    self.node = node
    self.node_height = 645 --奖励 总节点 位置
    self.cur_dexterity = 0  --当前的熟练度
    self.add_dexterity_step = 0 --添加熟练度ADD动画速度
    self.add_add_dexterity_step = 0
    self.last_max_exp = 0
    self.add_bar_step = 0
    self.cur_bar_percent = 0
    self.last_bar_percent = 0
    self.max_exp = data_template.proficiency_config[(user_logic.last_level)].exp
    self.dexterity_bar = nil
    self.dexterity_node = nil
    self.exp_action_time = 0.5
    self.add_add_dexterity = 0
    self.start_bar_action = false

    self.head_light = self:getChildByName("panel"):getChildByName("headlight")
    self.dexterity_bar = self:getChildByName("panel"):getChildByName("exp_bar")
    self.cur_dexterity = cur_dexterity
    self.last_dexterity = last_dexterity
    local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
    local dexterity_add_text = self:getChildByName("panel"):getChildByName("update_value")

    ui_helper:SetText(dexterity_bar_text,tostring(last_dexterity).."/"..tostring(self.max_exp))
    ui_helper:SetText(dexterity_add_text,0)
    self.dexterity_bar:setPercent(last_dexterity/self.max_exp*100)
    local level = self:getChildByName("panel"):getChildByName("level")
    ui_helper:SetText(level,tostring(user_logic.last_level))

    local pos_y = self.node_height
    self:setPosition(cc.p(0,pos_y))
    self:PlayAnimation("enter", false, function ()

        self.last_max_exp = self.max_exp
        self.add_dexterity_step = math.ceil(cur_dexterity / (60 * self.exp_action_time))
        self.add_add_dexterity_step = math.ceil(self.last_add_dexterity / (60 * self.exp_action_time))
        self.cur_bar_percent = math.ceil(cur_dexterity/self.max_exp*100)
        if self.cur_bar_percent > 100 then
            self.cur_bar_percent = 100
        end
        self.last_bar_percent = math.ceil(last_dexterity/self.max_exp*100)
        self.add_bar_step = self.cur_bar_percent / (60 * self.exp_action_time)
        --光条
        local width = self.dexterity_bar:getContentSize().width
        local bar_width = width * self.cur_bar_percent /100
        local bar_pos_width = self.dexterity_bar:getPositionX()
        local light_posX = bar_pos_width + bar_width
        self.head_light:setPositionX(light_posX)
        self.start_bar_action = true
        if user_logic.level > user_logic.last_level then --升级
            self:PlayAnimation("levelup", false, function ()
                self:LevelChange()
            end)
        else --等级无变动
            self:PlayAnimation("add", false, function ()
            end)
        end
    end)
end

function meta:Update(elapsed_time)
    if self.start_bar_action == true then
        --熟练度动画
        if self.last_dexterity ~= self.cur_dexterity then
            local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
            self.last_dexterity = self.last_dexterity + self.add_dexterity_step
            if self.last_dexterity > self.cur_dexterity then
                self.last_dexterity = self.cur_dexterity
            end
            ui_helper:SetText(dexterity_bar_text,tostring(self.last_dexterity).."/"..tostring(self.max_exp))
        end
        --增加的熟练度动画
        if self.last_add_dexterity ~= 0 then
            local dexterity_add_text = self:getChildByName("panel"):getChildByName("update_value")
            self.add_add_dexterity = self.add_add_dexterity + self.add_add_dexterity_step
            if self.add_add_dexterity > self.last_add_dexterity then
                self.add_add_dexterity = self.last_add_dexterity
            end
            ui_helper:SetText(dexterity_add_text,"+".. tostring(self.add_add_dexterity))
        end
        --熟练度条动画
        if self.last_bar_percent ~= self.cur_bar_percent then
            local num  = self.dexterity_bar:getPercent()+ self.add_bar_step
            self.last_bar_percent = self.last_bar_percent + self.add_bar_step
            if self.last_bar_percent > self.cur_bar_percent then
                num = self.cur_bar_percent
                self.last_bar_percent = self.cur_bar_percent
            end

            local width = self.dexterity_bar:getContentSize().width
            local bar_width = width * num /100
            local bar_pos_width = self.dexterity_bar:getPositionX()
            local light_posX = bar_pos_width + bar_width
            self.head_light:setPositionX(light_posX)
            self.head_light:setVisible(true)
            self.dexterity_bar:setPercent(num)
        end
    end
end

--技能解锁动画
function meta:LevelChange()
    self.max_exp = data_template.proficiency_config[(user_logic.level)].exp
    self.last_dexterity = self.last_max_exp
    self.cur_bar_percent = math.ceil(self.cur_dexterity/self.max_exp*100)
    self.last_bar_percent = 0
    self.dexterity_bar:setPercent(self.last_bar_percent)
    local level = self:getChildByName("panel"):getChildByName("level")
    ui_helper:SetText(level,tostring(user_logic.level))
    local dexterity_bar_text = self:getChildByName("panel"):getChildByName("value")
    ui_helper:SetText(dexterity_bar_text,tostring(self.cur_dexterity).."/"..tostring(self.max_exp))
end


function meta:RegisterWidgetEvent()

end

function meta:RegisterEvent()
    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "next" then
            self:DispatchGraphicEvent("exp_over")
            self:DispatchGraphicEvent("reward_action_over")
        end
    end)
end

return meta
