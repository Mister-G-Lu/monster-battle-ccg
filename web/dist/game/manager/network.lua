local socket = require "socket"
local crypt = require "crypt"
local bit = require "bit"
local event_listener = require "utils.event_listener"
local json = require "utils.json"
local timer = require "manager.time"

require "utils.protobuf"

local protobuf = protobuf

-- OFFLINE MODE
-- ============
-- The original client talks to the mu77 game server over TCP. This build
-- replaces that transport with an in-process server (manager.offline_server)
-- so the game runs as a single-player campaign with no Internet connection.
-- The public API (Connect/Send/Update/HeartBeat/RegisterCommand/...) keeps
-- its original shape, so every logic module works unchanged.
OFFLINE_MODE = true

local NET_STATUS =
{
    ["unconnected"] = 1,
    ["try_connect"] = 2,
    ["connected"] = 3,
    ["lost_connection"] = 4,
}

local HEART_BEAT_DELAY = 15

local HEADER_SIZE = 2

local str_char = string.char
local bit_rshift = bit.rshift
local bit_band = bit.band

-- In offline mode the server module is required lazily to avoid a circular
-- require (manager.offline_server requires manager.network at load time).
local function GetOfflineServer()
    return require "manager.offline_server"
end

local function unpack_package(text)
    local size = #text

    if size < HEADER_SIZE then
        return nil, text
    end

    local s = text:byte(1) * 256 + text:byte(2)
    if size < s + HEADER_SIZE then
        return nil, text
    end

    return text:sub(3, 2 + s), text:sub(3 + s)
end

local network = {}

function network:Init()
    self.event_listener = event_listener.New()
    self:Clear()
end

function network:RegisterProto()
    -- local buff = aandm.getDataFromFile("common/client.pb")
    local buff = aandm.getDataFromFile("common/server.pb")
    protobuf.register(buff)
end

function network:SetTime()

    self.next_heart_beat_time = timer:Now() + HEART_BEAT_DELAY
end

function network:Clear()
    self.last_content = ""
    self.socket = nil

    self.status = NET_STATUS["unconnected"]
    self.session = 1
    self.push_number = 1

    -- <request name, session record>
    self.req_record_map = {}
    -- <session, handler>
    self.callback_map = {}
    self.waiting_heart_beat_response = false

    self.ping_num = 0
    self.ping_total_time = 0
    self.ping_time = 0
end

function network:ResetSession()
    self.session = 1
    self.push_number = 1
    self.ping_time = 0
end

-- Set heartbeat delay
function network:SetHeartBeatDelay(time)
    HEART_BEAT_DELAY = time
    self.next_heart_beat_time = timer:Now() + HEART_BEAT_DELAY
end

function network:Connect(ip, port)
    print("[NETWORK] Connect(" .. tostring(ip) .. ", " .. tostring(port) .. ") OFFLINE_MODE=" .. tostring(OFFLINE_MODE))
    if OFFLINE_MODE then
        -- In-process server: "connecting" just (re)initializes it.
        GetOfflineServer():Init()
        self.socket = nil
        self.status = NET_STATUS["connected"]
        self.server_ip = ip
        self.server_prot = port
        return nil, self.status
    end

    if self:IsConnected() then
        self:Disconnect()
    end

    self.socket = socket.tcp6()

    if self.status == NET_STATUS["unconnected"] then
        self.socket:settimeout(6)
    else
        self.socket:settimeout(3)
    end
    local status, err = self.socket:connect(ip, port)

    if err then
        self.socket:settimeout(0)
        self.status = NET_STATUS["unconnected"]
        self.socket:close()
        err = nil                           -- tcp6ʧ?ܾͳ??tcp4
        self.socket = socket.tcp()
        if self.status == NET_STATUS["unconnected"] then
            self.socket:settimeout(6)
        else
            self.socket:settimeout(3)
        end

        status, err = self.socket:connect(ip, port)
        if err then
            self.status = NET_STATUS["unconnected"]
            print(err .. "tcp4")
        else
            self.socket:settimeout(0)
            self.status = NET_STATUS["connected"]
            self.server_ip = ip
            self.server_prot = port
        end
    else
        self.socket:settimeout(0)
        self.status = NET_STATUS["connected"]
        self.server_ip = ip
        self.server_prot = port
    end

    return err, self.status
