local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local graphic = require "manager.graphic"
local text_loader = require "manager.text_loader"
local data_template = require "manager.data_template"

local deck_logic = require "logic.deck"
local resource_logic = require "logic.resource"
local audio_manager = require "manager.audio_manager"
local CARD_CONFIG = data_template.card_config
local POWER_CONFIG_MAP = data_template.power_config
local UPGRADE_CONFIG = data_template.card_upgrade_config


local meta = class("card_upgrade_panel",function ()
    return ui_helper:LoadCocosUI("interface/deck/levelup_panel.csb")
end)

function meta:ctor()
    local root = self:getChildByName("node")
    self.root = root
    self.close_btn = root:getChildByName("close_btn")

    self.src_card_node = ui_helper:ExpandUI(root, "card1", "modules.deck.card_bag_item")

    self.tar_card_node = ui_helper:ExpandUI(root, "card2", "modules.deck.card_bag_item")


    local detailbg = root:getChildByName("detailbg")

    local reward_group = detailbg:getChildByName("reward_group")
    self.material_list = {}
    for i = 1, 6 do
        local bg = reward_group:getChildByName("bg"..i)
        local item = ui_helper:ExpandUI(reward_group, "reward"..i.."_item", "modules.common.material_item")
        self.material_list[i] = { backgroup = bg, item = item }
    end

    self.confirm_btn = detailbg:getChildByName("confirm_btn")

    self.req_res_icon = self.confirm_btn:getChildByName("icon")
    self.req_res_value = self.confirm_btn:getChildByName("value")

    local upgrade_spine = root:getChildByName("upgrade_spine")
    local skeleton_node = sp.SkeletonAnimation:create("animation/card_upgrade.json", "animation/card_upgrade.atlas", 0.45)
    -- skeleton_node:setAnimation(0, "card_upgrade", true)
    skeleton_node:setPosition(0, -5)
    skeleton_node:setVisible(false)
    upgrade_spine:addChild(skeleton_node)

    self.upgrade_ing = false

    self.skeleton_node = skeleton_node
    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

function meta:UpgradeCard()
    self.src_card_node = ui_helper:ExpandUI(self.root, "card1", "modules.deck.card_bag_item")
    self.tar_card_node = ui_helper:ExpandUI(self.root, "card2", "modules.deck.card_bag_item")
end

