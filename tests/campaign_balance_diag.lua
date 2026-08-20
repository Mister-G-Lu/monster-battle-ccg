-- campaign_balance_diag.lua — cheap sanity on node HP / pool sizes.
package.path = "src/?.lua;" .. package.path
local campaign = require("manager.campaign_data")
local cards = campaign.load_cards_from_csv("csv_data/all_card_config.csv")
local fail = 0
for _, node in ipairs(campaign.all_nodes()) do
    if not node.hp or node.hp < 8 then
        print("[FAIL] " .. node.id .. " hp too low")
        fail = fail + 1
    end
    local ids = campaign.enemy_model_ids(node, cards)
    if #ids < 4 then
        print("[FAIL] " .. node.id .. " enemy deck too small (" .. #ids .. ")")
        fail = fail + 1
    else
        print("[OK] " .. node.id .. " hp=" .. node.hp .. " enemy=" .. #ids)
    end
end
if fail > 0 then os.exit(1) end
print("RESULT: ALL CHECKS PASSED")
