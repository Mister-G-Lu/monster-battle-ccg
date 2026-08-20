-- campaign_panel.lua
-- Programmatic campaign map for "The Shadow Road" (the handcrafted campaign
-- ported from build/web/game.html). Lives as a full-screen layer child of the
-- home panel (same pattern as arena_panel) and drives the native battle engine
-- via req_campaign_battle_start.
--
-- Because this build has no Cocos Studio .csb for the campaign, the map is
-- drawn with plain Cocos nodes (LayerColor + system-font labels + one-by-one
-- touch listeners), the same approach main.lua uses for its splash screen.

local graphic = require "manager.graphic"
local network = require "manager.network"
local campaign_data = require "manager.campaign_data"
local ui_helper = require "manager.ui_helper"

local meta = class("campaign_panel", function ()
    return cc.Layer:create()
end)

local TYPE_LABEL = { skirmish = "Skirmish", elite = "Elite", boss = "Boss" }
local ROW_H = 30
local HEADER_H = 26

local function win_size()
    local ok, size = pcall(function ()
        return cc.Director:getInstance():getWinSize()
    end)
    if ok and size then return size end
    return { width = 1280, height = 720 }
end

function meta:ctor()
    local size = win_size()
    self.win_size = size

    -- full-screen dim background (also swallows stray touches)
    local bg = cc.LayerColor:create(cc.Color(18, 18, 31, 255))
    bg:setContentSize(size)
    bg:setPosition(cc.p(0, 0))
    self:addChild(bg, -10)
    self.bg = bg
    self:_SwallowTouches(bg)

    -- title
    self.title = cc.Label:createWithSystemFont("The Shadow Road", "Arial", 34)
    self.title:setAnchorPoint(cc.p(0.5, 0.5))
    self.title:setPosition(cc.p(size.width / 2, size.height - 40))
    self.title:setColor(ui_helper:GetColor3B(0xe94560))
    self:addChild(self.title, 5)

    -- stats line
    self.stats = cc.Label:createWithSystemFont("", "Arial", 20)
    self.stats:setAnchorPoint(cc.p(0.5, 0.5))
    self.stats:setPosition(cc.p(size.width / 2, size.height - 72))
    self.stats:setColor(ui_helper:GetColor3B(0x8b8ba7))
    self:addChild(self.stats, 5)

    -- info bar (shows the current node's description + power)
    self.info = cc.Label:createWithSystemFont("", "Arial", 17)
    self.info:setAnchorPoint(cc.p(0.5, 0.5))
    self.info:setPosition(cc.p(size.width / 2, 40))
    self.info:setColor(ui_helper:GetColor3B(0xbbbbbb))
    self:addChild(self.info, 5)

    -- back button
    self.back_btn = self:_MakeButton("Back", size.width - 70, size.height - 40, function ()
        self:Hide()
    end)
    -- reset button
    self.reset_btn = self:_MakeButton("Reset", size.width - 140, size.height - 40, function ()
        network:Send("req_campaign_reset", {}, function (result, recv)
            if result == "success" then self:Refresh() end
        end)
    end)

    -- scrollable node list
    self.scroll = ccui.ScrollView:create()
    self.scroll:setContentSize(cc.size(size.width - 40, size.height - 160))
    self.scroll:setPosition(cc.p(20, 60))
    self.scroll:setDirection(ccui.ScrollViewDir.vertical)
    self.scroll:setTouchEnabled(true)
    self.scroll:setBounceEnabled(true)
    self:addChild(self.scroll, 5)

    self.cleared = {}
    self.info_map = {}

    graphic:RegisterEvent("refresh_campaign", function ()
        self:Refresh()
    end)
end

-- register a swallow-touches listener on a plain node (framework Layer:onTouch)
function meta:_SwallowTouches(node)
    pcall(function ()
        node:onTouch(function () return true end, false, true)
    end)
end

function meta:_MakeButton(text, x, y, callback)
    local label = cc.Label:createWithSystemFont(text, "Arial", 22)
    label:setAnchorPoint(cc.p(0.5, 0.5))
    label:setPosition(cc.p(x, y))
    label:setColor(ui_helper:GetColor3B(0xdddddd))
    self:addChild(label, 6)
    local listener = cc.EventListenerTouchOneByOne:create()
    listener:registerScriptHandler(function (touch)
        return cc.rectContainsPoint(label:getBoundingBox(), touch:getLocation())
    end, cc.Handler.EVENT_TOUCH_BEGAN)
    listener:registerScriptHandler(function ()
        callback()
    end, cc.Handler.EVENT_TOUCH_ENDED)
    label:getEventDispatcher():addEventListenerWithSceneGraphPriority(listener, label)
    return label
end

function meta:Show()
    self:setVisible(true)
    self:Refresh()
end

function meta:Hide()
    self:setVisible(false)
end

function meta:Refresh()
    network:Send("query_campaign_info", {}, function (result, recv)
        if result ~= "success" then return end
        self.cleared = (recv and recv.cleared) or {}
        self.info_map = recv or {}
        self:Render()
    end)
end

-- first node not yet cleared
function meta:CurrentNodeId()
    for _, node in ipairs(campaign_data:GetNodes()) do
        if not self.cleared[node.id] then return node.id end
    end
    return nil
end

function meta:IsUnlocked(node)
    local nodes = campaign_data:GetNodes()
    for i, n in ipairs(nodes) do
        if n.id == node.id then
            if i == 1 then return true end
            return self.cleared[nodes[i - 1].id] == true
        end
    end
    return true
end

function meta:Render()
    local size = self.win_size
    self.stats:setString(string.format(
        "HP %d   Bosses %d/4   Deck %d   %dW-%dL",
        tonumber(self.info_map.player_max_hp) or 30,
        tonumber(self.info_map.bosses_slain) or 0,
        #(self.info_map.collection or {}),
        tonumber(self.info_map.wins) or 0,
        tonumber(self.info_map.losses) or 0))

    if self.info_map.complete then
        self.title:setString("The Shadow Road - Complete")
    else
        self.title:setString("The Shadow Road")
    end

    -- rebuild scroll content (clear the inner container, NOT the scrollview
    -- itself — ScrollView:addChild routes to the inner container, and calling
    -- removeAllChildren on the scrollview would drop the container too)
    pcall(function ()
        self.scroll:getInnerContainer():removeAllChildren()
    end)
    local cur = self:CurrentNodeId()
    local total_h = 0
    local y = 0

    for _, region in ipairs(campaign_data.REGIONS) do
        total_h = total_h + HEADER_H + (#region.nodes * ROW_H) + 8
    end
    self.scroll:setInnerContainerSize(cc.size(size.width - 40, math.max(total_h, size.height - 160)))

    local inner_h = math.max(total_h, size.height - 160)
    y = inner_h

    for _, region in ipairs(campaign_data.REGIONS) do
        local header = cc.Label:createWithSystemFont(region.name .. "  -  " .. region.sub, "Arial", 20)
        header:setAnchorPoint(cc.p(0, 1))
        header:setPosition(cc.p(0, y))
        header:setColor(ui_helper:GetColor3B(0x53d769))
        self.scroll:addChild(header)
        y = y - HEADER_H

        for _, node in ipairs(region.nodes) do
            self:_AddNodeRow(node, y)
            y = y - ROW_H
        end
        y = y - 8
    end

    -- current-node info bar
    local cur_node = campaign_data:GetNode(cur)
    if cur_node then
        local txt = cur_node.name .. ": " .. cur_node.desc
        if cur_node.power then
            txt = txt .. "  [Power: " .. cur_node.power.name .. "]"
        end
        self.info:setString(txt)
    end

    pcall(function () self.scroll:scrollToTop(0, true) end)
end

function meta:_AddNodeRow(node, y)
    local cleared = self.cleared[node.id] == true
    local locked = not cleared and not self:IsUnlocked(node)
    local current = (not cleared) and (node.id == self:CurrentNodeId()) and not locked

    local type_label = TYPE_LABEL[node.type] or node.type
    local prefix = cleared and "[x] " or (locked and "[lock] " or (current and ">> " or "    "))
    local power = node.power and ("  ~" .. node.power.name) or ""
    local text = string.format("%s%s %s - %s (HP %d)%s",
        prefix, type_label, node.name, node.enemy_name, tonumber(node.hp) or 0, power)

    local label = cc.Label:createWithSystemFont(text, "Arial", 19)
    label:setAnchorPoint(cc.p(0, 1))
    label:setPosition(cc.p(6, y))
    if cleared then
        label:setColor(ui_helper:GetColor3B(0x53d769))
    elseif current then
        label:setColor(ui_helper:GetColor3B(0xf39c12))
    elseif locked then
        label:setColor(ui_helper:GetColor3B(0x666666))
    elseif node.type == "boss" then
        label:setColor(ui_helper:GetColor3B(0xff8fa3))
    else
        label:setColor(ui_helper:GetColor3B(0xeeeeee))
    end
    self.scroll:addChild(label)

    -- tap to fight
    local listener = cc.EventListenerTouchOneByOne:create()
    listener:registerScriptHandler(function (touch)
        return cc.rectContainsPoint(label:getBoundingBox(), touch:getLocation())
    end, cc.Handler.EVENT_TOUCH_BEGAN)
    listener:registerScriptHandler(function ()
        self:_OnNodeTap(node)
    end, cc.Handler.EVENT_TOUCH_ENDED)
    label:getEventDispatcher():addEventListenerWithSceneGraphPriority(listener, label)
end

function meta:_OnNodeTap(node)
    if self.cleared[node.id] then
        -- replays are allowed, like the web prototype
    elseif not self:IsUnlocked(node) then
        graphic:DispatchEvent("show_message", "campaign_node_locked")
        return
    end
    network:Send("req_campaign_battle_start", { node_id = node.id }, function (result, recv)
        if result ~= "success" then
            graphic:DispatchEvent("show_message", result or "campaign_start_failed")
        end
        -- on success the battle scene is pushed automatically by cmd_battle_start
    end)
end

function meta:Update(elapsed_time)
    -- no per-frame work needed
end

return meta
