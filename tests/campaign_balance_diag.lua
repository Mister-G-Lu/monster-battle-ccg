-- campaign_balance_diag.lua  (diagnostic, not part of the CI suite)
-- Plays every campaign node N times with a greedy bot and reports how battles
-- conclude (natural hero kill vs MAX_ROUNDS stalemate) plus win rates.

local NODES = arg or { "w1" }
local RUNS = tonumber(arg and arg[2]) or 3

path = "res/data/"
local bit_stub = {}
function bit_stub.band(a, b)
    local r, p = 0, 1
    while (a > 0 or b > 0) and p <= 2^31 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end
function bit_stub.bor(a, b)
    local r, p = 0, 1
    while (a > 0 or b > 0) and p <= 2^31 do
        if a % 2 == 1 or b % 2 == 1 then r = r + p end
        a = math.floor(a / 2); b = math.floor(b / 2); p = p * 2
    end
    return r
end
function bit_stub.bnot(a) return 0xFFFFFFFF - bit_stub.band(a, 0xFFFFFFFF) end
function bit_stub.lshift(a, n) return bit_stub.band(a * 2^n, 0xFFFFFFFF) end
function bit_stub.rshift(a, n) return math.floor(bit_stub.band(a, 0xFFFFFFFF) / 2^n) end
package.loaded["bit"] = bit_stub

aandm = {}
function aandm.loadConfig(name)
    local base = string.match(name, "([^/\\]+)%.csv$") or name
    local f = io.open("csv_plain/" .. base .. ".csv", "r")
    if not f then return "" end
    local c = f:read("*a"); f:close(); return c
end
function aandm.getDataFromFile() return nil end
socket = {}; crypt = {}
package.loaded["socket"] = socket
package.loaded["crypt"] = crypt
protobuf = { register = function() end, encode = function() return "" end, decode2 = function() return {} end }
package.loaded["utils.protobuf"] = protobuf
cc = {}
cc.LANGUAGE_ENGLISH = 0; cc.LANGUAGE_CHINESE = 1
cc.PLATFORM_OS_WINDOWS = 4; cc.PLATFORM_OS_MAC = 5; cc.PLATFORM_OS_LINUX = 6
cc.PLATFORM_OS_ANDROID = 3; cc.PLATFORM_OS_IPHONE = 2; cc.PLATFORM_OS_IPAD = 1
local app = { getCurrentLanguage = function() return 0 end, getTargetPlatform = function() return 4 end }
cc.Application = { getInstance = function() return app end }
cc.FileUtils = { getInstance = function() return { getWritablePath = function() return "sim_save_diag/" end } end }
cc.UserDefault = { getInstance = function() return { getStringForKey = function() return "" end, getIntegerForKey = function(_, d) return d or 0 end, getBoolForKey = function(_, d) return d or false end, getDoubleForKey = function(_, d) return d or 0 end, setStringForKey = function() end, setIntegerForKey = function() end, setBoolForKey = function() end, setDoubleForKey = function() end, flush = function() end } end }
cc.Director = { getInstance = function() return { getTextureCache = function() return {} end, getScheduler = function() return { scheduleScriptFunc = function() return 1 end } end, getRunningScene = function() return nil end } end }

package.path = "decrypted/src/?.lua;" .. "decrypted/?.lua;" .. package.path
local time = require "manager.time"; time:Init()
require "common.ext.init"
local data_template = require "manager.data_template"
data_template:Init()
while not data_template.is_load_complete do data_template:LoadFromCSV() end
local campaign_data = require "manager.campaign_data"
local network = require "manager.network"
network:RegisterProto()
network:Connect("offline", 28800)
network:Send("req_login_game", {name="diag", token="sim", type="debug", channel="debug", language="en-US", version="1.4"}, function() end)
local offline_server = require "manager.offline_server"

local function play(b, cap)
    local t = 0
    while not b.is_over and t < cap do
        t = t + 1
        local g = 0
        while b.own.is_sacrifice and g < 12 do
            g = g + 1
            local aff = false
            for p = 1, 4 do
                local c = b.own:GetHandCard(p)
                if c and c.type == "monster" and c.cost <= b.own.cur_crystal and b.own:GetCurMonsterSlotPos() > 0 then aff = true end
            end
            if aff then break end
            local sp = nil
            for p = 1, 4 do if b.own:GetHandCard(p) then sp = p break end end
            if not sp then break end
            b:HandleSacrifice({is_hand = true, pos = sp})
        end
        for p = 1, 4 do
            local c = b.own:GetHandCard(p)
            if c and c.cost and c.cost <= b.own.cur_crystal then
                if c.type == "monster" then
                    local s = b.own:GetCurMonsterSlotPos()
                    if s > 0 then b:HandleMove({src_pos = p, is_enemy = false, target_pos = s}) end
                else
                    for s = 1, 3 do
                        local slot = b.own:GetBattleCard(s)
                        if slot and slot.monster then b:HandleMove({src_pos = p, is_enemy = false, target_pos = s}); break end
                    end
                end
            end
        end
        b:HandleAttack({})
    end
    return t
end

local all_nodes = campaign_data:GetNodes()
for _, node in ipairs(all_nodes) do
    local wins, losses, stalls = 0, 0, 0
    local rounds = {}
    for _ = 1, RUNS do
        network:Send("req_campaign_battle_start", {node_id = node.id}, function() end)
        local b = offline_server.current_battle
        local t = play(b, 55)
        table.insert(rounds, b.round)
        if b.is_over then
            if b.win_user_id == "player" then wins = wins + 1 else losses = losses + 1 end
        else
            stalls = stalls + 1
        end
    end
    local avg = 0
    for _, r in ipairs(rounds) do avg = avg + r end
    avg = #rounds > 0 and (avg / #rounds) or 0
    print(string.format("%-4s %-9s HP=%-3d  W=%d L=%d stall=%d  avg_rounds=%.1f",
        node.id, node.type, tonumber(node.hp) or 0, wins, losses, stalls, avg))
end
