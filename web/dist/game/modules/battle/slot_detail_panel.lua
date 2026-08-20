local global = require "manager.global"
local ui_helper = require "manager.ui_helper"
local constants = require "common.constants"
local resource = require "manager.resource"
local data_template = require "manager.data_template"

local battle_logic = require "logic.battle"
local text_loader = require "manager.text_loader"
local defines = require "manager.defines"
local STATUS_KIND = constants.STATUS_KIND
local POWER_NAME = constants.POWER_NAME
local STATUS_CONFIG_MAP = data_template.status_config
local POWER_CONFIG_MAP = data_template.power_config


local status_sub_item = class("status_sub_item", function (node)
    node:setVisible(true)
    return node
end)

function status_sub_item:ctor()
    self.backgroup_node = self:getChildByName("bg")
    self.skill_empty_node = self:getChildByName("skill_empty")
    self.desc_txt = self:getChildByName("desc")
    self.status_count = 0
end

function status_sub_item:SetSkillStatus(template)
    self.skill_template = template
end

function status_sub_item:SetDesc(desc)
    ui_helper:SetText(self.desc_txt, desc)
end

function status_sub_item:AgainstSkill(status_name)
    local status_config = STATUS_CONFIG_MAP[status_name]
    if not status_config then
        return
    end

    local skill_item = self.skill_template:clone()
    skill_item:setVisible(true)
    local icon_img  = skill_item:getChildByName("icon")
    local name_txt  = skill_item:getChildByName("name")
    local round_txt = skill_item:getChildByName("desc")
    if self.status_count == 0 then
        self.skill_empty_node:setVisible(false)
    end

    ui_helper:SetText(name_txt, status_config.info_desc)
    ui_helper:SetText(round_txt, status_config.round_desc)
    icon_img:loadTexture(resource:GetSkillIcon(status_config.icon))

    local size1 = name_txt:getContentSize()
    local size2 = name_txt:getAutoRenderSize()

    local row_num = math.ceil(size2.width / size1.width)
    name_txt:setContentSize({ width = size1.width, height = size1.height * row_num})

    -- 重新设置大小
    local item_size = skill_item:getContentSize()
    local new_height = item_size.height + (size1.height * (row_num - 1))
    skill_item:setContentSize({ width = item_size.width, height = new_height })

    icon_img:setPositionY(new_height + 0.5)
    name_txt:setPositionY(new_height - 2)
    round_txt:setPositionY(5)

    self:AddItem(skill_item, new_height)
end

-- 插入状态信息
function status_sub_item:PushStatus(status_name, status_info)
    local value = status_info.value
    local round = status_info.round

    local status_config = STATUS_CONFIG_MAP[status_name]
    if not status_config then
        return
    end

    local skill_item = self.skill_template:clone()
    skill_item:setVisible(true)
    local icon_img  = skill_item:getChildByName("icon")
    local name_txt  = skill_item:getChildByName("name")
    local round_txt = skill_item:getChildByName("desc")
    if self.status_count == 0 then
        self.skill_empty_node:setVisible(false)
    end

    ui_helper:SetText(round_txt, string.format(status_config.round_desc, round))
    ui_helper:SetText(name_txt, string.format(status_config.info_desc, value))
    icon_img:loadTexture(resource:GetSkillIcon(status_config.icon))



    local size1 = name_txt:getContentSize()
    local size2 = name_txt:getAutoRenderSize()

    local row_num = math.ceil(size2.width / size1.width)
    name_txt:setContentSize({ width = size1.width, height = size1.height * row_num})

    -- 重新设置大小
    local item_size = skill_item:getContentSize()
    local new_height = item_size.height + (size1.height * (row_num - 1))
    skill_item:setContentSize({ width = item_size.width, height = new_height })

    icon_img:setPositionY(new_height + 0.5)
    name_txt:setPositionY(new_height - 2)
    round_txt:setPositionY(5)

    self:AddItem(skill_item, new_height)
end

function status_sub_item:AddItem(skill_item, item_height)
    item_height = item_height + 3
    skill_item:setPosition(0, 40 + self.status_count * item_height)
    local height = 70 + self.status_count * item_height
    self:setContentSize({ width = 548.00, height =  height })
    self.backgroup_node:setContentSize({ width = 546.00, height = 5 + (1 + self.status_count) * item_height})
    self.desc_txt:setPositionY(height - 8)
    self.backgroup_node:setPositionY(height - 20)

    self:updateTransform()
    self.status_count = self.status_count + 1
    self:addChild(skill_item)
