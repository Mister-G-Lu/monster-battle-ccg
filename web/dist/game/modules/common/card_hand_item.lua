local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"
local defines = require "manager.defines"

local data_template = require "manager.data_template"
local deck_logic = require "logic.deck"

local CARD_CONFIG = data_template.card_config
local MAIN_POWER = constants.MAIN_POWER
local BATTLE_VALUE_SCALE = constants.BATTLE_VALUE_SCALE

local POWER_POS = {

}

local meta = class("card_hand_item",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/deck/card_hand_template.csb")

end)

function meta:ctor()
    local template_node = self:getChildByName("card_template")
    -- 卡图
    self.card_icon_img = template_node:getChildByName("card")

    -- 背景图
    self.backgroup_img = template_node:getChildByName("background")
    -- 种类
    self.border1_spr = template_node:getChildByName("border1")
    self.border2_spr = template_node:getChildByName("border2")
    -- 颜色1
    local color_tip1 = template_node:getChildByName("color_tip1")
    self.color_tip1_bg = color_tip1:getChildByName("bg")
    self.color_tip1_icon = color_tip1:getChildByName("icon")

    -- 颜色2
    local color_tip2 = template_node:getChildByName("color_tip2")
    self.color_tip2_bg = color_tip2:getChildByName("bg")
    self.color_tip2_icon = color_tip2:getChildByName("icon")
    -- 标题颜色1
    self.title_bg1 = template_node:getChildByName("title_bg1")
    -- 标题颜色2
    self.title_bg2 = template_node:getChildByName("title_bg2")
    -- 卡费
    self.crystal_cost_txt = template_node:getChildByName("crystal_cost")
    self.crystal_cost_txt_sacle = self.crystal_cost_txt:getScale()
    -- 卡牌名称+星级
    self.title_txt = template_node:getChildByName("title")
    self.title_txt:setVisible(false)
    self.title_txt2 = template_node:getChildByName("title2")
    self.title_txt2:setVisible(true)
    -- 怪兽的类型
    local card_type_node = template_node:getChildByName("kind")
    self.card_type_img = card_type_node:getChildByName("icon")

    -- 生命或者护盾
    local hp_n_armor_template = template_node:getChildByName("hp_n_armor_template")
    self.property_node = hp_n_armor_template
    self.property_icon = hp_n_armor_template
    self.property_value = hp_n_armor_template:getChildByName("value")
    self.property_value_scale = self.property_value:getScale()

    --已上阵提示
    local online_tips = ui_helper:LoadCocosUI("interface/deck/online_tips.csb")
    online_tips:setScale(1.4)
    template_node:addChild(online_tips,100)
    online_tips:setPosition(cc.p(155,190))
    self.online_tips = online_tips
    self.online_tips:setVisible(false)

    -- 品质
    self.quality_img = template_node:getChildByName("quality")

    -- 主要技能
    local main_power_list = {}
    for i = 1, 2 do
        local main_power = template_node:getChildByName("skill1_template"..i)
        local icon_img = main_power:getChildByName("skill_icon")
        local num_txt = main_power:getChildByName("value")
        main_power.src_scale = num_txt:getScale()
        main_power.num_txt = num_txt
        main_power.icon_img = icon_img
        main_power_list[i] = main_power
    end
    self.main_power_list = main_power_list
    -- 其他技能
    local other_power_list = {}
    self.skill2_shadow_img = template_node:getChildByName("skill2_shadow")
    for i = 1, 3 do
        local other_power = template_node:getChildByName("skill2_template"..i)
        local bg_img = other_power:getChildByName("bg")
        local icon_img = other_power:getChildByName("icon")
        local num_txt = other_power:getChildByName("value")
        other_power.src_scale = num_txt:getScale()
        other_power.bg_img = bg_img
        other_power.icon_img = icon_img
        other_power.num_txt = num_txt
        other_power_list[i] = other_power
        POWER_POS[i] = other_power:getPositionX()
    end
    self.other_power_list = other_power_list

