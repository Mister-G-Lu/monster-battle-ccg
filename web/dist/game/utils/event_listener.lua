local one_to_one_listener = {}
one_to_one_listener.__index = one_to_one_listener

function one_to_one_listener:Register(event_name, handler)
    self[event_name] = handler
end

function one_to_one_listener:Dispatch(event_name, ...)
    local handler = self[event_name]
    if handler then
        handler(...)

    else
        --print(event_name .. '    handler not found')
    end
end

local one_to_multi_listener = {}
one_to_multi_listener.__index = one_to_multi_listener

function one_to_multi_listener:Register(event_name, handler)
    local handler_list = self.handlers[event_name]
    if not handler_list then
        handler_list = {max_num = 0}
        self.handlers[event_name] = handler_list
    end

    local insert = false
    for i = 1, handler_list.max_num do
        if not handler_list[i] then
            handler_list[i] = handler
            return i
        end
    end

    table.insert(handler_list, handler)
    handler_list.max_num = handler_list.max_num + 1

    return handler_list.max_num
end

function one_to_multi_listener:Dispatch(event_name, ...)
    local handler_list = self.handlers[event_name]
    if not handler_list then
        return
    end

    for i = 1, handler_list.max_num do
        local handler = handler_list[i]
        if handler then
            handler(...)
        end
    end
end

function one_to_multi_listener:Unregister(event_name, handler_id)
    local handler_list = self.handlers[event_name]
    if handler_list then
        handler_list[handler_id] = nil
    end
end

local event_listener = {}
function event_listener.New(type)

    local new_event_listener = {}

    if type == "multi" then
        new_event_listener.handlers = {}
        setmetatable(new_event_listener, one_to_multi_listener)

    else
        setmetatable(new_event_listener, one_to_one_listener)
    end

    return new_event_listener
end

return event_listener
