-- 战斗战牌
local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local bit = require "utils.bit_extension"

local battle_logic = require "logic.battle"
local constants = require "common.constants"
local defines = require "manager.defines"

local skill_template = require "modules.battle.skill_template"
local audio_manager = require "manager.audio_manager"
local data_template = require "manager.data_template"


local CARD_KIND_COLOR = defines["CARD_KIND_COLOR"]
local STATUS_TYPE = constants["STATUS_TYPE"]
local POWER_NAME = constants["POWER_NAME"]
local MAIN_POWER = constants.MAIN_POWER
local STATUS_CONFIG_MAP = data_template.status_config
local CARD_IMMOLATION_CRYSTAL = constants["CARD_IMMOLATION_CRYSTAL"]


local meta = class("battle_slot_card",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/battle/battle_slot_card.csb")
end)

meta.STATUS = {
    disabled = 1,
    enabled = 2,
}

meta.cur_status = 0

local old_position = {x = 0, y = 0}

function meta:ctor(node, is_enemy)

    ui_helper:BindTimeLine(self, "interface/battle/battle_slot_card.csb")

    local root_node = self:getChildByName("card_node")
    local level_node = self:getChildByName("level")
    ui_helper:BindTimeLine(level_node, "interface/battle/battlecard_level.csb")
    self.monster_level_txt = level_node:getChildByName("value")
    local level_skele_container = level_node:getChildByName("animation")
    local level_skele_node = sp.SkeletonAnimation:create("animation/lv_number.json", "animation/lv_number.atlas", 1)
    level_skele_container:addChild(level_skele_node)
    self.level_node = level_node
    self.level_skele_node = level_skele_node
    self.is_show_level = false

    -- 光照
    self.light_node = root_node:getChildByName("light")
    self.light_node:setVisible(false)
    ui_helper:BindTimeLine(self.light_node, "interface/battle/battle_card_light.csb")

    -- -- 卡牌底
    local card_template_node = root_node:getChildByName("card_template")
    local card_bottom_item = require("modules.common.battle_card_template").new(card_template_node)
    card_bottom_item:setVisible(false)
    if is_enemy then
        card_bottom_item:setPosition(90, 105)
    else
        card_bottom_item:setPosition(90, 124)
    end
    self.card_bottom_item = card_bottom_item

    -- Spine动画
    local skeleton_node = sp.SkeletonAnimation:create("animation/battle_card.json", "animation/battle_card.atlas", 1)
    skeleton_node:setAnimation(0, "card_normal", true)
    skeleton_node:setScale(1.3)
    skeleton_node:setPosition(old_position)
    skeleton_node:setToSetupPose()
    self.skeleton_node = skeleton_node

    local spine_node = root_node:getChildByName("spine_node")
    spine_node:addChild(skeleton_node)

    self.src_rotation = 0
    self.is_enemy = is_enemy
    if is_enemy then
        self.src_rotation = 180
    else
        self.is_enemy = false
    end
    card_bottom_item:setRotation(self.src_rotation)
    skeleton_node:setRotation(self.src_rotation)

    -- 渲染节点
    local render_texture = cc.RenderTexture:create(180, 229)
    render_texture:setPosition(0, -11)
    render_texture:setVisible(false)
    render_texture:setScale(1.012)
    root_node:addChild(render_texture, -1)
    self.render_texture = render_texture

    -- 卡牌UI
    local card_top_item = root_node:getChildByName("slot_ui")
    ui_helper:BindTimeLine(card_top_item, "interface/battle/card_battlefield_ui_template.csb")
    card_top_item:setPosition({ x = 0, y = 11})
    self.card_ui_panel = card_top_item

    local ui_node = card_top_item:getChildByName("ui_node")
    self.ui_node = ui_node

    -- 生命节点
    self.hp_node = ui_helper:ExpandUI(ui_node, "hp", "modules.battle.property_template")
    self.hp_node:SetIcon("creature_icon")

    -- 护甲节点
    self.armor_node =  ui_helper:ExpandUI(ui_node, "armor", "modules.battle.property_template")
    self.armor_node:SetIcon("armor")

    -- 主动技能模板
    self.as_widget_list = {}
    for i = 1, 4 do
        self.as_widget_list[i] = ui_helper:ExpandUI(ui_node, "skill1_template"..i, "modules.battle.skill_template")
        ui_helper:BindTimeLine(self.as_widget_list[i], "interface/battle/card_battlefield_skill1_template.csb")
        self.as_widget_list[i]:setVisible(false)
    end

    self.skill2_list_node = ui_node:getChildByName("skill2_listbg")

    -- 被动技能模板
    self.ps_widget_list = {}
    self.ps_widget_size = 0

    -- 是否在播放动画
    self.is_play_animation = false
    self.animation_stack = {}

    -- 献祭模块
    self.sacrifice_tip_node = ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_sacritip_node.csb")
    self.sacrifice_tip_node:PlayAnimation("normal")
    self.sacrifice_tip_node:setPosition({ x = 0, y = 90})
    self:addChild(self.sacrifice_tip_node)

    self.sacrifice_select_node = ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_sacritip_node.csb")
    self.sacrifice_select_node:PlayAnimation("normal")
    self.sacrifice_select_node:setPosition({ x = 0, y = 0})
    self:addChild(self.sacrifice_select_node)

    -- 创建手牌的demo
    local demo_node = require("modules.common.card_hand_item").new()
    demo_node:setPosition(219, 269)
    demo_node:setVisible(false)
    self:addChild(demo_node)
    -- 预渲染Demo
    self.demo_node = demo_node

    -- 预渲染节点
    local render_hand_texture = cc.RenderTexture:create(438, 538)
    render_hand_texture:setVisible(false)
    render_hand_texture:setScale(1.0)
    self:addChild(render_hand_texture)
    self.render_hand_texture = render_hand_texture


    -- 要隐藏的技能图标
    self.visible_power = {}

    -- 事件回调
    self.slot_event_callback = {}
    self.slot_end_callback = {}

    -- self:RegisterEvent()
    self:RegisterWidgetEvent()
