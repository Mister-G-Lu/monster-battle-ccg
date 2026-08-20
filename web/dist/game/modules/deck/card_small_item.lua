local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"
local defines = require "manager.defines"

local deck_logic = require "logic.deck"

local data_template = require "manager.data_template"

local MAIN_POWER = constants.MAIN_POWER


local meta = class("card_small_item",function (node)
    local path = "interface/deck/card_small_template.csb"
    if not node then
        node = ui_helper:LoadCocosUI(path)
    end
    ui_helper:BindTimeLine(node, path)
    return node
end)

function meta:ctor()
    local root_node = self:getChildByName("card_small_template")

    local card_template = root_node:getChildByName("card_template")
    self:PlayAnimation("normal")
    -- 卡牌背景
    self.card_backgroup_img = card_template
    -- 卡牌图片
    self.card_img = card_template:getChildByName("card")
    -- 卡牌边框1
    self.border1_spr = card_template:getChildByName("border")
    -- 卡牌消耗
    self.cost_value_txt = card_template:getChildByName("cost_value")
    -- 卡牌品质
    self.quality_img = card_template:getChildByName("quality")
    self.main_power_list = {}
    -- 技能1
    self.main_power_list[1] = card_template:getChildByName("icon1")
    -- 技能2
    self.main_power_list[2] = card_template:getChildByName("icon2")

    self.item_kindicon = root_node:getChildByName("item_kindicon")
    self.monster_level = root_node:getChildByName("monster_level")
    self.bar_shadow = root_node:getChildByName("loadingbarshadow")
end

function meta:ShowCardGroupInfo(data_index, card_config)
    self.data_index = data_index
    local config = card_config

    ui_helper:SetText(self.cost_value_txt, config.cost)
    local path = resource:GetCardImage(config.type, config.kind, config.res_path)
    self.card_img:setTexture(path)
    self.quality_img:loadTexture(resource:GetQualityImage(config.quality))

    self.item_kindicon:setVisible(false)
    self.monster_level:setVisible(false)
    if config.type ~= constants.CARD_TYPE.monster then
        self.card_backgroup_img:loadTexture(resource:GetKindBgImage(config.kind))
        self.item_kindicon:setVisible(true)
        self.item_kindicon:loadTexture(resource:GetCardTypeIcon(config.type))
    else
        self.monster_level:setVisible(true)
        ui_helper:SetText(self.monster_level, "★"..config.level)
    end

    -- 种类
    local kind_list = {}
    for k,v in pairs(constants["CARD_KIND"]) do
        if bit:GetBitNum(config.kind, v) == 1 then
            table.insert(kind_list, k)
        end
    end
    local len = #kind_list
    local CARD_KIND_COLOR = defines["CARD_KIND_COLOR"]
    self.border1_spr:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[1]]))

    for i = 1, 2 do
        local main_power = self.main_power_list[i]
        main_power:setVisible(false)
    end

    local power_list = config.power_list or {}
    local main_power_idx = 1
     for k,v in pairs(power_list) do
        local power_name = v.name
        if MAIN_POWER[power_name] == 1 then
            local main_power = self.main_power_list[main_power_idx]
            main_power:setVisible(true)
            main_power:loadTexture(resource:GetSkillIcon(power_name))
            main_power_idx = main_power_idx + 1
        end
    end
end


return meta
