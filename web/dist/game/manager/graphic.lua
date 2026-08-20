local event_listener = require "utils.event_listener"
local graphic = {}

graphic["EVENT_TYPE"] =
{

}

function graphic:Init()
    self.event_listener = event_listener.New("multi")
end

function graphic:RegisterEvent(event_name, handler)
    return self.event_listener:Register(event_name, handler)
end

function graphic:DispatchEvent(event_name, ...)
    self.event_listener:Dispatch(event_name, ...)
end

function graphic:UnregisterEvent(event_name, handler_id)
    self.event_listener:Unregister(event_name, handler_id)
end

function graphic:BindEventListener(name)
    self.event_listener = event_listener.New("multi")
end

return graphic
