local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"


local constants = require "common.constants"
local data_template = require "manager.data_template"

local MAIL_STAGE = constants["MAIL_STAGE"]
local MAIL_TYPE = constants["MAIL_TYPE"]

local meta = class("mail_template",function (node)
    return node
end)

function meta:ctor()
    -- 邮件-ICON
    self.icon_img = self:getChildByName("icon")
    -- 邮件-标题
    self.title_txt = self:getChildByName("name")
    -- 邮件-内容
    self.desc_txt = self:getChildByName("desc")
    -- 邮件-时间
    self.time_txt = self:getChildByName("time")
    -- 已读标签
    self.read_icon_node = self:getChildByName("read_icon")
end

-- 设置邮件信息
function meta:SetMailInfo(info)
    self.info = info
    ui_helper:SetText(self.title_txt, info.title)
    ui_helper:SetText(self.desc_txt, info.desc)

    -- 设置查看状态
    self:SetStage(info.stage)

    -- 邮件事件
    ui_helper:SetText(self.time_txt, timer:GetDateFormat(info.time))
end

function meta:SetStage(stage)
    self.read_icon_node:setVisible(stage == MAIL_STAGE["read"])
    local mail_type = self.info.type

    self:setCascadeColorEnabled(true)
    if stage == MAIL_STAGE["read"] then
        self:setColor(ui_helper:GetColor3B(0x7f7f7f))
    else
        self:setColor(ui_helper:GetColor3B(0xffffff))
    end

    self.icon_img:loadTexture(resource:GetMailIcon(mail_type, stage))
end

function meta:AddClick(func)
    ui_helper:AddClick(self, func)
end

return meta