end

-- Reconnect last server
function network:Reconnect()
    if OFFLINE_MODE then
        return nil, self.status
    end
    return self:Connect(self.server_ip, self.server_prot)
end

-- Resend queued requests after disconnect
function network:SendRecordMsg()
    if OFFLINE_MODE then
        return
    end
    if not self:IsConnected() then
        return
    end
    -- resend queued requests after reconnect
    for req_name, record_info in pairs(self.req_record_map) do
        local session = record_info.session
        local post_data = record_info.post_data
        print("resend after reconnect req_name = "..req_name, tostring(post_data))
        local t = protobuf.encode("GS2C", post_data)
        local size = #t
        local buf = string.char(bit_band(bit_rshift(size, 8), 0xff)) .. string.char(bit_band(size, 0xff)) .. t
        local i, err = self.socket:send(buf)
        if err then
            print("reconnect send err", err)
            if err == "closed" then
                self:Disconnect(NET_STATUS["lost_connection"])
            end
        end
    end
end


function network:IsConnected()
    return self.status == NET_STATUS["connected"]
end

function network:Disconnect(net_status)
    if OFFLINE_MODE then
        -- offline server never loses the connection; keep state intact
        return
    end

    if self.socket then
        self.socket:close()
    end

    self.socket = nil

    self.last_content = ""
    self.status = net_status or NET_STATUS["unconnected"]
    self.waiting_heart_beat_response = false
end


function network:Update()
    if OFFLINE_MODE then
        -- every request is answered synchronously inside network:Send
        return
    end

    if self.status == NET_STATUS["connected"] then
        local chunck, status, partial = self.socket:receive("*a")
        if status and status ~= "timeout" then
            print("net status ", status)
            self:Disconnect(NET_STATUS["lost_connection"])
            return
        end

        if partial and #partial ~= 0 then
            self.last_content = self.last_content .. partial
        elseif chunck then
            self.last_content = self.last_content .. chunck
        end

        local result
        result, self.last_content = unpack_package(self.last_content)
        if result then
            local msg_name, msg_content
            local msg = protobuf.decode2("GS2C", result)
            local cur_session = msg["session"]
            self.next_heart_beat_time = timer:Now() + HEART_BEAT_DELAY
            if cur_session > 0 then
                for k, v in pairs(msg) do
                    if k == "session" then
                        cur_session = v
                    else
                        msg_name = k
                        msg_content = v
                    end
                end

                local func_info = self.callback_map[cur_session]
                if func_info then
                    local callback = func_info.callback
                    local req_name = func_info.req_name
                    if msg_name == "result" and msg_content.status == "user_is_offline" then
                        -- user offline: reconnect then resend last request
                        self.waiting_heart_beat_response = false
                        self:Disconnect(NET_STATUS["try_connect"])
                    else
                        self.req_record_map[req_name] = nil
                        if callback then
                            if msg_name == "result" then
                                callback(msg_content.status)
                            else
                                callback("success", msg_content)
                            end
                            self.callback_map[cur_session] = nil
                        else
                            print("cur_session = "..cur_session.." no callback found")
                        end
                    end
                else
                    print("cur_session = "..cur_session)
                end
            else
                local push_number = msg["push_number"] or self.push_number
                msg["push_number"] = nil
                if push_number == self.push_number then
                    -- same push id: handle it
                    for k, v in pairs(msg) do
                        if k ~= "session" then
                            self.event_listener:Dispatch(k, v or {})
                        end
                    end
                    self.push_number = push_number + 1
                elseif push_number < self.push_number then
                    -- older push id: duplicate, drop
                    print("push_number is repeat > ", push_number, self.push_number)
                    for k, v in pairs(msg) do
                        print("k >>"..k, tostring(v))
                    end
                elseif push_number > self.push_number then
                    -- gap in push ids: ask server to resend
                    print("packet loss 》》》", push_number, self.push_number)
                    self.next_heart_beat_time = timer:Now() - 1
                    self:HeartBeat()
                end
            end
        end
    end
