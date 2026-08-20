local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local battle_logic = require "logic.battle"
local audio_manager = require "manager.audio_manager"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local pve_logic = require "logic.pve"

local data_template = require "manager.data_template"

local fight_node_class = class("fight_node",function (node)
    return node
end)

function fight_node_class:ctor()
    ui_helper:BindTimeLine(self, "interface/battle/battle_ui_fight_btn.csb")
    self.is_activity = false
end

-- Set activity state
function fight_node_class:SetActivity(is_true)
    if self.is_activity == is_true then
        return
    end
    if is_true then
        self:PlayAnimation("enter")
    else
        self:PlayAnimation("exit")
    end
    self.is_activity = is_true
end

local meta = class("battle_ui_panel",function ()
    return ui_helper:LoadCocosUI("interface/battle/battle_ui_panel.csb")
end)

local BATTLE_SLOT_MAX = constants.BATTLE_SLOT_MAX
local STAGE = battle_logic.STAGE
local CARD_TYPE = constants.CARD_TYPE


local READY_POS_X, READY_POS_Y = 320, 568
local READY_RADIUS = 150

local NUM_EMPTY_COLOR = ui_helper:GetColor4B(0xE24D29)
local NUM_FULL_COLOR = ui_helper:GetColor4B(0xFFE2A9)

function meta:ctor()

    self.dialogue_click = self:getChildByName("dialogue_click")
    self.dialogue_click:setTouchEnabled(false)

    -- Enemy info block
    local enemy_info = self:getChildByName("enemy_info")

    self.enemy_dialogue = self:getChildByName("dialogue_node2")
    ui_helper:BindTimeLine(self.enemy_dialogue, "interface/battle/guide/dialogue_node2.csb")

    local dialogue = self.enemy_dialogue:getChildByName("dialogue")
    local icon_bg = dialogue:getChildByName("iconbg")
    self.enemy_dialogue.icon = icon_bg:getChildByName("icon")
    self.enemy_dialogue.name = dialogue:getChildByName("name")
    self.enemy_dialogue.desc = dialogue:getChildByName("desc")

    self.enemy_name_text = enemy_info:getChildByName("enemy_name")

    self.enemy_monster_num_text = enemy_info:getChildByName("card_monster_num")
    ui_helper:SetText(self.enemy_monster_num_text, 0)

    self.enemy_item_num_text = enemy_info:getChildByName("card_item_num")
    ui_helper:SetText(self.enemy_item_num_text, 0)

    local crystal_node = enemy_info:getChildByName("crystal")
    ui_helper:BindTimeLine(crystal_node,"interface/battle/enemy_crystal.csb")
    self.enemy_crystal_node = crystal_node

    self.enemy_crystal_num_text = crystal_node:getChildByName("crystal_num")
    ui_helper:SetText(self.enemy_crystal_num_text, 0)

    self.pvplevel_value = enemy_info:getChildByName("pvplevel_value")
    ui_helper:SetText(self.pvplevel_value, 1)

    self.enemy_roundtip = enemy_info:getChildByName("enemy_roundtip")
    ui_helper:BindTimeLine(self.enemy_roundtip,"interface/battle/enemy_roundtip.csb")

    -- Our side info block
    local ourside_info = self:getChildByName("ourside_info")

    self.ourside_dialogue = self:getChildByName("dialogue_node1")
    ui_helper:BindTimeLine(self.ourside_dialogue, "interface/battle/guide/dialogue_node1.csb")
    local dialogue = self.ourside_dialogue:getChildByName("dialogue")
    local icon_bg = dialogue:getChildByName("iconbg")
    self.ourside_dialogue.icon = icon_bg:getChildByName("icon")
    self.ourside_dialogue.name = dialogue:getChildByName("name")
    self.ourside_dialogue.desc = dialogue:getChildByName("desc")


    self.monsters_num_text = ourside_info:getChildByName("card_monster_num")
    ui_helper:SetText(self.monsters_num_text, 0)

    self.item_num_text = ourside_info:getChildByName("card_item_num")
    ui_helper:SetText(self.item_num_text, 0)

    local crystal_node = ourside_info:getChildByName("crystal")
    ui_helper:BindTimeLine(crystal_node,"interface/battle/ourside_crystal.csb")
    self.ourside_crystal_node = crystal_node

    self.crystal_num_text = crystal_node:getChildByName("crystal_num")
    ui_helper:SetText(self.crystal_num_text, 0)

    -- pve info
    self.pve_num_total = self:getChildByName("pve_num_total")
    self.pve_num_total_value = self.pve_num_total:getChildByName("value")
    self.pve_num_total_upper_limit = self.pve_num_total:getChildByName("upper_limit")

    -- Action buttons
    -- Fight
    self.fight_node = fight_node_class.new(self:getChildByName("fight_node"))
    self.fight_btn = self.fight_node:getChildByName("fight_btn")

    -- Settings
    self.setting_btn = self:getChildByName("setting_btn")
    local guide_logic = require "logic.guide"
    local is_open_setting = guide_logic:IsOpenBattleSetting()
    self.setting_btn:setVisible(is_open_setting)

    -- Sacrifice button
    self.cur_sacrifice = false
    self.card_sacrifice_node = ourside_info:getChildByName("sacrifice_btn")
    ui_helper:BindTimeLine(self.card_sacrifice_node, "interface/battle/sacrifice_btn.csb")
    local temp = self.card_sacrifice_node:getChildByName("btn2")
    self.card_sacrifice_btn = temp:getChildByName("btn")

    -- Crystal animation
    local skeleton = sp.SkeletonAnimation:create("animation/effects_crystal.json", "animation/effects_crystal.atlas", 1)
    skeleton:setToSetupPose()
    skeleton:setVisible(false)
    skeleton:setPosition({x = 0, y = 0})
    self.ui_effect_node = skeleton
    self:addChild(self.ui_effect_node)

    self.skeleton_end_callback = {}
    self.skeleton_event_callback = {}

    -- First-move coin animation
    local skeleton = sp.SkeletonAnimation:create("animation/battlefield_effects.json", "animation/battlefield_effects.atlas", 1)
    skeleton:setToSetupPose()
    skeleton:setVisible(false)
    skeleton:setPosition({x = READY_POS_X, y = READY_POS_Y})
    self.ready_anim_node = skeleton
    self:addChild(skeleton)


    -- Round tip info
    local round_tip_node = ui_helper:LoadCocosUI("interface/battle/battle_ui_roundtip_panel.csb")
    local temp_node = round_tip_node:getChildByName("node")
    local round_tip_bg = temp_node:getChildByName("round_tip")
    local battle_txt = round_tip_bg:getChildByName("battle_txt")
    self.round_tip_txt = battle_txt:getChildByName("txt1")
    self.round_tip_node = round_tip_node
    round_tip_node:setVisible(false)
    self:addChild(round_tip_node)


    -- Character layer
    self.character_node = self:getChildByName("character_node")

    self:RegisterEvent()
    self:RegisterWidgetEvent()

    self.card_sacrifice_btn:setTouchEnabled(false)
