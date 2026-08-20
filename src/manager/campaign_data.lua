-- Native campaign module: adapters only. Node/deck/power literals live in
-- campaign_data_generated.lua (from content/campaign_data.json).
local gen = require("manager.campaign_data_generated")

local M = {}
M.REGIONS = gen.REGIONS
M.TOKENS = gen.TOKENS
M.STARTER_COLLECTION = gen.STARTER_COLLECTION

local KIND_FLAG = { war = 1, fortune = 2, balance = 4, nature = 8, chaos = 16 }

function M.kind_flag(kind)
    return KIND_FLAG[kind] or 0
end

function M.node_by_id(id)
    for _, region in ipairs(M.REGIONS) do
        for _, node in ipairs(region.nodes) do
            if node.id == id then return node, region end
        end
    end
end

function M.all_nodes()
    local out = {}
    for _, region in ipairs(M.REGIONS) do
        for _, node in ipairs(region.nodes) do
            out[#out + 1] = node
        end
    end
    return out
end

return M
