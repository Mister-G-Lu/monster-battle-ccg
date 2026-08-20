--local proxy = require "util.proxy"

local http_client = {}
local tag = 0
local tagstr = ""

local function GetHost(url)
    return string.match(url, '[^/]+%.[^/]+')
end

function http_client:Init()

    self.response_list = {}
    self.fail_counts = {}
    local connect_timeout = 2
    local timeout = 4


    HttpClient.init(function(status, tagstr, data, url)
        if status ~= 200 and url then
            local host = GetHost(url)
            local fail_counts = self.fail_counts[host]
            self.fail_counts[host] = fail_counts and fail_counts + 1 or 1
        end

        local response = self.response_list[tagstr]
        if not response then
            return
        end

        self.response_list[tagstr] = nil

        response(status, data)
    end, connect_timeout, timeout)
end

function http_client:Post(url, request_content, response)

    tag = tag + 1
    tagstr = tostring(tag)

    self.response_list[tagstr] = response
    print(url..request_content, tagstr)
    HttpClient.post(url, request_content, tagstr, "")
end

function http_client:Get(url, response)

    tag = tag + 1
    tagstr = tostring(tag)

    self.response_list[tagstr] = response
    HttpClient.get(url, tagstr, "")
end

do
    http_client:Init()
end

return http_client
