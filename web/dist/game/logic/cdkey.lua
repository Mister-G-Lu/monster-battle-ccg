local network = require "manager.network"
local graphic = require "manager.graphic"

local meta = {}

function meta:Init()

	self:RegisterMsgHandler()
end

function meta:ReqCdkeyAward(cdkey_code)
	network:Send("req_cdk_reward", { code = cdkey_code}, function (result, recv_msg)
		graphic:DispatchEvent("show_cdkey_result", result, recv_msg)
	end)
end

--推送
function meta:RegisterMsgHandler()

end

return meta
