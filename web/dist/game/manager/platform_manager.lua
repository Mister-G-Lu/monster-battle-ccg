local meta = {}

local TARGET_PLATFORM = cc.Application:getInstance():getTargetPlatform()

function meta:Init()
    if not _G["LOAD_CHANNEL_FILE"] then
        if TARGET_PLATFORM == cc.PLATFORM_OS_IPHONE or TARGET_PLATFORM == cc.PLATFORM_OS_IPAD or TARGET_PLATFORM == cc.PLATFORM_OS_ANDROID then
            local str = aandm.getDataFromFile("channel.txt")
            local str_iter = string.gmatch(str, "[^%s]+=([^%s]+)")

            local app_key = str_iter()
            local channel = str_iter()

            local adsensor_key = str_iter()
            local adsensor_channel = str_iter()

            local adtracking_key = str_iter()
            local adtracking_channel = str_iter()

            if app_key and channel then
                local analytics_manager = require "manager.analytics"
                analytics_manager:Init(app_key, channel)
            end

            _G["CHANNEL"] = channel
            _G["LOAD_CHANNEL_FILE"] = true
        end
    end
end

function meta:GetChannelName()
    if device.platform == "ios" then
        local str = aandm.getDataFromFile("channel.txt")
        local str_iter = string.gmatch(str, "[^%s]+=([^%s]+)")
        local app_key = str_iter()
        local channel = str_iter()
        return channel
    elseif device.platform == "android" then
        if ThirdHelper and ThirdHelper["getChannelName"] then
            return ThirdHelper["getChannelName"]()
        end
    end

    return ""
end

return meta
