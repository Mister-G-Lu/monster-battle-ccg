local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"

local audio_manager = require "manager.audio_manager"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local CHEST_STAGE = constants.CHEST_STAGE
local REWARD_TYPE = constants.REWARD_TYPE
local CARD_QUALITY = constants.CARD_QUALITY
local CARD_CONFIG = data_template.card_config

local chest_logic = require "logic.chest"

local meta = class("open_chest_panel",function ()
    return ui_helper:LoadCocosUI("interface/chest/open_cardbag_panel.csb")
end)

local OPEN_ANIM_NAME = {
    {"open_card_normal", "loop_card_front_normal"}, -- 普通
    {"open_card_rare", "loop_card_front_rare"},  -- 罕见
    {"open_card_legend", "loop_card_front_legend"}, -- 稀有
    {"open_card_epic", "loop_card_front_epic"},  -- 史诗
}

local function CreateChestInfo(harvert_info)
    local root_node = ccui.Layout:create()
    root_node:setContentSize({width = 653, height = 640})
    root_node:setBackGroundColor(display.COLOR_RED)
    root_node:setCascadeOpacityEnabled(true)

    local effect_node = sp.SkeletonAnimation:create("animation/open_card_bag.json", "animation/open_card_bag.atlas", 1)
    effect_node:setAnimation(0, "loop_card_back", true)
    effect_node:setPosition({x = 327, y = 320})
    effect_node:setRotation(-90)
    effect_node:setCascadeOpacityEnabled(true)

    local anim_name = {}
    local render_texture = nil

    local card_id = harvert_info.reward_card_id

    local card_config = CARD_CONFIG[tostring(card_id)]
    anim_name = OPEN_ANIM_NAME[CARD_QUALITY[card_config.quality]]
    if not anim_name then
        anim_name = OPEN_ANIM_NAME[1]
    end

    local width, height = 392, 512
    local demo_hand_card = require("modules.common.card_hand_item").new()
    demo_hand_card:SetCardInfo(card_config)
    demo_hand_card:setPosition(width / 2, height / 2 - 4)
    render_texture = cc.RenderTexture:create(width, height)
    -- render_texture:beginWithClear(1.0,1.0,1.0,1.0)
    render_texture:beginWithClear(0.0,0.0,0.0,0.0)
    demo_hand_card:visit()
    render_texture:endToLua()


    local card_texture = render_texture:getSprite():getTexture()
    card_texture:setAntiAliasTexParameters()
    effect_node:pushSlotTexture("card_info", 0, card_texture)

    root_node.effect_node = effect_node
    root_node:addChild(effect_node)



    local spine_event = function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "shake" then
            graphic:DispatchEvent("effect_screen_shake", float_value, int_value)
        end
    end
    effect_node:registerSpineEventHandler(spine_event, sp.EventType.ANIMATION_EVENT)


    local close_effect = sp.SkeletonAnimation:create("animation/card_upgrade.json", "animation/card_upgrade.atlas", 1)
    close_effect:setPosition({x = 327, y = 320})
    close_effect:setRotation(-90)
    close_effect:setCascadeOpacityEnabled(true)
    close_effect:pushSlotTexture("card_info", 0, card_texture)
    close_effect:setVisible(true)
    close_effect:registerSpineEventHandler(spine_event, sp.EventType.ANIMATION_EVENT)
    root_node.close_effect = close_effect
    root_node:addChild(close_effect)

    return root_node, anim_name
end

function meta:ctor()
    self:setVisible(false)

    local effect_node = sp.SkeletonAnimation:create("animation/open_card_bag.json", "animation/open_card_bag.atlas", 1)
    effect_node:setPosition(display.center)
    self:addChild(effect_node)
    self.effect_node = effect_node


    self.card_list_page = self:getChildByName("card_list")
    self.card_list_page:removeAllChildren()

    self.open_idx = 1


    self.card_detail_panel = require("modules.chest.card_detail_panel").new()
    self.card_detail_panel:setPositionY(-130)
    self:addChild(self.card_detail_panel)

    self.resolve_tip_node = self:getChildByName("resolve_tip2")
    ui_helper:BindTimeLine(self.resolve_tip_node, "interface/chest/resolve_tip2.csb")
    ui_helper:SetCocosSetting(self.resolve_tip_node, "interface/chest/resolve_tip2.csb")

    local x, y= self.resolve_tip_node:getPosition()
    self.item_animation_pos = {x = x, y = y}

    self.back_btn = self:getChildByName("back_btn")
    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

function meta:Update(elapsed_time)
    self.card_detail_panel:Update(elapsed_time)
end

