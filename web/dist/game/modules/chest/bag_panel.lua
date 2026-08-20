local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"
local timer = require "manager.time"

local constants = require "common.constants"

local chest_logic = require "logic.chest"
local arena_logic = require "logic.arena"

local ARENA_REWARD_NUM = constants["ARENA_REWARD_NUM"]


local meta = class("chest_bag_panel",function ()
    return ui_helper:LoadCocosUI("interface/chest/cardbag_panel.csb")
end)

function meta:ctor()
    local root_node = self:getChildByName("node")

    self.close_btn = root_node:getChildByName("close_btn")
    -- 剩余卡包数量
    self.chest_num_txt = root_node:getChildByName("num")
    -- 刷新时间
    self.refresh_time_txt = root_node:getChildByName("time")
    -- 卡包滚动条
    self.chest_scroll_list = root_node:getChildByName("scrollview")
    self.chest_item_list = {}
    -- 卡包模板
    self.chest_template = root_node:getChildByName("cardbag_template")
    self.chest_template:setVisible(false)

    self.cur_min = 0
    self:RegisterEvent()
    self:RegisterWidgetEvent()
end

-- 创建卡包模板
function meta:CreateChest()
    local new_chest = require("modules.chest.item_template").new(self.chest_template:clone())
    new_chest:setVisible(true)
    return new_chest
end

function meta:Update(elapsed_time)
    self.cur_min = self.cur_min + elapsed_time
    if self.cur_min >= 1 then
        self.cur_min = 0
        self:RefreshRewardTime()
    end
end

-- 刷新奖励时间
function meta:RefreshRewardTime()

    local diff_time = arena_logic.next_refresh_chest - timer:Now()
    if diff_time > 0 then
        -- -- 立刻请求刷新奖励
        -- self.start_time = false
        -- arena_logic:ReqRefreshReward(function ()
        --     self.start_time = true
        -- end)
    -- else
        local desc = text_loader:GetText("refresh_time_desc", timer:FormatTime(diff_time))
        ui_helper:SetText(self.refresh_time_txt, desc)
    end

end

function meta:Show()
    self:setVisible(true)
    ui_helper:SetText(self.chest_num_txt, arena_logic.last_reward_chest_num.."/"..ARENA_REWARD_NUM)
    self.start_time = true
    self:RefreshRewardTime()

    for _,v in pairs(chest_logic.chest_bag) do
        local chest_id = v.chest_id
        if v.chest_num > 0 then
            local item = self.chest_item_list[chest_id]
            if not item then
                item = self:CreateChest()
                self.chest_item_list[chest_id] = item
                self.chest_scroll_list:pushBackCustomItem(item)
                item:AddClick(function ()
                    chest_logic:OpenChest(chest_id)
                end)
            end
            item:SetChestInfo(v)
        end
    end
end

function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
    graphic:RegisterEvent("refresh_chest_info", function (chest_info)
        if not chest_info then
            return
        end
        local chest_id = chest_info.chest_id
        local chest_num = chest_info.chest_num
        local item = self.chest_item_list[chest_id]
        if chest_num <= 0 and item then
            self.chest_scroll_list:removeChild(item)
            self.chest_item_list[chest_id] = nil
        else
            if item then
                item:SetChestInfo(chest_info)
            else
                item = self:CreateChest()
                self.chest_item_list[chest_id] = item
                self.chest_scroll_list:pushBackCustomItem(item)
                item:AddClick(function ()
                    chest_logic:OpenChest(chest_id)
                end)
            end

        end
    end)

    graphic:RegisterEvent("refresh_reward_num", function ()
        ui_helper:SetText(self.chest_num_txt, arena_logic.last_reward_chest_num.."/"..ARENA_REWARD_NUM)
    end)
end

function meta:RegisterWidgetEvent()

    ui_helper:AddClick(self.close_btn, function ()
        graphic:DispatchEvent("pop_world_panel")
    end)

end



return meta
