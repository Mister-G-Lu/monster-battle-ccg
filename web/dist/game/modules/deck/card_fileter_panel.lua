local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"

local data_template = require "manager.data_template"
local CARD_CONFIG = data_template.card_config

local deck_logic = require "logic.deck"

local meta = class("card_fileter_panel",function (bing_node)
    ui_helper:SetCocosSetting(bing_node, "interface/deck/filter_panel.csb")
    return bing_node
end)

local function InitFilterCheckBox(widget)
    local chk_box = {}
    chk_box.selected = false
    chk_box.click_btn = widget
    chk_box.press_img = widget:getChildByName("press")
    return chk_box
end

function meta:ctor()
    self.card_type_chk_list = {}

    ui_helper:BindTimeLine(self, "interface/deck/filter_panel.csb")

    local filter_panel = self:getChildByName("filter_panel")

    local filter1 = filter_panel:getChildByName("filter1")
    self.card_type_chk_list["entire"] = InitFilterCheckBox(filter1:getChildByName("all_chk"))
    self.card_type_chk_list["entire"].selected = true
    self.card_type_chk_list["monster"] = InitFilterCheckBox(filter1:getChildByName("monster_chk"))
    self.card_type_chk_list["equip"] = InitFilterCheckBox(filter1:getChildByName("equip_chk"))
    self.card_type_chk_list["consume"] = InitFilterCheckBox(filter1:getChildByName("consume_chk"))

    self.card_kind_chk_list = {}
    local filter2 = filter_panel:getChildByName("filter2")
    self.card_kind_chk_list["entire"] = InitFilterCheckBox(filter2:getChildByName("entire_chk"))
    self.card_kind_chk_list["entire"].selected = true
    self.card_kind_chk_list["war"] = InitFilterCheckBox(filter2:getChildByName("war_chk"))
    self.card_kind_chk_list["fortune"] = InitFilterCheckBox(filter2:getChildByName("fortune_chk"))
    self.card_kind_chk_list["balance"] = InitFilterCheckBox(filter2:getChildByName("balance_chk"))
    self.card_kind_chk_list["nature"] = InitFilterCheckBox(filter2:getChildByName("nature_chk"))
    self.card_kind_chk_list["chaos"] = InitFilterCheckBox(filter2:getChildByName("chaos_chk"))
    self.card_kind_chk_list["all"] = InitFilterCheckBox(filter2:getChildByName("all_chk"))


    self.card_crystal_chk_list = {}
    local filter3 = filter_panel:getChildByName("filter3")
    self.card_crystal_chk_list["entire"] = InitFilterCheckBox(filter3:getChildByName("checkbox1"))
    self.card_crystal_chk_list["entire"].selected = true
    self.card_crystal_chk_list["crystal_1"] = InitFilterCheckBox(filter3:getChildByName("checkbox2"))
    self.card_crystal_chk_list["crystal_2"] = InitFilterCheckBox(filter3:getChildByName("checkbox3"))
    self.card_crystal_chk_list["crystal_3"] = InitFilterCheckBox(filter3:getChildByName("checkbox4"))
    self.card_crystal_chk_list["crystal_4"] = InitFilterCheckBox(filter3:getChildByName("checkbox5"))
    self.card_crystal_chk_list["crystal_5"] = InitFilterCheckBox(filter3:getChildByName("checkbox6"))

    self.card_quality_chk_list = {}
    local filter4 = filter_panel:getChildByName("filter4")
    self.card_quality_chk_list["entire"] = InitFilterCheckBox(filter4:getChildByName("checkbox1"))
    self.card_quality_chk_list["entire"].selected = true
    self.card_quality_chk_list["normal"] = InitFilterCheckBox(filter4:getChildByName("checkbox2"))
    self.card_quality_chk_list["rare"] = InitFilterCheckBox(filter4:getChildByName("checkbox3"))
    self.card_quality_chk_list["rarity"] = InitFilterCheckBox(filter4:getChildByName("checkbox4"))
    self.card_quality_chk_list["epic"] = InitFilterCheckBox(filter4:getChildByName("checkbox5"))

    self:PlayAnimation("normal")

    self.is_show = false

    self:RegisterWidgetEvent()
end

function meta:ResetFileter()
    local function Reset(list)
        list["entire"].selected = true
        for k, v in pairs(list) do
            if k == "entire" then
                v.selected = true
            else
                v.selected = false
            end
            v.press_img:setVisible(v.selected)
        end
    end
    Reset(self.card_type_chk_list)
    Reset(self.card_kind_chk_list)
    Reset(self.card_crystal_chk_list)
    Reset(self.card_quality_chk_list)