end

local meta = class("slot_detail_panel",function ()
    return ui_helper:LoadCocosUI("interface/battle/card_detail_panel.csb")
end)

local DETAIL_TYPE = {
    monster = "monster",
    equip = "equip"
}

function meta:ctor()

    self.equip_card_node = ui_helper:ExpandUI(self, "equip_card", "modules.common.card_hand_item")
    self.monster_card_node = ui_helper:ExpandUI(self, "monster_card", "modules.common.card_hand_item")

    local detail_bg = self:getChildByName("detail_bg")
    self.equip_detail_list = detail_bg:getChildByName("equip_detail_list")  --技能list
    self.monster_detail_list = detail_bg:getChildByName("monster_detail_list")  --怪兽list


    self.title_template = self:getChildByName("title_template")
    self.status_template = self:getChildByName("status_template")
    self.skill_status_template = self:getChildByName("skill_status_template")
    self.skill_desc_template = self:getChildByName("skill_desc_template")

    self.title_template:setVisible(false)
    self.status_template:setVisible(false)
    self.skill_status_template:setVisible(false)
    self.skill_desc_template:setVisible(false)


    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

function meta:Show(slot)
    self:setVisible(true)
    local monster_info = slot.monster
    local item_info = slot.item

    if monster_info then
        self.monster_card_node:setVisible(true)
        self.monster_card_node:SetCardInfo(monster_info)
    else
        self.monster_card_node:setVisible(false)
    end

    if item_info then
        self.equip_card_node:setVisible(true)
        self.equip_card_node:SetCardInfo(item_info)
    else
        self.equip_card_node:setVisible(false)
    end
    self.detail_type = nil
    self:SetDetailType(DETAIL_TYPE.monster)

    self:BuildSlotMonsterInfo(slot)
    self:BuildSlotEquipInfo(slot)
end

-- 生成标题项
function meta:BuildTitleItem(desc)
    local title_item = self.title_template:clone()
    title_item:setVisible(true)
    local desc_txt = title_item:getChildByName("desc")
    ui_helper:SetText(desc_txt, desc)
    return title_item
end

-- 生成BUFF状态
function meta:BuildBuffStatusItem(slot)
    local status_map = slot.status_map
    local status_item = status_sub_item.new(self.status_template:clone())
    status_item:SetDesc(text_loader:GetText("slot_detail_title_buff"))
    status_item:SetSkillStatus(self.skill_status_template)
    for status_name, status_info in pairs(status_map) do
        if STATUS_KIND[status_name] == 2 then
            status_item:PushStatus(status_name, status_info)
        end
    end

    return status_item
end
-- 生成DEBUff状态
function meta:BuildDebuffStatusItem(slot)
    local status_map = slot.status_map
    local status_item = status_sub_item.new(self.status_template:clone())
    status_item:SetDesc(text_loader:GetText("slot_detail_title_debuff"))
    status_item:SetSkillStatus(self.skill_status_template)
    for status_name, status_info in pairs(status_map) do
        if STATUS_KIND[status_name] == 1 then
            status_item:PushStatus(status_name, status_info)
        end
    end

    -- 禁用远程
    if slot.pos == 1 and slot:GetPower(POWER_NAME.ranged) then
        status_item:AgainstSkill("against_ranged")
    end

    -- 禁用近战
    if slot.pos ~= 1 and slot:GetPower(POWER_NAME.melee) then
        if not slot:GetPower(POWER_NAME.reach) and not slot:GetPower(POWER_NAME.backstab) then
            status_item:AgainstSkill("against_melee")
        end
    end

    return status_item
end

