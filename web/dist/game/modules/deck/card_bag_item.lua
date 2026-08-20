local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"

local data_template = require "manager.data_template"

local deck_logic = require "logic.deck"

local meta = class("card_bag_item",function (node)
    local path = "interface/deck/card_allcards_template.csb"
    if not node then
        node = ui_helper:LoadCocosUI(path)
    end
    ui_helper:BindTimeLine(node, path)
    return node
end)

function meta:ctor()
    self.click_panel = self:getChildByName("click_panel")
    self.click_panel:setSwallowTouches(false)

    self:setCascadeOpacityEnabled(true)
    self.click_panel:setCascadeOpacityEnabled(true)

    -- 卡牌放置节点
    local card_location_node = self.click_panel:getChildByName("card_location")
    card_location_node:setCascadeOpacityEnabled(true)
    self.render_texture = cc.RenderTexture:create(392, 512)
    self.render_texture:setCascadeOpacityEnabled(true)
    card_location_node:addChild(self.render_texture)
    card_location_node:setScale(0.36)

    self.numbers_panel = self.click_panel:getChildByName("numbers")
    self.bg = self.numbers_panel:getChildByName("bg")
    self.number_txt = self.numbers_panel:getChildByName("num")

    self.numbers_panel:setVisible(true)
    self.new_card_txt = self.click_panel:getChildByName("newcard_txt")
    self.levelup_icon_img = self.click_panel:getChildByName("levelup_tip")
    ui_helper:BindTimeLine(self.levelup_icon_img, "interface/deck/levelup_tip.csb")
    local online_tips = ui_helper:LoadCocosUI("interface/deck/online_tips.csb")
    self.click_panel:addChild(online_tips,100)
    online_tips:setScale(0.6)
    online_tips:setPosition(cc.p(127,145))
    self.online_tips = online_tips
    self:PlayAnimation("normal")
end

-- 初始化模板
function meta:InitCardTemplate(card_template_node)
    self.card_template_node = card_template_node
end


function meta:TheComposeNum(bool)
    if bool == true then
        self.bg:setVisible(false)
        self.number_txt:setVisible(false)
    else
        self.bg:setVisible(true)
        self.number_txt:setVisible(true)
    end
end


function meta:AddClickEvent(event)
    if event then
        self.click_panel:setSwallowTouches(false)
        ui_helper:AddClick(self.click_panel, event)
    else
        self.click_panel:setSwallowTouches(true)
    end
end

function meta:ShowCardGroupInfo(data_index, card_config, is_show_num, show_tips)

    self.data_index = data_index
    local card_id = card_config.uid
    is_show_num = is_show_num or false
    show_tips = show_tips or false
    local card_have = self:IfHaveCard(card_config.group_id)
    -- 卡牌模板
    if self.card_template_node == nil then
        self.card_template_node = require("modules.common.card_hand_item").new()
        self.card_template_node:setVisible(false)
        self.card_template_node:setPosition(198, 252)
        self:addChild(self.card_template_node)
    end

    self.card_template_node:SetCardInfo(card_config)
    self.card_template_node:setVisible(true)

    if card_have == true then
        self.card_template_node:Relativedisplay(true) -- 相对的显示
        self:PlayAnimation("normal")
    else
        self.card_template_node:Relativedisplay(false)
        self:PlayAnimation("card_alf",false)
    end

    self.render_texture:setVisible(true)
    self.render_texture:beginWithClear(0.0,0.0,0.0,0.0)
    self.card_template_node:visit()
    self.render_texture:endToLua()
    self.card_template_node:setVisible(false)

    local card_num = deck_logic:GetNumByGroupId(card_config.group_id)
    -- 是否是我的卡牌界面

    if show_tips and not deck_logic.is_compose then

        local card_detail_list = deck_logic:GetCardListByGroupId(card_config.group_id)
        local card_info = card_detail_list[1].card_info
        local card_id = card_info.id

        if deck_logic:CheckInDeck(card_id,deck_logic.cur_deck_id) then
            self.online_tips:setVisible(true)
        else
            self.online_tips:setVisible(false)
        end
    else
        self.online_tips:setVisible(false)
    end

    if card_num > 1 and not is_show_num then
        self.numbers_panel:setVisible(true)
        ui_helper:SetText(self.number_txt, "x"..card_num)
    else
        self.numbers_panel:setVisible(false)
    end
end
-- --这里设未来展示没有的牌为黑色
function meta:IfHaveCard(group_id)
    if not deck_logic.is_compose then
        return true
    end
    local card_num = deck_logic:GetNumByGroupId(group_id)
    if card_num == 0 then
        return false
    end
    return true
end

function meta:ShowDiffInfo(diff_hp, diff_cost, diff_power_list)
    self.card_template_node:ShowDiffInfo(diff_hp, diff_cost, diff_power_list)
end


return meta