end

-- TODO:rename function name
--      separation function "SetEmptyNode" and "runAction"
function meta:SetEmptyNode(empty_node, pos, is_move)
    self.empty_node = empty_node
    if is_move and self:isVisible() then
        self:stopAllActions()
        local x,y = empty_node:getPosition()
        local move_act = cc.MoveTo:create(0.2, {x = x, y = y})

        local callback = cc.CallFunc:create(function()
            self:RefreshPosition()
        end)

        local sequence = cc.Sequence:create(move_act, callback)
        self:runAction(sequence)
    else
        self:setPosition(empty_node:getPosition())
    end
    self.slot_pos = pos
    self.src_zorder = self:getLocalZOrder()
end

function meta:GetEmptyNode()
    return self.empty_node
end


function meta:SetStatus(status)
    if self.cur_status == status then
        return
    end

    local light_node = self.light_node
    if status == self.STATUS.disabled then
        -- 不可用动画
        if self.cur_status == self.STATUS.enabled then
            light_node:PlayAnimation("exit_active", false, function ()
                light_node:setVisible(false)
            end)
        else
            light_node:setVisible(false)
        end
    elseif status == self.STATUS.enabled then
        -- 可用动画
        light_node:setVisible(true)
        light_node:PlayAnimation("enter_active",false, function ()
            light_node:PlayAnimation("loop_active")
        end)
    end
    self.cur_status = status
end
-- 进入献祭状态
function meta:DoSacrificeMode(click_callback)
    self.sacrifice_select_node:setVisible(true)

    local crystal_num = CARD_IMMOLATION_CRYSTAL["battle"]

    local slot_info = self.slot_info
    local crystal_power = slot_info.power_map[POWER_NAME.crystal]
    if crystal_power then
        crystal_num = crystal_num + crystal_power.value
    end
    local root_node = self.sacrifice_tip_node:getChildByName("node")
    local tip1_node = root_node:getChildByName("tip1")
    local value_txt = tip1_node:getChildByName("value")
    ui_helper:SetText(value_txt, crystal_num)
    local title_node = tip1_node:getChildByName("title") --这个是手牌道具这些东西
    ui_helper:SetTextByKey(title_node, "the_battle_card") --这个是战斗手牌


    self.light_node:setVisible(true)
    local click_btn = self.sacrifice_select_node:getChildByName("click")
    ui_helper:AddClick(click_btn, function ()

        self.sacrifice_tip_node:setVisible(true)
        self.sacrifice_tip_node:PlayAnimation("tip")

        -- 开始发光
        self:SetStatus(self.STATUS.enabled)
        self.sacrifice_select_node:PlayAnimation("icon")
        click_callback(function ()
            self.sacrifice_tip_node:setVisible(false)

            self.sacrifice_select_node:PlayAnimation("normal")
            self:SetStatus(self.STATUS.disabled)

        end)
    end)
