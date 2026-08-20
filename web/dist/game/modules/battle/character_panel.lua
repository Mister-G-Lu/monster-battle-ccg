local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local battle_logic = require "logic.battle"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"
local graphic = require "manager.graphic"

local timer = require "manager.time"

local meta = class("character_panel",function ()
    return ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_panel.csb")
end)


local hand_template_panel = require("modules.battle.battle_hand_card")
local CARD_STATUS = hand_template_panel.STATUS
local OPERATE_STATUS = hand_template_panel.OPERATE_STATUS

local POWER_CONFIG_MAP = data_template.power_config
local POWER_ANIMATION = constants.POWER_ANIMATION
local EFFECT_ANIMATION = constants.EFFECT_ANIMATION
local POWER_ONLY_ONE = constants.POWER_ONLY_ONE
local POWER_NAME = constants.POWER_NAME
local BATTLE_SLOT_MAX = constants.BATTLE_SLOT_MAX
local STAGE = battle_logic.STAGE
local CARD_TYPE = constants.CARD_TYPE


local CARD_ZORDER = 10
local TIPS_ZORDER = 20
local BATTLE_ZORDER = 30
local SKILL_ZORDER = 50
local NUM_ZORDER = 90

local EFFECT_ZORDER = 80
local HAND_CARD_ZORDER = 100

local DETAIL_ZORDER = 200


local HURT_COLOR = ui_helper:GetColor4B(0xFE5C33)
local HEAL_COLOR = ui_helper:GetColor4B(0xC3FF12)

local SKILL_TIPS_SRC_POS = 55.5
local SKILL_TIPS_CEN_POS = 86

local SLOT_ICON_SKILL_NAME = {
    {
        ["melee"] = 1,
        ["magic"] = 2,
    },
    {
        ["ranged"] = 1,
        ["magic"] = 2,
    },
    {
        ["ranged"] = 1,
        ["magic"] = 2,
    },
}

function meta:ctor()
    self.own_pos_list = {}
    self.own_slot_list = {}
    self.own_tips_list = {}
    self.own_empty_list = {}
    self.own_number_list = {}
    self.own_skill_list = {}

    self.enemy_pos_list = {}
    self.enemy_slot_list = {}
    self.enemy_tips_list = {}
    self.enemy_empty_list = {}
    self.enemy_number_list = {}
    self.enemy_skill_list = {}

    self.effect_cache = {}

    self:PlayAnimation("normal")

    self:InitSlotIcon()

    for i = 1, 3 do
        local own_empty = self:getChildByName("own_empty"..i)
        self.own_empty_list[i] = own_empty

        local own_slot = self:getChildByName("own_slot"..i)
        local own_x, own_y = own_empty:getPosition()
        local own_pos = { x = own_x, y = own_y}

        self.own_slot_list[i] = require("modules.battle.battle_slot_card").new(own_slot, false)
        self.own_slot_list[i]:setLocalZOrder(CARD_ZORDER)
        self.own_slot_list[i]:SetEmptyNode(own_empty, i)
        self.own_slot_list[i]:setVisible(false)

        -- 放置提示提示
        local own_tips_node = ui_helper:LoadCocosUI("interface/battle/battlefield_animation_template.csb")
        own_tips_node:setPosition(own_pos)
        own_tips_node:PlayAnimation("active", true)
        own_tips_node:setVisible(false)
        self:addChild(own_tips_node, TIPS_ZORDER)
        self.own_tips_list[i] = own_tips_node

        -- 数字提示
        local own_number_tip = ui_helper:LoadCocosUI("interface/battle/number_tip.csb")
        own_number_tip:setPosition(own_pos)
        own_number_tip:setVisible(false)
        own_number_tip.number_txt = own_number_tip:getChildByName("value")
        self:addChild(own_number_tip, NUM_ZORDER)
        self.own_number_list[i] = own_number_tip

        -- 技能提示
        local own_skill_tip = ui_helper:LoadCocosUI("interface/battle/skill_tip.csb")
        own_skill_tip:setPosition(own_pos)
        local bubble_node = own_skill_tip:getChildByName("bubble")
        own_skill_tip.icon_img = bubble_node:getChildByName("icon")
        own_skill_tip.value_txt = bubble_node:getChildByName("value")
        own_skill_tip:setVisible(false)
        self:addChild(own_skill_tip, SKILL_ZORDER)
        self.own_skill_list[i] = own_skill_tip

        -- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>

        local enemy_empty = self:getChildByName("enemy_empty"..i)
        self.enemy_empty_list[i] = enemy_empty

        local enemy_slot = self:getChildByName("enemy_slot"..i)
        local x, y = enemy_empty:getPosition()
        local enemy_pos = { x = x, y = y }
        self.enemy_slot_list[i] = require("modules.battle.battle_slot_card").new(enemy_slot, true)
        self.enemy_slot_list[i]:setLocalZOrder(CARD_ZORDER)
        self.enemy_slot_list[i]:SetEmptyNode(enemy_empty, i)
        self.enemy_slot_list[i]:setVisible(false)

        self.enemy_pos_list[i] = enemy_pos

        local enemy_tips_node = ui_helper:LoadCocosUI("interface/battle/battlefield_animation_template.csb")
        enemy_tips_node:setPosition(enemy_pos)
        enemy_tips_node:PlayAnimation("active", true)
        enemy_tips_node:setVisible(false)
        self:addChild(enemy_tips_node, TIPS_ZORDER)
        self.enemy_tips_list[i] = enemy_tips_node

        -- 数字提示
        local enemy_number_tip = ui_helper:LoadCocosUI("interface/battle/number_tip.csb")
        enemy_number_tip:setPosition(enemy_pos)
        enemy_number_tip:setVisible(false)
        enemy_number_tip.number_txt = enemy_number_tip:getChildByName("value")
        self:addChild(enemy_number_tip, NUM_ZORDER)
        self.enemy_number_list[i] = enemy_number_tip

        -- 技能提示
        local enemy_skill_tip = ui_helper:LoadCocosUI("interface/battle/skill_tip.csb")
        local bubble_node = enemy_skill_tip:getChildByName("bubble")
        enemy_skill_tip.icon_img = bubble_node:getChildByName("icon")
        enemy_skill_tip.value_txt = bubble_node:getChildByName("value")
        enemy_skill_tip:setPosition(enemy_pos)
        enemy_skill_tip:setVisible(false)
        self:addChild(enemy_skill_tip, SKILL_ZORDER)
        self.enemy_skill_list[i] = enemy_skill_tip
    end

    -- 手牌信息
    self.hand_card_list = {}
    local handcard_node = self:getChildByName("handcard_node")
    for i = 1, 4 do
    --     -- 子节点与代码文件绑定
        local temp = handcard_node:getChildByName("handcard"..i)
        self.hand_card_list[i] = hand_template_panel.new(temp)
        self.hand_card_list[i]:setLocalZOrder(4 - i)
        self.hand_card_list[i]:ResetTransform(i)
    end
    handcard_node:setLocalZOrder(HAND_CARD_ZORDER)
    self.handcard_node = handcard_node

    -- 当前选中的卡牌下标
    self.select_card_idx = 0
    self.cur_move_card = nil
    self.cur_operate_status = OPERATE_STATUS.normal

    -- 创建献祭卡
    self.temp_show_card = require("modules.battle.battle_show_card").new()
    self.temp_show_card:setVisible(false)
    self:addChild(self.temp_show_card, 200)

    -- 是否是我方回合
    self.own_round = false

    -- 是否献祭状态
    self.is_sacrifice_mode = false
    self.sacrifice_data = nil
    self.sacrifice_back_btn = self:getChildByName("back_btn")
    self.sacrifice_confirm_btn = self:getChildByName("confirm_btn")



    -- 手牌明细界面
    self.hand_card_detail = ui_helper:ExpandUI(self, "detail_panel", "modules.battle.card_detail_panel")
    self.hand_card_detail:setLocalZOrder(DETAIL_ZORDER)

    -- 动画播放序列
    self.animation_play_queue = {}
    self.is_anim_over = true

    self:RegisterWidgetEvent()
    self:RegisterEvent()
    self:RegisterTouchEvent()
