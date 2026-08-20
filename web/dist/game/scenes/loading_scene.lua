local ui_helper = require "manager.ui_helper"

local meta = class("loading_scene",function ()
    return cc.Scene:create()
end)

function meta:ctor()
    -- local ui_root = ui_helper:LoadCocosUI("interface/loading_panel.csb")
    -- self:addChild(ui_root)

    -- local card = require("modules.deck.card_bag_item").new()
    -- card:setPosition(320, 500)
    -- card:ShowCardGroupInfo(0, { uid = tostring(110076), num = 1}, false)
    -- self:addChild(card)

    -- 测试
    local hand_card1 = require("modules.common.card_hand_item").new()
    hand_card1:SetCardId(tostring(110011))
    local function aa(node)
        local children = node:getChildren()
        local min_x = 0
        local min_y = 0
        local max_x = 0
        local max_y = 0
        for k,v in pairs(children) do
            local rect = v:getBoundingBox()
            rect.width = rect.width
            rect.height = rect.height
            local p = node:convertToWorldSpace({x = rect.x, y = rect.y})
            if p.x < min_x then
                min_x = p.x
            end
            if p.y < min_y then
                min_y = p.y
            end
            if max_x < (p.x + rect.width) then
                max_x = p.x + rect.width
            end

            if max_y < (p.y + rect.height) then
                max_y = p.y + rect.height
            end
            local n_min_x, n_min_y, n_max_x, n_max_y = aa(v)
            if n_min_x < min_x then
                min_x = n_min_x
            end
            if n_min_y < min_y then
                min_y = n_min_y
            end
            if max_x < n_max_x then
                max_x = n_max_x
            end

            if max_y < n_max_y then
                max_y = n_max_y
            end

        end
        return min_x, min_y, max_x, max_y
    end
    local min_x, min_y, max_x, max_y = aa(hand_card1)
    local rect = {}
    rect.x = min_x
    rect.y = min_y
    rect.width = max_x - min_x
    rect.height = max_y - min_y
    hand_card1:setPosition(-min_x, -min_y)
    self:addChild(hand_card1)

    local renderTexture = cc.RenderTexture:create(rect.width, rect.height)
    self:addChild(renderTexture)

        -- hand_card1:SetCardId(card_id)
        -- renderTexture:beginWithClear(0.0, 0.0, 0.0, 0.0);
        -- hand_card1:visit()
        -- renderTexture:endToLua()
        -- renderTexture:saveToFile("aaa.png")

    -- local list = {
    --     110131, 110132, 110133, 110134, 110135, 110136, 110137,
    --     110141, 110142, 110143, 110144, 110145, 110146, 110147, 110148,
    --     120081, 120082, 120083, 120084, 120085, 120086, 120087,
    --     120121, 120122, 120123, 120124, 120125, 120126, 120127,
    --     130071, 130072, 130073, 130074, 130075, 130076, 130077,
    --     130121, 130122, 130123, 130124, 130125, 130126, 130127,
    --     140071, 140072, 140073, 140074, 140075, 140076, 140077,
    --     140121, 140122, 140123, 140124, 140125, 140126, 140127,
    --     150121, 150122, 150123, 150124, 150125, 150126, 150127,
    --     150141, 150142, 150143, 150144, 150145, 150146, 150147, 150148,
    -- }
    -- card_config

    local data_manager = require "manager.data_template"
    local card_config = data_manager.card_config

    local list = {}
    for k,v in pairs(card_config) do
        -- print(k,v)
        table.insert(list, k)
    end
    local index = 1

    local director = cc.Director:getInstance()
    director:getScheduler():scheduleScriptFunc(function(elapsed_time)
        if #list < index then
            print("搞定了")
            return
        end

        local card_id = tostring(list[index])
        hand_card1:SetCardId(card_id)
        renderTexture:beginWithClear(0.0, 0.0, 0.0, 0.0);
        hand_card1:visit()
        renderTexture:endToLua()
        renderTexture:saveToFile("new_card/"..card_id..".png")
        index = index + 1
    end, 0, false)


    -- local text = director:getTextureCache():addImage("res/ui/pic_card/card_back.png")
    -- -- local text = director:getTextureCache():addImage(renderTexture:newImage(true),"aaaa")

    -- local new_texture = renderTexture:getSprite():getTexture()
    -- local spr = cc.Sprite:createWithTexture(new_texture)
    -- -- spr:setTexture(text)
    -- spr:setPosition(180,650)
    -- self:addChild(spr)

    -- -- local spritess = renderTexture:getSprite()
    -- -- -- 主动开启抗锯齿
    -- -- -- spritess:getTexture():setAntiAliasTexParameters()
    -- -- spritess:setPosition(180,650)
    -- -- spritess:setAnchorPoint(0,0)
    -- -- -- spritess:setPosition(480,1200)
    -- -- self:addChild(spritess)


    -- -- local node = ui_helper:LoadCocosUI("panel_general2/card_hand_template.csb")
    -- -- node:setPosition(300,320)
    -- -- node:setAnchorPoint(0,0)

    -- -- self:addChild(node)

    -- local skeletonNode = sp.SkeletonAnimation:create("spine/skeleton.json", "spine/skeleton.atlas", 1.3)
    -- skeletonNode:setAnimation(0, "animation", true)
    -- skeletonNode:pushSlotTexture("card_border", 1, new_texture)
    -- skeletonNode:setPosition(300,300)

    -- self:addChild(skeletonNode)

end


function meta:OnEnter()

end

function meta:OnExit()
end


return meta
