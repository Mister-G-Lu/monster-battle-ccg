local json = require "utils.json"

local configuration = {}

function configuration:Init()

    local template = {
        account = nil,
        password = nil,
        version = nil,
        locale = "zh-CN",
        has_account = false,
        version = nil,
        user_id = nil,
    }

    self.json_obj = {}

    self.path = self:GetConfigPath()

    local fp = io.open(self.path, "r")
    if not fp then
        fp = io.open(self.path, "w")
        fp:close()
        return
    end

    local content = fp:read("*a")
    fp:close()

    if string.len(content) ~= 0 then
        self.json_obj = json:decode(content)
    end

    for k,v in pairs(template) do
        if self.json_obj[k] == nil then
            self.json_obj[k] = v
        end
    end
end

function configuration:HasAccount()
    return self.json_obj["has_account"]
end

function configuration:SetAccountAndPwd(account, password)
    self.json_obj["account"] = account
    self.json_obj["password"] = password
    self.json_obj["has_account"] = true
end

function configuration:GetAccountAndPwd()
    return self.json_obj["account"], self.json_obj["password"]
end

-- 获取语言
function configuration:GetLocale()
    return self.json_obj["locale"]
end

-- 设置语言
function configuration:SetLocale(locale)
    self.json_obj["locale"] = locale
end

function configuration:SetVersion(v)
    self.json_obj["version"] = v
end

function configuration:GetVersion()
    return self.json_obj["version"]
end

function configuration:SetUserId(user_id)
    self.json_obj["user_id"] = user_id
end

function configuration:GetUserId()
    return self.json_obj["user_id"]
end

function configuration:SetSessionId(session_id)
    self.json_obj["session_id"] = session_id
end

function configuration:GetSessionId()
    return self.json_obj["session_id"]
end

function configuration:SetWECHATIsBanded(isBanded)
    self.json_obj["wechat_band"] = isBanded
end

function configuration:GetWECHATIsBanded()
    return self.json_obj["wechat_band"]
end

function configuration:SetQQIsBanded(isBanded)
    self.json_obj["qq_band"] = isBanded
end

function configuration:GetQQIsBanded()
    return self.json_obj["qq_band"]
end

function configuration:SetFBIsBanded(isBanded)
    self.json_obj["fb_band"] = isBanded
end

function configuration:GetFBIsBanded()
    return self.json_obj["fb_band"]
end

function configuration:SetGGIsBanded(isBanded)
    self.json_obj["gg_band"] = isBanded
end

function configuration:GetGGIsBanded()
    return self.json_obj["gg_band"]
end

function configuration:SetGCIsBanded(isBanded)
    self.json_obj["gc_band"] = isBanded
end

function configuration:GetGCIsBanded()
    return self.json_obj["gc_band"]
end

function configuration:SetNeedShowLoginBtn(isShow)
    self.json_obj["lb_isShow"] = isShow
end

function configuration:GetNeedShowLoginBtn()
    return self.json_obj["lb_isShow"]
end

function configuration:IsShowHelp()
    return self.json_obj["is_show_help"] or false
end

function configuration:SetShowHelp(is_bool)
    self.json_obj["is_show_help"] = true
    self:Save()
end

-- 配置写入
function configuration:Save()
    --清空文件，然后重新写入
    local str = json:encode(self.json_obj)
    if str then
        local fp = io.open(self.path, "w+")

        if fp then
            fp:write(str)
            fp:close()
        else
            print("出错了。。。。")
        end
    end
end

-- 获取配置文件地址
function configuration:GetConfigPath()
    local platform = cc.Application:getInstance():getTargetPlatform()

    local path = ""
    if platform == cc.PLATFORM_OS_WINDOWS then
        path = "src/config.conf"
    elseif platform == cc.PLATFORM_OS_LINUX or platform == cc.PLATFORM_OS_MAC then
        path = "./config.conf"
    else
        path = cc.FileUtils:getInstance():getWritablePath()
        path = path  .. "config.conf"
    end
    return path
end


return configuration
