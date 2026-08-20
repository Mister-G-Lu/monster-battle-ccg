local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local arena_logic = require "logic.arena"
local deck_logic = require "logic.deck"
local MAX_EXP = 660
local WORLD_TIPS_ZORDER = 2500
local defines = require "manager.defines"
local TAB_TYPE = defines.DECK_TAB_TYPE

local meta = ui_helper:NewPanel("periphery_match_panel","interface/ladder/ladder_panel.csb")

function meta:OnInit()
    self:Init()
    self:InitCard()
end

function meta:Init()
    self.card_group = self:getChildByName("cardgroup")
    self.card_group_node = self.card_group:getChildByName("node")
    self.close_btn = self.card_group_node:getChildByName("cancel_btn")
    self.open_select = false
    self.ladder_rule = self:getChildByName("ladder_rule")
    local card_groupbg = self.card_group_node:getChildByName("card_groupbg")
    card_groupbg:getChildByName("desc1"):setVisible(false)
    card_groupbg:getChildByName("cardicon"):setVisible(false)
    card_groupbg:getChildByName("icon1"):setVisible(false)
    card_groupbg:getChildByName("group_selcectbtn"):setTouchEnabled(false)
    card_groupbg:getChildByName("group_selcectbtn"):getChildByName("arrow"):setVisible(false)
    self.confirm_btn = self.card_group_node:getChildByName("confirm_btn")
    ui_helper:SetTextByKey(self.confirm_btn:getChildByName("desc"),"pvp_confirm_btn_value")

    ui_helper:SetTextByKey(card_groupbg:getChildByName("group_selcectbtn"):getChildByName("group_name"),"world_deck_btn")
    --tips
    local help_tips_node = require("modules.common.help_tips").new()
    self:addChild(help_tips_node, WORLD_TIPS_ZORDER)
    self.info_btn = self:getChildByName("info_btn")
    self:SetHelpTipsPos(help_tips_node)
    self.template = self:getChildByName("template")
    self.elo = self.template:getChildByName("elo")
    self.elo_bar = self:getChildByName("elo_bar")
    self.bar_text = self.elo_bar:getChildByName("elo")
    --elo 进度条
    self:ShowEloBar()
    --天梯规则界面
    self:LadderRulePanel()
end
--设置ELO进度条
function meta:ShowEloBar()

    self:getChildByName("template"):loadTexture("ui/ui_icon/ladder_headicon/level"..arena_logic.ladder_lv..".png")
    self.elo:setString(tostring(arena_logic.elo_value))
    self.stage_value = self.template:getChildByName("value")
    self.stage_value:setString(tostring(arena_logic.ladder_lv))

    local cur_stage = #arena_logic.periphery_config - arena_logic.ladder_lv
    local next_stage = #arena_logic.periphery_config - arena_logic.ladder_lv + 1
    local cur_state_elo = 0
    local next_stage_elo = 0
    if cur_stage == 0 then
        cur_state_elo = 1000
        next_stage_elo = arena_logic.periphery_config[1].req_reward_cup
    else
        cur_state_elo = arena_logic.periphery_config[cur_stage].req_reward_cup
        next_stage_elo = arena_logic.periphery_config[next_stage].req_reward_cup
    end
    self.elo_bar:getChildByName("elo_point1"):getChildByName("elo_point_value1"):setString(tostring(cur_state_elo))
    self.elo_bar:getChildByName("elo_point1"):getChildByName("ladder_value1"):setString(tostring(arena_logic.ladder_lv))
    self.elo_bar:getChildByName("elo_point2"):getChildByName("elo_point_value1"):setString(tostring(next_stage_elo))
    self.elo_bar:getChildByName("elo_point2"):getChildByName("ladder_value1"):setString(tostring(arena_logic.ladder_lv-1))
    local endPoint = arena_logic.ladder_lv - 1
    if endPoint < 0 then
        endPoint = 1
    end
    self.elo_bar:getChildByName("elo_point2"):getChildByName("ladder_value1"):setString(tostring(endPoint))
    --经验条
    local need_elo = next_stage_elo - cur_state_elo
    local cur_par = next_stage_elo - arena_logic.elo_value
    local pars = (need_elo - cur_par)/need_elo
    local bar_step = MAX_EXP/need_elo
    if arena_logic.ladder_lv == 1 then
        ui_helper:SetText(self.bar_text,text_loader:GetText("arena_bar_text"," --"))
    else
        ui_helper:SetText(self.bar_text,text_loader:GetText("arena_bar_text",tostring(next_stage_elo- arena_logic.elo_value)))
    end
    --第一阶 没有配表 起始ELO值
    if cur_stage == 0 then
        local elo = arena_logic.elo_value- 1000
        if elo < 0 then
            elo = 0
        end
        self.elo_bar:getChildByName("bar"):setPositionX(bar_step* elo)
    else
        self.elo_bar:getChildByName("bar"):setPositionX(MAX_EXP*pars)
    end