end

-- Heartbeat
function network:HeartBeat()
    if OFFLINE_MODE then
        return
    end

    if not self:IsConnected() then
        return
    end

    if self.waiting_heart_beat_response then
        if timer:Now() > (self.heart_beat_time + HEART_BEAT_DELAY) then
            self.waiting_heart_beat_response = false
            self:Disconnect(NET_STATUS["try_connect"])
        end
    else
        if timer:Now() < self.next_heart_beat_time then
            return
        end

        local now_time = os.clock()
        self:Send("heart_beat", { push_number = self.push_number }, function ()
            self.waiting_heart_beat_response = false
            self.ping_time = os.clock() - now_time
        end)

        self.waiting_heart_beat_response = true
        self.heart_beat_time = timer:Now()
    end
end

-- Get ping time
function network:GetPingTimer()
    return self.ping_time
end

-- Send request
-- @msg message body
-- @callback callback
function network:Send(req_name, ...)
    local param1 = select(1, ...)
    local param2 = select(2, ...)
    local req_key = select(3, ...)
    local callback = nil
    local msg = {}
    if type(param1) == "function" then
        msg[req_name] = {}
        callback = param1
    else
        msg[req_name] = param1
        callback = param2
    end

    if req_name == "req_reconnect_game" then
        self.req_record_map[req_name] = nil
    end

    -- connection check is the caller's job
    if not self:IsConnected() then
        if callback then callback("lost_connection") end
        return
    end

    req_key = req_key or req_name
    if self.req_record_map[req_key] then
        print("duplicate request req_name = "..req_key, tostring(msg[req_name]))
        return
    end

    -- outbound request gets a session id
    self.session = self.session + 1
    if self.session <= 0 then
        self.session = 1
    end

    if OFFLINE_MODE then
        -- Answer the request directly with the in-process server. The
        -- callback receives the same ("success", content) / (status) shapes
        -- the real server's response dispatch produced. Note: the server may
        -- fire pushes (DispatchCommand) synchronously while handling, and the
        -- callback may itself send new requests, so clear the record first.
        self.req_record_map[req_key] = {
            post_data = msg,
            session = self.session
        }
        local handler = function(result, content)
            self.req_record_map[req_key] = nil
            if callback then
                callback(result, content)
            end
        end
        GetOfflineServer():HandleRequest(req_name, msg[req_name] or {}, handler)
        return true
    end

    msg.session = self.session
    local t = nil
    if req_name == "req_login_game" or req_name == "req_reconnect_game" then
        local special_data = {}
        special_data["session"] = self.session
        special_data["req_name"] = req_name
        table.merge(special_data, msg[req_name])
        t = json:encode(special_data)
    else
        t = protobuf.encode("GS2C", msg)
    end
    local size = #t
    local buf = string.char(bit_band(bit_rshift(size, 8), 0xff)) .. string.char(bit_band(size, 0xff)) .. t

    local i, err = self.socket:send(buf)
    if err then
        print("send err", err)
        if err == "closed" then
            self:Disconnect(NET_STATUS["lost_connection"])
        end
        callback("lost_connection")
    else
        self.req_record_map[req_key] = {
            post_data = msg,
            session = self.session
        }
        self.callback_map[self.session] = {
            req_name = req_key,
            callback = callback
        }
    end
    return true
end


function network:RegisterCommand(msg_name, handler)
    self.event_listener:Register(msg_name, handler)
end

function network:DispatchCommand(msg_name, msg_content)
    self.event_listener:Dispatch(msg_name, msg_content)
end

-- Has lost connection
function network:HasLostConnection()
    if OFFLINE_MODE then
        return false
    end
    return self.status == NET_STATUS["lost_connection"]
end

-- Is trying to reconnect
function network:HasTryConnection()
    if OFFLINE_MODE then
        return false
    end
    return self.status == NET_STATUS["try_connect"]
end

function network:ResetTryConnection()
    if OFFLINE_MODE then
        return
    end
    self.status = NET_STATUS["try_connect"]
end

do
    network:Init()
end

return network