end

function meta:Update(elapsed_time)
    self.hand_card_detail_panel:Update(elapsed_time)
end

function meta:SetEnemyCrystal(num, diff_value)
    ui_helper:SetText(self.enemy_crystal_num_text, num)
    if diff_value and diff_value ~= 0 then
        self.enemy_crystal_node:PlayAnimation("change", false)
    end
end

-- Set enemy monster count
function meta:SetEnemyMonsterNum(num)
    ui_helper:SetText(self.enemy_monster_num_text, num)
    if num == 0 then
        self.enemy_monster_num_text:setColor(NUM_EMPTY_COLOR)
    else
        self.enemy_monster_num_text:setColor(NUM_FULL_COLOR)
    end
end

-- Set enemy item count
function meta:SetEnemyItemNum(num)
    ui_helper:SetText(self.enemy_item_num_text, num)
    if num == 0 then
        self.enemy_item_num_text:setColor(NUM_EMPTY_COLOR)
    else
        self.enemy_item_num_text:setColor(NUM_FULL_COLOR)
    end
end

-- Set our monster count
function meta:SetOwnMonsterNum(num)
    ui_helper:SetText(self.monsters_num_text, num)
    if num == 0 then
        self.monsters_num_text:setColor(NUM_EMPTY_COLOR)
    else
        self.monsters_num_text:setColor(NUM_FULL_COLOR)
    end
end

-- Set our item count
function meta:SetOwnItemNum(num)
    ui_helper:SetText(self.item_num_text, num)
    if num == 0 then
        self.item_num_text:setColor(NUM_EMPTY_COLOR)
    else
        self.item_num_text:setColor(NUM_FULL_COLOR)
    end
end

function meta:SetOwnCrystal(num, diff_value)
    ui_helper:SetText(self.crystal_num_text, num)
    if diff_value and diff_value ~= 0 then
        self.ourside_crystal_node:PlayAnimation("change", false)
    end
end

