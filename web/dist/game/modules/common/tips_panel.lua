local resouce = require "manager.resource"
local text_loader = require "manager.text_loader"
local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"


local meta = class("TipsPanel",function ()
    return cc.Layer:create()
end)

function meta:ctor()

    self.cur_idx = 1
    self.tips_stack = {}
    self.cache_msg = {}
    self.is_visible = false




    self:registerScriptHandler(function(event)
        if event == "enter" then
            self.is_visible = true
            for i = 1, 5 do
                self.tips_stack[i] = ui_helper:LoadCocosUI("interface/common/error_tip.csb")
                self.tips_stack[i]:setVisible(false)
                local node = self.tips_stack[i]:getChildByName("node")
                self.tips_stack[i].desc_txt = node:getChildByName("desc")
                self:addChild(self.tips_stack[i])
            end
            self:RegisterEvent()
        elseif event == "exit" then
            self.is_visible = false
            for i = 1, 5 do
                self:removeChild(self.tips_stack[i])
            end
            if self.handler_id ~= nil then
                graphic:UnregisterEvent("show_message", self.handler_id)
            end
        end
    end)
end

function meta:ShowTips(msg,...)
    if self.cache_msg[msg] then
        return
    end
    print("msg = "..tostring(msg))

    self.cache_msg[msg] = 1
    local tips_node = self.tips_stack[self.cur_idx]
    tips_node:setVisible(true)
    tips_node:PlayAnimation("enter",false, function ()
        tips_node:setVisible(false)
    end)
    ui_helper:SetTextByKey(tips_node.desc_txt, msg, ...)
    self.cur_idx = self.cur_idx + 1
    if self.cur_idx > #self.tips_stack then
        self.cur_idx = 1
    end
end

function meta:Update(elapsed_time)
    for k,v in pairs(self.cache_msg) do
        v = v - elapsed_time
        if v <= 0 then
            self.cache_msg[k] = nil
        else
            self.cache_msg[k] = v
        end
    end

end

function meta:RegisterEvent()

    -- 显示消息
    self.handler_id = graphic:RegisterEvent("show_message",function (msg, ...)
        self:ShowTips(msg, ...)
    end)
    -- print("RegisterEvent >> self.handler_id = "..self.handler_id)
end


return meta
