local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local graphic = require "manager.graphic"
local text_loader = require "manager.text_loader"
local data_template = require "manager.data_template"
local audio_manager = require "manager.audio_manager"
local world = require "modules.world.world_panel"
local resource_logic = require "logic.resource"
local deck_logic = require "logic.deck"

local CARD_CONFIG = data_template.card_config
local POWER_CONFIG_MAP = data_template.power_config
local RESOLVE_CONFIG = data_template.card_resolve_config

local ITEM_CONFIG = data_template.item_config
local meta = class("card_resolve_panel",function ()
    return ui_helper:LoadCocosUI("interface/deck/resolve_panel.csb")
end)

function meta:ctor()

    local root = self:getChildByName("node")
    self.root = root

    self.close_btn = root:getChildByName("close_btn")

    local detailbg = root:getChildByName("detailbg")
    local reward_group = detailbg:getChildByName("reward_group")
    self.material_list = {}
    for i = 1, 4 do
        local bg = reward_group:getChildByName("bg"..i)
        local item = ui_helper:ExpandUI(reward_group, "reward"..i.."_item", "modules.common.material_item")
        self.material_list[i] = { backgroup = bg, item = item }
    end

    self.confirm_btn = detailbg:getChildByName("confirm_btn")

    local card  = self:getChildByName("card")
    local skeleton_node = sp.SkeletonAnimation:create("animation/card_upgrade.json", "animation/card_upgrade.atlas", 0.43)
    skeleton_node:setAnimation(0, "card_resolve_loop", true)
    card:addChild(skeleton_node)
    self.skeleton_node = skeleton_node


    -- 预渲染节点
    local render_texture = cc.RenderTexture:create(392, 512)
    render_texture:setVisible(false)
    self.render_texture = render_texture
    card:addChild(render_texture)

    self.animation_over = true
    -- 卡牌模板
    self.card_template_node = require("modules.common.card_hand_item").new()
    self.card_template_node:setVisible(false)
    self.card_template_node:setPosition(198, 252)
    self:addChild(self.card_template_node)
    self.resolve_ing = false
    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

-- 显示组ID
function meta:Show(card_info, card_config)

    self:setVisible(true)
    self:PlayAnimation("normal")
    self.skeleton_node:setAnimation(0, "card_resolve_loop", true)
    self.animation_over = true
    self.card_template_node:SetCardInfo(card_config)
    self.card_template_node:setVisible(true)
    self.render_texture:beginWithClear(0.0,0.0,0.0,0.0)
    self.card_template_node:visit()
    self.render_texture:endToLua()
    self.card_template_node:setVisible(false)


    local card_texture = self.render_texture:getSprite():getTexture()
    self.skeleton_node:pushSlotTexture("card_info", 0, card_texture)

    self.card_info = card_info
    local resolve_item_list = RESOLVE_CONFIG[card_info.model_id]

    if not resolve_item_list then
        return
    end
    self.item_pos = {}
    for i = 1, 4 do
        local root = self.material_list[i]
        local item = resolve_item_list[i]
        if item then

            local item_pos = root.item:convertToWorldSpace(cc.p(0,0)) --转换成世界坐标系
            self.item_pos[i] = item_pos
            root.backgroup:setVisible(true)
            root.item:setVisible(true)
            root.item:ShowItem(item)
            root.item:AddClick(
                function (pos)
                    -- 点击选中
                    local reward_info = {}
                    reward_info["type"] = constants["REWARD_TYPE"]["resource"]
                    reward_info["attr_id"] = item.item_id
                    reward_info["value"] = item.item_num
                    graphic:DispatchEvent("show_reward_tips", reward_info, pos)
                end,
                function ()
                    -- 取消选中
                    graphic:DispatchEvent("hide_reward_tips")
                end
            )
        else
            root.backgroup:setVisible(false)
            root.item:setVisible(false)
        end
    end
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.close_btn, function ()
        graphic:DispatchEvent("pop_world_panel", "desk", "card_resolve_panel")
    end)

    ui_helper:AddClick(self.confirm_btn, function ()
        if self.resolve_ing then
            return
        end
        local card_info = self.card_info
        deck_logic:ResolveCard(card_info.id, function (reward_list)
            self.resolve_ing = true
            local show_reward_list = {}
            local item_pos = self.item_pos
            for k,v in pairs(reward_list) do
                local show_reward_info = {}
                local pos = {}
                pos["x"] = item_pos[k].x
                pos["y"] = item_pos[k].y
                show_reward_info.pos = pos
                show_reward_info.reward = v
                table.insert(show_reward_list, show_reward_info)
            end
            graphic:DispatchEvent("show_reward_animation", show_reward_list)
            self.skeleton_node:setAnimation(0, "card_resolve", false)
            self:PlayAnimation("enter_resolve",false,function()
                self.resolve_ing = false
            end)
        end)
    end)


    self.skeleton_node:registerSpineEventHandler(function (event)
        if event.animation == "card_resolve" then
            graphic:DispatchEvent("pop_world_panel", "desk", "card_resolve_panel")
            self.animation_over = true
        end
    end, sp.EventType.ANIMATION_END)

    self.skeleton_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name

        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "shake" then
            graphic:DispatchEvent("effect_screen_shake", float_value, int_value)
        end
    end, sp.EventType.ANIMATION_EVENT)
end




function meta:RegisterEvent()

end

return meta