-- ---------------------------------------------------------------------------
-- Campaign commander HP HUD (The Shadow Road). Plain system-font labels glued
-- to each side's crystal block; created on first use so non-campaign battles
-- are untouched. The server pushes totals through cmd_battle_hero and
-- battle_logic forwards them as "update_hero_hp".
-- ---------------------------------------------------------------------------
function meta:_EnsureHeroHud()
    if self.hero_hud_ready then return end
    self.hero_hud_ready = true
    local enemy_info = self:getChildByName("enemy_info")
    local ourside_info = self:getChildByName("ourside_info")
    if enemy_info and self.enemy_crystal_node then
        local pos = self.enemy_crystal_node:getPosition()
        local label = cc.Label:createWithSystemFont("", "Arial", 20)
        label:setAnchorPoint(cc.p(0.5, 0.5))
        label:setPosition(cc.p(pos.x, pos.y - 42))
        label:setColor(ui_helper:GetColor3B(0xff8fa3))
        enemy_info:addChild(label, 10)
        self.enemy_hero_label = label
    end
    if ourside_info and self.ourside_crystal_node then
        local pos = self.ourside_crystal_node:getPosition()
        local label = cc.Label:createWithSystemFont("", "Arial", 20)
        label:setAnchorPoint(cc.p(0.5, 0.5))
        label:setPosition(cc.p(pos.x, pos.y + 42))
        label:setColor(ui_helper:GetColor3B(0x53d769))
        ourside_info:addChild(label, 10)
        self.own_hero_label = label
    end
end

function meta:SetHeroHp(own_hp, own_max_hp, enemy_hp, enemy_max_hp)
    self:_EnsureHeroHud()
    if self.enemy_hero_label then
        ui_helper:SetText(self.enemy_hero_label,
            string.format("HP %d/%d", tonumber(enemy_hp) or 0, tonumber(enemy_max_hp) or 0))
    end
    if self.own_hero_label then
        ui_helper:SetText(self.own_hero_label,
            string.format("HP %d/%d", tonumber(own_hp) or 0, tonumber(own_max_hp) or 0))
    end
end

-- First-move animation
function meta:RunReadyAnimation()
    local ready_anim_node = self.ready_anim_node
    ready_anim_node:setVisible(true)
    ready_anim_node:setAnimation(0, "gold_coin_ready", false)
    if battle_logic.is_first then
        ready_anim_node:addAnimation(0, "gold_coin_ourside", false)
    else
        ready_anim_node:addAnimation(0, "gold_coin_enemy", false)
    end

    local pos_x, pos_y = 0, 0
    local r = math.random(READY_RADIUS)
    local ao = math.random(360)
    pos_x = READY_POS_X + r * math.cos(ao * 3.14 / 180)
    pos_y = READY_POS_Y + r * math.sin(ao * 3.14 / 180)

    ready_anim_node:registerSpineEventHandler(function (event)
        local anim_name = event.animation
        if anim_name == "gold_coin_ready" then
            local move_act = cc.MoveTo:create(0.6, {x = pos_x, y = pos_y})
            ready_anim_node:runAction(move_act)
        else
            ready_anim_node:setVisible(false)
            battle_logic:DispatchEvent("anim_complete", anim_name)
            self.allow_show_setting = true
        end
    end, sp.EventType.ANIMATION_END)
end

-- Set character layer
function meta:SetCharacterLayer(layer)
    self.character_node:addChild(layer)
end

function meta:ShowSlotIcon()
    if battle_logic.battle_type ~= "guide" then
        battle_logic:DispatchEvent("show_slot_icon")
    end
end