end

-- 退出献祭模式
function meta:ExitSacrificeMode(pos)
    self.sacrifice_tip_node:setVisible(false)
    self.sacrifice_select_node:setVisible(false)
    self.sacrifice_select_node:PlayAnimation("normal")
    self:SetStatus(self.STATUS.disabled)
end

-- 设置生命
function meta:SetHp(hp, is_refrish)
    if is_refrish then
        self.hp_node:SetValue(hp)
    else
        if self.hp_node:UpdateValue(hp, true) then
            self.hp_node:PlayAnimation("exit", false)
        end
    end

end

-- 设置护甲
function meta:SetArmor(armor, is_refrish)
    if is_refrish then
        self.armor_node:SetValue(armor)
    else
        if self.armor_node:UpdateValue(armor, true) then
            self.armor_node:PlayAnimation("exit", false)
            -- 护甲卡移除
            self:RemoveEquip()
            self.card_ui_panel:PlayAnimation("exit_equip")
        end
    end
end

function meta:SetMonsterCard(monster_card)
    if monster_card.level > 1 then
        self.is_show_level = true
        ui_helper:SetText(self.monster_level_txt, monster_card.level)
    else
        self.is_show_level = false
    end

    -- 手牌渲染模板
    self.demo_node:SetCardInfo(monster_card)
    self.render_hand_texture:beginWithClear(0.0,0.0,0.0,0.0)
    self.demo_node:setVisible(true)
    self.demo_node:visit()
    self.demo_node:setVisible(false)
    self.render_hand_texture:endToLua()


    -- 战斗渲染模板
    self.card_bottom_item:SetCardInfo(monster_card)
    self.render_texture:beginWithClear(0.0,0.0,0.0,0.0)
    self.card_bottom_item:setVisible(true)
    self.card_bottom_item:visit()
    self.card_bottom_item:setVisible(false)
    self.render_texture:endToLua()


    local card_texture = self.render_texture:getSprite():getTexture()
    card_texture:setAntiAliasTexParameters()
    self.skeleton_node:pushSlotTexture("card_info", 0, card_texture)

    local card_texture = self.render_hand_texture:getSprite():getTexture()
    card_texture:setAntiAliasTexParameters()
    self.skeleton_node:pushSlotTexture("card_pro_2", 0, card_texture)

    self.hp_node:InitValue(monster_card.hp)
    self.armor_node:InitValue(0)
    self.armor_node:setVisible(false)
end

function meta:SetItemCard(item_card, is_anim, callback)
    if is_anim == nil then
        is_anim = true
    end
    self.card_bottom_item:SetEquipInfo(item_card)
    self.render_texture:beginWithClear(0.0,0.0,0.0,0.0)
    self.card_bottom_item:setVisible(true)
    self.card_bottom_item:visit()
    self.card_bottom_item:setVisible(false)
    self.render_texture:endToLua()

    local card_texture = self.render_texture:getSprite():getTexture()
    card_texture:setAntiAliasTexParameters()
    self.skeleton_node:pushSlotTexture("card_info", 0, card_texture)

    if item_card then
        if is_anim then
            self:PlayEffectAnimation("effects_equipment", callback)
        else
            if callback then callback() end
        end
        if item_card.hp > 0 then
            self.armor_node:setVisible(true)
            self.armor_node:InitValue(item_card.hp)
        else
            self.armor_node:setVisible(false)
        end
    else
        self.armor_node:setVisible(false)
        if callback then callback() end
    end
end

-- 设置无效技能
function meta:SetVisibleSkill(power_name)
    local power_widget = self:GetPowerWidget(power_name)
    if power_widget then
        power_widget:setVisible(false)
    else
        self.visible_power[power_name] = true
    end
    self:RefreshPassiveListPos()
