local TARGET_PLATFORM = cc.Application:getInstance():getTargetPlatform()

local shader_manager = {} 

function shader_manager:Init()
    self.programs = {}

    self.vert_file_list = {}
    self.frag_file_list = {}

    self.vert_file_list["battle_role"] = "res/shader/battle_role.vert"
    self.frag_file_list["battle_role"] = "res/shader/battle_role.frag"

    self.vert_file_list["tile"] = "res/shader/common.vert"
    self.frag_file_list["tile"] = "res/shader/tile.frag"

    self.programs["battle_role"] = cc.GLProgram:createWithFilenames(self.vert_file_list["battle_role"], self.frag_file_list["battle_role"])
    self.programs["battle_role"]:retain()

    self.programs["tile"] = cc.GLProgram:createWithFilenames(self.vert_file_list["tile"], self.frag_file_list["tile"])
    self.programs["tile"]:retain()

    local listener = cc.EventListenerCustom:create("event_renderer_recreated", function()
        print("EVENT_RENDERER_RECREATED")
        self:Reload()
    end)

    cc.Director:getInstance():getEventDispatcher():addEventListenerWithFixedPriority(listener, 1)
end

function shader_manager:GetProgram(name)
    return self.programs[name]
end

function shader_manager:Reload()

    for name, program in pairs(self.programs) do
        program:reset()

        program:initWithFilenames(self.vert_file_list[name], self.frag_file_list[name])

        program:link()
        program:updateUniforms()
    end
end

return shader_manager
