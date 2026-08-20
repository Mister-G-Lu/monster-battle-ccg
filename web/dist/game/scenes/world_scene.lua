local ui_helper = require "manager.ui_helper"
local graphic = require "manager.graphic"
local action_manager = require "manager.action_manager"
local text_loader = require "manager.text_loader"

local user_logic = require "logic.user"

local meta = class("world_scene",function ()
    return cc.Scene:create()
end)

local WORLD_SUB_ZORDER = 900
local WORLD_MAIN_ZORDER = 950

local WORLD_PANEL_ZORDER = 1000
local WORLD_REWARD_ZORDER = 2500
local WORLD_TOP_ZORDER = 3000
local WORLD_WARING_ZORDER = 9999


local SYSTEM_STATE = {
    home = 1,
    deck = 2,
}

function meta:ctor()

    self.last_panel_name = ""
    self.system_module_map = {}
    self.waring = false
    -- 主UI层
    local ui_root = require("modules.world.world_panel").new()
    self:addChild(ui_root, WORLD_MAIN_ZORDER)
    self.world_panel = ui_root

    -- 奖励Tips层
    local reward_node = require("modules.common.reward_tips").new()
    self:addChild(reward_node, WORLD_REWARD_ZORDER)

    self.reward_tips_panel = reward_node
    -- 通用邀请界面

    --网络信号不佳提示
    self.waring_panel = require("modules.waring.waring_panel").new()
    self.waring_panel:setVisible(false)
    self:addChild(self.waring_panel,WORLD_WARING_ZORDER)

    -- 加入遮罩层
    self.mask_node = ccui.Layout:create()
    self.mask_node:setContentSize(display.sizeInPixels.width, display.sizeInPixels.height)
    self.mask_node:setBackGroundColor(ui_helper:GetColor4B(0x303030))
    self.mask_node:setBackGroundColorOpacity(255 * 0.9)
    self.mask_node:setBackGroundColorType(1)
    self.mask_node:setTouchEnabled(true)
    self.mask_node:setVisible(false)
    self:addChild(self.mask_node, WORLD_PANEL_ZORDER)

    self.sub_panel_cache = {}
    self.sub_panel_stack = {}
    self.sub_panel_stack_index = 0
    self.is_show_exit_view = false

    self:RegisterEvent()
    self:RegisterWidgetEvent()

    graphic:DispatchEvent("switch_system_module", "home", true)
end
-- 获取子界面
function meta:GetSubPanel(module, name)
    local key = module.."."..name
    local sub_panel = self.sub_panel_cache[key]
    if not sub_panel then
        sub_panel = require("modules."..key).new()
        sub_panel.__name = key
        sub_panel:setVisible(false)
        sub_panel:setName(key)
        if sub_panel["OnSupperInit"] then
            sub_panel:OnSupperInit()
        end

        self:addChild(sub_panel)
        self.sub_panel_cache[key] = sub_panel
    end
    return sub_panel
end

function meta:Update(elapsed_time)

    self.world_panel:Update(elapsed_time)
    user_logic:Update(elapsed_time)

    for k,v in pairs(self.system_module_map) do
        if v and v:isVisible() then
            v:Update(elapsed_time)
        end
    end

    for k,v in pairs(self.sub_panel_cache) do
        if v and v:isVisible() and v["Update"] then
            v:Update(elapsed_time)
        end
    end
end