function meta:Show(show_data_list, hide_callback)
    self.hide_callback = hide_callback
    self:setVisible(true)
    -- Bug fix: back_btn is left disabled after every open (the handler that
    -- enables it only fires after all cards are tapped through). The panel is
    -- cached and reused by world_scene, so without this reset the button stays
    -- permanently disabled and the player is stuck on a black screen.
    self.back_btn:setTouchEnabled(false)
    self:PlayAnimation("enter")
    self.resolve_tip_node:setVisible(false)
    self.card_list_page:removeAllChildren()
    self.effect_node:setToSetupPose()

    local harvert_list = show_data_list.card_list
    self.reward_list = show_data_list.reward_list
    self.total_card_num = #harvert_list
    self.card_node_list = {}
    self.harvert_list = harvert_list
    self.card_detail_panel:setVisible(false)

    local is_include_resolve = false
    for k,v in pairs(harvert_list) do
        local root_node, anim_name = CreateChestInfo(v)
        local is_click = 0
        root_node:setTouchEnabled(true)
        root_node:addTouchEventListener(function(widget, event_type)
            if event_type == ccui.TouchEventType.began then
                if is_click == 2 then
                    self.card_detail_panel:Show(v.reward_card_id)
                end
            end
            if event_type == ccui.TouchEventType.ended or event_type == ccui.TouchEventType.canceled then

                if is_click == 0 then
                    self.card_list_page:scrollToPage(k - 1)
                    local effect_node = root_node.effect_node
                    effect_node:setAnimation(0, anim_name[1], false)
                    effect_node:addAnimation(0, anim_name[2], true)

                    effect_node:registerSpineEventHandler(function (event)
                        for k,v in pairs(OPEN_ANIM_NAME) do
                            if v[1] == event.animation then
                                self.total_card_num = self.total_card_num - 1
                                if self.total_card_num == 0 then
                                    self.back_btn:setTouchEnabled(true)
                                    self:PlayAnimation("complete")
                                end
                                break
                            end
                        end
                        is_click = 2
                        if v.is_resolve then
                            local card_resolve_tips = ui_helper:LoadCocosUI("interface/chest/resolve_tip.csb")
                            card_resolve_tips:setPosition({x = 100, y = 460})
                            card_resolve_tips:setScale(0.69)
                            card_resolve_tips:setRotation(-90)
                            card_resolve_tips:PlayAnimation("enter")
                            root_node.card_resolve_tips = card_resolve_tips
                            root_node:addChild(card_resolve_tips)
                            is_include_resolve = true
                        end

                    if self.total_card_num == 0 and is_include_resolve then
                        self.resolve_tip_node:setVisible(true)
                        self.resolve_tip_node:PlayAnimation("enter")
                    end
                    end, sp.EventType.ANIMATION_END)
                    is_click = 1
                elseif is_click == 2 then
                    self.card_detail_panel:Hide()
                end
            end
        end)
        self.card_list_page:addPage(root_node)
        self.card_node_list[k] = root_node
    end
end

function meta:DoExit()
    local new_item_list = {}

    for k,v in pairs(self.card_node_list) do
        local effect_node = v.effect_node
        effect_node:setVisible(false)
        local close_effect = v.close_effect
        local harvert_info = self.harvert_list[k]
        if harvert_info.is_resolve then
            close_effect:setAnimation(0, "card_auto_resolve", false)
        else
            close_effect:setAnimation(0, "card_auto_over", false)
        end

        if v.card_resolve_tips then
            v.card_resolve_tips:PlayAnimation("exit")
        end
    end

    local center = self.item_animation_pos
    -- local center = display.center

    local show_reward_list = {}
    for k,v in pairs(self.reward_list) do
        local show_reward_info = {}
        local pos = {}
        pos["x"] = center.x
        pos["y"] = center.y
        show_reward_info.pos = pos
        show_reward_info.reward = v
        table.insert(show_reward_list, show_reward_info)
    end

    graphic:DispatchEvent("show_reward_animation",show_reward_list)


    local delay = cc.DelayTime:create(1.5)
    local sequence = cc.Sequence:create(delay, cc.CallFunc:create(function ()
        graphic:DispatchEvent("pop_world_panel", "home", "open_chest_panel")
    end))
    self:runAction(sequence)

end

function meta:Hide()

    self:PlayAnimation("exit", false, function ()
        self:setVisible(false)
        chest_logic.is_open_chesting = false
        self.card_list_page:removeAllChildren()
        if self.hide_callback then self.hide_callback() end
    end)
end

-- 注册渲染事件
function meta:RegisterEvent()
end

-- 注册UI事件
function meta:RegisterWidgetEvent()
    local effect_node = self.effect_node

    ui_helper:AddClick(self.back_btn, function ()
        self.back_btn:setTouchEnabled(false)
        self:DoExit()
    end)

    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "enter_card_bag" then
            effect_node:setAnimation(0, "enter_card_bag", false)
            effect_node:addAnimation(0, "open_card_bag", false)
        end
    end)

    effect_node:registerSpineEventHandler(function (event)
    end, sp.EventType.ANIMATION_START)

    effect_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        end
    end, sp.EventType.ANIMATION_EVENT)

end

return meta