end

function meta:InitSlotIcon()
    self.own_empty1 = self:getChildByName("own_empty1")
    self.own_empty2 = self:getChildByName("own_empty2")
    self.own_empty3 = self:getChildByName("own_empty3")

    self.own_empty1.skill1 = self.own_empty1:getChildByName("skill1")
    self.own_empty1.skill2 = self.own_empty1:getChildByName("skill2")

    self.own_empty2.skill1 = self.own_empty2:getChildByName("skill1")
    self.own_empty2.skill2 = self.own_empty2:getChildByName("skill2")

    self.own_empty3.skill1 = self.own_empty3:getChildByName("skill1")
    self.own_empty3.skill2 = self.own_empty3:getChildByName("skill2")

    self.own_empty1.skill1:setVisible(false)
    self.own_empty1.skill2:setVisible(false)

    self.own_empty2.skill1:setVisible(false)
    self.own_empty2.skill2:setVisible(false)

    self.own_empty3.skill1:setVisible(false)
    self.own_empty3.skill2:setVisible(false)    
end

function meta:ShowAllSlotIcon(skill_name)
    for slot_pos, slot_info in pairs(SLOT_ICON_SKILL_NAME) do
        if skill_name then
            self:ShowSlotIcon(slot_pos, skill_name)
        else
            for skill_name, _ in pairs(slot_info) do
                self:ShowSlotIcon(slot_pos, skill_name)
            end
        end
    end
end

function meta:ShowSlotIcon(slot_pos, skill_name)
    local slot_index = "own_empty" .. slot_pos

    local skill_pos = SLOT_ICON_SKILL_NAME[slot_pos][skill_name]
    local skill_index
    if skill_pos then
        skill_index = "skill" .. skill_pos
    else
        return false
    end

    local anim_name = skill_name .. "_in"
    local slot_icon_node = self[slot_index][skill_index]
    if not slot_icon_node:isVisible() then
        slot_icon_node:setVisible(true)

        local size = slot_icon_node:getContentSize()
        local skeleton_node = sp.SkeletonAnimation:create("animation/battle_slot_icon.json", "animation/battle_slot_icon.atlas", 1)
        skeleton_node:setAnimation(0, anim_name, false)
        skeleton_node:setPosition({ x = size.width / 2, y = size.height / 2 })

        slot_icon_node:addChild(skeleton_node)

        skeleton_node:registerSpineEventHandler(function (event)
            local float_value = event.eventData.floatValue
            local int_value = event.eventData.intValue
            local string_value = event.eventData.stringValue
            local event_name = event.eventData.name
            if event_name == "bullet" then
                if float_value == 0 then
                    skeleton_node:setPosition({x = tar_x, y = tar_y})
                else
                    local move_act = cc.MoveTo:create(float_value, {x = tar_x, y = tar_y})
                    local curve_func = cc[string_value]
                    if curve_func then
                        move_act = curve_func:create(move_act)
                    end
                    skeleton_node:setPosition({x = src_x, y = src_y})
                    skeleton_node:runAction(move_act)
                end
            elseif event_name == "sound" then
                audio_manager:PlayEffect(string_value)
            elseif event_name == "rotation" then
                local anger = CalcAnger(src_x, src_y, tar_x, tar_y)
                skeleton_node:setRotation(anger)
            elseif event_name == "hurt" then
                battle_logic:DispatchEvent("sub_event_complete")
                is_hurt_event = true
            elseif event_name == "shake" then
                battle_logic:DispatchEvent("effect_screen_shake", float_value, int_value)
            end
        end, sp.EventType.ANIMATION_EVENT)

    end
end

-- 添加动画队列
function meta:AddAnimation(anim_name, callback)
    local anim_data = {}
    anim_data.name = anim_name
    anim_data.callback = callback
    table.insert(self.animation_play_queue, anim_data)
end

-- 设置播放的动画
function meta:SetAnimation(anim_name)
    self.animation_play_queue = {}
    self:PlayAnimation(anim_name, true)
end

-- 获取战斗位置列表
function meta:GetSlotList(is_own)
    if is_own then
        return self.own_slot_list
    else
        return self.enemy_slot_list
    end
end

