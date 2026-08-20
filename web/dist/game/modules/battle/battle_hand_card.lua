-- 战斗手牌
local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local audio_manager = require "manager.audio_manager"

local battle_logic = require "logic.battle"
local data_template = require "manager.data_template"
local CARD_CONFIG = data_template.card_config

local constants = require "common.constants"
local CARD_IMMOLATION_CRYSTAL = constants["CARD_IMMOLATION_CRYSTAL"]
local POWER_NAME = constants["POWER_NAME"]

local meta = class("battle_hand_card",function (node)
    if node then
        ui_helper:BindTimeLine(node, "interface/battle/battle_hand_card.csb")
        return node
    end
    return ui_helper:LoadCocosUI("interface/battle/battle_hand_card.csb")
end)

meta.STATUS = {
    disabled = 1,
    enabled = 2,
}

meta.cur_status = 0

meta.OPERATE_STATUS = {
    normal = 1,             -- 默认状态
    selected = 2,           -- 选择状态
    moved = 3,              -- 选择状态
    summon = 4,             -- 落卡状态
    replenish = 5,          -- 补充状态
}

function meta:ctor()

    self.action_list = {}

    local hand_card = self:getChildByName("handcard")
    hand_card:setScale(1)
    self.hand_card = hand_card

    self.light_node = hand_card:getChildByName("light")
    self.light_node:setVisible(false)
    ui_helper:BindTimeLine(self.light_node, "interface/battle/battle_hand_card_light.csb")
    -- self.light_node:PlayAnimation("loop_active")

    -- 创建手牌的demo
    local demo_node = ui_helper:ExpandUI(hand_card, "template", "modules.common.card_hand_item")
    demo_node:setScale(1)
    demo_node:setPosition(219, 269)
    demo_node:setVisible(false)
    -- 预渲染Demo
    self.demo_node = demo_node

    self.pre_x, self.pre_y = self:getParent():getPosition()


    -- 预渲染节点
    local render_texture = cc.RenderTexture:create(438, 538)
    render_texture:setPosition(219, 269)
    render_texture:setVisible(false)
    render_texture:setScale(1.0)
    hand_card:addChild(render_texture)

    self.render_texture = render_texture

    local skeleton_node = sp.SkeletonAnimation:create("animation/battle_handcard.json", "animation/battle_handcard.atlas", 1)
    skeleton_node:setScale(3.2)
    skeleton_node:setAnimation(0, "handcard_normal", false)
    skeleton_node:setPosition({ x = 160, y = 210})
    hand_card:addChild(skeleton_node)
    skeleton_node:setVisible(true)

    --阴影 
    local card_shadow  = ui_helper:LoadCocosUI("interface/battle/battle_hand_card_shadow.csb")
    self.card_shadow = card_shadow
    card_shadow:setLocalZOrder(-100)
    card_shadow:setPosition(cc.p(25,-15))
    skeleton_node:addChild(card_shadow)
    -- card_shadow:setVisible(false)

    -- 显示节点
    self.show_node = skeleton_node

    -- 献祭模块
    self.sacrifice_tip_node = ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_sacritip_node.csb")
    self.sacrifice_tip_node:PlayAnimation("normal")
    self.sacrifice_tip_node:setPosition({ x = 0, y = 90})
    self:addChild(self.sacrifice_tip_node)

    self.sacrifice_select_node = ui_helper:LoadCocosUI("interface/battle/battle_ui_handcard_sacritip_node.csb")
    self.sacrifice_select_node:PlayAnimation("normal")
    self.sacrifice_select_node:setPosition({ x = 0, y = 0})
    self:addChild(self.sacrifice_select_node)

    -- 是否正在播放动画
    self.is_play_animation = false

    self.hand_event_callback = {}
    self.hand_end_callback = {}

    ui_helper:BindTimeLine(self, "interface/battle/battle_hand_card.csb")

    self:setCascadeOpacityEnabled(true)

    self:RegisterWidgetEvent()
end

-- 重置记录信息
function meta:ResetTransform(hand_pos)
    local pos_x, pos_y = self:getPosition()
    local transform = {}

    local rotation =  self:getRotation()
    self.hand_pos = hand_pos
    transform.rotation = rotation
    transform.pos = { x = pos_x, y = pos_y}
    transform.scale = self:getScale()
    transform.zorder = self:getLocalZOrder()
    self.transform = transform
end


