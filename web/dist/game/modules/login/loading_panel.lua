local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"

local login_logic = require "logic.login"

local meta = class("loading_panel",function (node)
    return node
end)

-- 加载最长时间2秒
local LOADING_TIME = 2
local STAGE = login_logic.STAGE

function meta:ctor()
    local loading_bg = self:getChildByName("loading_bg")

    -- 随机提示文字
    self.random_desc_txt = loading_bg:getChildByName("random_desc")

    -- 进度条
    self.loading_bar = loading_bg:getChildByName("loadingbar")

    self.is_loading_start = false
    self.cur_percent = 0
    self.next_percent = 0

    self.loading_bar:setPercent(0)

    local director = cc.Director:getInstance()
    local scheduler = director:getScheduler()
    local schedule_id = nil
    self:registerScriptHandler(function(event)
        if event == "enter" then
            schedule_id = scheduler:scheduleScriptFunc(function (elapsed_time)
                self:Update(elapsed_time)
            end, LOADING_TIME / 100, false)
        elseif event == "exit" then
            scheduler:unscheduleScriptEntry(schedule_id)
        end
    end)


    self:RegisterWidgetEvent()
    self:RegisterEvent()
end

-- 设置随机文字
function meta:SetRandomDesc(text)
    ui_helper:SetText(self.random_desc_txt, text)
end

function meta:SetPercent(percent)
    if not self.is_loading_start then
        self.is_loading_start = true
        self.cur_percent = 0
        self.next_percent = 0
        self.loading_bar:setPercent(0)
    end
    self.next_percent = percent
end


function meta:Update(elapsed_time)
    if not self.is_loading_start then
        return
    end

    if self.cur_percent < self.next_percent then
        self.cur_percent = self.cur_percent + 1
        self.loading_bar:setPercent(self.cur_percent)
    end

    if self.cur_percent >= 100 then
        self.is_loading_start = false
        graphic:DispatchEvent("switch_login_stage", STAGE.complete)
    end
end

function meta:RegisterEvent()

end

function meta:RegisterWidgetEvent()

end


return meta