-- 播放移动动画
function meta:DoMoveBattleCard(is_own, src, dest)
    local slot_list
    if is_own then
        slot_list = self.own_slot_list
    else
        slot_list = self.enemy_slot_list
    end

    local src_widget = slot_list[src]
    local dest_widget = slot_list[dest]

    local src_empty = src_widget:GetEmptyNode()
    local dest_empty = dest_widget:GetEmptyNode()

    dest_widget:SetEmptyNode(src_empty, src, true)
    src_widget:SetEmptyNode(dest_empty, dest, true)

    slot_list[dest] = src_widget
    slot_list[src] = dest_widget
end

-- 设置怪兽卡
function meta:SetMonsterCard(is_own, pos, monster)
    local slot_list
    if is_own then
        slot_list = self.own_slot_list
    else
        slot_list = self.enemy_slot_list
    end
    local src_slot = slot_list[pos]
    if not monster then
        src_slot:setVisible(false)
        return
    end
    src_slot:SetMonsterCard(monster)
    src_slot.name = monster.name
    src_slot:DoDeploySlot(is_own)
    -- 更新UI信息
    local player = battle_logic:GetPlayerByOwn(is_own)
    src_slot:UpdateSlotInfo(player:GetBattleCard(pos))
end

-- 设置道具卡
function meta:SetItemCard(is_own, pos, item)
    local slot_list
    if is_own then
        slot_list = self.own_slot_list
    else
        slot_list = self.enemy_slot_list
    end
    local src_slot = slot_list[pos]
    src_slot:SetItemCard(item, true, function ()
        -- 更新UI信息
        local player = battle_logic:GetPlayerByOwn(is_own)
        local slot_info = player:GetBattleCard(pos)
        src_slot:UpdateSlotInfo(slot_info)
        src_slot:RefreshPosition()
    end)

end

function meta:DoAttckAnimation(is_own, pos, callback)
    local slot_list
    if is_own then
        slot_list = self.own_slot_list
    else
        slot_list = self.enemy_slot_list
    end
    local src_slot = slot_list[pos]
    local x,y = src_slot:getPosition()
    local actionUp = cc.JumpBy:create(0.3, cc.p(0,0), 10, 1)
    local actionCall = cc.CallFunc:create(callback)
    src_slot:runAction(cc.Sequence:create(actionUp, actionCall))
end

function meta:DoDeadAnimation(is_own, pos, callback)
    local slot_list
    if is_own then
        slot_list = self.own_slot_list
    else
        slot_list = self.enemy_slot_list
    end
    local src_slot = slot_list[pos]
    src_slot:stopAllActions()
    src_slot:PlayPowerAnimation("card_dead_normal", false, function ()
        src_slot:PlayAnimation("normal")
        src_slot:setVisible(false)
        callback()
    end)
end

-- 播放命中动画
function meta:DoHitAnimation(is_own, pos, callback)
    local slot_list
    local hurt_anim = ""
    if is_own then
        slot_list = self.own_slot_list
        hurt_anim = "hurt_ourside"
    else
        slot_list = self.enemy_slot_list
        hurt_anim = "hurt_enemy"
    end

    local slot = slot_list[pos]
    slot:PlayAnimation(hurt_anim, false, function ()
        slot:PlayAnimation("normal",false, function ()
            callback()
        end)
    end)
end

function meta:SetSlotHp(is_own, tar_pos, hp)
    local slot_list
    local number_list
    if is_own then
        slot_list = self.own_slot_list
        number_list = self.own_number_list
    else
        slot_list = self.enemy_slot_list
        number_list = self.enemy_number_list
    end
    local src_slot = slot_list[tar_pos]
    src_slot:SetHp(hp)

    local number_tip_node = number_list[tar_pos]
    number_tip_node:setVisible(true)
    if hp <= 0 then
        ui_helper:SetText(number_tip_node.number_txt, hp)
        number_tip_node.number_txt:setTextColor(HURT_COLOR)
    else
        ui_helper:SetText(number_tip_node.number_txt, "+"..hp)
        number_tip_node.number_txt:setTextColor(HEAL_COLOR)
    end
    number_tip_node:PlayAnimation("enter", false, function ()
        number_tip_node:setVisible(false)
    end)
end

function meta:SetSlotDefine(is_own, tar_pos, ad)
    local slot_list
    local number_list
    if is_own then
        slot_list = self.own_slot_list
        number_list = self.own_number_list
    else
        slot_list = self.enemy_slot_list
        number_list = self.enemy_number_list
    end

    local src_slot = slot_list[tar_pos]
    src_slot:SetArmor(ad)

    local number_tip_node = number_list[tar_pos]
    number_tip_node:setVisible(true)
    if ad <= 0 then
        ui_helper:SetText(number_tip_node.number_txt, ad)
        number_tip_node.number_txt:setTextColor(HURT_COLOR)
    else
        ui_helper:SetText(number_tip_node.number_txt, "+"..ad)
        number_tip_node.number_txt:setTextColor(HEAL_COLOR)
    end
    number_tip_node:PlayAnimation("enter", false, function ()
        number_tip_node:setVisible(false)
    end)
end

function meta:Update(elapsed_time)
    for i = 1, 3 do
        self.own_slot_list[i]:Update(elapsed_time)
        self.enemy_slot_list[i]:Update(elapsed_time)
    end

    self.hand_card_detail:Update(elapsed_time)

    local anim_data = self.animation_play_queue[1]
    if self.is_anim_over and anim_data then
        self.is_anim_over = false
        self:PlayAnimation(anim_data.name, false ,function ()
            self.is_anim_over = true
            if anim_data.callback then anim_data.callback() end
        end)
        table.remove(self.animation_play_queue, 1)
    end

end


-- 设置手牌
-- idx 手牌ID
-- card_info 卡牌信息
-- is_anim 是否是补充卡牌
function meta:SetHandCard(idx, card_info, is_anim)
    is_anim = is_anim or false
    local widget = self.hand_card_list[idx]
    if card_info then
        widget:Show(card_info)
        if is_anim then
            self.cur_operate_status = OPERATE_STATUS.replenish
            self.is_anim_over = false
            widget:ReplenishAnimation(card_info.type, function ()
                self.is_anim_over = true
                self.cur_operate_status = OPERATE_STATUS.normal
                battle_logic:DispatchEvent("update_operate_card")
            end)
        end
    else
        self.cur_operate_status = OPERATE_STATUS.normal
        widget:setVisible(false)
    end