function meta:RegisterEvent()



    -- Exit sacrifice mode
    battle_logic:RegisterEvent("exit_sacrifice_mode",function ()
        self:PlayAnimation("exit_sacri")
    end)

    -- Enter battlefield
    battle_logic:RegisterEvent("battlefield_enter", function ()
        self:setVisible(true)
        self:PlayAnimation("enter")
    end)

    -- Initialize player info
    battle_logic:RegisterEvent("init_player_info",function (own_player, enemy_player)
        self:SetOwnCrystal(own_player.cur_crystal)
        self:SetOwnMonsterNum(own_player:GetAllMonsterLenght())
        self:SetOwnItemNum(own_player:GetAllItemLenght())

        for i = 1, 4 do
            local card_info = own_player.hand_card[i]
            battle_logic:DispatchEvent("update_hand_card", true, i, card_info, false)
        end

        self:SetEnemyCrystal(enemy_player.cur_crystal)
        self:SetEnemyMonsterNum(enemy_player:GetAllMonsterLenght())
        self:SetEnemyItemNum(enemy_player:GetAllItemLenght())

        if battle_logic.battle_type == "daily" then
            self.enemy_name_text:setVisible(false)
            self.pve_num_total:setVisible(true)

            ui_helper:SetText(self.pve_num_total_value, battle_logic.pve_win_cur_value)

            local pve_play_id = tonumber(pve_logic.play_id .. pve_logic.difficulty)
            local cur_pve_play_config = data_template.pve_play_config[pve_play_id]
            ui_helper:SetText(self.pve_num_total_upper_limit, '/'..cur_pve_play_config.win_target_value)
        else
            self.enemy_name_text:setVisible(true)
            self.pve_num_total:setVisible(false)
            ui_helper:SetTextByKey(self.enemy_name_text, enemy_player.user_name)
        end

        if battle_logic.start_type ~= nil then
            self.allow_show_setting = true
        end

    end)

    -- Decide who goes first
    battle_logic:RegisterEvent("gold_coin_ready", function ()
        self:RunReadyAnimation()
    end)


    battle_logic:RegisterEvent("update_pve_win_cur_value", function ()
        ui_helper:SetText(self.pve_num_total_value, battle_logic.pve_win_cur_value)
    end)

    -- Update crystal count
    battle_logic:RegisterEvent("update_crystal_num",function (is_own, num, diff_value)
        if is_own then
            self:SetOwnCrystal(num, diff_value)
        else
            self:SetEnemyCrystal(num, diff_value)
        end
    end)
    -- Commander HP (Shadow Road campaign duel)
    battle_logic:RegisterEvent("update_hero_hp", function (own_hp, own_max_hp, enemy_hp, enemy_max_hp)
        if battle_logic.battle_type ~= "campaign" then return end
        pcall(function ()
            self:SetHeroHp(own_hp, own_max_hp, enemy_hp, enemy_max_hp)
        end)
    end)
    -- Update monster count
    battle_logic:RegisterEvent("update_monster_num",function (is_own, num)
        if is_own then
            self:SetOwnMonsterNum(num)
        else
            self:SetEnemyMonsterNum(num)
        end
    end)

    -- Update item count
    battle_logic:RegisterEvent("update_item_num",function (is_own, num)
        if is_own then
            self:SetOwnItemNum(num)
        else
            self:SetEnemyItemNum(num)
        end
    end)

    -- Battle round
    battle_logic:RegisterEvent("update_battle_round",function (round)
        -- ui_helper:SetTextByKey(self.title_text,"battle_pvp_text",round)
    end)

    -- Update sacrifice stage
    battle_logic:RegisterEvent("update_sacrifice_stage", function (is_sacrifice)
        -- if is_sacrifice then
        --     is_sacrifice = battle_logic.own_player.is_sacrifice
        -- end
        -- Outside our turn the sacrifice button stays disabled
        -- if is_sacrifice and battle_logic.cur_stage ~= STAGE.own then
        --     is_sacrifice = false
        -- end
        if self.cur_sacrifice == is_sacrifice then
            return
        end

        self.card_sacrifice_btn:setTouchEnabled(is_sacrifice)
        self.cur_sacrifice = is_sacrifice
        if is_sacrifice then
            self.card_sacrifice_node:PlayAnimation("enter")
        else
            self.card_sacrifice_node:PlayAnimation("exit")
        end
    end)

    -- Set battle stage
    battle_logic:RegisterEvent("update_battle_stage",function (stage)
        if stage == STAGE.own then

            self.round_tip_node:setVisible(true)
            self.round_tip_node:PlayAnimation("enter", false, function ()
                self.round_tip_node:setVisible(false)
                if battle_logic.is_first_animation then
                    battle_logic.is_first_animation = false
                    self:ShowSlotIcon()
                end
                battle_logic:DispatchEvent("update_operate_card")
            end)

            if battle_logic.is_first_animation then
                ui_helper:SetTextByKey(self.round_tip_txt, "battle_round_first")
            else
                ui_helper:SetTextByKey(self.round_tip_txt, "battle_round_own")
            end
            self.fight_btn:setTouchEnabled(true)
            self.fight_node:SetActivity(true)

        elseif stage == STAGE.wait then
            self.fight_node:SetActivity(false)
            self.fight_btn:setTouchEnabled(false)

            if self.anim_stage == STAGE.enemy then
                self.enemy_roundtip:PlayAnimation("exit", false, function()
                end)
            end
        else

            if battle_logic.is_first_animation then
                self.round_tip_node:setVisible(true)
                self.round_tip_node:PlayAnimation("enter", false, function ()
                    self.round_tip_node:setVisible(false)
                    battle_logic.is_first_animation = false
                    self:ShowSlotIcon()
                end)
                ui_helper:SetTextByKey(self.round_tip_txt, "battle_round_after")
            else
                -- self:PlayAnimation("exit_round")
            end

            self.enemy_roundtip:PlayAnimation("enter", false, function()
                self.enemy_roundtip:PlayAnimation("loop", true)
            end)
        end
        self.anim_stage = stage
    end)

    -- Add crystal
    battle_logic:RegisterEvent("add_crystal", function (is_own, pos, rotation)
        local ui_effect_node = self.ui_effect_node
        ui_effect_node:setVisible(true)
        ui_effect_node:setPosition(pos)
        ui_effect_node:setRotation(rotation)
        ui_effect_node:setToSetupPose()
        ui_effect_node:setAnimation(0, "effects_crystal", false)


        self.skeleton_end_callback["effects_crystal"] = function ()
            battle_logic:DispatchEvent("show_crystal_animation")
        end

        local target_pos = {}

        if is_own then
            local x, y = self.ourside_crystal_node:getPosition()
            target_pos = {x = x, y = y}
        else
            local x, y = self.enemy_crystal_node:getPosition()
            target_pos = {x = x, y = y}
        end

        self.skeleton_event_callback["move_crystal"] = function (int_value, float_value, string_value)
            local move_act = cc.MoveTo:create(float_value, target_pos)
            local rotation_act = cc.RotateTo:create(float_value, 0)
            local curve_func = cc[string_value]
            if curve_func then
                move_act = curve_func:create(move_act)
                rotation_act = curve_func:create(rotation_act)
            end
            local swap_act = cc.Spawn:create(move_act, rotation_act)
            ui_effect_node:runAction(swap_act)
        end
    end)

    battle_logic:RegisterEvent("update_dialogue", function(is_own, trigger_event)
        local pos = trigger_event.dialogue_pos
        local icon = trigger_event.dialogue_icon
        local name = trigger_event.dialogue_name
        local text = trigger_event.dialogue_text

        if pos == "down" then
            self.cur_dialogue = self.ourside_dialogue
        else
            self.cur_dialogue = self.enemy_dialogue
        end


        self.cur_dialogue:setVisible(true)
        ui_helper:SetText(self.cur_dialogue.name, name)
        ui_helper:SetText(self.cur_dialogue.desc, text)
        local resource = require "manager.resource"
        ui_helper:SetImage(self.cur_dialogue.icon, resource:GetGuideIcon(icon))

        self.cur_dialogue:PlayAnimation("enter")

        self.dialogue_click:setTouchEnabled(true)

        ui_helper:AddClick(self.dialogue_click, function ()
            self.enemy_dialogue:PlayAnimation("exit", false, function()
                self.enemy_dialogue:setVisible(false)
            end)

            self.ourside_dialogue:PlayAnimation("exit", false, function()
                self.ourside_dialogue:setVisible(false)
            end)

            self.dialogue_click:setTouchEnabled(false)
        end)
    end)

    battle_logic:RegisterEvent("remind_fight_btn", function()
        self.fight_node:PlayAnimation("remind", true)
    end)
