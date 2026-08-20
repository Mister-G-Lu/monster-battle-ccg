-- campaign_test.lua — canonical campaign data, no Android runtime required.
package.path = "src/?.lua;" .. package.path

local failures = 0
local function check(cond, msg)
    if cond then
        print("[PASS] " .. msg)
    else
        failures = failures + 1
        print("[FAIL] " .. msg)
    end
end

local campaign = require("manager.campaign_data")

check(campaign.REGIONS ~= nil, "REGIONS present")
check(#campaign.REGIONS == 4, "4 regions")
check(#campaign.STARTER_COLLECTION > 0, "starter collection")
check(campaign.TOKENS.sapling ~= nil, "sapling token")

local nodes = campaign.all_nodes()
check(#nodes == 19, "19 nodes")

local w1, act1 = campaign.node_by_id("w1")
check(w1 ~= nil and w1.name == "Forest Trail", "w1 Forest Trail")
check(act1 and act1.id == "act1", "w1 lives in act1")
check(w1.hp == 14, "w1 hp 14")
check(w1.pool and w1.pool.kinds[1] == "nature", "w1 nature pool")
check(w1.pool.size == 9, "w1 pool size 9")

local cards = campaign.load_cards_from_csv("csv_data/all_card_config.csv")
local n = 0
for _ in pairs(cards) do n = n + 1 end
check(n > 500, "csv card index (" .. n .. ")")

local ids = campaign.resolve_pool(w1.pool, cards)
check(#ids == 9, "w1 pool resolves to 9 cards")
for _, id in ipairs(ids) do
    local c = cards[id]
    check(c ~= nil and c.type == "monster" and c.kind == "nature", "pool card " .. tostring(id) .. " is nature monster")
end

local mons, items = campaign.split_collection(campaign.STARTER_COLLECTION, cards)
check(#mons > 0 and #items > 0, "starter splits into monsters and items")

local enemy = campaign.enemy_model_ids(w1, cards)
check(#enemy == 9, "w1 enemy deck ids")

local w4 = campaign.node_by_id("w4")
check(w4.deck_ids ~= nil and #w4.deck_ids > 0, "elite uses explicit deck_ids")
check(w4.power and w4.power.id == "muster", "w4 muster power from JSON")

print()
if failures > 0 then
    print("RESULT: " .. failures .. " FAILURE(S)")
    os.exit(1)
end
print("RESULT: ALL CHECKS PASSED")