-- 生成技能项
function meta:BuildSkillItem(power, type)
    local skill_item = self.skill_desc_template:clone()
    skill_item:setVisible(true)

    local power_config = POWER_CONFIG_MAP[power.name]
    local name = power_config.name_desc
    local desc = power_config.info_desc

    -- 技能图标
    local icon_img = skill_item:getChildByName("icon")
    icon_img:loadTexture(resource:GetSkillIcon(power.name))
    -- 技能名称
    local title_txt = skill_item:getChildByName("title")
    ui_helper:SetText(title_txt, name)
    -- 技能描述
    local desc_txt = skill_item:getChildByName("desc")
    ui_helper:SetText(desc_txt, desc)
    local size1 = desc_txt:getContentSize()
    local size2 = desc_txt:getAutoRenderSize()
    local row_num = math.ceil(size2.width / size1.width)
    --字体位置偏移（根据语种）
    local height = size1.height * defines.FONT_OFFSET[text_loader.cur_lang]
    desc_txt:setContentSize({ width = size1.width, height = height * row_num })
    -- 重新设置大小
    local item_size = skill_item:getContentSize()
    local new_height = item_size.height + (size1.height * (row_num - 1))
    skill_item:setContentSize({ width = item_size.width, height = new_height })

    icon_img:setPositionY(new_height + 2)
    title_txt:setPositionY(new_height + 1.4)
    desc_txt:setPositionY(new_height - 28.2)

    return skill_item
end

function meta:BuildSlotMonsterInfo(slot)
    local monster_detail_list = self.monster_detail_list
    monster_detail_list:removeAllChildren()

    local buff_status_item = self:BuildBuffStatusItem(slot)
    local debuff_status_item = self:BuildDebuffStatusItem(slot)
    local len = buff_status_item.status_count + debuff_status_item.status_count
    -- 状态标题
    if len ~= 0 then
        monster_detail_list:pushBackCustomItem(self:BuildTitleItem(text_loader:GetText("slot_detail_title_status")))
    end
    -- BUFF
    if buff_status_item.status_count ~= 0 then
        monster_detail_list:pushBackCustomItem(buff_status_item)
    end
    -- DEBUFF
    if debuff_status_item.status_count ~= 0 then
        monster_detail_list:pushBackCustomItem(debuff_status_item)
    end
    -- 技能说明标题
    monster_detail_list:pushBackCustomItem(self:BuildTitleItem(text_loader:GetText("slot_detail_title_power")))
    local monster_info = slot.monster

    for k, power in pairs(monster_info.power_list) do
        monster_detail_list:pushBackCustomItem(self:BuildSkillItem(power))
    end
    -- 刷新列表布局
    monster_detail_list:requestDoLayout()
end

function meta:BuildSlotEquipInfo(slot)
    local item_info = slot.item
    if item_info == nil then
        return
    end

    local equip_detail_list = self.equip_detail_list
    equip_detail_list:removeAllChildren()
    -- -- 状态标题
    -- equip_detail_list:pushBackCustomItem(self:BuildTitleItem(text_loader:GetText("slot_detail_title_status")))
    -- 技能说明标题
    equip_detail_list:pushBackCustomItem(self:BuildTitleItem(text_loader:GetText("slot_detail_title_power")))

    local item_info = slot.item
    local power_list = item_info.power_list or {}
    for k, power in pairs(power_list) do
        equip_detail_list:pushBackCustomItem(self:BuildSkillItem(power))
    end
end


function meta:Hide()
    self:setVisible(false)
    battle_logic:ReqOperationFoucs(false, false, -1)
end

-- 切换描述类型
function meta:SetDetailType(detail_type)
    if self.detail_type == detail_type then
        return
    end

    if detail_type == DETAIL_TYPE.monster then
        self:PlayAnimation("to_monsterdetail", false, function ()
            self:PlayAnimation("normal_monsterdetail")
        end)

        self.equip_detail_list:setVisible(false)
        self.monster_detail_list:setVisible(true)
    elseif detail_type == DETAIL_TYPE.equip then
        self:PlayAnimation("to_equipdetail", false, function ()
            self:PlayAnimation("normal_equipdetail")
        end)

        self.equip_detail_list:setVisible(true)
        self.monster_detail_list:setVisible(false)
    end
    self.detail_type = detail_type
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()
    local back_btn = self:getChildByName("back_btn")
    ui_helper:AddClick(back_btn, function ()
        battle_logic:DispatchEvent("pop_battle_panel")
    end)

    self.equip_card_node:AddClick(function ()
        self:SetDetailType(DETAIL_TYPE.equip)
    end)

    self.monster_card_node:AddClick(function ()
        self:SetDetailType(DETAIL_TYPE.monster)
    end)
end

return meta