end

function meta:RegisterWidgetEvent()
    -- Fight
    ui_helper:AddClick(self.fight_btn, function ()
        battle_logic:ReqBattleAttack("normal")
    end)

    -- Settings
    ui_helper:AddClick(self.setting_btn, function ()
        if self.allow_show_setting then
            self.allow_show_setting = false
            battle_logic:DispatchEvent("push_battle_panel","battle_setting_panel", function ()
                self.allow_show_setting = true
            end)
        end
    end)

    -- Sacrifice card
    ui_helper:AddClick(self.card_sacrifice_btn, function ()
        battle_logic:DispatchEvent("enter_sacrifice_mode")
        self:PlayAnimation("enter_sacri")
    end)

    local effect_node = self.ui_effect_node

    -- Animation end event
    effect_node:registerSpineEventHandler(function (event)
        local anim_name = event.animation
        local callback = self.skeleton_end_callback[anim_name]
        if callback then
            callback()
            self.skeleton_end_callback[anim_name] = nil
        end
        self.skeleton_event_callback = {}
        effect_node:setVisible(false)
    end, sp.EventType.ANIMATION_END)

    -- Animation event
    effect_node:registerSpineEventHandler(function (event)
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local int_value = event.eventData.intValue
        local event_name = event.eventData.name

        local callback = self.skeleton_event_callback[event_name]
        if callback then
            callback(int_value, float_value, string_value)
        end

        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        end
    end, sp.EventType.ANIMATION_EVENT)

    -- First-move animation
    self.ready_anim_node:registerSpineEventHandler(function (event)
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local int_value = event.eventData.intValue
        local event_name = event.eventData.name

        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        end
    end, sp.EventType.ANIMATION_EVENT)

end



return meta
