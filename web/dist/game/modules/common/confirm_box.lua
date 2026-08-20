local ui_helper = require "manager.ui_helper"
local text_loader = require "manager.text_loader"

local meta = class("confirm_box",function (node)
    if node then
        return node
    end
    return ui_helper:LoadCocosUI("interface/common/msgbox_simple.csb")
end)


function meta:ctor()
    local msgbox_node = self:getChildByName("msgbox")
    local size = msgbox_node:getContentSize()
    self.center_x = size.width / 2

    local titlebg_node = msgbox_node:getChildByName("titlebg")
    self.title_txt = titlebg_node:getChildByName("title")

    self.desc_txt = msgbox_node:getChildByName("desc")

    self.close_btn = msgbox_node:getChildByName("close_btn")
    -- 确定
    self.confirm_btn = msgbox_node:getChildByName("confirm_btn")
    self.confirm_btn:setVisible(false)
    self.confirm_desc_txt = self.confirm_btn:getChildByName("desc")
    -- 取消
    self.cancel_btn = msgbox_node:getChildByName("cancel_btn")
    self.cancel_btn:setVisible(false)
    self.cancel_desc_txt = self.cancel_btn:getChildByName("desc")
    -- 通知
    self.nofity_btn = msgbox_node:getChildByName("nofity_btn")
    self.nofity_btn:setVisible(false)
    self.nofity_desc_txt = self.nofity_btn:getChildByName("desc")
    self:setVisible(false)
    ui_helper:BindTimeLine(self, "interface/common/msgbox_simple.csb")
end

function meta:Show(is_nofiy, title, desc, confirm_txt, cancel_txt, confirm_func, cancel_func)
    if is_nofiy then
        self:ShowNofity(title, desc, confirm_txt, confirm_func)
    else
        self:ShowConfirm(title, desc, confirm_txt, cancel_txt, confirm_func, cancel_func)
    end
end

function meta:ShowConfirm(title, desc, confirm_txt, cancel_txt, confirm_func, cancel_func)
    self:setVisible(true)
    self.confirm_btn:setVisible(true)
    self.cancel_btn:setVisible(true)
    self.nofity_btn:setVisible(false)

    ui_helper:SetText(self.title_txt, title)
    ui_helper:SetText(self.desc_txt, desc)
    ui_helper:SetText(self.confirm_desc_txt, confirm_txt)
    ui_helper:SetText(self.cancel_desc_txt, cancel_txt)

    self.confirm_btn:setVisible(true)
    self.confirm_btn:setTouchEnabled(true)
    ui_helper:AddClick(self.confirm_btn, confirm_func)

    self.cancel_btn:setVisible(true)
    self.cancel_btn:setTouchEnabled(true)
    ui_helper:AddClick(self.cancel_btn, cancel_func)
    ui_helper:AddClick(self.close_btn, cancel_func)

    self:PlayAnimation("enter_msgbox")
end

-- 显示通知栏
function meta:ShowNofity(title, desc, confirm_txt, confirm_func)
    self:setVisible(true)
    self.confirm_btn:setVisible(false)
    self.cancel_btn:setVisible(false)
    self.nofity_btn:setVisible(true)

    ui_helper:SetText(self.title_txt, title)
    ui_helper:SetText(self.desc_txt, desc)
    ui_helper:SetText(self.nofity_desc_txt, confirm_txt)

    self.nofity_btn:setTouchEnabled(true)
    ui_helper:AddClick(self.nofity_btn, confirm_func)
    ui_helper:AddClick(self.close_btn, confirm_func)

    self.cancel_btn:setVisible(false)

    self:PlayAnimation("enter_msgbox")
end

function meta:Hide(func)
    self:PlayAnimation("exit_msgbox", false, function ()

        self:setVisible(false)
        if func then
            func()
        end
    end)

end


return meta
