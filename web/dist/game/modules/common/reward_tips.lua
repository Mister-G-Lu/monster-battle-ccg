local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local resource = require "manager.resource"

local resource_logic = require "logic.resource"

local ITEM_CONFIG = data_template.item_config
local CHEST_CONFIG = data_template.chest_config
local MATERIAL_KIND = constants["MATERIAL_KIND"]

local meta = class("reward_tips",function (node)
    return ui_helper:LoadCocosUI("interface/common/itemdetail_node.csb")
end)

function meta:ctor()

    local root = self:getChildByName("bg")
    -- 名称
    self.name_txt = root:getChildByName("name")
    self.src_name_pos_y = self.name_txt:getPositionY()
    -- 描述
    self.desc_txt = root:getChildByName("desc")
    self.src_desc_pos_y = self.desc_txt:getPositionY()


    self.src_desc_size = self.desc_txt:getContentSize()
    local render = self.desc_txt:getVirtualRenderer()
    render:setDimensions(self.src_desc_size.width, 0)

    -- 背景
    self.back_group_img = root

    self.content_size = root:getContentSize()

    self:setVisible(false)
end

-- 自适应尺寸
function meta:SetDesc(desc)
    local render = self.desc_txt:getVirtualRenderer()
    ui_helper:SetText(self.desc_txt, desc)
    local new_size = render:getContentSize()

    local diff_height = new_size.height - self.src_desc_size.height + 6
    if diff_height < 0 then
        return
    end

    self.desc_txt:setContentSize(new_size)

    -- 修正背景框尺寸
    local new_content_size = { width = self.content_size.width, height = 0}
    new_content_size["height"] = self.content_size.height + diff_height
    self.back_group_img:setContentSize(new_content_size)

    -- 修正控件位置
    self.name_txt:setPositionY(self.src_name_pos_y + diff_height)
    self.desc_txt:setPositionY(self.src_desc_pos_y + diff_height)
end

function meta:Show(reward_info, pos)
    self:setVisible(true)

    local center = (self.content_size.width / 2)
    local offset = pos.x - (self.content_size.width / 2)

    if offset < 0 then
        self:setPosition({x = center, y = pos.y})
    else
        self:setPosition(pos)
    end

    if reward_info.type == constants["REWARD_TYPE"]["resource"] then
        local item_id = reward_info.attr_id
        local config = ITEM_CONFIG[item_id]
        if config then
            ui_helper:SetText(self.name_txt, config.name)
            self:SetDesc(config.desc)
        end
    elseif reward_info.type == constants["REWARD_TYPE"]["chest"] then
        local item_id = reward_info.attr_id
        local config = CHEST_CONFIG[item_id]
        if config then
            ui_helper:SetText(self.name_txt, config.name)
            self:SetDesc(config.desc)
        end
    end
end

function meta:Hide()
    self:setVisible(false)
end


return meta