end

function meta:RegisterWidgetEvent()

    local filter_btn = self:getChildByName("filter_btn")
    ui_helper:AddClick(filter_btn, function ()
        self.is_show = not self.is_show
        if self.is_show then
            self.is_refresh = false
            ui_helper:SetTextByKey(filter_btn:getChildByName("desc"),"filter_open_desc")
            self:PlayAnimation("enter", false, function ()
                self:PlayAnimation("loop")
            end)
        else
            self:PlayAnimation("exit")
            ui_helper:SetTextByKey(filter_btn:getChildByName("desc"),"filter_close_desc")
            if self.is_refresh then
                graphic:DispatchEvent("refresh_card_list", self:GetFilterList())
            end
        end
    end)


    local function fileter_handler(filter_list)
    -- 类型过滤监听
        local other_count = 0
        for k,v in pairs(filter_list) do
            v.press_img:setVisible(v.selected)
            ui_helper:AddClick(v.click_btn,function ()
                 if k == "entire" and v.selected then
                    -- 全部是无法主动点掉的
                    return
                end
                v.selected = not v.selected
                v.press_img:setVisible(v.selected)
                self.is_refresh = true
                if k ~= "entire" then
                    if v.selected then
                        filter_list["entire"].selected = false
                        filter_list["entire"].press_img:setVisible(false)
                        other_count = other_count + 1
                    else
                        other_count = other_count - 1
                        if other_count == 0 then
                            filter_list["entire"].selected = true
                            filter_list["entire"].press_img:setVisible(true)
                        end
                    end
                else
                    if v.selected then
                        other_count = 0
                        for k,v in pairs(filter_list) do
                            if k ~= "entire" then
                                v.selected = false
                                v.press_img:setVisible(false)
                            end
                        end
                    end
                end
            end)
        end
    end

    fileter_handler(self.card_type_chk_list)
    fileter_handler(self.card_kind_chk_list)
    fileter_handler(self.card_crystal_chk_list)
    fileter_handler(self.card_quality_chk_list)

end


-- 获取过滤后的列表
function meta:GetFilterList()

    local filter_list = {}
    local card_group_list = deck_logic:GetFilterList()
    for k, group in pairs(card_group_list) do
        local card_id = group[table.maxn(group)]
        local config = deck_logic:GetCardConfigByModelId(card_id)
        local is_filter = true
        -- 检查类型过滤
        if not self.card_type_chk_list["entire"].selected and is_filter then

            if config.type == constants.CARD_TYPE.armor or config.type == constants.CARD_TYPE.equip  then
                if  not self.card_type_chk_list["equip"].selected then
                    is_filter = false
                end
            else
                if not self.card_type_chk_list[config.type].selected then
                    is_filter = false
                end
            end
        end
        -- 检查种类过滤
        if not self.card_kind_chk_list["entire"].selected and is_filter then
            local is_select = false
            for k,v in pairs(config.kind_list) do
                if self.card_kind_chk_list[v].selected and not is_select then
                    is_select = true
                end
            end
            is_filter = is_select
        end
        -- 检查卡费过滤
        if not self.card_crystal_chk_list["entire"].selected and is_filter then
            local key = "crystal_"..config.cost
            local filter_cond = self.card_crystal_chk_list[key]
            if filter_cond and not filter_cond.selected then
                is_filter = false
            end
            if not filter_cond and not self.card_crystal_chk_list["crystal_5"].selected then
                is_filter = false
            end
        end
        -- 检查品质过滤
        if not self.card_quality_chk_list["entire"].selected and is_filter then
            local filter_cond = self.card_quality_chk_list[config.quality]
            if filter_cond and not filter_cond.selected then
                is_filter = false
            end
        end

        if is_filter then
            table.insert(filter_list, config)
        end

    end

    -- 怪兽类型优先级
    local type_sork_order = {
        ["monster"] = 4,
        ["equip"] = 2,
        ["armor"] = 2,
        ["consume"] = 1,
    }

    local function comps(a_config, b_config)
        if type_sork_order[a_config.type] == type_sork_order[b_config.type] then
            if a_config.kind == b_config.kind then
                if a_config.cost == b_config.cost then
                    return a_config.quality > b_config.quality
                end
                return a_config.cost < b_config.cost
            end
            return a_config.kind > b_config.kind
        end
        return type_sork_order[a_config.type] > type_sork_order[b_config.type]
    end

    table.sort(filter_list, comps)


    return filter_list
end


return meta
