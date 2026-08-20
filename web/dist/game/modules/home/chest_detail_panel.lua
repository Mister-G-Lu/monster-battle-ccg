local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"

local chest_logic = require "logic.chest"
local timer = require "manager.time"


local audio_manager = require "manager.audio_manager"
local constants = require "common.constants"
local data_template = require "manager.data_template"
local CHEST_STAGE = constants.CHEST_STAGE
local REWARD_TYPE = constants.REWARD_TYPE
local CARD_QUALITY = constants.CARD_QUALITY
local CARD_CONFIG = data_template.card_config

local meta = class("chest_detail_panel",function (node)
    return node
end)

function meta:ctor()

    -- 卡包明细
    self.chest_title_txt = self:getChildByName("title")

    self.coin_img = self:getChildByName("coin")
    self.coin_value_txt = self.coin_img:getChildByName("value")

    self.card_img = self:getChildByName("card")
    self.card_value_txt = self.card_img:getChildByName("value")

    self.atleast_template = self:getChildByName("atleast_template")

    self.open_btn = self:getChildByName("open_btn")

    self.waiting_node = self.open_btn:getChildByName("waiting_icon")
    ui_helper:BindTimeLine(self.waiting_node, "interface/world/waiting_tip.csb")

    self.time_txt = self.waiting_node:getChildByName("time")

    self.open_txt = self.open_btn:getChildByName("open_txt")

    self.empty_txt = self:getChildByName("empty_txt")


    self.atleast_node_list = {}
    for i = 1, 3 do
        local node_temp = self:getChildByName("atleast_template"..i)
        node_temp.value_txt = node_temp:getChildByName("value")
        node_temp:setVisible(false)
        self.atleast_node_list[i] = node_temp
    end


    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

function meta:Update(elapsed_time)
    local chest_info = self.chest_info
    if not chest_info then
        return
    end
    if chest_info.stage == CHEST_STAGE.opening then
        local diff_time = timer:GetDiffSecond(chest_info.open_time)
        if diff_time > 0 then
            ui_helper:SetTextByKey(self.time_txt, "chest_time_desc", timer:FormatTime(diff_time))
        else
            chest_info.open_time = 0
            chest_info.stage = CHEST_STAGE.wait_open
            self:Refresh(self.cur_chest_idx, chest_info)
        end
    end
end

function meta:Refresh(index, chest_info)
    self.chest_info = chest_info
    self.cur_chest_idx = index

    local chest_config = data_template.chest_config[chest_info.chest_id]

    if chest_info.stage == CHEST_STAGE.wait_open then
        self.open_btn:setEnabled(true)
        self.waiting_node:setVisible(false)
        self.open_txt:setVisible(true)

        if chest_info.open_time == 0 then
            ui_helper:SetTextByKey(self.open_txt, "chest_stage_use")
        else
            ui_helper:SetTextByKey(self.open_txt, "chest_stage_open")
        end
    elseif chest_info.stage == CHEST_STAGE.opening then
        self.open_btn:setEnabled(false)
        self.waiting_node:setVisible(true)
        self.open_txt:setVisible(false)
        self.waiting_node:PlayAnimation("waiting", true)

        local diff_time = timer:GetDiffSecond(chest_info.open_time)
        ui_helper:SetTextByKey(self.time_txt, "chest_time_desc", timer:FormatTime(diff_time))
    end

    -- 卡包名称
    ui_helper:SetText(self.chest_title_txt, chest_config.name)

    -- 金钱
    local reward_money = chest_config.reward_money
    ui_helper:SetTextByKey(self.coin_value_txt, "chest_money_desc", reward_money[1], reward_money[2])
    -- 卡牌数量
    local card_num = chest_config.card_num
    ui_helper:SetTextByKey(self.card_value_txt, "chest_card_desc", card_num)
    -- 保底卡牌状态
    for i = 1, 3 do
        self.atleast_node_list[i]:setVisible(false)
    end
    local index = 1
    local guarantee_list = chest_config.guarantee
    for k,v in pairs(guarantee_list) do
        if v > 0 then
            local node_temp = self.atleast_node_list[index]
            node_temp:setVisible(true)
            node_temp:loadTexture(resource:GetQualityImage(constants["CARD_QUALITY"][k]))
            local quality_desc = text_loader:GetText("card_quality_"..k)
            ui_helper:SetText(node_temp.value_txt, quality_desc.."x"..v)
            index = index + 1
        end
    end

    if index == 1 then
        self.empty_txt:setVisible(true)
    else
        self.empty_txt:setVisible(false)
    end

end


-- 注册渲染事件
function meta:RegisterEvent()
end

-- 注册UI事件
function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.open_btn, function ()
        chest_logic:OpenChest(self.cur_chest_idx)
    end)
end

return meta
