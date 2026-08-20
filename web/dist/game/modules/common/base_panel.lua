local graphic = require "manager.graphic"
local ui_helper = require "manager.ui_helper"

local meta = class("base_panel",function (csb_path)
    return ui_helper:LoadCocosUI(csb_path)
end)

function meta:ctor()
    self.initd = false
    self.event_handler_list = {}
    self:registerScriptHandler(function(event)
        if event == "enter" then
            self:OnSupperEnter()
        elseif event == "exit" then
            self:OnSuperExit()
        end
    end)
end

function meta:OnSupperEnter()
    if self.initd then
        return
    end
    if self["OnEnter"] then
        self:OnEnter()
    end
    self.initd = true
end

function meta:OnSuperExit()
    if self["OnExit"] then
        self:OnExit()
    end
    -- self:UnregisterEvent()
end

-- 反注册渲染事件
function meta:UnregisterEvent()
    for event_name, hander_id in pairs(self.event_handler_list) do
        graphic:UnregisterEvent(event_name, hander_id)
    end
end

-- 注册渲染事件
function meta:RegisterGraphic(event_name, handler)
    local new_handler_id = graphic:RegisterEvent(event_name, handler)
    self.event_handler_list[event_name] = new_handler_id
end

function meta:DispatchGraphicEvent(event_name, ...)
     graphic:DispatchEvent(event_name, ...)
end

return meta
