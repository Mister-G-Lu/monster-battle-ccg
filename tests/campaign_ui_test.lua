-- campaign_ui_test.lua
-- UI-level regression coverage for the native Adventure / Shadow Road screen.
--
-- This runs the real campaign_panel.lua with a small Cocos node model. It
-- verifies the things a service-only test cannot see:
--   * a full 19-node road is rendered before/after a progress refresh;
--   * rows live in ScrollView's inner container, so refreshing never leaves
--     an empty or duplicated map;
--   * a node tap calls the campaign battle endpoint; and
--   * Back returns through world_scene's home route rather than merely hiding
--     a child layer after a battle.
--
-- No decrypted APK fixture is required. Run with LuaJIT or Lua 5.1:
--     luajit tests/campaign_ui_test.lua

package.path = "src/?.lua;" .. package.path

local failures = 0
local function check(condition, message)
    if condition then
        print("[PASS] " .. message)
    else
        failures = failures + 1
        print("[FAIL] " .. message)
    end
end
local function section(name) print("\n=== " .. name .. " ===") end

-- ---------------------------------------------------------------------------
-- Cocos UI model. It deliberately gives ScrollView a separate inner
-- container, matching the device behavior that matters for map refreshes.
-- ---------------------------------------------------------------------------
local all_labels = {}
local function new_node(kind)
    local node = {
        kind = kind,
        children = {},
        visible = true,
        listeners = {},
    }
    function node:setContentSize(size) self.content_size = size end
    function node:setPosition(position) self.position = position end
    function node:setAnchorPoint(anchor) self.anchor = anchor end
    function node:setColor(color) self.color = color end
    function node:setVisible(value) self.visible = value end
    function node:addChild(child, zorder)
        child.parent = self
        child.zorder = zorder
        self.children[#self.children + 1] = child
    end
    function node:removeAllChildren() self.children = {} end
    function node:removeFromParent()
        self.removed = true
        if not self.parent then return end
        for i, child in ipairs(self.parent.children) do
            if child == self then table.remove(self.parent.children, i); break end
        end
    end
    function node:onTouch() end
    function node:setString(value) self.text = tostring(value or "") end
    function node:getBoundingBox() return { x = 0, y = 0, width = 1000, height = 1000 } end
    node.dispatcher = {
        addEventListenerWithSceneGraphPriority = function(_, listener)
            node.listeners[#node.listeners + 1] = listener
        end,
    }
    function node:getEventDispatcher() return self.dispatcher end
    return node
end

-- The game uses common.ext.init's native-object class form. This minimal
-- version keeps that construction contract for cc.Layer:create().
function class(_, creator)
    local cls = {}
    cls.__index = cls
    function cls.new(...)
        local instance = creator(...)
        for key, value in pairs(cls) do instance[key] = value end
        instance.class = cls
        instance:ctor(...)
        return instance
    end
    return cls
end

cc = {}
cc.p = function(x, y) return { x = x, y = y } end
cc.size = function(width, height) return { width = width, height = height } end
cc.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
cc.Layer = { create = function() return new_node("layer") end }
cc.LayerColor = { create = function() return new_node("layer_color") end }
cc.Label = {
    createWithSystemFont = function(_, text)
        local label = new_node("label")
        label.text = text or ""
        all_labels[#all_labels + 1] = label
        return label
    end,
}
cc.Director = {
    getInstance = function()
        return { getWinSize = function() return { width = 1280, height = 720 } end }
    end,
}
cc.Handler = { EVENT_TOUCH_BEGAN = 1, EVENT_TOUCH_ENDED = 2 }
cc.EventListenerTouchOneByOne = {
    create = function()
        local listener = {}
        function listener:registerScriptHandler(callback, event)
            if event == cc.Handler.EVENT_TOUCH_BEGAN then self.began = callback end
            if event == cc.Handler.EVENT_TOUCH_ENDED then self.ended = callback end
        end
        return listener
    end,
}
cc.rectContainsPoint = function() return true end

ccui = {
    ScrollViewDir = { vertical = 1 },
    ScrollView = {
        create = function()
            local scroll = new_node("scroll")
            scroll.inner = new_node("scroll_inner")
            function scroll:getInnerContainer() return self.inner end
            function scroll:setDirection(value) self.direction = value end
            function scroll:setTouchEnabled(value) self.touch_enabled = value end
            function scroll:setBounceEnabled(value) self.bounce_enabled = value end
            function scroll:setInnerContainerSize(size) self.inner_size = size end
            function scroll:scrollToTop() self.scrolled_to_top = true end
            return scroll
        end,
    },
}

-- ---------------------------------------------------------------------------
-- Network / graphic stubs. The panel talks to these exactly as it does on a
-- device, while the test controls the saved campaign payload.
-- ---------------------------------------------------------------------------
local requests = {}
local network_mode = "success"
local campaign_payload = {
    cleared = {}, collection = { 110011, 120021, 130031, 140021, 150011, 140031 },
    vitality = 30, bosses_slain = 0, wins = 0, losses = 0, complete = false,
}

package.loaded["manager.network"] = {
    Send = function(_, request_name, payload, callback)
        requests[#requests + 1] = { name = request_name, payload = payload or {} }
        if request_name == "req_campaign_info" then
            if network_mode == "success" then
                callback("success", campaign_payload)
            else
                callback("fail", {})
            end
        elseif callback then
            callback("success", {})
        end
    end,
}

local registered_events = {}
local dispatched_events = {}
package.loaded["manager.graphic"] = {
    RegisterEvent = function(_, name, callback) registered_events[name] = callback end,
    DispatchEvent = function(_, name, ...)
        dispatched_events[#dispatched_events + 1] = { name = name, args = { ... } }
    end,
}
package.loaded["manager.ui_helper"] = {
    GetColor3B = function(_, value) return value end,
}
package.loaded["manager.data_template"] = { card_config = {} }

local campaign_data = require "manager.campaign_data"
local campaign_panel = require "modules.world.system.campaign_panel"

local function label_contains(root, needle)
    for _, child in ipairs(root.children or {}) do
        if type(child.text) == "string" and string.find(child.text, needle, 1, true) then return true end
        if label_contains(child, needle) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
section("1. Adventure renders a usable canonical road")
local panel = campaign_panel.new()
panel:Show()

check(panel.visible == true, "campaign panel becomes visible")
check(requests[1] and requests[1].name == "req_campaign_info", "Show requests campaign progress")
check(panel.rendered_node_count == #campaign_data.all_nodes(),
    "all canonical nodes render (got " .. tostring(panel.rendered_node_count) .. ")")
check(#panel.scroll.inner.children == #campaign_data.all_nodes() + #campaign_data.REGIONS,
    "rows and headers are in ScrollView's inner container")
check(label_contains(panel.scroll.inner, "Forest Trail"), "first Adventure node is visible")
check(label_contains(panel.scroll.inner, ">> Skirmish Forest Trail"), "current node is highlighted")

-- ---------------------------------------------------------------------------
section("2. Battle refresh updates the road without losing its rows")
campaign_payload = {
    cleared = { w1 = true }, collection = { 1, 2, 3, 4, 5, 6, 7 },
    vitality = 30, bosses_slain = 0, wins = 1, losses = 0, complete = false,
}
registered_events.refresh_campaign({ node_id = "w1", victory = true })

check(panel:CurrentNodeId() == "w2", "refresh advances current node to w2")
check(panel.rendered_node_count == #campaign_data.all_nodes(), "refresh keeps all campaign rows")
check(#panel.scroll.inner.children == #campaign_data.all_nodes() + #campaign_data.REGIONS,
    "refresh clears old inner-container rows before rebuilding")
check(label_contains(panel.scroll.inner, ">> Skirmish Wolf Den"), "new current node is highlighted")

-- ---------------------------------------------------------------------------
section("3. Tapping a visible node starts the native campaign battle")
requests = {}
panel:_OnNodeTap(campaign_data.node_by_id("w2"))
check(requests[1] and requests[1].name == "req_campaign_battle_start",
    "node tap sends req_campaign_battle_start")
check(requests[1] and requests[1].payload.node_id == "w2", "node tap sends the selected node id")

-- ---------------------------------------------------------------------------
section("4. Back exits through the world-system router")
local back_listener = panel.back_btn.listeners[1]
check(back_listener and back_listener.ended ~= nil, "Back label has a touch-end handler")
if back_listener and back_listener.ended then back_listener.ended() end
local last = dispatched_events[#dispatched_events]
check(panel.visible == false, "Back hides the campaign panel")
check(last and last.name == "switch_system_module" and last.args[1] == "home",
    "Back switches the world system back to home")

-- ---------------------------------------------------------------------------
section("5. Failed first progress reads retain the canonical map")
network_mode = "fail"
local failed_panel = campaign_panel.new()
failed_panel:Show()
check(failed_panel.rendered_node_count == #campaign_data.all_nodes(),
    "failed first campaign-info request does not blank the map")
check(label_contains(failed_panel.scroll.inner, "Forest Trail"),
    "fallback still renders the first canonical Adventure encounter")
check(failed_panel.info.text == "Campaign progress is unavailable. Showing the road.",
    "failed request gives a visible recovery message")

-- ---------------------------------------------------------------------------
section("6. Empty campaign loot completes the native result UI")
-- A defeat has no reward rows. The stock result sequence previously waited
-- forever for a reward-panel callback that could never arrive, so it never
-- popped back to Adventure. Exercise the real patched method without loading
-- the full battle scene.
package.loaded["manager.ui_helper"].NewPanel = function() return {} end
package.loaded["manager.global"] = {}
package.loaded["manager.resource"] = {}
package.loaded["manager.audio_manager"] = {}
package.loaded["logic.resource"] = {}
package.loaded["logic.battle"] = {}
package.loaded["logic.user"] = {}
package.loaded["manager.defines"] = {}
package.loaded["logic.arena"] = {}
package.loaded["manager.spine"] = {}
package.loaded["common.constants"] = {}
local result_panel = require "modules.battle.battle_result_panel"
local empty_result = {}
result_panel.ShowReward(empty_result, {})
check(empty_result.reward_action_over == true,
    "empty campaign reward list completes the result sequence for return")

print("\n" .. string.rep("=", 60))
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CAMPAIGN UI CHECKS PASSED")