end

function meta:SetCardEnabled(idx)
   self.hand_card_list[idx]:SetStatus(CARD_STATUS.enabled)
end

-- 设置选中的卡牌
function meta:SetSelectCard(idx)

    if self.select_card_idx == idx and idx > 0 then
        return
    end
    if idx == 0 then
        self.cur_operate_status = OPERATE_STATUS.normal
        if self.cur_move_card then
            self.cur_move_card:SetOperateStatus(self.cur_operate_status)
        end
        self.cur_move_card = nil
        battle_logic:ReqOperationFoucs(true, true, -1)
    elseif self.select_card_idx ~= idx then

        if self.select_card_idx and self.select_card_idx ~= 0 then
            self.hand_card_list[self.select_card_idx]:SetOperateStatus(OPERATE_STATUS.normal)
        end

        self.cur_operate_status = OPERATE_STATUS.selected
        self.cur_move_card = self.hand_card_list[idx]
        local pos_x, pos_y = self.cur_move_card:getPosition()
        local card_info = battle_logic.own_player:GetHandCard(idx)
        local pos = self.handcard_node:convertToWorldSpace({x = pos_x, y = pos_y})
        battle_logic:DispatchEvent("show_hand_card_detail", card_info, idx)
        battle_logic:ReqOperationFoucs(true, true, idx)
    end
    if battle_logic.is_play_animation or battle_logic.own_player == nil then
        return
    end
    if self.cur_move_card then
        self.cur_move_card:SetOperateStatus(self.cur_operate_status)
    end
    if self.select_card_idx ~= 0 then
        local old_card = self.hand_card_list[self.select_card_idx]
        -- print( debug.traceback() )
        old_card:RollBackAnimation()
    end
    self.select_card_idx = idx

    local own_map, enemy_map = battle_logic:GetPlaceSlotPos(idx)
    battle_logic:DispatchEvent("do_tips_animation", own_map, enemy_map)
end


function meta:RegisterWidgetEvent()
    -- 战斗节点详情监听
    for i = 1, 3 do
        local own_empty =  self.own_empty_list[i]

        own_empty:addTouchEventListener(function (widget, event_type)
            if event_type ~= ccui.TouchEventType.ended then
                return
            end
            local slot_info = battle_logic.own_player:GetBattleCard(i)
            if slot_info then
                battle_logic:DispatchEvent("push_battle_panel","slot_detail_panel", slot_info)
            end
        end)
        local enemy_empty =  self.enemy_empty_list[i]
        enemy_empty:addTouchEventListener(function (widget, event_type)
            if event_type ~= ccui.TouchEventType.ended then
                return
            end
            local slot_info = battle_logic.enemy_player:GetBattleCard(i)
            if slot_info then
                battle_logic:DispatchEvent("push_battle_panel","slot_detail_panel", slot_info)
            end
        end)
    end

    -- 献祭确定
    ui_helper:AddClick(self.sacrifice_confirm_btn, function ()
        if not self.is_sacrifice_mode then
            return
        end

        local sacrifice_data = self.sacrifice_data
        if sacrifice_data == nil then
            graphic:DispatchEvent("show_message", "un_sacrifice_target")
        else
            local is_hand = sacrifice_data.is_hand
            local pos = sacrifice_data.pos


            local callback = function (is_success)
                if is_success then
                    battle_logic:DispatchEvent("exit_sacrifice_mode")
                else
                    self.temp_show_card:setVisible(false)
                end
            end
            if battle_logic:ReqSacrificeCard(is_hand, pos, callback) then
                if is_hand == true then
                    local hand_card = self.hand_card_list[pos]
                    hand_card:setVisible(false)
                    self.temp_show_card:CloneHandCard(hand_card)
                else
                    local slot_card = self.own_slot_list[pos]
                    slot_card:setVisible(false)
                    self.temp_show_card:CloneSlotCard(slot_card)
                end
            end
        end
    end)
    -- 献祭取消
    ui_helper:AddClick(self.sacrifice_back_btn, function ()
        if not self.is_sacrifice_mode then
            return
        end
        battle_logic:DispatchEvent("exit_sacrifice_mode")
    end)
end

