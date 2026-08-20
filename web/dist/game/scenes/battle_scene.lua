local ui_helper = require "manager.ui_helper"
local battle_logic = require "logic.battle"
local action_manager = require "manager.action_manager"
local text_loader = require "manager.text_loader"


-- UI层
local WORLD_PANEL_ZORDER = 1000
local WORLD_WARING_ZORDER = 9999

local meta = class("battle_scene",function ()
    return cc.Scene:create()
end)

function meta:ctor()

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
    self.waring = false
    self.is_standby = false
    self.standby_cache = {}
    self:InitScene()


    self.allow_show_setting = true

    self:RegisterEvent()
end

function meta:Update(elapsed_time)
    if self.is_standby == false then
        if #self.standby_cache == 0 then
            self.is_standby = true
        else
            local func = self.standby_cache[1]
            table.remove(self.standby_cache,1)
            func()
        end
    else
        self.backgroup_panel:Update(elapsed_time)
        battle_logic:Update(elapsed_time)
        self.character_panel:Update(elapsed_time)
        self.match_panel:Update(elapsed_time)
        self.battle_result_panel:Update(elapsed_time)
    end
end
function meta:InitScene()
    self.standby_cache = {}

    -- --网络信号不佳提示
    self.waring_panel = require("modules.waring.waring_panel").new()
    self.waring_panel:setVisible(false)
    self:addChild(self.waring_panel,WORLD_WARING_ZORDER)

    -- 战场背景层
    table.insert(self.standby_cache, function ()
        self.backgroup_panel = require("modules.battle.backgroup_panel").new()
        self.backgroup_panel:setVisible(false)
        self:addChild(self.backgroup_panel, 1)
    end)

    -- UI层
    table.insert(self.standby_cache, function ()
        self.battle_ui_panel = require("modules.battle.battle_ui_panel").new()
        self.battle_ui_panel:setVisible(false)
        self:addChild(self.battle_ui_panel, 3)
    end)

    -- 战场角色层
    table.insert(self.standby_cache, function ()
        self.character_panel = require("modules.battle.character_panel").new()
        self.character_panel:setVisible(false)
        self.battle_ui_panel:SetCharacterLayer(self.character_panel)
    end)


    -- 匹配层
    table.insert(self.standby_cache, function ()
        self.match_panel = require("modules.battle.match_panel").new()
        self.match_panel:setVisible(false)
        self:addChild(self.match_panel, 4)
    end)

    -- 战斗结果
    table.insert(self.standby_cache, function ()
        self.battle_result_panel = require("modules.battle.battle_result_panel").new()
        self.battle_result_panel:setVisible(false)
        self:addChild(self.battle_result_panel, 5)
    end)

    -- 准备继续
    table.insert(self.standby_cache, function ()
        self.backgroup_panel:setVisible(true)
        self.match_panel:Show()
    end)

end

function meta:GetSubPanel(name)
    local sub_panel = self.sub_panel_cache[name]
    if not sub_panel then
        sub_panel = require("modules.battle."..name).new()
        sub_panel.__name = name
        sub_panel:setVisible(false)
        self:addChild(sub_panel)
        self.sub_panel_cache[name] = sub_panel
    end
    return sub_panel
end

function meta:RegisterEvent()

    -- -- 显示卡牌明细
    -- battle_logic:RegisterEvent("show_card_detail",function (...)
    --     self.card_detail_panel:Show(...)
    -- end)

    -- -- 隐藏卡牌明细
    -- battle_logic:RegisterEvent("hide_card_detail",function ()
    --     self.card_detail_panel:Hide()
    -- end)

    -- 显示战场关闭了
    battle_logic:RegisterEvent("show_battle_null",function ()
        if self.is_show_exit_view then
            return
        end

        self.is_show_exit_view = true
        local title = text_loader:GetText("battle_exit_title")
        local desc = text_loader:GetText("battle_exit_desc")
        local confirm_txt = text_loader:GetText("battle_exit_confirm")

        local confirm_box = require("modules.common.confirm_box").new()
        confirm_box:ShowNofity(title, desc, confirm_txt,
            function ()
                confirm_box:Hide(function ()
                    self.is_show_exit_view = false
                    self:removeChild(confirm_box)
                    battle_logic:ExitBattle()
                end)
            end
        )
        self:addChild(confirm_box, 9999)
    end)

    -- 显示界面
    battle_logic:RegisterEvent("push_battle_panel", function (panel_name, ...)
        local sub_panel = self:GetSubPanel(panel_name)
        local index = 0
        -- 1.查找是否已经在显示
        for i = 1, self.sub_panel_stack_index do
            local panel = self.sub_panel_stack[i]
            if sub_panel:GetName() == panel:GetName() then
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
        sub_panel:Show(...)
    end)

    -- 隐藏界面
    battle_logic:RegisterEvent("pop_battle_panel", function (close_name)
        local sub_panel = self.sub_panel_stack[self.sub_panel_stack_index]
        if close_name and sub_panel:GetName() ~= close_name then
            -- 1.查找是在第几层
            for i = 1, self.sub_panel_stack_index do
                local panel = self.sub_panel_stack[i]
                if panel:GetName() == close_name then
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
            -- 关闭最高层界面
        self.sub_panel_stack_index = self.sub_panel_stack_index - 1
        sub_panel:Hide()
        if self.sub_panel_stack_index == 0 then
            self.mask_node:setVisible(false)
        else
            local panel_zorder = WORLD_PANEL_ZORDER + self.sub_panel_stack_index * 2
            local mask_zorder = panel_zorder - 1
            self.mask_node:setLocalZOrder(mask_zorder)
        end
    end)

    -- 屏幕震动
    battle_logic:RegisterEvent("effect_screen_shake", function (shake_time, shake_margin)
        action_manager:CreateShake("screen_shake", self, shake_time, shake_margin)
    end)



    --监听手机返回键
    local key_listener = cc.EventListenerKeyboard:create()
    key_listener:registerScriptHandler(function(key, event)
        if key ~= cc.KeyCode.KEY_ESCAPE then
            return
        end
        if self.allow_show_setting then
            self.allow_show_setting = false
            battle_logic:DispatchEvent("push_battle_panel","battle_setting_panel", function ()
                self.allow_show_setting = true
            end)
        end
    end, cc.Handler.EVENT_KEYBOARD_RELEASED)

    local event_dispatcher = self:getEventDispatcher()
    event_dispatcher:addEventListenerWithSceneGraphPriority(key_listener, self)
end


function meta:OnExit()
end


return meta