end

-- 设置技能可用状态
function meta:SetAgainstSkill(power_list, is_against)
    power_list = power_list or {}
    is_against = is_against or false
    local handler = function (widget_list)
        for k,v in pairs(widget_list) do
            if v:isVisible() then
                for idx, power_name in pairs(power_list) do
                    if v.power_name == power_name then
                        v:SetAgainst(is_against)
                        break
                    end
                end
            end
        end
    end

    handler(self.as_widget_list)
    handler(self.ps_widget_list)
end

-- 设置远程禁用
function meta:SetRangedAgainst(is_against)
    if self.ranged_widget then
        self.ranged_widget:SetAgainst(is_against)
    end
end

-- 设置近战禁用
function meta:SetMeleeAgainst(is_against)
    if self.melee_widget then
        self.melee_widget:SetAgainst(is_against)
        if self.slot_info:GetPower(POWER_NAME.reach) or self.slot_info:GetPower(POWER_NAME.backstab) then
            self.melee_widget:SetAgainst(false)
        end
    end
end

-- 刷新位置信息所影响的数据
function meta:RefreshPosition()
    local slot_pos = self.slot_pos

    local slot_info = nil
    if self.is_enemy then
        slot_info = battle_logic.enemy_player.battle_slot[slot_pos]
    else
        slot_info = battle_logic.own_player.battle_slot[slot_pos]
    end
    if not slot_info then
        return
    end
    if slot_pos == 1 then
        self:SetMeleeAgainst(false)
        self:SetRangedAgainst(true)
    else
        self:SetMeleeAgainst(true)
        self:SetRangedAgainst(false)
    end

end


-- 更新战斗位置信息
function meta:UpdateSlotInfo(slot_info)
    local as_select_idx = 0
    local ps_select_idx = 0

    for i = 1, 4 do
        self.as_widget_list[i]:SetAgainst(false)
        self.as_widget_list[i]:setVisible(false)
    end

    self.slot_info = slot_info

    self.ranged_widget = nil
    self.melee_widget = nil
    local other_power_name_list = {}
    local as_select_idx = 0
    for k,v in pairs(slot_info.power_map) do
        if MAIN_POWER[k] == 1 then
            as_select_idx = as_select_idx + 1
            local widget = self.as_widget_list[as_select_idx]
            if widget then
                widget:setVisible(true)
                widget:SetIcon(k)
                widget:InitValue(v.value)

                if k == POWER_NAME.ranged then
                    self.ranged_widget = widget
                end

                if k == POWER_NAME.melee then
                    self.melee_widget = widget
                end
            end

            if self.visible_power[k] then
                widget:setVisible(false)
                self.visible_power[k] = false
            end
        else
            table.insert(other_power_name_list, k)
        end
    end

    local size = #other_power_name_list
    if size == 0 then
        self.skill2_list_node:setVisible(false)
    else
        self.skill2_list_node:setVisible(true)
    end

    for k,v in pairs(self.ps_widget_list) do
        v:setVisible(false)
    end

    for k,v in pairs(other_power_name_list) do
        local template = self.ps_widget_list[k]
        if not template then
            template = skill_template.new()
            table.insert(self.ps_widget_list, template)
            self.skill2_list_node:addChild(template)
        end
        template:SetIcon(v)
        template:InitValue(slot_info:GetPowerValue(v))
        template:setVisible(true)

        if self.visible_power[v] then
            template:setVisible(false)
            self.visible_power[v] = false
        end
    end

    self:RefreshPassiveListPos()
    self:RefreshStatusInfo(slot_info.status_map)
end

-- 刷新被动列表位置
function meta:RefreshPassiveListPos()
    local idx = 1
    local size = 0
    for _, template in pairs(self.ps_widget_list) do
        if template:isVisible() then
            size = size + 1
        end
    end

    if size == 0 then
        self.skill2_list_node:setVisible(false)
    else
        self.skill2_list_node:setVisible(true)
    end

    for _, template in pairs(self.ps_widget_list) do
        if template:isVisible() then
            local offset_x = 71 - ((size - 1) * 30) / 2 + (idx - 1) * 30
            template:setPosition({x = offset_x, y = 15})
            idx = idx + 1
        end
    end

