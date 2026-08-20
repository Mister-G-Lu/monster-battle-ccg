local crypt = require "crypt"
local md5 = require "md5"
local config = require "manager.configuration"

local TARGET_PLATFORM = cc.Application:getInstance():getTargetPlatform()

local error_tracer = {}
function error_tracer:Init()
    self.upload_time = 0
    self.has_error = false
    self.logic_err = ""
    self.download_err = ""
    self.upload_delay = 0
    self.upload_count = 1
    self.can_upload = TARGET_PLATFORM == cc.PLATFORM_OS_IPHONE or TARGET_PLATFORM == cc.PLATFORM_OS_IPAD or TARGET_PLATFORM == cc.PLATFORM_OS_ANDROID
end

function error_tracer:SetUpdateDelay(Delay)
    self.upload_delay = Delay
end

function error_tracer:GetUpdateDelay()
    return self.upload_delay
end

function error_tracer:PushErrorInfo(content)
    if not self.has_error then
        self.upload_time = os.time() + self.upload_delay
    end
    self.logic_err = self.logic_err .. "\n" .. content

    self.has_error = true
end

function error_tracer:Update(elapsed_time)
    if self.has_error and os.time() > self.upload_time and self.can_upload then
        self:UploadCrash()
    end
end

function error_tracer:UploadCrash()
    if not self.has_error then
        return
    end

    if self.upload_count > 3 then
        return
    end

    local account_id, _ = config:GetAccountAndPwd()
    local user_id = config:GetUserId()

    local cur_time = os.time()
    local cur_time_info = os.date("!*t", cur_time)
    local time = cur_time + 86400 * 3

    -- local channel_info = platform_manager:GetChannelInfo()
    local dir = "/cm/crash/all/"

    -- if channel_info.enable_error_folder then
    --     dir = "/cm/crash/" .. channel_info.name
    -- end

    if user_id then
        error_file = user_id
    elseif account_id then
        error_file = tostring(account_id)
    else
        error_file = "no_info/" .. cur_time
    end

    local path = string.format("%s/%d%02d%02d/%s.txt", dir, cur_time_info.year, cur_time_info.month, cur_time_info.day, error_file)

    local api_secret = "94fdB9SYWEQqaBA4hC3BhVwRiHs="
    local b = string.format('{"bucket":"adventure-mobile","expiration":%d,"save-key":"%s"}', time, path)
    local policy = crypt.base64encode(b)

    local k = md5.sum(policy .. "&" .. api_secret)
    local signature = string.gsub(k, ".", function (c)
        return string.format("%02x", string.byte(c))
    end)

    local writable_path = cc.FileUtils:getInstance():getWritablePath()
    local local_file_path = writable_path .. "error.txt"
    local file = io.open(local_file_path, "w")
    file:write(self.logic_err)
    file:close()

    self.has_error = false
    self.upload_count = self.upload_count + 1

    local url = "http://v0.api.upyun.com/adventure-mobile"
    aandm.uploadCrash(url, local_file_path, policy, signature)
end


return error_tracer
