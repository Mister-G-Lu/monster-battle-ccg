local ui_helper = require "manager.ui_helper"
local data_template = require "manager.data_template"
local resource = require "manager.resource"

local resource_logic = require "logic.resource"


local ITEM_CONFIG = data_template.item_config

local meta = class("item_reward_animation",function ()
    return cc.Layer:create()
end)


function meta:ReduceObj(item_id,value_num,k,pos,node_num) --对象 、 数量 、num 是几种 、pos 位置

    local node_distance = 100 --node 间距
    local reward_node_bag = ui_helper:LoadCocosUI("interface/common/reward_node.csb")
    reward_node_bag:setPosition(cc.p(30,1000 - k * node_distance)) -- 最高点 1000

    self:addChild(reward_node_bag)
    reward_node_bag:PlayAnimation("enter")  --tip 动画
    local config = ITEM_CONFIG[item_id]
    local img = resource:GetItemIcon(config.res_path)
    local bg = reward_node_bag:getChildByName("bg")
    local node_value = bg:getChildByName("value")
    local icon = bg:getChildByName("icon")
    icon:loadTexture(img)
    node_value:setString(self.reward_node_num[k])
    local flag
    if value_num >10 then --最多10组动画
        local value_item_add = value_num % 10
        local value_item = (value_num - value_item_add) / 10
        local value_item_end = value_item + value_item_add
        for i=1,10 do
            local sp = cc.Sprite:create()
            sp:setPosition(pos)
            sp:setTexture(img)
            self:addChild(sp)
            if i ==10 then
                self:MoveAction(sp,reward_node_bag,k,value_num,node_num,value_item_end)
            else
                self:MoveAction(sp,reward_node_bag,k,value_num,node_num,value_item)
            end

        end
    else
        for i=1,value_num do
            local sp = cc.Sprite:create()
            sp:setPosition(pos)
            sp:setTexture(img)
            self:addChild(sp)
            local value_item = 1
            self:MoveAction(sp,reward_node_bag,k,value_num,node_num,value_item)
        end
    end
    self.num = self.num -1
end

function meta:Show(reward_list, callback)
    self.callback = callback
    local list = {}
    list = reward_list
    self.num = #list
    self.reward_node_num = {}
    self.call_times = 0
    for k,v in pairs(list) do
        local pos = v.pos
        local reward_info = v.reward
        local reward_item = require("modules.common.material_item").new()
        reward_item:ShowReward(reward_info)
        if not pos then
            pos.x = display.cx
            pos.y = display.cy
        end
        reward_item:setPosition(cc.p(pos))
        self:addChild(reward_item)
        local value = reward_info.value
        local item_id = tonumber(reward_info.attr_id)
        reward_item:setVisible(false)
        local node_num = tonumber(resource_logic:GetItemNum(item_id))
        local num = node_num - value
        self.reward_node_num[k] = num
        self.call_times = self.call_times + value
        self:ReduceObj(item_id,value,k,pos,node_num)
    end
end


function meta:MoveAction(sp,node,k,value_num,node_num,value_item)

    local bg = node:getChildByName("bg")
    local value = bg:getChildByName("value")

    local sp_x = sp:getPositionX()
    local sp_y = sp:getPositionY()

    local node_x = node:getPositionX()
    local node_y = node:getPositionY()

    local distance_x = math.abs(sp_x*sp_x - node_x * node_x)
    local distance_y = math.abs(sp_y*sp_y - node_y * node_y)

    local distance = math.sqrt(distance_x + distance_y)

    local speed_num = math.random(1,5) --随机数自己调节
    local speed = 600 + 20 * speed_num --运行速度自己调节
    local time = distance / speed  --运行时间

    local x_add_random =  math.random(1,6)
    local y_add_random =  math.random(1,6)

    local x_add = 50 * x_add_random  --曲线幅度
    local y_add = 50 * y_add_random
    local centre_x = node_x + (sp_x - node_x)/2 + x_add
    local centre_y = node_y + (sp_y - node_y)/2 + y_add

    local bezier = {
        cc.p(sp_x,sp_y),
        cc.p(centre_x,centre_y),
        cc.p(node_x,node_y)  --这里可以设置触碰点 node_x＋10,node_y - 10 之类
    }
    local time_add = 0.1 * math.random(1,6)  --增加时间
    local bezier_time = time + time_add
    local bezier = cc.BezierTo:create(time,bezier)
    local func = cc.CallFunc:create(function ()
            sp:removeFromParent()  --消失筹码
            node:PlayAnimation("tip")  --tip 动画
            self.call_times = self.call_times - value_item
            self.reward_node_num[k] = self.reward_node_num[k] + value_item
            value:setString(self.reward_node_num[k])
            if self.reward_node_num[k] == node_num then
                node:PlayAnimation("exit")
            end
            if self.call_times == 0 then
                local delaytime = cc.DelayTime:create(1) --delaytime =1  消失
                local func2 = cc.CallFunc:create(function ()
                    if self.num == 0 then
                        self:Exit()
                    end
               end)
                local seq2 = cc.Sequence:create(delaytime,func2)
                self:runAction(seq2)
             end
        end)
    local seq = cc.Sequence:create(bezier,func)
    sp:runAction(seq)
end


function meta:Exit()
    self:removeFromParent()

    if self.callback then
        self.callback()
    end
end

return meta