end
function meta:Relativedisplay(bool)
    if bool == true then
        local gary_state = cc.GLProgramState:getOrCreateWithGLProgramName("ShaderPositionTextureColor_noMVP")
        self.card_icon_img:setGLProgramState(gary_state)
    else
        local gary_state = cc.GLProgramState:getOrCreateWithGLProgramName("ShaderUIGrayScale")
        self.card_icon_img:setGLProgramState(gary_state)
    end
end

function meta:SetCardId(uid)
    self.uid = uid
    self:SetCardInfo(CARD_CONFIG[uid])
end

function meta:SetCardInfo(card_config, in_detail_card)
    if not card_config then
        return
    end
    local config = card_config

    local name = config["name"]
    if CARD_CONFIG[config.uid] then
        name = CARD_CONFIG[config.uid]["name"]
    end

    in_detail_card = in_detail_card or false
    --是否已上阵
    if in_detail_card and not deck_logic.is_compose then

        local card_detail_list = deck_logic:GetCardListByGroupId(config.group_id)
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

    ui_helper:SetText(self.crystal_cost_txt, config.cost) -- 水晶水量
    self.crystal_cost_txt:setScale(self.crystal_cost_txt_sacle)
    self.crystal_cost_txt:setColor(ui_helper:GetColor4B(0xFFFFFF))

    local path = resource:GetCardImage(config.type, config.kind, config.res_path)
    self.card_icon_img:setTexture(path)
    self.title_txt:setVisible(false)
    self.title_txt2:setVisible(false)
    -- if (...) ~= nil then
    ui_helper:SetText(self.title_txt, name.." ★"..config.level)  -- 卡牌名称
    self.title_txt:setVisible(true)
    -- else
    --     ui_helper:SetText(self.title_txt2," ★"..config.level)
    --     self.title_txt2:setVisible(true)
    -- end
    ui_helper:SetText(self.title_txt2," ★"..config.level)  -- 卡牌名称
    if config.type == constants.CARD_TYPE.consume then
        self.backgroup_img:setTexture("ui/kind_bg/consumables_bg.png")
    else
        local path = resource:GetKindBgImage(config.kind)
        self.backgroup_img:setTexture(path)
    end

    self.card_type_img:loadTexture(resource:GetCardTypeIcon(config.type))

    -- 种类
    local kind_list = {}
    for k,v in pairs(constants["CARD_KIND"]) do
        if bit:GetBitNum(config.kind, v) == 1 then
            table.insert(kind_list, k)
        end
    end

    -- -- kind_list = {"fortune","chaos"}
    local len = #kind_list
    local CARD_KIND_COLOR = defines["CARD_KIND_COLOR"]
    self.border1_spr:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[1]]))
    self.color_tip1_bg:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[1]]))
    self.title_bg1:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[1]]))
    self.color_tip1_icon:loadTexture(resource:GetKindIcon(kind_list[1]))



    if len ~= 1 then
        self.color_tip2_bg:setVisible(true)
        self.title_bg2:setVisible(true)
        self.color_tip2_icon:setVisible(true)

        self.border2_spr:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[2]]))
        self.color_tip2_bg:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[2]]))
        self.title_bg2:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[2]]))
        self.color_tip2_icon:loadTexture(resource:GetKindIcon(kind_list[2]))
    else
        self.border2_spr:setColor(ui_helper:GetColor4B(CARD_KIND_COLOR[kind_list[1]]))
        self.color_tip2_bg:setVisible(false)
        self.title_bg2:setVisible(false)
        self.color_tip2_icon:setVisible(false)
    end

    -- 品质
    self.quality_img:loadTexture(resource:GetQualityImage(config.quality))

    -- 生命或者护盾
    if config.type == constants.CARD_TYPE.monster then
        self.property_icon:loadTexture("ui/pic_card/hp_bg.png", ccui.TextureResType.plistType)
    else
        self.property_icon:loadTexture("ui/pic_card/armor_bg.png", ccui.TextureResType.plistType)
    end
    self.property_icon:ignoreContentAdaptWithSize(false)
    if config.hp > 0 then
        self.property_node:setVisible(true)
        ui_helper:SetText(self.property_value, config.hp * BATTLE_VALUE_SCALE)
    else
        self.property_node:setVisible(false)
    end
    self.property_value:setScale(self.property_value_scale)
    self.property_value:setColor(ui_helper:GetColor4B(0xFFFFFF))



    for i = 1, 2 do
        local main_power = self.main_power_list[i]
        main_power:setVisible(false)
    end

    for i = 1, 3 do
        local other_power = self.other_power_list[i]
        other_power:setVisible(false)
    end

    self.power_map = {}
    local power_list = config.power_list or {}
    local main_power_idx = 1
    local other_power_list = {}
    for k,v in pairs(power_list) do
        local power_name = v.name

        if MAIN_POWER[power_name] == 1 then
            local main_power = self.main_power_list[main_power_idx]
            main_power:setVisible(true)
            main_power.icon_img:loadTexture(resource:GetSkillIcon(power_name))
            ui_helper:SetText(main_power.num_txt, v.value * BATTLE_VALUE_SCALE)
            main_power.num_txt:setScale(main_power.src_scale)
            main_power.num_txt:setColor(ui_helper:GetColor4B(0xFFFFFF))
            main_power_idx = main_power_idx + 1
            self.power_map[power_name] = main_power
        else
            table.insert(other_power_list, v)
        end
    end

    local size = #other_power_list
    if size == 0 then
        self.skill2_shadow_img:setVisible(false)
    else
        self.skill2_shadow_img:setVisible(true)
    end

    local idx = 1
    for i = 1, size do
        local power = other_power_list[i]
        local other_power = self.other_power_list[i]
        other_power:setVisible(true)
        -- other_power.bg_img:setColor(ui_helper:GetColor4B(new_color))
        other_power.icon_img:loadTexture(resource:GetSkillIcon(power.name))
        self.power_map[power.name] = other_power

        if power.value == 0 then
            other_power.num_txt:setVisible(false)
        else
            other_power.num_txt:setVisible(true)
            ui_helper:SetText(other_power.num_txt, power.value * BATTLE_VALUE_SCALE)
            other_power.num_txt:setScale(other_power.src_scale)
            other_power.num_txt:setColor(ui_helper:GetColor4B(0xFFFFFF))
        end
    end