end

-- 添加被动技能
function meta:PushPassiveSkill(name, value)
    value = value or 0
    local power_widget = self:GetPowerWidget(name)
    if not power_widget then
        template = skill_template.new()
        table.insert(self.ps_widget_list, template)
        self.skill2_list_node:addChild(template)
        template:SetIcon(name)
        template:InitValue(value)
        template:setVisible(true)
        self:RefreshPassiveListPos()
    end
end

-- 删除被动技能
function meta:DelPassiveSkill(name)
    local power_widget = self:GetPowerWidget(name)
    if power_widget then
        power_widget:setVisible(false)
        self:RefreshPassiveListPos()
    end
end

-- 点击事件
function meta:IsClick(pos)
    local camera = cc.Camera:getVisitingCamera()
    return self.empty_node:hitTest(pos, camera, nil)
end

-- 部署卡牌
function meta:DoDeploySlot(is_own, end_callback)
    self.card_ui_panel:setVisible(false)
    local anim_name = ""
    if is_own then
        anim_name = "card_hand_to_battle"
    else
        anim_name = "card_summon_back"
    end

    -- anim_name, tar_slot, callback, effect_callback
    -- battle_logic.is_play_animation = true
    self:PlayPowerAnimation(anim_name, false ,function ()
        -- 落卡动画完毕，继续执行指令
        -- battle_logic.is_play_animation = false
        if end_callback then end_callback() end
    end)
end

-- 献祭动画
function meta:DoSacrificeSlot(callback)
    self.card_ui_panel:setVisible(false)
    self:PlayPowerAnimation("card_destroy", false, function ()
        if callback then
            callback()
        end
        self.skeleton_node:setToSetupPose()
        self:setVisible(false)
    end) 
end

-- 摧毁装备
function meta:DoDestroyEquip()
end

-- 移除装备
function meta:RemoveEquip()
    self:SetItemCard(nil)
end

function meta:Update(elapsed_time)
    if not self.is_play_animation and #self.animation_stack > 0 then
        local _next = self.animation_stack[1]
        -- 两个动画的间隔要超过1秒
        performWithDelay(self, function ()
            self:PlayPowerAnimation(_next.anim_name, _next.tar_slot, _next.callback, _next.effect_callback)
            table.remove(self.animation_stack, 1)
        end, 0.2)

    end
end

-- 刷新状态信息
function meta:RefreshStatusInfo(status_map)
    status_map = status_map or {}
    for k,v in pairs(status_map) do
        self:DoStatusAnimation(k, v.round, v.value)
    end
end

-- 播放状态动画
function meta:DoStatusAnimation(name, round, value, callback)

    local status_config = STATUS_CONFIG_MAP[name]
    if not status_config then
        if callback then callback() end
        return
    end

    local fix_power = status_config.fix_power
    local fix_symbol = status_config.fix_symbol

    -- 1.属性修正
    if fix_power ~= "" then
        local widget = self:GetPowerWidget(fix_power)
        if widget then
            if round == 0 then
                widget:PushValue(name, 0)
            else
                widget:PushValue(name, value * fix_symbol)
            end
        end
    end
    -- 2.状态显示
    local show_status = status_config.show_status
    if show_status ~= "" then
        if round == 0 then
            self:DelPassiveSkill(show_status)
        else
            self:PushPassiveSkill(show_status)
        end
    end
    -- 3.禁用技能列表
    if round == 0 then
        self:SetAgainstSkill(status_config.against_power_list, false)
    else
        self:SetAgainstSkill(status_config.against_power_list, true)
    end

    if callback then callback() end
end

-- 更新技能值
function meta:GetPowerWidget(power_name)
    for k,v in pairs(self.as_widget_list) do
        if v:isVisible() and v.power_name == power_name then
            return v
        end
    end

    for k,v in pairs(self.ps_widget_list) do
        if v:isVisible() and v.power_name == power_name then
            return v
        end
    end
    return nil
end

