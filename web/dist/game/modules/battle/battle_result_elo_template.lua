local ui_helper = require "manager.ui_helper"
local arena_logic = require"logic.arena"

local meta = ui_helper:NewPanel("battle_result_elo_template", "interface/battle/battle_end2/ladder_end_panel.csb")

function meta:OnEnter()

end

function meta:Init(cur_elo,last_elo)

    local bar = self:getChildByName("bar")
    self.bar = require("modules.battle.battle_result_elo_bar").new(bar)
    self.bar:Init(cur_elo,last_elo,node)
    local action_name = ""
    local skeleton = sp.SkeletonAnimation:create("animation/level_icon.json", "animation/level_icon.atlas", 1)
    skeleton:setToSetupPose()
    skeleton:setPosition({x = 0, y = 0})
    self.skeleton = skeleton

    self:getChildByName("headicon"):addChild(self.skeleton)
    self:PlayAnimation("enter",false,function()
    end)
    self.action_over = false
    local headicon = self:getChildByName("headicon")
    local level = headicon:getChildByName("level")
    ui_helper:BindTimeLine(level,"interface/battle/battle_end2/ladder_desc.csb")
    level:PlayAnimation("loop")
    level:setLocalZOrder(1000)
    self.level = level
    self.level:getChildByName("level"):setString(tostring(arena_logic:GetLastLevel()))

    -- local render_hand_texture = cc.RenderTexture:create(220, 221)
    -- render_hand_texture:setVisible(false)
    -- render_hand_texture:setScale(1.0)
    -- self:addChild(render_hand_texture)
    -- self.render_hand_texture = render_hand_texture
    --
    -- local sp = cc.Sprite:create()
    -- sp:setPosition(cc.p(110,110))
    --

    -- sp:setTexture(texture_icon)
    -- self.render_hand_texture:beginWithClear(0.0,0.0,0.0,0.0)
    -- sp:setVisible(true)
    -- sp:visit()
    -- self.render_hand_texture:endToLua()
    --
    -- local card_texture = self.render_hand_texture:getSprite():getTexture()
    -- card_texture:setAntiAliasTexParameters()

    local path = "ui/ui_icon/ladder_headicon/level"
    local texture_icon = path .. tostring(arena_logic:GetLastLevel())..".png"
    local texture_cache = cc.Director:getInstance():getTextureCache()
    local card_texture = texture_cache:addImage(texture_icon)
    skeleton:pushSlotTexture("level_icon", 0, card_texture)
    
    self.skeleton:setAnimation(0,"level_icon_loop",true)
    self:RegisterWidgetEvent()
end

function meta:Update(elapsed_time)
    if self.bar then
        self.bar:Update(elapsed_time)
    end
end

function meta:RegisterWidgetEvent()
    self.skeleton:registerSpineEventHandler(function (event)

        if event.animation == "level_icon_up" or event.animation == "level_icon_down" then
            local block = cc.CallFunc:create(function()
                self.skeleton:setAnimation(0,"level_icon_loop",true)
            end)
            local delay = cc.DelayTime:create(0.01)
            local sequence = cc.Sequence:create(delay, block)
            self:runAction(sequence)
        end
    end, sp.EventType.ANIMATION_END)

    self.skeleton:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "change" then
            -- local sp = cc.Sprite:create()
            -- sp:setPosition(cc.p(110,110))
            local path = "ui/ui_icon/ladder_headicon/level"
            local texture_icon = path .. tostring(arena_logic:GetLevel())..".png"
            local texture_cache = cc.Director:getInstance():getTextureCache()
            local card_texture = texture_cache:addImage(texture_icon)
            self.skeleton:pushSlotTexture("level_icon", 0, card_texture)
        elseif event_name == "font_in" then
            self.level:PlayAnimation("enter")
        elseif event_name == "font_out" then
            self.level:PlayAnimation("exit")
        end
    end, sp.EventType.ANIMATION_EVENT)
end

function meta:OnExit()
    self:UnregisterEvent()
end

function meta:RegisterEvent()
    self:SetFrameEventCallFunc(function (frame)
        local event_name = frame:getEvent()
        if event_name == "end" then
            self:DispatchGraphicEvent("start_result_elo_bar")
        end
    end)

    self:RegisterGraphic("level_up_skeleton",function()
        self.level:getChildByName("level"):setString(tostring(arena_logic:GetLevel()))
        self.skeleton:setAnimation(0,"level_icon_up",false)
    end)
    self:RegisterGraphic("level_down_skeleton",function()
        self.skeleton:setAnimation(0,"level_icon_down",false)
        self.level:getChildByName("level"):setString(tostring(arena_logic:GetLevel()))
    end)
end

return meta
