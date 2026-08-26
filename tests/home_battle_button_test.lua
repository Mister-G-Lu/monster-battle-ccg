-- home_battle_button_test.lua
-- Regression: the home bar's "Battle" button must lead straight to
-- The Shadow Road campaign map.
--
-- `client_lang_en-US.csv` labels interface/world/main_panel.csb pvpbtn.desc
-- as "Battle" and pvebtn.desc as "Adventure".  The stock build sends pvpbtn
-- to PvP matchmaking and pvebtn to the PvE mission list (Gerbip Tide); this
-- offline build has exactly one destination, so:
--   * the visible door is the one labelled "Battle" (pvpbtn)
--   * the duplicate "Adventure" door is hidden
--   * tapping either one opens the campaign panel, never the PvE list
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
        graphic_dispatched[name] = (graphic_dispatched[name] or 0) + 1
    end,
    RegisterEvent = function() end,
}

local configuration_state = { show_help = false }
package.loaded["manager.configuration"] = {
    IsShowHelp = function() return configuration_state.show_help end,
    SetShowHelp = function(_, v) configuration_state.show_help = v end,
}

local pve_shown = 0
package.loaded["logic.pve"] = {
    play_id = nil, difficulty = nil, login_pve_data = {}, adv_passid = {},
    ShowPve = function() pve_shown = pve_shown + 1 end,
    Query = function() end,
}
package.loaded["logic.mail"] = { new_mail_num = 0, Query = function() end }
package.loaded["logic.user"] = { task_hint = false, achi_hint = false }

-- The campaign panel is the destination under test; stand in for it so the
-- test can observe Show() without a real Cocos scene.
local campaign_shown = 0
local campaign_stub = {}
campaign_stub.setVisible = function(_, v) campaign_stub.visible = v end
campaign_stub.Show = function() campaign_shown = campaign_shown + 1 end
campaign_stub.Update = function() end
package.loaded["modules.world.system.campaign_panel"] = {
    new = function() return campaign_stub end,
}
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
section("2. The Battle button is the campaign door")
check(panel.campaign_btn == panel.pvp_btn,
    "the campaign door is pvpbtn, the button labelled \"Battle\"")
check(panel.pvp_btn.visible == true, "Battle button is visible")
check(panel.pve_btn.visible == false,
    "the duplicate Adventure door is hidden (one door, one destination)")

-- ---------------------------------------------------------------------------
section("3. Tapping Battle opens the campaign map")
check(click_handlers["pvpbtn"] ~= nil, "the Battle button has a click handler")
if click_handlers["pvpbtn"] then
    click_handlers["pvpbtn"]()
end
check(campaign_shown == 1, "tapping Battle opened the campaign panel (Show called once)")
check(pve_shown == 0, "tapping Battle never opened the stock PvE mission list")

-- the hidden duplicate is wired to the same place, so a .csb that exposes it
-- instead of pvpbtn still lands in the campaign
if click_handlers["pvebtn"] then
    click_handlers["pvebtn"]()
end
check(campaign_shown == 2, "the Adventure door, if tapped, also opens the campaign")
check(pve_shown == 0, "no path reaches pve_logic:ShowPve() while the campaign loads")

-- ---------------------------------------------------------------------------
section("4. Fallback when the campaign panel cannot be built")
local fallback = setmetatable({}, { __index = home_panel })
fallback.campaign_node = nil
home_panel.OpenCampaign(fallback)
check(pve_shown == 1,
    "with no campaign panel the Battle button falls back to the PvE list")

-- ---------------------------------------------------------------------------
print("\n" .. string.rep("=", 60))
if failures == 0 then
    print("RESULT: ALL HOME BATTLE BUTTON CHECKS PASSED")
else
    print("RESULT: " .. failures .. " FAILED")
end
os.exit(failures == 0 and 0 or 1)
