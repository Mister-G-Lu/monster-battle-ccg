local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local resource = require "manager.resource"
local graphic = require "manager.graphic"

local resource_logic = require "logic.resource"

local ITEM_CONFIG = data_template.item_config
local MATERIAL_KIND = constants["MATERIAL_KIND"]

local meta = class("material_item",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/common/itemicon_template.csb")
end)

function meta:ctor()

    self.bg_node = self:getChildByName("bg")
    self.icon_img = self:getChildByName("icon")
    self.num_txt = self:getChildByName("num")

    self.bg_node:setVisible(false)
end
-- 显示
function meta:ShowMaterial(material_info)

    if not material_info then return end
    self:setVisible(true)
    if material_info.kind == MATERIAL_KIND.item then
        local item_id = tonumber(material_info.attr_id)
        local cur_num = resource_logic:GetItemNum(item_id)
        local config = ITEM_CONFIG[item_id]
        self.icon_img:loadTexture(resource:GetItemIcon(config.res_path))
        local req_num = tonumber(material_info.num)
        local str = cur_num.."/"..req_num
        ui_helper:SetText(self.num_txt, str)
        if req_num > cur_num then
            self.num_txt:setColor(ui_helper:GetColor4B(0xFF6A6A))
        else
            self.num_txt:setColor(ui_helper:GetColor4B(0xA9FF3C))
        end
    end
end

function meta:SetBackGroupVisible(is_visible)
    self.bg_node:setVisible(is_visible)
end

function meta:ShowReward(reward_info)
    if not reward_info then return end
    self:setVisible(true)
    if reward_info.type == constants["REWARD_TYPE"]["resource"] then
        self:ShowItem({ item_id = reward_info.attr_id, item_num = reward_info.value })
    elseif reward_info.type == constants["REWARD_TYPE"]["chest"] then
        self:ShowChest({ chest_id = reward_info.attr_id, chest_num = reward_info.value })
    end

    self:AddClick(
        function (pos)
            graphic:DispatchEvent("show_reward_tips", reward_info, pos)
        end,
        function ()
            graphic:DispatchEvent("hide_reward_tips")
        end
    )
end


-- 设置灰色
function meta:SetGray(bool)
    if not bool then
        local gary_state = cc.GLProgramState:getOrCreateWithGLProgramName("ShaderPositionTextureColor_noMVP")
        self.icon_img:setGLProgramState(gary_state)
    else
        local gary_state = cc.GLProgramState:getOrCreateWithGLProgramName("ShaderUIGrayScale")
        self.icon_img:setGLProgramState(gary_state)
    end
end

function meta:ShowChest(chest_info)
    if not chest_info then return end
    self:setVisible(true)

    ui_helper:SetText(self.num_txt, chest_info.chest_num)
    self.icon_img:loadTexture(resource:GetItemIcon("cardbag1"))

end

function meta:ShowItem(item_info)
    if not item_info then return end
    self:setVisible(true)
    local config = ITEM_CONFIG[item_info.item_id]
    self.icon_img:loadTexture(resource:GetItemIcon(config.res_path))
    ui_helper:SetText(self.num_txt, item_info.item_num)
end

function meta:AddClick(click_event, end_event)
    self.icon_img:setTouchEnabled(true)
    self.icon_img:addTouchEventListener(function(widget, event_type)
        if event_type == ccui.TouchEventType.began then
            if click_event then click_event(widget:getWorldPosition()) end
        end
        if event_type == ccui.TouchEventType.ended or event_type == ccui.TouchEventType.canceled then
            if end_event then end_event() end
        end
    end)
end

function meta:SetTouchEnabled(bool)
    self.icon_img:setTouchEnabled(bool)
end

return meta