-- 播放特效动画
function meta:PlayEffectAnimation(effect_name, callback)
    local project_name = nil
    local anim_name = nil

    local data = string.split(effect_name, ":")
    if #data == 1 then
        project_name = data[1]
        anim_name = data[1]
    else
        project_name = data[1]
        anim_name = data[2]
    end

    local data_path = "animation/"..project_name..".json"
    local atlas_path = "animation/"..project_name..".atlas"

    -- 角色特效
    local effect_node = sp.SkeletonAnimation:create(data_path, atlas_path, 1)
    effect_node:setAnimation(0, anim_name, false)
    self:addChild(effect_node)

    effect_node:setRotation(self.src_rotation)
    if self.is_enemy then
        effect_node:setPosition({ x = 0, y = -127})
    else
        effect_node:setPosition({ x = 0, y = -23})
    end

    self.render_texture:setRotation(0)
    self.render_texture:setVisible(false)
    self.skeleton_node:setVisible(true)

    local end_callback = function (event)
        self.render_texture:setRotation(self.src_rotation)
        -- self.render_texture:setVisible(true)
        -- self.skeleton_node:setVisible(false)

        performWithDelay(self, function()
            self:removeChild(effect_node)
        end, 0.5)

        if callback then
            callback()
        end

    end
    effect_node:registerSpineEventHandler(end_callback, sp.EventType.ANIMATION_END)



    local event_callback = function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "hurt" then
            battle_logic:DispatchEvent("sub_event_complete")
        elseif event_name == "shake" then
            battle_logic:DispatchEvent("effect_screen_shake", float_value, int_value)
        end
    end
    effect_node:registerSpineEventHandler(event_callback, sp.EventType.ANIMATION_EVENT)
end

