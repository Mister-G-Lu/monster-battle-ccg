local global = require "manager.global"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local resource = require "manager.resource"
local text_loader = require "manager.text_loader"

local bit = require "utils.bit_extension"
local constants = require "common.constants"
local data_template = require "manager.data_template"

local CHEST_CONFIG = data_template.chest_config


local meta = class("chest_template_panel",function (node)
    return node
end)

function meta:ctor()

    -- 卡包背景
    self.chest_icon = self:getChildByName("chest_icon")
    -- 卡包名称
    self.name_txt = self:getChildByName("name")
    -- 卡包数量
    self.num_txt = self:getChildByName("num")

    local info = self:getChildByName("info")
    -- 卡数量
    self.num_card_txt = info:getChildByName("total")
    -- 品质数量
    self.quality_img = info:getChildByName("icon2")
    self.quality_txt = info:getChildByName("atleast")

end


function meta:SetChestInfo(chest_info)
    ui_helper:SetText(self.num_txt, "x"..chest_info.chest_num)
    local config = CHEST_CONFIG[chest_info.chest_id]
    if not config then
        self:setVisible(false)
        return
    end
    self:setVisible(true)
    ui_helper:SetText(self.name_txt, config.name)
    local card_num = config.card_num
    ui_helper:SetTextByKey(self.num_card_txt, "chest_have_card_num", card_num)

    local quality = config.quality
    self.chest_icon:loadTexture(resource:GetChestStyle(constants["CHEST_QUALITY"][quality]))



    local guarantee_list = config.guarantee
    local quality_icon = 0
    local quality_num = 0
    for k,v in pairs(guarantee_list) do
        if v > 0 then
            quality_icon = k
            quality_num = v
        end
    end
    if quality_icon == 0 then
        self.quality_txt:setVisible(false)
        self.quality_img:setVisible(false)
    else
        self.quality_txt:setVisible(true)
        self.quality_img:setVisible(true)
        self.quality_img:loadTexture(resource:GetQualityImage(quality_icon))
        local quality_desc = text_loader:GetText("card_quality_"..quality_icon)
        local desc = text_loader:GetText("chest_quality_at_least", quality_desc, quality_num)

        ui_helper:SetText(self.quality_txt, desc)
    end

end

-- 添加
function meta:AddClick(func)
    ui_helper:AddClick(self, function ()
        if func then func() end
    end)
end



return meta