function meta:RegisterEvent()

    graphic:RegisterEvent("friend_match_success",function (callback)
        graphic:DispatchEvent("pop_world_panel", "common", "confirm_box",callback)
    end)

    graphic:RegisterEvent("switch_system_module",function (func_name)
        if self.last_panel_name == func_name then
            return
        end
        local system_panel = self.system_module_map[func_name]
        if not system_panel then
            system_panel = require("modules.world.system."..func_name.."_panel").new()
            self.system_module_map[func_name] = system_panel
            self:addChild(system_panel, WORLD_SUB_ZORDER)
        end

        local last_panel = self.system_module_map[self.last_panel_name]
        if last_panel then
            last_panel:Hide()
            system_panel:Show()
        else
            system_panel:Show()
        end
        self.last_panel_name = func_name

        if func_name == "home" then
            self.world_panel:setLocalZOrder(WORLD_MAIN_ZORDER)
        else
            self.world_panel:setLocalZOrder(WORLD_TOP_ZORDER)
        end
    end)

    -- 显示界面
    graphic:RegisterEvent("push_world_panel", function (panel_module, panel_name, ...)

        local sub_panel = self:GetSubPanel(panel_module, panel_name)

        local index = 0
        -- 1.查找是否已经在显示
        for i = 1, self.sub_panel_stack_index do
            local panel = self.sub_panel_stack[i]
            if sub_panel.__name == panel.__name then
                index = i
                break
            end
        end

        if index ~= 0 then
            table.remove(self.sub_panel_stack, index)
            self.sub_panel_stack_index = self.sub_panel_stack_index - 1

            for i = index, self.sub_panel_stack_index do
                local sub_panel = self.sub_panel_stack[i]
                sub_panel:setLocalZOrder(WORLD_PANEL_ZORDER + i * 2)
            end
        end
        -- 加入页面栈

        local top_panel = self.sub_panel_stack[self.sub_panel_stack_index]

        if top_panel ~= sub_panel then
            self.sub_panel_stack_index = self.sub_panel_stack_index + 1
            self.sub_panel_stack[self.sub_panel_stack_index] = sub_panel

            -- 显示层优先级
            local panel_zorder = WORLD_PANEL_ZORDER + self.sub_panel_stack_index * 2
            -- 遮罩层优先级 = 显示层优先级-1
            local mask_zorder = panel_zorder - 1
            self.mask_node:setVisible(true)
            self.mask_node:setLocalZOrder(mask_zorder)
            ui_helper:AddClick(self.mask_node, function ()
                if sub_panel["DoExit"] then
                    sub_panel:DoExit()
                end
            end)
            -- 显示层
            sub_panel:setLocalZOrder(panel_zorder)
        end

            sub_panel:Show(...)
    end)

    -- 隐藏界面
    graphic:RegisterEvent("pop_world_panel", function (panel_module, panel_name,...)
        panel_module = panel_module or ""
        panel_name = panel_name or ""
        local close_name = panel_module.."."..panel_name
        local sub_panel = self.sub_panel_stack[self.sub_panel_stack_index]
        if close_name and sub_panel.__name ~= close_name then
            -- 1.查找是在第几层
            local index = 0
            for i = 1, self.sub_panel_stack_index do
                local panel = self.sub_panel_stack[i]
                if panel.__name == close_name then
                    index = i
                    break
                end
            end
            -- 2.删除第几层,重新设置高层的渲染优先级
            if index ~= 0 then
                sub_panel = self.sub_panel_stack[index]
                table.remove(self.sub_panel_stack, index)
                for i = index, self.sub_panel_stack_index - 1 do
                    local cur_panel = self.sub_panel_stack[i]
                    cur_panel:setLocalZOrder(WORLD_PANEL_ZORDER + i * 2)
                end
            end
        end
        -- local key = sub_panel.__name
        -- self.sub_panel_cache[key] = nil
        -- 关闭最高层界面
        self.sub_panel_stack_index = self.sub_panel_stack_index - 1
        sub_panel:Hide(...)
        -- self:removeChild(sub_panel)

        if self.sub_panel_stack_index == 0 then
            self.mask_node:setVisible(false)
        else
            local panel_zorder = WORLD_PANEL_ZORDER + self.sub_panel_stack_index * 2
            local mask_zorder = panel_zorder - 1
            self.mask_node:setLocalZOrder(mask_zorder)
        end
    end)

    -- 二次确认界面（2个按钮）
    graphic:RegisterEvent("show_confirm_box", function (title, desc, confirm_txt, cancel_txt, confirm_func, cancel_func)
        graphic:DispatchEvent("push_world_panel", "common", "confirm_box", false, title, desc, confirm_txt, cancel_txt, confirm_func, cancel_func)
    end)

    -- 通知界面（1个按钮）
    graphic:RegisterEvent("show_nofity_box", function (title, desc, confirm_txt, confirm_func)
        graphic:DispatchEvent("push_world_panel", "common", "confirm_box", true, title, desc, confirm_txt, nil, confirm_func, nil)
    end)

    -- 通用道具飞行动画
    graphic:RegisterEvent("show_reward_animation", function (reward_list, func)
        local reward_node = require("modules.common.item_reward_animation").new()
        self:addChild(reward_node, WORLD_TOP_ZORDER)
        reward_node:Show(reward_list, func)
    end)

    graphic:RegisterEvent("show_reward_tips", function (reward_info, pos)
        if not reward_info then return end
        self.reward_tips_panel:Show(reward_info, pos)
    end)

    graphic:RegisterEvent("hide_reward_tips", function ()
        self.reward_tips_panel:Hide()
    end)

    -- 特效屏幕震动
    graphic:RegisterEvent("effect_screen_shake", function (shake_time, shake_margin)
        action_manager:CreateShake("screen_shake", self, shake_time, shake_margin)
    end)
end

function meta:RegisterWidgetEvent()
    --监听手机返回键
    local key_listener = cc.EventListenerKeyboard:create()
    key_listener:registerScriptHandler(function(key, event)
        if key ~= cc.KeyCode.KEY_ESCAPE then
            return
        end

        local arena_logic = require "logic.arena"
        if arena_logic.cur_stage == arena_logic.STAGE.match then
            return
        end

        if self.is_show_exit_view then
            return
        end

        self.is_show_exit_view = true
        local title = text_loader:GetText("game_exit_title")
        local desc = text_loader:GetText("game_exit_desc")
        local confirm_txt = text_loader:GetText("game_exit_confirm")
        local cancel_txt = text_loader:GetText("game_exit_cancel")

        graphic:DispatchEvent("show_confirm_box", title, desc, confirm_txt, cancel_txt,
        function ()
            -- 确认
            cc.Director:getInstance():endToLua()
        end,
        function ()
            -- 退出
            self.is_show_exit_view = false
            graphic:DispatchEvent("pop_world_panel", "common", "confirm_box")
        end)


    end, cc.Handler.EVENT_KEYBOARD_RELEASED)

    local event_dispatcher = self:getEventDispatcher()
    event_dispatcher:addEventListenerWithSceneGraphPriority(key_listener, self)
end



return meta
