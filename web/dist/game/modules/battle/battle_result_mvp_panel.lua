local ui_helper = require "manager.ui_helper"
-- local resource = require "manager.resource"
-- local constants = require "common.constants"
local data_template = require "manager.data_template"
local deck_logic = require"logic.deck"
local user_logic = require"logic.user"
-- local MVP_OFFSET_Y = 180
-- local MVO_OFFSET_X = 320
local meta = ui_helper:NewPanel("battle_result_mvp_panel", "interface/battle/battle_end2/mvp_node.csb")

function meta:OnInit()

end

function meta:Init(mvp_info)

    local node = self:getChildByName("panel")
    self.node = node
    self.confirm_btn = node:getChildByName("btn"):getChildByName("mvp_btn")
    self.card_desc = node:getChildByName("btn"):getChildByName("mvp_help_desc") --
    self.mvp_card_id = mvp_info.card_id
    self.card = node:getChildByName("info"):getChildByName("card")      --MVP卡牌
    self.state = node:getChildByName("info"):getChildByName("state")    --敌人或自己
    self.card_name = node:getChildByName("info"):getChildByName("name")
    self.info_btn = node:getChildByName("info"):getChildByName("infobtn")
    local card_info = data_template.card_config[tostring(self.mvp_card_id)]
    local name = card_info.name.." ★"..tostring(card_info.level)
    ui_helper:SetTextByKey(self.card_name,name)
    self.bubble = ui_helper:LoadCocosUI("interface/battle/battle_end2/mvp_bubble.csb")
    self.bubble:setPosition(cc.p(self.info_btn:getContentSize().width,self.info_btn:getContentSize().height))
    self.bubble:setVisible(false)
    local card_state_info = mvp_info.card_stat_info

    local state_config = data_template.card_state_config
    local bubble = self.bubble:getChildByName("mvp_bubble")
    bubble:getChildByName("title1"):setVisible(false)
    bubble:getChildByName("title2"):setVisible(false)
    bubble:getChildByName("value1"):setVisible(false)
    bubble:getChildByName("value2"):setVisible(false)
    for k,v in pairs(card_state_info) do
        local title = bubble:getChildByName("title"..k)
        local value = bubble:getChildByName("value"..k)
        title:setVisible(true)
        value:setVisible(true)
        for j,m in pairs(state_config) do 
            if m.stat_name == v.stat_name then
                ui_helper:SetTextByKey(title,m.desc)
                ui_helper:SetTextByKey(value,v.stat_value)
            end
        end
    end
    self.info_btn:addChild(self.bubble)
    self:RegisterWidgetEvent()
    self:setVisible(true)
    self:PlayAnimation("enter")
    self:setPosition(cc.p(0,645-62))
    self.have_card= false
    local group_id = deck_logic:GetGroupIdByUid(self.mvp_card_id)
    if deck_logic:GetNumByGroupId(group_id) >0 then
        self.have_card = true
        ui_helper:SetTextByKey(self.card_desc,"battle_result_upgrade_desc")
    else
        ui_helper:SetTextByKey(self.card_desc,"battle_result_synthesis_desc")
    end

    if mvp_info.user_id == user_logic.user_id then
        ui_helper:SetTextByKey(self.state,"battle_result_self")
    else
        ui_helper:SetTextByKey(self.state,"battle_result_enemy")
    end
    --卡牌 展示
    local card_panle = require("modules.deck.card_small_item").new(self.card)
    card_panle:ShowCardGroupInfo(1, card_info, true)
    card_panle.monster_level:setVisible(false)
    card_panle.bar_shadow:setVisible(false)
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.confirm_btn,function()
        if self.have_card then
            self:DispatchGraphicEvent("card_upgrade")
        else
            self:DispatchGraphicEvent("card_synthesis")
        end
    end)

    self:AddClick(
        function (pos)
            self.bubble:setVisible(true)
            self.bubble:PlayAnimation("enter")
        end,
        function ()

            self.bubble:PlayAnimation("exit",false,function()
                self.bubble:setVisible(false)
            end)
        end
    )
end

function meta:AddClick(click_event, end_event)
    self.info_btn:setTouchEnabled(true)
    self.info_btn:addTouchEventListener(function(widget, event_type)
        if event_type == ccui.TouchEventType.began then
            if click_event then click_event(widget:getWorldPosition()) end
        end
        if event_type == ccui.TouchEventType.ended or event_type == ccui.TouchEventType.canceled then
            if end_event then end_event() end
        end
    end)
end

function meta:RegisterEvent()
    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "next" then
            self:DispatchGraphicEvent("mvp_over")
        end
    end)
end

return meta
