-- home_battle_button_test.lua
-- Home-level UI regression: the visible "Adventure" door must lead straight
-- to The Shadow Road as a world-system panel.
--
-- `client_lang_en-US.csv` labels interface/world/main_panel.csb pvpbtn.desc
-- as "Battle" and pvebtn.desc as "Adventure". The offline game's campaign
-- belongs behind Adventure. It must be routed through world_scene's
-- switch_system_module event rather than built as a hidden child of home;
-- otherwise returning from a pushed battle can reveal the empty legacy PvE
-- screen. The hidden Battle compatibility door is wired to the same route.
--
-- Run under LuaJIT after scripts/setup_test_env.py:
--     luajit tests/home_battle_button_test.lua

local failures = 0
local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        failures = failures + 1
        print("[FAIL] " .. msg)
    end
end
local function section(name) print("\n=== " .. name .. " ===") end

-- ---------------------------------------------------------------------------
-- Minimal Cocos stand-ins.  home_panel.lua only talks to the UI through
-- getChildByName / setVisible / addChild / AddClick / BindTimeLine, so a
-- name-keyed node tree is enough to exercise the real wiring.
-- ---------------------------------------------------------------------------
cc = {}
cc.Layer = { create = function() return {} end }
cc.LayerColor = { create = function() return {} end }
cc.Label = { createWithSystemFont = function() return {} end }
cc.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
cc.p = function(x, y) return { x = x, y = y } end
cc.size = function(w, h) return { width = w, height = h } end

local click_handlers = {}

local NODE_NAMES = {
    "mailbox", "pvpbtn", "pvebtn", "event", "cardbag", "cardbook", "shop",
    "helpbtn", "setting", "friend", "ladder", "task", "achievement",
}

local function new_node(name)
    local n = { name = name, _kids = {}, visible = true, animations = {} }
    function n:getChildByName(k)
        local kid = self._kids[k]
        if not kid then
            -- unknown children are created on demand, like a .csb lookup that
            -- always resolves in the shipped layout
            kid = new_node(k)
            self._kids[k] = kid
        end
        return kid
    end
    function n:setVisible(v) self.visible = v end
    function n:addChild(c) self._kids[#self._kids + 1] = c end
    function n:PlayAnimation(a, l) table.insert(self.animations, a) end
    return n
end

local root = new_node("main_panel")
for _, name in ipairs(NODE_NAMES) do
    root._kids[name] = new_node(name)
end

package.loaded["manager.ui_helper"] = {
    LoadCocosUI = function(_, csb) return root end,
    SetText = function() end,
    SetTextByKey = function() end,
    BindTimeLine = function() end,
    SetCocosSetting = function() end,
    GetColor3B = function() return {} end,
    AddClick = function(_, node, cb)
        click_handlers[node.name] = cb
    end,
}

local graphic_dispatched = {}
package.loaded["manager.graphic"] = {
    DispatchEvent = function(_, name, ...)
        graphic_dispatched[name] = graphic_dispatched[name] or {}
        table.insert(graphic_dispatched[name], { ... })
    end,
    RegisterEvent = function() end,
}

local configuration_state = { show_help = false }
package.loaded["manager.configuration"] = {
    IsShowHelp = function() return configuration_state.show_help end,
    SetShowHelp = function(_, v) configuration_state.show_help = v end,
}

package.loaded["logic.mail"] = { new_mail_num = 0, Query = function() end }
package.loaded["logic.user"] = { task_hint = false, achi_hint = false }

package.loaded["modules.world.system.arena_panel"] = {
    new = function()
        return { setVisible = function() end, Update = function() end }
    end,
}

package.path = "decrypted/src/?.lua;decrypted/?.lua;" .. package.path

-- ---------------------------------------------------------------------------
section("1. Build the home panel")
require "common.ext.init"
local home_panel = require "modules.world.system.home_panel"

-- instantiate through the real ctor: the panel IS the loaded .csb node, so
-- give that node the class as its metatable (what class()/new() does on device)
setmetatable(root, { __index = home_panel })
home_panel.ctor(root)
local panel = root

check(panel.pvp_btn ~= nil, "main_panel.csb exposes the Battle button (pvpbtn)")
check(panel.pve_btn ~= nil, "main_panel.csb exposes the Adventure button (pvebtn)")

-- ---------------------------------------------------------------------------
section("2. Adventure is the campaign door")
check(panel.campaign_btn == panel.pve_btn,
    "the campaign door is pvebtn, the button labelled \"Adventure\"")
check(panel.pve_btn.visible == true, "Adventure button is visible")
check(panel.pvp_btn.visible == false,
    "duplicate Battle button is hidden when Adventure is available")

-- ---------------------------------------------------------------------------
section("3. Tapping Adventure opens the world-system campaign")
check(click_handlers["pvebtn"] ~= nil, "the Adventure button has a click handler")
if click_handlers["pvebtn"] then
    click_handlers["pvebtn"]()
end
local switches = graphic_dispatched["switch_system_module"] or {}
check(#switches == 1, "Adventure dispatched one world-system switch")
check(switches[1] and switches[1][1] == "campaign",
    "Adventure routes to the campaign world-system panel")

-- The hidden compatibility door is wired too. A layout with no Adventure
-- button still reaches the same system panel rather than the legacy PvE list.
if click_handlers["pvpbtn"] then
    click_handlers["pvpbtn"]()
end
switches = graphic_dispatched["switch_system_module"] or {}
check(#switches == 2 and switches[2][1] == "campaign",
    "Battle compatibility door also routes to campaign")

-- ---------------------------------------------------------------------------
section("4. Direct OpenCampaign never falls back to the legacy PvE module")
local standalone = setmetatable({}, { __index = home_panel })
home_panel.OpenCampaign(standalone)
switches = graphic_dispatched["switch_system_module"] or {}
check(#switches == 3 and switches[3][1] == "campaign",
    "OpenCampaign always selects campaign through world_scene")

-- ---------------------------------------------------------------------------
print("\n" .. string.rep("=", 60))
if failures == 0 then
    print("RESULT: ALL HOME BATTLE BUTTON CHECKS PASSED")
else
    print("RESULT: " .. failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
