-- campaign_panel.lua
-- Programmatic campaign map for "The Shadow Road" (the handcrafted campaign
-- defined in content/campaign_data.json). Lives as a full-screen layer child
-- of the home panel (same pattern as arena_panel) and drives the native
-- battle engine via req_campaign_battle_start — the campaign is served by
-- the app's own offline service (campaign_service.lua), not by a web app.
--
-- Because this build has no Cocos Studio .csb for the campaign, the map is
-- drawn with plain Cocos nodes (LayerColor + system-font labels + one-by-one
-- touch listeners), the same approach main.lua uses for its splash screen.

local graphic = require "manager.graphic"
local network = require "manager.network"
local campaign_data = require "manager.campaign_data"
local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"

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

    graphic:RegisterEvent("refresh_campaign", function (campaign_info)
        -- a finished campaign battle: pass through the fresh recruit draft
        -- (if any) so the chooser can open without another round trip
        if campaign_info and campaign_info.recruit_offers then
            self._pending_offers = campaign_info.recruit_offers
        end
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
    network:Send("req_campaign_info", {}, function (result, recv)
        if result ~= "success" then return end
        self.cleared = (recv and recv.cleared) or {}
        self.info_map = recv or {}
        self:Render()
        if recv and recv.pending_recruit then
            self:ShowRecruitChooser(recv.pending_recruit)
        end
    end)
end

-- first node not yet cleared
function meta:CurrentNodeId()
    for _, node in ipairs(campaign_data.all_nodes()) do
        if not self.cleared[node.id] then return node.id end
    end
    return nil
end

function meta:IsUnlocked(node)
    local nodes = campaign_data.all_nodes()
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
        tonumber(self.info_map.vitality) or 30,
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
    local cur_node = campaign_data.node_by_id(cur)
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
    if not self.cleared[node.id] and not self:IsUnlocked(node) then
        graphic:DispatchEvent("show_message", "campaign_node_locked")
        return
    end
    -- a first-clear recruit is still pending: pick it before the next fight
    if self.info_map.pending_recruit then
        self:ShowRecruitChooser(self.info_map.pending_recruit)
        return
    end
    network:Send("req_campaign_battle_start", { node_id = node.id }, function (result, recv)
        if result ~= "success" then
            if result == "campaign_recruit_pending" then
                self:ShowRecruitChooser(self.info_map.pending_recruit)
            else
                graphic:DispatchEvent("show_message", result or "campaign_start_failed")
            end
        end
        -- on success the battle scene is pushed automatically by cmd_battle_start
    end)
end

-- ---------------------------------------------------------------------------
-- First-clear recruit draft ("collection IS your deck" — the web prototype's
-- reward loop, now served by the native service's req_campaign_recruit_*).
-- ---------------------------------------------------------------------------

function meta:CardName(card_id)
    local cfg = data_template.card_config and data_template.card_config[tostring(card_id)]
    if cfg and cfg.name then return cfg.name end
    return tostring(card_id)
end

function meta:ShowRecruitChooser(node_id)
    if self.recruit_layer then
        return
    end
    local size = self.win_size
    local layer = cc.LayerColor:create(cc.Color(6, 6, 14, 230))
    layer:setContentSize(size)
    layer:setPosition(cc.p(0, 0))
    self:addChild(layer, 50)
    self.recruit_layer = layer
    self:_SwallowTouches(layer)

    local title = cc.Label:createWithSystemFont("New recruit — pick a card", "Arial", 30)
    title:setAnchorPoint(cc.p(0.5, 0.5))
    title:setPosition(cc.p(size.width / 2, size.height - 120))
    title:setColor(ui_helper:GetColor3B(0xe94560))
    layer:addChild(title)

    -- fetch the offers the service drafted for this clear
    local function render_offers(offers)
        local offer_ids = offers or self._pending_offers or {}
        self._pending_offers = nil
        if #offer_ids == 0 then
            self:HideRecruitChooser()
            return
        end
        for i, id in ipairs(offer_ids) do
            local label = cc.Label:createWithSystemFont(self:CardName(id), "Arial", 26)
            label:setAnchorPoint(cc.p(0.5, 0.5))
            label:setPosition(cc.p(size.width / 2, size.height - 200 - (i - 1) * 60))
            label:setColor(ui_helper:GetColor3B(0xffd76a))
            layer:addChild(label)
            local listener = cc.EventListenerTouchOneByOne:create()
            listener:registerScriptHandler(function (touch)
                return cc.rectContainsPoint(label:getBoundingBox(), touch:getLocation())
            end, cc.Handler.EVENT_TOUCH_BEGAN)
            listener:registerScriptHandler(function ()
                network:Send("req_campaign_recruit", { node_id = node_id, card_id = id }, function (result)
                    if result == "success" then
                        self:HideRecruitChooser()
                        self:Refresh()
                    end
                end)
            end, cc.Handler.EVENT_TOUCH_ENDED)
            label:getEventDispatcher():addEventListenerWithSceneGraphPriority(listener, label)
        end
        local skip = cc.Label:createWithSystemFont("Skip (+15 EXP)", "Arial", 22)
        skip:setAnchorPoint(cc.p(0.5, 0.5))
        skip:setPosition(cc.p(size.width / 2, 90))
        skip:setColor(ui_helper:GetColor3B(0x8b8ba7))
        layer:addChild(skip)
        local listener = cc.EventListenerTouchOneByOne:create()
        listener:registerScriptHandler(function (touch)
            return cc.rectContainsPoint(skip:getBoundingBox(), touch:getLocation())
        end, cc.Handler.EVENT_TOUCH_BEGAN)
        listener:registerScriptHandler(function ()
            network:Send("req_campaign_skip_recruit", {}, function (result)
                if result == "success" then
                    self:HideRecruitChooser()
                    self:Refresh()
                end
            end)
        end, cc.Handler.EVENT_TOUCH_ENDED)
        skip:getEventDispatcher():addEventListenerWithSceneGraphPriority(listener, skip)
    end

    if self._pending_offers then
        render_offers(nil)
    else
        network:Send("req_campaign_recruit_offers", { node_id = node_id }, function (result, recv)
            if result ~= "success" then
                self:HideRecruitChooser()
                return
            end
            render_offers(recv and recv.offers or {})
        end)
    end
end

function meta:HideRecruitChooser()
    if self.recruit_layer then
        self.recruit_layer:removeFromParent()
        self.recruit_layer = nil
    end
end

function meta:Update(elapsed_time)
    -- no per-frame work needed
end

return meta