function meta:Show(card_select_info)
    
    self.upgrade_ing = false
    self.select_card = card_select_info
    local card_model_id = card_select_info["model_id"]
    self:setVisible(true)
    graphic:DispatchEvent("switch_world_status", true)

    local upgrade_config = UPGRADE_CONFIG[card_model_id]
    local next_card_id = 0

    if not upgrade_config then
        next_card_id = card_model_id
    else
        next_card_id = upgrade_config["next_card_id"]
    end

    local src_card_config = deck_logic:GetCardConfigByModelId(card_model_id)
    local next_card_config = deck_logic:GetCardConfigByModelId(next_card_id)


    self.src_card_node:ShowCardGroupInfo(1, src_card_config, true)
    self.tar_card_node:ShowCardGroupInfo(1, next_card_config, true)

    local diff_hp = next_card_config.hp - src_card_config.hp
    local diff_cost = next_card_config.cost - src_card_config.cost
    local diff_power_list = {}
    for k,v in pairs(next_card_config.power_list) do
        diff_power_list[v.name] = v.value
    end
    for k,v in pairs(src_card_config.power_list) do
        if diff_power_list[v.name] then
            diff_power_list[v.name] = diff_power_list[v.name] - v.value
        end
    end
    self.tar_card_node:ShowDiffInfo(diff_hp, diff_cost, diff_power_list)

    self.next_card_id = next_card_id

    if not upgrade_config then
        return
    end

    local req_material_list = upgrade_config["req_material_list"]
    local req_money = upgrade_config["req_money"]
    local req_coin = upgrade_config["req_coin"]

    for i = 1, 6 do
        local root = self.material_list[i]
        local req_material = req_material_list[i]
        if req_material then
            root.backgroup:setVisible(true)
            root.item:setVisible(true)
            root.item:ShowMaterial(req_material)
            root.item:AddClick(
                function (pos)
                    -- 点击选中
                    local reward_info = {}
                    reward_info["type"] = constants["REWARD_TYPE"]["resource"]
                    reward_info["attr_id"] = tonumber(req_material.attr_id)
                    reward_info["value"] = req_material.num
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

    if req_money ~= 0 then
        if req_money >= resource_logic.money then
            self.req_res_value:setColor(ui_helper:GetColor4B(0xFF6A6A))
        else
            self.req_res_value:setColor(ui_helper:GetColor4B(0xA9FF3C))
        end

        ui_helper:SetText(self.req_res_value, ui_helper:ConvertUnit(req_money))
    end

end

function meta:Hide()
    self:setVisible(false)
    graphic:DispatchEvent("switch_world_status", false)
end


function meta:RegisterWidgetEvent()

    -- 取消
    ui_helper:AddClick(self.close_btn, function ()
        if self.upgrade_ing then
            return 
        end
        graphic:DispatchEvent("pop_world_panel")
    end)

    local skeleton_node = self.skeleton_node
    -- 升级
    ui_helper:AddClick(self.confirm_btn, function ()

        if self.upgrade_ing then
            return 
        end

        
        local select_card = self.select_card
        local card_id = select_card.id
        deck_logic:UpgradeCard(select_card, self.next_card_id, function (new_upgrade_card)
            
            self.upgrade_ing = true
            self.skeleton_node:setVisible(true)
            self.new_upgrade_card = new_upgrade_card
            self.skeleton_node:setAnimation(0, "card_upgrade", false)
            local render_texture = self.src_card_node.render_texture
            local card_texture = render_texture:getSprite():getTexture()
            self.skeleton_node:pushSlotTexture("card_info", 0, card_texture)

            self:PlayAnimation("enter_levelup", false,function()
                self.src_card_node:setVisible(false)
                self.tar_card_node:setVisible(false)
            end)
            -- graphic:DispatchEvent("show_message", "card_upgrade_success")
            -- graphic:DispatchEvent("pop_world_panel")
        end)
    end)

    self.skeleton_node:registerSpineEventHandler(function (event)
        local int_value = event.eventData.intValue
        local float_value = event.eventData.floatValue
        local string_value = event.eventData.stringValue
        local event_name = event.eventData.name
        if event_name == "sound" then
            audio_manager:PlayEffect(string_value)
        elseif event_name == "change" then
                
            local render_texture = self.tar_card_node.render_texture
            local card_texture = render_texture:getSprite():getTexture()
            self.skeleton_node:pushSlotTexture("card_info", 0, card_texture)

            -- self:Show(self.new_upgrade_card)
                -- self.src_card_node:setVisible(true)
                -- self.tar_card_node:setVisible(true)
        elseif event_name == "next_card" then

            self.src_card_node:setOpacity(0)
            self.tar_card_node:setOpacity(0)
            self.src_card_node:setVisible(true)
            self.tar_card_node:setVisible(true)

            local render_texture = self.tar_card_node.render_texture
            local card_texture = render_texture:getSprite():getTexture()
            -- self.skeleton_node:pushSlotTexture("card_info", 0, card_texture)

            local action = cc.FadeIn:create(0.3)
            self.src_card_node:runAction(action)
            self.tar_card_node:runAction(action)
            
            self:PlayAnimation("exit_levelup",false,function()
                self.skeleton_node:setVisible(false)
                
                self:UpgradeCard()
                self:Show(self.new_upgrade_card)
                -- graphic:DispatchEvent("show_message", "card_upgrade_success")
            end)
           
        end

    end, sp.EventType.ANIMATION_EVENT)    

    -- skeleton_node:registerSpineEventHandler(function (event)
    --     local int_value = event.eventData.intValue
    --     local float_value = event.eventData.floatValue
    --     local string_value = event.eventData.stringValue
    --     local event_name = event.eventData.name

    --     if event_name == "sound" then
    --         audio_manager:PlayEffect(string_value)
    --     elseif event_name == "change" then
    --         -- self:PlayAnimation("exit_levelup")
    --         -- self:Show(new_upgrade_card)
    --     end
    -- end, sp.EventType.ANIMATION_EVENT)

    -- skeleton_node:registerSpineEventHandler(function (event)
    --     skeleton_node:setVisible(true)

    -- end, sp.EventType.ANIMATION_START)

    -- skeleton_node:registerSpineEventHandler(function (event)
    --     skeleton_node:setVisible(false)

    -- end, sp.EventType.ANIMATION_END)
end

function meta:RegisterEvent()
end

return meta
