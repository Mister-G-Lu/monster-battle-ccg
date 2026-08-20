local resource = require "manager.resource"
local text_loader = require "manager.text_loader"
local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local timer = require "manager.time"
local defines = require "manager.defines"

local mail_logic = require "logic.mail"

local constants = require "common.constants"
local MAIL_MAX_NUM = constants.MAIL_MAX_NUM
local MAIL_STAGE = constants["MAIL_STAGE"]
local MAIL_TYPE = constants["MAIL_TYPE"]

local data_template = require "manager.data_template"

local meta = class("mail_inbox_panel",function (node)
    return ui_helper:LoadCocosUI("interface/mail/mailbox_panel.csb")
end)

local MAX_ROW = 6
local SUB_PANEL_HEIGHT = 120

function meta:ctor()
    local inbox_node = self:getChildByName("node")

    -- 退出
    self.close_btn = inbox_node:getChildByName("close_btn")

    -- 邮件模板
    local mail_template = inbox_node:getChildByName("mail_template")
    mail_template:setVisible(false)
    mail_template:clone()

    self.mail_number_node = inbox_node:getChildByName("num")

    -- 收件箱列表
    self.mail_list = ui_helper:ExpandUI(inbox_node, "mail_listview", "widget/refine_list_view")
    self.mail_list:Init(MAX_ROW, SUB_PANEL_HEIGHT, function ()
        local new_mail = require("modules.mail.mail_template").new(mail_template:clone())
        new_mail:setVisible(true)
        return new_mail
    end)

    -- 邮件明细
    self.mail_detailbg = ui_helper:ExpandUI(inbox_node, "mail_detailbg", "modules/mail/detail_panel")
    self.mail_detailbg:setVisible(false)


    -- 标题Spine动画
    self.title_spine = inbox_node:getChildByName("title_spine")
    local size = self.title_spine:getContentSize()
    local skeleton_node = sp.SkeletonAnimation:create("animation/msgbox_title_mailbox.json", "animation/msgbox_title_mailbox.atlas", 1)
    skeleton_node:setAnimation(0, "animation", true)
    skeleton_node:setPosition({ x = size.width / 2, y = 0})
    self.title_spine:addChild(skeleton_node)

    self:setVisible(false)

    self:RegisterEvent()
    self:RegisterWidgetEvent()
end


function meta:Show()
    self:setVisible(true)

    local mail_list = mail_logic:GetMailList()
    local mail_number = #mail_list
    local mail_number_text = mail_number .. "/" .. MAIL_MAX_NUM

    ui_helper:SetText(self.mail_number_node, mail_number_text)

    self.mail_list:Show( #mail_list, function (cur_row, item_node)
        local mail_info = mail_list[cur_row]
        item_node:SetMailInfo(mail_info)
        item_node:AddClick(function ()
            mail_info = mail_list[cur_row]
            self.mail_detailbg:Show(mail_info, function ()
                local mail_info = mail_list[cur_row]
                item_node:SetMailInfo(mail_info)
            end)

            if mail_logic:LookMail(mail_info) then
                item_node:SetStage(MAIL_STAGE["read"])
            end
        end)
    end)
end


function meta:Hide()
    self:setVisible(false)
end

function meta:RegisterEvent()
end

function meta:RegisterWidgetEvent()
    ui_helper:AddClick(self.close_btn, function ()
        graphic:DispatchEvent("pop_world_panel")
    end)
end


return meta