-- 播放行动动画
function meta:PlayPowerAnimation(anim_name, tar_slot, callback, effect_callback)
    if self.is_play_animation then
        local cache = {}
        cache.anim_name = anim_name
        cache.tar_slot = tar_slot
        cache.callback = callback
        cache.effect_callback = effect_callback
        table.insert(self.animation_stack, cache)
        return
    end


    self.is_play_animation = true
    local skeleton_node = self.skeleton_node

    if anim_name == "card_unsummon" and self.is_enemy then
        skeleton_node:setRotation(0)
        local card_texture = self.render_texture:getSprite():getTexture()
        card_texture:setAntiAliasTexParameters()
        skeleton_node:pushSlotTexture("card_info", 0, card_texture, true)
    end

    if anim_name == "card_melee" and self.is_enemy then
        anim_name = "card_melee_back"
    end
    if anim_name == "card_magic" and self.is_enemy then
        anim_name = "card_magic_back"
    end
    if anim_name == "card_random" and self.is_enemy then
        anim_name = "card_random_back"
    end
    if anim_name == "card_remote" and self.is_enemy then
        anim_name = "card_remote_back"
    end

    
    skeleton_node:setAnimation(0, anim_name, false)
    if anim_name == "card_dead_normal" or anim_name == "card_destroy" then
        -- 如果是死亡。就停止旋转了。重新设置渲染图
        if self.src_rotation ~= 0 then
            skeleton_node:setRotation(0)
            local card_texture = self.render_texture:getSprite():getTexture()
            card_texture:setAntiAliasTexParameters()
            skeleton_node:pushSlotTexture("card_info", 0, card_texture, true)
        end
    elseif anim_name == "card_summon" then
        self:setLocalZOrder(150)
    else
        -- 如果不是死亡或者献祭，动画都要提高到最大
        self:setLocalZOrder(15)
    end

    self:setVisible(true)

    skeleton_node:registerSpineEventHandler(function (event)
        skeleton_node:setVisible(true)
        local anim_name = event.animation

    end, sp.EventType.ANIMATION_START)

    if anim_name == "card_summon_back" then
        -- 敌方部署卡牌的时候会出现闪牌，只能通过setup来解决。
        skeleton_node:setToSetupPose()
    end

    skeleton_node:registerSpineEventHandler(function (event)
        if callback then
            callback()
            callback = nil
        end
        self.is_play_animation = false

        local anim_name = event.animation

        skeleton_node:setRotation(self.src_rotation)

        if anim_name == "card_unsummon" then
            self:setVisible(false)
            skeleton_node:setPosition(old_position)
            skeleton_node:setToSetupPose()
        end

        self:setLocalZOrder(self.src_zorder)

        self.slot_event_callback = {}
    end, sp.EventType.ANIMATION_END)

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

    skeleton_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue

        local event_callback = self.slot_event_callback[event.eventData.name]
        if event_callback then
            event_callback(int_value, float_value, string_value)
        end
        if event.eventData.name == "collimation" then
            -- 处理瞄准事件
            -- local anger = CalcAnger(src_x, src_y, dest_x, dest_y)

            -- local curve_func = cc[string_value]
            -- if float_value == 0 then
            --     skeleton_node:setRotation(anger)
            -- else
            --     local rotation_act = cc.RotateTo:create(float_value, anger)
            --     if curve_func then
            --         rotation_act = curve_func:create(rotation_act)
            --     end
            --     skeleton_node:runAction(rotation_act)
            -- end

        elseif event.eventData.name == "forward" then
            -- 前进事件
            local x, y = self:getPosition()
            local xx, yy = tar_slot:getPosition()
            local offset_x = math.floor(xx - x)
            local offset_y = math.floor(yy - y)
            if offset_y < 0 then
                offset_y = offset_y + 232
            elseif offset_y > 0 then
                offset_y = offset_y - 232
            end
            if offset_x < -10 then
                offset_x = offset_x + 50
            elseif offset_x > 10 then
                offset_x = offset_x - 50
            end

            local curve_func = cc[string_value]

            if float_value == 0 then
                skeleton_node:setPosition({x = offset_x, y = offset_y})
            else
                local move_act = cc.MoveTo:create(float_value, {x = offset_x, y = offset_y})
                if curve_func then
                    move_act = curve_func:create(move_act)
                end
                skeleton_node:runAction(move_act)
            end
        elseif event.eventData.name == "backward" then
            -- 后退事件
            if float_value == 0 then
                skeleton_node:setPosition(old_position)
                skeleton_node:setRotation(self.src_rotation)
                self:setLocalZOrder(self.src_zorder)
            else
                local curve_func = cc[string_value]
                local move_act = cc.MoveTo:create(float_value, old_position)
                local rotation_act = cc.RotateTo:create(float_value, self.src_rotation)

                if curve_func then
                    move_act = curve_func:create(move_act)
                    rotation_act = curve_func:create(rotation_act)
                end
                local call_func = cc.CallFunc:create(function ()
                    self:setLocalZOrder(self.src_zorder)
                end)
                local swap_act = cc.Spawn:create(move_act, rotation_act)
                skeleton_node:runAction(cc.Sequence:create(swap_act, call_func))
            end
        elseif event.eventData.name == "hurt" then
            battle_logic:DispatchEvent("sub_event_complete")
        elseif event.eventData.name == "effect" then
            if effect_callback then
                effect_callback(int_value, float_value, string_value)
            end
        elseif event.eventData.name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event.eventData.name == "ui_enter" then
            self.card_ui_panel:setVisible(true)
            self.card_ui_panel:PlayAnimation("enter_attack", false, function()
                self:RefreshPosition()
            end)
        elseif event.eventData.name == "ui_exit" then
            self.card_ui_panel:PlayAnimation("exit_attack")
        elseif event.eventData.name == "show_crystal" then
            local location = self:convertToWorldSpace({x = 0, y = 0})
            local rotation = 0
            battle_logic:DispatchEvent("add_crystal", not self.is_enemy, location, rotation)
        elseif event.eventData.name == "shake" then
            battle_logic:DispatchEvent("effect_screen_shake", float_value, int_value)
        elseif event.eventData.name == "unsummon_out" then

            local x = 0
            local y = display.height
            if not self.is_enemy then
                y = -y
            end

            local move_act = cc.MoveTo:create(0.5, {x = x, y = y})
            skeleton_node:runAction(move_act)
        elseif event.eventData.name == "lv_info" then
            if self.is_show_level then
                self.level_node:PlayAnimation("enter")
                self.level_skele_node:setAnimation(0, "lv_number", false)
            end
        end

    end, sp.EventType.ANIMATION_EVENT)


    skeleton_node:addAnimation(0, "card_normal", false)
end

function meta:RegisterWidgetEvent()
    self.level_skele_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue

        local event_name = event.eventData.name
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        end
    end, sp.EventType.ANIMATION_EVENT)
end

function meta:RegisterEvent()

end


return meta