end

--初始化卡片
function meta:InitCard()
    local card_small_node = self.card_group_node:getChildByName("monster")
    local card_small_item = self.card_group_node:getChildByName("item")
    card_small_node:setVisible(true)
    card_small_item:setVisible(true)
    self.touch_list = {}
    self.small_card_list = {}
    self.small_item_list = {}
    self.render_queue = {}
    -- 是否显示大卡
    self:SetDeckInfo(deck_logic.cur_deck_id)
    for i = 1, 8 do
        self.touch_list[i] = card_small_node:getChildByName("touch"..i)
        self.touch_list[i]:setTag(i)
    end
    for i = 9, 16 do
        self.touch_list[i] = card_small_item:getChildByName("touch"..i)
        self.touch_list[i]:setTag(i)
    end
    --怪物卡牌
    for i = 1, 8 do
        local card_node = card_small_node:getChildByName("template"..i)
        local sub_panel = require("modules.deck.card_small_item").new(card_node)
        self.small_card_list[i] = sub_panel
    end
    --道具卡牌
    for i = 1, 8 do
        local card_node = card_small_item:getChildByName("template"..i)
        local sub_panel = require("modules.deck.card_small_item").new(card_node)
        self.small_item_list[i] = sub_panel
    end
    --初始化卡片信息
    local deck_info = deck_logic:GetDeckInfo(deck_logic.cur_deck_id)
    self.deck_info = deck_info
    self.card_detail = ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_detail_panel.csb")
    self.card_group_node:addChild(self.card_detail)
    self.card_detail:setName("card_detail")
    self.card_detail:setPosition(cc.p(0,300))
    self.card_detail:setVisible(false)

    self.hand_card_detail = ui_helper:ExpandUI(self.card_group_node, "card_detail", "modules.pve.pve_card_detail_panel")
    self.hand_card_detail:setVisible(true)
    self.hand_card_detail:setLocalZOrder(10000)
    self:RefreshDeckCard(self.deck_idx,TAB_TYPE.monster)
    self:RefreshDeckCard(self.deck_idx,TAB_TYPE.item)
end
--天梯规则界面
function meta:LadderRulePanel()
    self.ladder_rule_panel = require("modules.pvp.ladder_rule_panel").new()
    self:addChild(self.ladder_rule_panel)
end

-- 设置卡组信息
function meta:SetDeckInfo(deck_idx)
    if self.deck_idx == deck_idx then
        return
    end
    self.deck_idx = deck_idx
    self:RefreshDeckCard(self.deck_idx, self.cur_tab)
end

-- 设置卡牌状态
function meta:SetTabelType(tab_type, is_animation)
    is_animation = is_animation or 0
    if self.cur_tab == tab_type and not is_change then
        return
    end
    self.cur_tab = tab_type
    self:RefreshDeckCard(self.deck_idx, tab_type, is_animation)
end

--刷新卡牌
function meta:RefreshDeckCard(deck_idx, tab_type, is_animation)
    if not deck_idx or not tab_type then
        return
    end
    local deck_info = deck_logic:GetDeckInfo(deck_idx)
    if not deck_info then
        return
    end
    local card_list = {}
    local power_value = 0
    for i = 1, 8 do
        local monster_id = deck_info["monster_pos_"..i]
        local item_id = deck_info["item_pos_"..i]
        if monster_id then
            local config = deck_logic:GetCardConfigByCardId(monster_id)
            power_value = power_value + config.score
        end
        if item_id then
            local config = deck_logic:GetCardConfigByCardId(item_id)
            power_value = power_value + config.score
        end

        if tab_type == TAB_TYPE.monster then
            card_list[i] = monster_id
        else
            card_list[i] = item_id
        end

        local card_id = card_list[i]
        if card_id then
            local card_config = deck_logic:GetCardConfigByCardId(card_id)
            local nodes = {}
            if tab_type == TAB_TYPE.monster then
                nodes = self.small_card_list[i]
            else
                nodes = self.small_item_list[i]
            end
            nodes:setVisible(false)
            local render = nil
                -- 渲染,
                render = function ()
                    nodes:ShowCardGroupInfo(i, card_config, true)
                    local tt = (i-1) % 4 + 1
                    -- -- 双行渲染
                    local block = cc.CallFunc:create(function ()
                        nodes:setVisible(true)
                        if is_animation == 0 then
                            nodes:PlayAnimation("enter")
                        end
                    end)
                    nodes:runAction(cc.Sequence:create(cc.DelayTime:create(tt * 0.02), block))
                end
            table.insert(self.render_queue, render)
        end
    end
