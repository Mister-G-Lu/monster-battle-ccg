local spine_manager = {}

local focus_tracker = {}
focus_tracker.__index = focus_tracker

function focus_tracker.New(root_node, slot_name)
    local t = {}
    t.slot_name = slot_name
    t.root_node = root_node

    t.is_play = false

    t.root_node:registerSpineEventHandler(function(event)
        --t.root_node:setVisible(false)
        --t.widget:setVisible(false)
        --t.widget:setScale(1.0, 1.0)
        t.is_play = false
    end, sp.EventType.ANIMATION_END)

    return setmetatable(t, focus_tracker)
end

function focus_tracker:Bind(animation, x, y, widget)
    if not widget then
        self.root_node:setVisible(false)
        return
    end

    self.offset_x = x
    self.offset_y = y

    self.widget = widget

    self.root_node:setPosition(x, y)
    self.root_node:setVisible(true)
    self.root_node:setToSetupPose()

    self.is_play = true

    self.root_node:setAnimation(0, animation, false)
end

function focus_tracker:Hide()
    self.root_node:setVisible(false)
    self.root_node:clearTrack(0)

    if self.widget then
        self.widget:setScale(1.0, 1.0)
    end

    self.is_play = false
end

function focus_tracker:Update()
    if self.root_node:isVisible() and self.widget and self.is_play then
        local x, y, scale_x, scale_y = self.root_node:getSlotTransform(self.slot_name)
        self.widget:setPosition(self.offset_x + x, self.offset_y + y)
        self.widget:setScale(scale_x, scale_y)
    end
end


function spine_manager:Init()
    self.nodes = {}
end

function spine_manager:GetNode(name, scale, use_nearest_sample)
    local spine_node

    if not self.nodes[name] then
        local filename = "res/spine/" .. name
        spine_node = sp.SkeletonAnimation:create(filename .. ".json", filename .. ".atlas", scale or 1.0)
        if use_nearest_sample then
            local texture = cc.Director:getInstance():getTextureCache():addImage(filename .. ".png")
            texture:setTexParameters(gl.NEAREST, gl.NEAREST, gl.CLAMP_TO_EDGE, gl.CLAMP_TO_EDGE)
        end

        self.nodes[name] = spine_node
        spine_node:retain()

    else
        spine_node = self.nodes[name]:clone()
    end

    return spine_node
end

function spine_manager:DestroyNode(name)
    local spine_node = self.nodes[name]

    if spine_node then
        spine_node:release()
        self.nodes[name] = nil
    end
end

function spine_manager:Clear()
    for k, v in pairs(self.nodes) do
        v:release()
        self.nodes[k] = nil
    end
end


function spine_manager:CreateFocusTracker(root_node, slot_name)
    return focus_tracker.New(root_node, slot_name)
end

do
    spine_manager:Init()
end

return spine_manager