end

function meta:ShowDiffInfo(diff_hp, diff_cost, diff_power_list)
    local color = 0xA9FF3C
    local scale_rate = 1.2
    if diff_hp > 0 then
        local src_scale = self.property_value:getScale()
        self.property_value:setColor(ui_helper:GetColor4B(color))
        self.property_value:setScale(src_scale * scale_rate)
    end

    if diff_cost > 0 then
        local src_scale = self.crystal_cost_txt:getScale()
        self.crystal_cost_txt:setColor(ui_helper:GetColor4B(color))
        self.crystal_cost_txt:setScale(src_scale * scale_rate)
    end

    for k,v in pairs(diff_power_list) do
        if v > 0 then

            local widget = self.power_map[k]
            if widget then
                local src_scale = widget.num_txt:getScale()
                widget.num_txt:setColor(ui_helper:GetColor4B(color))
                widget.num_txt:setScale(src_scale * scale_rate)
            end
        end
    end
end

function meta:AddClick(func)
    self.border1_spr:setTouchEnabled(true)
    self.border2_spr:setTouchEnabled(true)
    ui_helper:AddClick(self.border1_spr, func)
    ui_helper:AddClick(self.border2_spr, func)
    -- ui_helper:AddClick(self.backgroup_img, func)
end



return meta