-- 出牌失败之后的回滚
function meta:RollBackAnimation(callback)
    local hand_card = battle_logic.own_player:GetHandCard(self.hand_pos)
    if hand_card == nil then
        return
    end
    self.show_node:setToSetupPose()
    self.show_node:setAnimation(0, "handcard_normal", false)

    self:setVisible(true)
    self:setLocalZOrder(self.transform.zorder)
    self:stopAllActions()
    local move_act = cc.MoveTo:create(0.2, self.transform.pos)
    local rotation_act = cc.RotateTo:create(0.2, self.transform.rotation)
    local scale_act = cc.ScaleTo:create(0.2, self.transform.scale)
    local call_func = cc.CallFunc:create(function ()
        if callback then
            callback()
        end
    end)
    self:runAction(cc.Sequence:create(cc.Spawn:create(move_act, rotation_act, scale_act), call_func))
end

-- 设置手牌信息
function meta:Show(card_info, is_anim)
    self:setPosition(self.transform.pos)
    self:setRotation(self.transform.rotation)
    self:setLocalZOrder(self.transform.zorder)
    self:setVisible(true)
    self.card_info = card_info

    self.show_node:setToSetupPose()

    self.demo_node:setVisible(true)
    self.demo_node:SetCardInfo(card_info)
    self.render_texture:beginWithClear(0.0,0.0,0.0,0.0)
    self.demo_node:visit()
    self.render_texture:endToLua()
    self.demo_node:setVisible(false)

    self.card_texture = self.render_texture:getSprite():getTexture()
    self.card_texture:setAntiAliasTexParameters()
    self.show_node:pushSlotTexture("card_info", 0, self.card_texture)

    self:SetStatus(self.STATUS.disabled)
    self:setVisible(true)
    self.show_node:setAnimation(0, "handcard_normal", false)
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

-- 是否已经点击
function meta:IsClick(touch)

    local pos = touch:getLocation()
    local camera = cc.Camera:getVisitingCamera()
    if not self:isVisible() then
        return false
    end
    return self.hand_card:hitTest(pos, camera, nil)
end

-- 设置操作状态
function meta:SetOperateStatus(status)
    if status == self.OPERATE_STATUS.normal then
        self:RollBackAnimation()
        -- self:setVisible(true)
        self:setOpacity(255)

    elseif status == self.OPERATE_STATUS.selected then
        -- self:setVisible(false)
        self:setOpacity(0)

    elseif status == self.OPERATE_STATUS.moved then
        -- self:setVisible(true)
        self:setOpacity(255)

    end
end

-- 开始移动
function meta:StartMove(pos)
    self:stopAllActions()
    local rotate_act = cc.RotateTo:create(0.08, 0)
    self:runAction(rotate_act)
    self:setOpacity(255)


    local new_pos = { x = pos.x - self.pre_x, y = pos.y - self.pre_y}
    self:setPosition(new_pos)

    self.show_node:setAnimation(0, "handcard_enterbattlefield",false)
end

-- 正在移动
function meta:DoMove(pos)
    local new_pos = { x = pos.x - self.pre_x, y = pos.y - self.pre_y}
    self:setPosition(new_pos)
end

-- 放置动画
function meta:PlaceAnimation(callback, end_callback)
    self.hand_event_callback["summon"] = callback
    self.show_node:setAnimation(0, "handcard_summon",false)
    self.light_node:setVisible(false)

    -- 放置动画结束
    self.hand_end_callback["handcard_summon"] = end_callback
end

-- 消耗品
function meta:ConsumeAnimation(callback)
    self.show_node:setAnimation(0, "handcard_destroy_magic",false)
    self.light_node:setVisible(false)
    self.card_shadow:setVisible(false)
    -- 消耗品动画结束
    self.hand_end_callback["handcard_destroy_magic"] = callback
end

-- 牌堆丢弃动画
function meta:DisDeckAnimation(card_type, callback)
    self:setRotation(0)
    -- local anim_name = ""
    -- if card_type == constants.CARD_TYPE.monster then
    --     anim_name = "handcard_drawmonster"
    --     self:setPosition({x = 150, y = display.c_top + 100})
    -- else
    --     anim_name = "handcard_drawitem"
    --     self:setPosition({x = -150, y = display.c_top + 100})
    -- end
    -- self.show_node:setAnimation(0, anim_name, false)
    -- self.show_node:addAnimation(0, "handcard_destroy2", false)
    self.show_node:setAnimation(0, "handcard_destroy2", false)
    self.card_shadow:setVisible(false)
    self.hand_end_callback["handcard_destroy2"] = callback
end


-- 补充动画
function meta:ReplenishAnimation(card_type, callback)
    -- self:setRotation(0)
    local anim_name = "handcard_in_card"
    -- if card_type == constants.CARD_TYPE.monster then
    --     anim_name = "handcard_drawmonster"
    --     self:setPosition({x = 150, y = display.c_top + 100})
    -- else
    --     anim_name = "handcard_drawitem"
    --     self:setPosition({x = -150, y = display.c_top + 100})
    -- end

    self.light_node:setVisible(false)
    self.card_shadow:setVisible(false)
    self.show_node:setAnimation(0, anim_name,false)
    self.hand_end_callback[anim_name] = function ()
        self.light_node:setVisible(true)
        if callback then
            callback()
        end
    end