function meta:RegisterEvent()

    -- 进入献祭模式
    battle_logic:RegisterEvent("enter_sacrifice_mode",function ()
        if self.is_sacrifice_mode then
            return
        end

        -- 献祭按键回调
        local sacrifice_callback = function (is_hand, pos, cancel_func)
            local data = self.sacrifice_data or {}
            if data.cancel_func then
                data.cancel_func()
            end

            if data.is_hand == is_hand and data.pos == pos then
                self.sacrifice_data = nil
                self.sacrifice_confirm_btn:setColor(ui_helper:GetColor4B(0x7f7f7f))
            else
                data.is_hand = is_hand
                data.pos = pos
                data.cancel_func = cancel_func
                self.sacrifice_data = data
                self.sacrifice_confirm_btn:setColor(ui_helper:GetColor4B(0xffffff))
            end
        end
        self.sacrifice_data = nil
        self.sacrifice_confirm_btn:setColor(ui_helper:GetColor4B(0x7f7f7f))

        local duration = self:PlayAnimation("enter_sacri")
        for i = 1, 3 do
            local own_slot = self.own_slot_list[i]
            own_slot:SetStatus(own_slot.STATUS.disabled)

            local enemy_slot = self.enemy_slot_list[i]
            enemy_slot:setLocalZOrder(-1)

            local move_act = cc.MoveBy:create(duration, { x = 0, y = 264 })
            local curve_func = cc["EaseCubicActionInOut"]:create(move_act)
            own_slot:runAction(curve_func)
            if own_slot:isVisible() then
                own_slot:DoSacrificeMode(function (cancel_func)
                    sacrifice_callback(false, i, cancel_func)
                end)
            end
        end

        for i = 1, 4 do
            local hand_card = self.hand_card_list[i]
            hand_card:SetStatus(hand_card.STATUS.disabled)
            if hand_card:isVisible() then
                hand_card:DoSacrificeMode(function (cancel_func)
                    sacrifice_callback(true, i, cancel_func)
                end)
            end
        end
        self.is_sacrifice_mode = true
    end)

    -- 退出献祭模式
    battle_logic:RegisterEvent("exit_sacrifice_mode",function ( callback)
        if not self.is_sacrifice_mode then
            return
        end

        local duration = self:PlayAnimation("exit_sacri", false, function ()
            for i = 1, 3 do
                local enemy_slot = self.enemy_slot_list[i]
                enemy_slot:setLocalZOrder(CARD_ZORDER)
            end
            if callback then callback() end
        end)

        for i = 1, 3 do
            local own_slot = self.own_slot_list[i]
            local move_act = cc.MoveBy:create(duration, { x = 0, y = -264 })
            local curve_func = cc["EaseCubicActionInOut"]:create(move_act)
            own_slot:runAction(curve_func)
            own_slot:ExitSacrificeMode(i)
        end

        for i = 1, 4 do
            local hand_card = self.hand_card_list[i]
            hand_card:ExitSacrificeMode(i)
        end
        battle_logic:DispatchEvent("update_operate_card")

        self.sacrifice_data = nil
        self.is_sacrifice_mode = false
    end)

    -- 进入战场
    battle_logic:RegisterEvent("handcard_enter", function ()
        self:setVisible(true)
        self:PlayAnimation("enter", false, function ()
            -- 进入战场时，重置位置
            for i = 1, 4 do
                local pos_x, pos_y = self.hand_card_list[i]:getPosition()
                self.hand_card_list[i]:ResetTransform(i)
            end
        end)
        self.is_sacrifice_mode = false
    end)

    battle_logic:RegisterEvent("show_slot_icon",function (slot_pos, skill_name)
        if slot_pos then
            self:ShowSlotIcon(slot_pos, skill_name)
        else
            self:ShowAllSlotIcon(skill_name)
        end
    end)

    -- 设置手牌
    battle_logic:RegisterEvent("update_hand_card",function (is_own, idx, card, is_anim)
        if is_own then
            self:SetHandCard(idx, card, is_anim)
        end
    end)

    -- 设置战斗状态
    battle_logic:RegisterEvent("update_battle_stage",function (stage)
        local callback = function ()
            if stage == STAGE.own then
                self:AddAnimation("enter_round", function ()
                    for i = 1, 4 do
                        local pos_x, pos_y = self.hand_card_list[i]:getPosition()
                        self.hand_card_list[i]:ResetTransform(i)
                    end
                end)
                self.own_round = true
            else
                if self.own_round then
                    self:AddAnimation("exit_round", function ()
                        for i = 1, 4 do
                            local hand_card = self.hand_card_list[i]
                            hand_card:ResetTransform(i)
                            hand_card:SetStatus(CARD_STATUS.disabled)
                        end

                        for i = 1, 3 do
                            local own_tips_node = self.own_tips_list[i]
                            own_tips_node:setVisible(false)
                            local enemy_tips_node = self.enemy_tips_list[i]
                            enemy_tips_node:setVisible(false)
                        end
                    end)
                end
                self.own_round = false
            end
        end
        if self.is_sacrifice_mode then
            -- 如果当前处于献祭状态，必须先状态此状态
            battle_logic:DispatchEvent("exit_sacrifice_mode", callback)
        else
            callback()
        end
    end)

    -- 卡牌操作结束
    battle_logic:RegisterEvent("battle_oper_card_end",function (pos,callback)

        for i,v in ipairs(self.own_slot_list) do
            if v:IsClick(pos) then
                callback(false, v.slot_pos)
                return
            end
        end

        for i,v in ipairs(self.enemy_slot_list) do
            if v:IsClick(pos) then
                callback(true, v.slot_pos)
                return
            end
        end
        callback(true, -1)
    end)

    -- 部署手牌怪兽卡
    battle_logic:RegisterEvent("drop_hand_monster_card", function (src_pos, tar_pos, callback)
        local hand_card = self.hand_card_list[src_pos]
        if callback then callback() end
        battle_logic.is_play_animation = false
        hand_card:setVisible(false)


        local tar_slot = self.own_slot_list[tar_pos]
        local xx, yy = tar_slot:getPosition()

        local parent = hand_card:getParent()
        local sx, sy = parent:getPosition()
        local pt = hand_card:convertToWorldSpace({ x = 0, y = 0});
        tar_slot:setPosition(pt)

        local move_act = cc.MoveTo:create(0.3, { x = xx, y = yy})
        tar_slot:runAction(cc["EaseSineOut"]:create(move_act))

    end)

    -- 道具手牌动画
    battle_logic:RegisterEvent("item_hand_card", function (src_pos, tar_pos, callback)
        local hand_card = self.hand_card_list[src_pos]
        hand_card:ConsumeAnimation(callback)

        local tar_slot = self.own_slot_list[tar_pos]

        local xx, yy = tar_slot:getPosition()
        local parent = hand_card:getParent()
        local pt = parent:convertToNodeSpace({ x = xx, y = yy -22});

        local move_act = cc.MoveTo:create(0.4, pt)
        hand_card:runAction(cc["EaseSineOut"]:create(move_act))
    end)

    -- 消费牌
    battle_logic:RegisterEvent("consume_hand_card", function (src_pos, tar_pos, callback)
        local hand_card = self.hand_card_list[src_pos]
        hand_card:ConsumeAnimation(callback)

        -- local tar_slot = self.own_slot_list[tar_pos]

        -- local xx, yy = tar_slot:getPosition()
        -- local parent = hand_card:getParent()
        -- local pt = parent:convertToNodeSpace({ x = xx, y = yy -22});

        -- local move_act = cc.MoveTo:create(0.4, pt)
        -- hand_card:runAction(cc["EaseSineOut"]:create(move_act))
    end)

    -- 设置回滚动画
    battle_logic:RegisterEvent("hand_card_roll_back", function (src_pos)
        self.hand_card_list[src_pos]:RollBackAnimation()
    end)

    -- 献祭卡牌
    battle_logic:RegisterEvent("discard_hand_card", function (is_own, pos, is_sacrifice, callback)
        local widget = self.hand_card_list[pos]
        if not is_own  or not widget then
            callback()
            return
        end
        if is_sacrifice then
            self.temp_show_card:DoHandSacrificeAnimation(is_own, callback)
        else
            widget:DisCardAnimation(is_sacrifice, callback)
        end
    end)

    -- 更新操作状态
    battle_logic:RegisterEvent("update_operate_card", function ()
        if battle_logic.cur_stage == STAGE.own then
            local idxs = battle_logic:GetOperationCardIdx()
            local oper_count = 0
            for i,v in ipairs(idxs) do
                if v then
                    self.hand_card_list[i]:SetStatus(CARD_STATUS.enabled)
                    if battle_logic.battle_type == "guide" then
                        local card = self.hand_card_list[i].card_info
                        local power_list = card.power_list
                        if power_list and card.type == "monster" then
                            for _, power in pairs(power_list) do
                                self:ShowAllSlotIcon(power.name)
                            end
                        end
                    end
                    oper_count = oper_count + 1
                else
                    self.hand_card_list[i]:SetStatus(CARD_STATUS.disabled)
                end
            end
            -- refine:所有操作执行完毕后，自动进行战斗
            if oper_count == 0 then
                if battle_logic.battle_type == "guide" then
                    battle_logic:DispatchEvent("remind_fight_btn")
                end
                -- battle_logic:ReqBattleAttack()
            end
        end
    end)

    -- 销毁战斗位置
    battle_logic:RegisterEvent("sacrifice_slot", function (is_own, pos, is_sacrifice, callback)
        local slot_list = self:GetSlotList(is_own)
        local src_slot = slot_list[pos]
        if is_own then
            self.temp_show_card:DoSlotSacrificeAnimation(is_own, callback)
        else
            src_slot:DoSacrificeSlot(callback)
        end
    end)

    -- 销毁装备卡
    battle_logic:RegisterEvent("destroy_slot_item", function (is_own, pos)
        local slot_list = self:GetSlotList(is_own)
        local src_slot = slot_list[pos]
        src_slot:DoDestroyEquip()
        self:SetItemCard(is_own, pos, nil)
    end)

    -- 献祭牌堆的卡牌
    battle_logic:RegisterEvent("discard_deck_card", function (is_own, discard_card)
        self.temp_show_card:DoSacrificeDeckCard(is_own, discard_card)
    end)

    -- 部署怪兽卡
    battle_logic:RegisterEvent("deploy_monster_card",function (is_own, pos, monster)
        self:SetMonsterCard(is_own, pos, monster)
    end)

    -- 部署道具卡
    battle_logic:RegisterEvent("deploy_item_card",function (is_own, pos, item)
        self:SetItemCard(is_own, pos, item)
    end)

    -- 移动卡牌
    battle_logic:RegisterEvent("move_battle_card",function (is_own, src, dest, callback)
        self:DoMoveBattleCard(is_own, src, dest)
        if callback then
            performWithDelay(self, callback, 0.3)
        end
    end)

    -- 更新血量
    battle_logic:RegisterEvent("update_slot_hp", function (is_own, tar_pos, hp)
        self:SetSlotHp(is_own, tar_pos, hp)
    end)

    -- 设置血量
    battle_logic:RegisterEvent("set_slot_hp", function (is_own, tar_pos, hp)
        local slot_list
        if is_own then
            slot_list = self.own_slot_list
        else
            slot_list = self.enemy_slot_list
        end
        local src_slot = slot_list[tar_pos]
        src_slot:SetHp(hp, true)
    end)

    -- 更新防御
    battle_logic:RegisterEvent("update_slot_define", function (is_own, tar_pos, define)
        self:SetSlotDefine(is_own, tar_pos, define)
    end)

    battle_logic:RegisterEvent("set_slot_define", function (is_own, tar_pos, define)
        local slot_list
        if is_own then
            slot_list = self.own_slot_list
        else
            slot_list = self.enemy_slot_list
        end
        local src_slot = slot_list[tar_pos]
        src_slot:SetArmor(define, true)
    end)
    -- 执行攻击动画
    battle_logic:RegisterEvent("do_attack_animation", function (is_own, tar_pos, callback)
        self:DoAttckAnimation(is_own, tar_pos, callback)
    end)
    -- 执行命中动画
    battle_logic:RegisterEvent("do_hit_animation", function (is_own, tar_pos, callback)
        self:DoHitAnimation(is_own, tar_pos, callback)
    end)
    -- 执行死亡动画
    battle_logic:RegisterEvent("do_dead_animation", function (is_own, tar_pos, callback)
        self:DoDeadAnimation(is_own, tar_pos, callback)
    end)
    -- 执行状态动画
    battle_logic:RegisterEvent("do_status_animation", function (is_own, tar_pos, status_name, status_round, status_value, callback)
        local slot_list = self:GetSlotList(is_own)
        local src_slot = slot_list[tar_pos]
        src_slot:DoStatusAnimation(status_name, status_round, status_value, callback)
    end)

    -- 执行提示动画
    battle_logic:RegisterEvent("do_tips_animation", function (own_tips_map, enemy_tips_map)
        own_tips_map = own_tips_map or {}
        enemy_tips_map = enemy_tips_map or {}
        if battle_logic.cur_stage ~= battle_logic.STAGE.own then
            return
        end
        for i = 1, 3 do
            local own_tips_node = self.own_tips_list[i]
            own_tips_node:setVisible(own_tips_map[i])
            local enemy_tips_node = self.enemy_tips_list[i]
            enemy_tips_node:setVisible(enemy_tips_map[i])
        end
    end)

    -- 指定护盾格挡
    battle_logic:RegisterEvent("do_armor_block", function (tar_user_id, tar_pos)
        local skill_tip = nil
        if battle_logic.own_player.user_id == tar_user_id then
            skill_tip = self.own_skill_list[tar_pos]
        else
            skill_tip = self.enemy_skill_list[tar_pos]
        end

        local icon_img = skill_tip.icon_img
        local value_txt = skill_tip.value_txt
        local value = 0
        if value == 0 or not value then
            value_txt:setVisible(false)
            icon_img:setPositionX(SKILL_TIPS_CEN_POS)
        else
            value_txt:setVisible(true)
            icon_img:setPositionX(SKILL_TIPS_SRC_POS)
        end
        icon_img:loadTexture(resource:GetSkillIcon("armor"))
        skill_tip:setVisible(true)
        skill_tip:PlayAnimation("enter", false, function ()
            skill_tip:setVisible(false)
            battle_logic:DispatchEvent("sub_event_complete")
        end)
    end)

    -- 执行技能动画
    battle_logic:RegisterEvent("do_power_animation",function (tar_user_id, tar_pos, tar_pos_list, power_name, src_user_id, src_pos, value, callback)
        local src_slot = self:GetSlotList(battle_logic.own_player.user_id == src_user_id)[src_pos]
        local tar_slot = self:GetSlotList(battle_logic.own_player.user_id == tar_user_id)[tar_pos]

        local power_config = POWER_CONFIG_MAP[power_name]

        local anim_name = nil
        -- 获取吟唱动画
        if power_config.casting_anim ~= "" then
            anim_name = power_config.casting_anim
        end

        if src_slot and POWER_ONLY_ONE[power_name] then
            src_slot:SetVisibleSkill(power_name)
        end

        local skill_tip = nil
        if battle_logic.own_player.user_id == src_user_id then
            skill_tip = self.own_skill_list[src_pos]
        else
            skill_tip = self.enemy_skill_list[src_pos]
        end

        -- 执行特效播放
        local function do_effect_list()
            local is_has = false
            local effect_name = nil
            if power_config.hit_effect ~= "" then
                effect_name = power_config.hit_effect
            end

            if src_slot and tar_slot and src_slot.next_power_animation then
                effect_name = src_slot.next_power_animation
                src_slot.next_power_animation = nil
            end

            local effect_src_slot = src_slot
            if power_config.hit_effect_type == "moved" then
                effect_src_slot = src_slot
            elseif power_config.hit_effect_type == "fixed" then
                effect_src_slot = tar_slot
            end

            if effect_name and tar_slot then
                is_has = true
                battle_logic:DispatchEvent("do_effect_animation", effect_src_slot, tar_slot, effect_name)
            end

            if effect_name and tar_pos_list then
                for _, pos in pairs(tar_pos_list) do
                    is_has = true
                    local tar = self:GetSlotList(battle_logic.own_player.user_id == tar_user_id)[pos]
                    if tar then
                        battle_logic:DispatchEvent("do_effect_animation", effect_src_slot, tar, effect_name)
                    end
                end
            end

            -- 设置下次动画效果,以及技能提示
            if power_config.cover_effect ~= "" and src_slot then
                src_slot.next_power_animation = power_config.cover_effect
                src_slot.next_power_tips = power_config.name
            end
            return is_has
        end

        local do_effect_func = do_effect_list

        if skill_tip then
            local icon_img = skill_tip.icon_img
            local value_txt = skill_tip.value_txt
            if value == 0 or not value then
                value_txt:setVisible(false)
                icon_img:setPositionX(SKILL_TIPS_CEN_POS)
            else
                value_txt:setVisible(true)
                icon_img:setPositionX(SKILL_TIPS_SRC_POS)
            end
            if src_slot.next_power_tips then
                power_name = src_slot.next_power_tips
                src_slot.next_power_tips = nil
            end
            icon_img:loadTexture(resource:GetSkillIcon(power_name))
            ui_helper:SetText(value_txt, tostring(value))
            skill_tip:setVisible(true)

            if anim_name == nil then
                -- 如果没有施法动画，就直接播放特效。
                if do_effect_func then
                    if not do_effect_func() then
                        battle_logic:DispatchEvent("sub_event_complete")
                    end
                    do_effect_func = nil
                end
            end

            skill_tip:PlayAnimation("enter", false, function ()
                skill_tip:setVisible(false)
            end)
        end

        local anim_slot = src_slot
        if anim_name == "card_unsummon" then
            anim_slot = tar_slot
        end

        if anim_slot and anim_name then
            anim_slot:PlayPowerAnimation(anim_name, anim_slot, callback, function ()
                if do_effect_func() then
                    do_effect_func = nil
                else
                    battle_logic:DispatchEvent("sub_event_complete")
                end
            end)
        else
            -- 恐惧技能没有施法动画，被上面执行do_effect_func过了
            if do_effect_func then
                if do_effect_func() then
                    do_effect_func = nil
                else
                    battle_logic:DispatchEvent("sub_event_complete")
                end
            end
        end
    end)

    -- 执行特效动画
    battle_logic:RegisterEvent("do_effect_animation",function (src_slot, tar_slot, effect_name, is_ador, rotation)
        local project_name = nil
        local anim_name = nil

        rotation = rotation or 0


        local data = string.split(effect_name, ":")
        if #data == 1 then
            project_name = data[1]
            anim_name = data[1]
        else
            project_name = data[1]
            anim_name = data[2]
        end

        if not src_slot then
            src_slot = tar_slot
        end

        local is_hurt_event = false


        local data_path = "animation/"..project_name..".json"
        local atlas_path = "animation/"..project_name..".atlas"

        local effect_node = sp.SkeletonAnimation:create(data_path, atlas_path, 1)
        effect_node:setAnimation(0, anim_name, false)
        self:addChild(effect_node, EFFECT_ZORDER)

        local src_x, src_y = src_slot:getPosition()
        local tar_x, tar_y = tar_slot:getPosition()
        effect_node:setPosition({x = src_x, y = src_y})

        effect_node:setRotation(rotation)

        local CalcAnger = function(src_x, src_y, desc_x, desc_y)
            local x = desc_x - src_x
            local y = desc_y - src_y
            local anger = 90 - math.atan(y / x) * 180 / math.pi

            if x >= 0 then
                anger = anger + 0
            else
                anger = anger + 180;
            end
            return anger % 360
        end
        -- 特效结束事件
        effect_node:registerSpineEventHandler(function (event)
            performWithDelay(self, function()
                self:removeChild(effect_node)
            end, 0.5)
            -- 如果是装饰的特效，就不做hurt事件
            if not is_hurt_event and not is_ador then
                battle_logic:DispatchEvent("sub_event_complete")
            end
        end, sp.EventType.ANIMATION_END)

        -- 特效自定义事件
        effect_node:registerSpineEventHandler(function (event)
            local float_value = event.eventData.floatValue
            local int_value = event.eventData.intValue
            local string_value = event.eventData.stringValue
            local event_name = event.eventData.name
            if event_name == "bullet" then
                if float_value == 0 then
                    effect_node:setPosition({x = tar_x, y = tar_y})
                else
                    local move_act = cc.MoveTo:create(float_value, {x = tar_x, y = tar_y})
                    local curve_func = cc[string_value]
                    if curve_func then
                        move_act = curve_func:create(move_act)
                    end
                    effect_node:setPosition({x = src_x, y = src_y})
                    effect_node:runAction(move_act)
                end
            elseif event_name == "sound" then
                audio_manager:PlayEffect(string_value)
            elseif event_name == "rotation" then
                local anger = CalcAnger(src_x, src_y, tar_x, tar_y)
                effect_node:setRotation(anger)
            elseif event_name == "hurt" then
                battle_logic:DispatchEvent("sub_event_complete")
                is_hurt_event = true
            elseif event_name == "shake" then
                battle_logic:DispatchEvent("effect_screen_shake", float_value, int_value)
            end
        end, sp.EventType.ANIMATION_EVENT)
    end)

    -- 执行伤害特效
    battle_logic:RegisterEvent("do_hurt_effect", function (value, is_own, tar_pos)
        if value >= 3 and value <= 5 then
            battle_logic:DispatchEvent("effect_screen_shake", 0.4, 11)
            local tar_slot = self:GetSlotList(is_own)[tar_pos]
            battle_logic:DispatchEvent("do_effect_animation", tar_slot, tar_slot, "effects_hurt_smoke_2", true, math.random(360))
        elseif value > 5 then
            battle_logic:DispatchEvent("effect_screen_shake", 0.6, 16)
            local tar_slot = self:GetSlotList(is_own)[tar_pos]
            battle_logic:DispatchEvent("do_effect_animation", tar_slot, tar_slot, "effects_hurt_smoke", true, math.random(360))
            audio_manager:PlayEffect("big_hurt")
        end
    end)