end

function meta:Show()
    local deck = deck_logic:GetDeckInfo(self.deck_idx)
    self.deck_info = deck
    self:RefreshDeckCard(self.deck_idx,TAB_TYPE.monster)
    self:RefreshDeckCard(self.deck_idx,TAB_TYPE.item)
    self:setVisible(true)
    --规则界面
    self.ladder_rule_panel:Show()
end

--显示卡牌详细信息
function meta:ShowCardDetail(idx)

    if idx <= 8 then --怪兽卡牌
        local card_uid = self.deck_info["monster_pos_"..idx]
        local card_group_info = deck_logic:GetCardConfigByCardId(card_uid)
        if not card_group_info then
            return
        end
        card_group_info.uid = card_uid
        self:DispatchGraphicEvent("show_hand_card_detail", card_group_info, idx)
    else --道具卡牌
        local card_uid = self.deck_info["item_pos_"..idx - 8]
        local card_group_info = deck_logic:GetCardConfigByCardId(card_uid)
        if not card_group_info then
            return
        end
        self:DispatchGraphicEvent("show_hand_card_detail", card_group_info, idx - 8)
    end
end

function meta:Update(elapsed_time)
    if #self.render_queue > 0 then
        local render = self.render_queue[1]
        render()
        table.remove(self.render_queue,1)
    end
end

function meta:Hide()
    self:setVisible(false)
    self:DispatchGraphicEvent("switch_world_status",true)
end

function meta:RegisterEvent()

    -- TODO:这是注册渲染事件的方法了。怎么控件事件也在这里面注册了
    --开始战斗
    ui_helper:AddClick(self.confirm_btn,function()
        self:DispatchGraphicEvent("do_join_match")
    end)
    --关闭
    ui_helper:AddClick(self.close_btn, function ()
        self.open_select = false
        self:Hide()
        self:DispatchGraphicEvent("switch_system_module", "home")
    end)
    --天梯规则界面
    ui_helper:AddClick(self.ladder_rule,function()
        --list滚动到玩家当前段位
        self:DispatchGraphicEvent("find_cur_ladder_level")
        self.ladder_rule_panel:setVisible(true)
    end)
    local function item_touch(sender,event_type)
        if event_type == ccui.TouchEventType.began then
            self:ShowCardDetail(sender:getTag())
        end
        if event_type == ccui.TouchEventType.canceled  or event_type == ccui.TouchEventType.ended then
            self:DispatchGraphicEvent("hide_hand_card_detail")
        end
    end
    for i = 1, 16 do
       self.touch_list[i]:addTouchEventListener(item_touch)
    end
     --tips
    self:AddClick(function(widget)
        self.help_tips_node:Show()
    end,
    function(widget)
        self.help_tips_node:Hide()
    end)
end
--tips
function meta:SetHelpTipsPos(help_tips_node)
    local rank_info_name = text_loader:GetText("arena_info_name")
    local rank_info_desc = text_loader:GetText("arena_info_desc")
    help_tips_node:SetTitle(rank_info_name)
    help_tips_node:SetContext(rank_info_desc)
    local info_btn_x, info_btn_y = self.info_btn:getPosition()
    local help_tips_width = help_tips_node.root_node:getContentSize().width
    local help_tips_x = info_btn_x - help_tips_width / 2
    local help_tips_y = info_btn_y - help_tips_node.root_node:getContentSize().height*1.2
    help_tips_node:setPosition(help_tips_x, help_tips_y)
    self.help_tips_node = help_tips_node
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