end

-- 丢弃动画
function meta:DisCardAnimation(is_sacrifice, end_callback)
    local anim_name = "handcard_destroy2"
    if is_sacrifice then
        anim_name = "handcard_destroy"
    end
    self.show_node:setAnimation(0, anim_name,false)
    self.hand_end_callback[anim_name] = end_callback
    self.card_shadow:setVisible(false)
end

-- 进入献祭状态
function meta:DoSacrificeMode(click_callback)

    self.sacrifice_select_node:setVisible(true)

    local card_info = self.card_info
    local crystal_num = CARD_IMMOLATION_CRYSTAL[card_info.type]
    --dump(card_info,"=======================")
    card_info.power_list = card_info.power_list or {}
    for k,v in pairs(card_info.power_list) do
        if v.name == POWER_NAME.crystal then
            -- 额外水晶->转化这张卡的时候获得额外的能量水晶
            crystal_num = crystal_num + v.value
        end
    end

    local root_node = self.sacrifice_tip_node:getChildByName("node")

    local tip1_node = root_node:getChildByName("tip1")
    local value_txt = tip1_node:getChildByName("value")
    local sacriicon =root_node:getChildByName("sacriicon")
    ui_helper:SetText(value_txt, crystal_num)
    local title_node = tip1_node:getChildByName("title") --这个是手牌道具这些东西



    self.light_node:setVisible(true)
    local click_btn = self.sacrifice_select_node:getChildByName("click")
    local zorder = self:getLocalZOrder()

    ui_helper:AddClick(click_btn, function ()

        if card_info.type == "monster" then --怪兽
            ui_helper:SetTextByKey(title_node, "monster_property_card")
        else --道具
            ui_helper:SetTextByKey(title_node, "the_property_card") --这个是道具牌
        end
        self.sacrifice_tip_node:setVisible(true)
        self.sacrifice_tip_node:PlayAnimation("tip")
        self:setLocalZOrder(20)

        -- 开始发光
        self:SetStatus(self.STATUS.enabled)
        self.sacrifice_select_node:PlayAnimation("icon")
        click_callback(function ()
            self:setLocalZOrder(zorder)
            self.sacrifice_tip_node:setVisible(false)
            self.sacrifice_select_node:PlayAnimation("normal")
            self:SetStatus(self.STATUS.disabled)

        end)
    end)
end

-- 退出献祭模式
function meta:ExitSacrificeMode(pos)
    self:setLocalZOrder(4 - pos)    
    self.sacrifice_tip_node:setVisible(false)
    self.sacrifice_select_node:setVisible(false)
    self.sacrifice_select_node:PlayAnimation("normal")
    self:SetStatus(self.STATUS.disabled)
end

function meta:RegisterWidgetEvent()
    self.show_node:registerSpineEventHandler(function (event)
        if event.animation == "handcard_summon" then
            self:setVisible(false)
        end
        local callback = self.hand_end_callback[event.animation]
        if callback then
            -- 在cocos绑定的Spine的lua接口中，不能再事件中Set新的动画。
            performWithDelay(self, function() callback() end, 0.01)
            self.hand_end_callback[event.animation] = nil
        end
        is_play_animation = false
    end, sp.EventType.ANIMATION_END)

    self.show_node:registerSpineEventHandler(function (event)
        is_play_animation = true
        -- if event.animation == "handcard_normal" then
        --     self.render_texture:setVisible(true)
        --     self.show_node:setVisible(false)
        -- else
        --     self.render_texture:setVisible(false)
        --     self.show_node:setVisible(true)
        -- end
    end, sp.EventType.ANIMATION_START)

    self.show_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name

        local callback = self.hand_event_callback[event_name]
        if callback then
            callback(int_value, float_value, string_value)
        end
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "scaleto" then
            self:stopAllActions()
            local scale_act = cc.ScaleTo:create(float_value, int_value / 10)
            local curve_func = cc[string_value]
            if curve_func then
                rotation_act = curve_func:create(rotation_act)
            end
            skeleton_node:runAction(rotation_act)
        elseif event_name == "show_crystal" then
            local location = self:convertToWorldSpace({x = 0, y = 0})
            local rotation = self.transform.rotation
            battle_logic:DispatchEvent("add_crystal", true, location, rotation)
        elseif event_name == "shake" then
            battle_logic:DispatchEvent("effect_screen_shake", float_value, int_value)
        elseif event_name == "shadow_out" then
            self.card_shadow:setVisible(true)
        end
    end, sp.EventType.ANIMATION_EVENT)
end


return meta