end


-- 注册触摸事件
function meta:RegisterTouchEvent()


    local function onTouchBegin(touch,event)
        local p = touch:getLocation()
        self.pre_touch_pos = p

        for i = 1, 4 do
            if self.hand_card_list[i]:IsClick(touch) and battle_logic.battle_result == nil then
                self:SetSelectCard(i)
                return true
            end
        end

        return true
    end

    local function onTouchMove(touch,event)
        local p = touch:getLocation()
        if not self.cur_move_card then
            self.select_card_idx = 0
            return
        end

        if self.cur_operate_status == OPERATE_STATUS.moved then
               -- 移动卡牌
            self.cur_move_card:DoMove(p)
        else
            if self.cur_operate_status == OPERATE_STATUS.selected and self.pre_touch_pos.y < p.y and p.y > 170 and battle_logic.cur_stage == STAGE.own then
                -- 如果是向上移动，并超过了170像素。就认为进行移动状态。 只有我方行动的时候。才可以进入拖动状态
                self.cur_operate_status = OPERATE_STATUS.moved
                self.cur_move_card:SetOperateStatus(OPERATE_STATUS.moved)
                -- 进入移动状态
                self.cur_move_card:StartMove(p)

                battle_logic:DispatchEvent("hide_hand_card_detail")
            else
                local is_selected = false
                for i = 1, 4 do
                    if self.hand_card_list[i]:IsClick(touch) then
                        self:SetSelectCard(i)
                        return
                    end
                end
                if not is_selected then
                    self:SetSelectCard(0)
                    battle_logic:DispatchEvent("hide_hand_card_detail")
                end
            end
        end

        self.pre_touch_pos = p
    end

    local function onTouchEnd(touch,event)
        -- 战场退出事件执行
        if self.battlefield_exit_event then
            self.battlefield_exit_event()
            self.battlefield_exit_event = nil
        end

        local p = touch:getLocation()
        if not self.cur_move_card then
            self.select_card_idx = 0
            return
        end

        -- print("self.cur_operate_status = "..self.cur_operate_status)

        if self.cur_operate_status == OPERATE_STATUS.moved then
            battle_logic:DispatchEvent("battle_oper_card_end", p, function (is_enemy, target)
                local own_player = battle_logic.own_player
                if target == -1 or battle_logic.cur_stage ~= battle_logic.STAGE.own then
                    -- 回滚操作
                    self:SetSelectCard(0)
                end
                local src_pos = self.select_card_idx
                if battle_logic:DoHandCard(src_pos, is_enemy, target) then
                    self.cur_operate_status = OPERATE_STATUS.summon
                    self.cur_move_card = nil                    
                    battle_logic:ReqBattleMove(src_pos, is_enemy, target, function (result, recv_msg)
                        if result ~= "success" then
                            graphic:DispatchEvent("show_message", result)
                            self.hand_card_list[src_pos]:setVisible(true)
                            self.hand_card_list[src_pos]:RollBackAnimation()
                            self:SetSelectCard(0)
                            self.cur_operate_status = OPERATE_STATUS.normal
                        end
                        self.select_card_idx = 0
                    end)
                    local own_map, enemy_map = battle_logic:GetPlaceSlotPos(0)
                    battle_logic:DispatchEvent("do_tips_animation", own_map, enemy_map)
                else
                    self:SetSelectCard(0)
                end
            end)
        else
            self:SetSelectCard(0)
            battle_logic:DispatchEvent("hide_hand_card_detail")
        end
        self.pre_touch_pos = p
    end

    local listener = cc.EventListenerTouchOneByOne:create();
    listener:setSwallowTouches(false)
    listener:registerScriptHandler(onTouchBegin,cc.Handler.EVENT_TOUCH_BEGAN);
    listener:registerScriptHandler(onTouchMove,cc.Handler.EVENT_TOUCH_MOVED);
    listener:registerScriptHandler(onTouchEnd,cc.Handler.EVENT_TOUCH_ENDED);

    local event_dispatcher = cc.Director:getInstance():getEventDispatcher()
    event_dispatcher:addEventListenerWithSceneGraphPriority(listener, self);
end


return meta
