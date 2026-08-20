local meta = {}

function meta:Init()

    self.event_listener = (require "utils.event_listener").New()

    if ThirdHelper ~= nil and ThirdHelper["singIn"] ~= nil and ThirdHelper["singOut"] ~= nil then
        PlatformSDK.registerLuaHandler(function(event_type, ...)
            self.event_listener:Dispatch(event_type, ...)
        end)
    end
end

function meta:RegisterEvent(event_type, handler)
    self.event_listener:Register(event_type, handler)
end

function meta:DispatchEvent(event_type, ...)
    self.event_listener:Dispatch(event_type, ...)
end

function meta:getPlatformType()
	if device.platform == "ios" then
		return 1
	else
		return 0
	end
end

return meta