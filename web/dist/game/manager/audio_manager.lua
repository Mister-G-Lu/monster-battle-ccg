local AudioManager = AudioManager

local EFFECT = {}
local MUSIC = {}

local audio_manager = {}

function audio_manager:Init()
    self.music_volume = 0.7
    self.effect_volume = 0.7
    self.cur_music = nil
    self.cur_music_id = cc.AUDIO_INVAILD_ID
    self.cur_effect_id = cc.AUDIO_INVAILD_ID
end

function audio_manager:PlayMusic(music_type, loop)
    if loop == nil then
        loop = false
    end

    if self.cur_music == music_type then
        return
    end

    if self.cur_music_id ~= cc.AUDIO_INVAILD_ID then
        ccexp.AudioEngine:stop(self.cur_music_id)
        self.cur_music_id = cc.AUDIO_INVAILD_ID
    end
    local sound_path = "res/sound/" .. music_type .. ".mp3"
    self.cur_music = music_type
    self.cur_music_id = ccexp.AudioEngine:play2d(sound_path, true, self.music_volume)
end

function audio_manager:PlayEffect(effect_type, loop)
    if loop == nil then
        loop = false
    end
    local sound_path = "res/sound/" .. effect_type .. ".mp3"
    self.cur_effect_id = ccexp.AudioEngine:play2d(sound_path, loop, self.effect_volume)
end

function audio_manager:StopMusic()
    ccexp.AudioEngine:stop(self.cur_music_id)
    self.cur_music_id = cc.AUDIO_INVAILD_ID

end

function audio_manager:StopEffect(effect_type)
    -- AudioManager.stopEffect(EFFECT[effect_type])
end

function audio_manager:SetMusicMute(mute)
    -- AudioManager.setMusicMute(mute)
end

-- 设置特效禁音
function audio_manager:SetEffectMute(mute)
    -- AudioManager.setEffectMute(mute)
end

-- 获取当前音乐
function audio_manager:GetCurrentMusic()
    return self.cur_music
end

-- 停止当前音乐
function audio_manager:StopCurrentMusic()
    if self.cur_music then
        self:StopMusic()
        self.cur_music = nil
    end
end



return audio_manager
