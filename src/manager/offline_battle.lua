local bit = require "bit"
local bit_band = bit.band
local bit_lshift = bit.lshift
-- offline_battle.lua
-- Single-player battle engine. Re-implements the server-side battle rules
-- (cards, powers, statuses, rounds, combat) and emits the same cmd_battle
-- commands the client animates. The opponent is driven by a simple AI.

local constants = require "common.constants"

local CARD_TYPE = constants.CARD_TYPE
local POWER_NAME = constants.POWER_NAME
local STATUS_TYPE = constants.STATUS_TYPE
local BATTLE_SLOT_MAX = constants.BATTLE_SLOT_MAX
local IMMOLATION = constants.CARD_IMMOLATION_CRYSTAL

local MAX_ROUNDS = 50  -- force game over after this many rounds to prevent infinite battles

local offline_battle = {}

-- =====================================================================
-- Card helpers
-- =====================================================================

-- Build a CardInfo message (msg.card.CardInfo) from a card model config.
-- @config  a row from data_template.card_config (keyed by model id string)
-- @uid     unique card instance id
function offline_battle.BuildCardInfo(config, uid, hand_pos, user_id)
    local power_list = {}
    if config and config.power_list then
        for _, p in ipairs(config.power_list) do
            table.insert(power_list, {
                name = p.name,
                value = tonumber(p.value) or 0,
                target_type = p.target_type or "",
                type = p.type or "passive",
            })
        end
    end
    local card = {
        id = tonumber(uid) or tonumber(config and config.uid) or 0,
        uid = tostring(uid),
        name = (config and config.name) or "",
        hp = tonumber(config and config.hp) or 0,
        cost = tonumber(config and config.cost) or 0,
        type = (config and config.type) or "monster",
        quality = (config and config.quality) or "normal",
        kind = tonumber(config and config.kind) or 0,
        power_list = power_list,
        level = tonumber(config and config.level) or 1,
        strength = tonumber(config and config.score) or 0,
        res_path = (config and config.res_path) or "",
        hand_pos = hand_pos or 0,
    }
    if user_id then
        card.user_id = user_id
    end
    return card
end

-- =====================================================================

local battle_model = require "manager.offline_battle_model"
local Actor = battle_model.Actor
local Slot = battle_model.Slot

-- Battle engine
-- =====================================================================

-- @opts: { battle_id, battle_type, battle_object_type, pve_info = {play_id, difficulty, pve_win_cur_value},
--          own_deck = {monster_list={CardInfo}, item_list={CardInfo}},
--          enemy_deck = {monster_list={CardInfo}, item_list={CardInfo}},
--          own_name, enemy_name, enemy_arena_level }
function offline_battle.New(opts, emit)
    local self = {}
    setmetatable(self, { __index = offline_battle })
    self.opts = opts
    self.emit = emit or function() end  -- called with a Command table
    self.battle_id = opts.battle_id or "offline_" .. math.random(100000, 999999)
    self.round = 0
    self.is_over = false
    self.win_user_id = nil
    self.pve_win_cur_value = (opts.pve_info and opts.pve_info.pve_win_cur_value) or 0
    self.pve_win_target = opts.pve_win_target or 0

    -- Campaign hero-HP duel (The Shadow Road). When opts.campaign is present
    -- the battle is decided by commander HP instead of the monster-count
    -- model: creatures with no blocker strike the enemy commander, killing
    -- blows spill overkill damage onto the commander, and elite/boss
    -- scripted powers run on the enemy turn.
    self.campaign = opts.campaign
    self.hero_mode = self.campaign ~= nil
    self.own_hp = 0
    self.own_max_hp = 0
    self.enemy_hp = 0
    self.enemy_max_hp = 0
    self.gathering = 0
    self.power = self.campaign and self.campaign.power or nil
    self.power_phase2 = false
    self.phase2_applied = false
    self.power_used = false
    self.hero_dirty = false
    if self.hero_mode then
        self.own_max_hp = tonumber(self.campaign.player_hp) or 30
        self.own_hp = self.own_max_hp
        self.enemy_max_hp = tonumber(self.campaign.enemy_hp) or 20
        self.enemy_hp = self.enemy_max_hp
    end

    self.own = Actor.New("player", opts.own_name or "Player")
    self.enemy = Actor.New("enemy", opts.enemy_name or "Enemy")
    self.own.is_ai = false
    self.enemy.is_ai = true

    -- load decks
    local function load_actor(actor, deck)
        deck = deck or { monster_list = {}, item_list = {} }
        actor.monster_card = {}
        actor.item_card = {}
        for _, c in ipairs(deck.monster_list or {}) do
            table.insert(actor.monster_card, c)
        end
        for _, c in ipairs(deck.item_list or {}) do
            table.insert(actor.item_card, c)
        end
        actor.monster_len = #actor.monster_card
        actor.item_len = #actor.item_card
        -- shuffle
        local function shuffle(t)
            for i = #t, 2, -1 do
                local j = math.random(i)
                t[i], t[j] = t[j], t[i]
            end
        end
        shuffle(actor.monster_card)
        shuffle(actor.item_card)
        -- initial hand: 2 monsters + 2 items
        actor:SetHandCard(1, actor:DrawCard(CARD_TYPE.monster))
        actor:SetHandCard(2, actor:DrawCard(CARD_TYPE.monster))
        actor:SetHandCard(3, actor:DrawCard(CARD_TYPE.item))
        actor:SetHandCard(4, actor:DrawCard(CARD_TYPE.item))
    end
    load_actor(self.own, opts.own_deck)
    load_actor(self.enemy, opts.enemy_deck)

    -- strength
    self.own.strength = self:CalcStrength(self.own)
    self.enemy.strength = self:CalcStrength(self.enemy)
    self.enemy.arena_level = opts.enemy_arena_level or 1

    return self
end

function offline_battle:CalcStrength(actor)
    local s = 0
    for _, c in ipairs(actor.monster_card) do s = s + (c.strength or 0) end
    for _, c in ipairs(actor.item_card) do s = s + (c.strength or 0) end
    for i = 1, 4 do
        local c = actor.hand_card[i]
        if c then s = s + (c.strength or 0) end
    end
    return s
end

-- push one battle command
function offline_battle:PushCommand(name, data)
    local cmd = {}
    cmd[name] = data
    self.emit(cmd)
end

-- =====================================================================
-- Campaign: hero HP + scripted-power plumbing
-- =====================================================================

-- Damage a commander (face hits, Gathering Power, Umbral Toll, overkill).
-- Does not finish the battle directly; CheckGameOver() handles commander
-- HP <= 0 at the end of the current combat/power phase. Commander HP
-- changes are pushed separately via cmd_battle_hero, so no hero_* events
-- ever enter the client's event_list.
function offline_battle:DamageHero(actor, amount)
    if not self.hero_mode or not actor or not amount or amount <= 0 then return end
    if actor == self.own then
        self.own_hp = math.max(0, self.own_hp - amount)
    else
        self.enemy_hp = math.max(0, self.enemy_hp - amount)
        self:CheckCampaignPhase2()
    end
    self.hero_dirty = true
end

-- Heal a commander (Overgrowth / Hungering Dark / Umbral Toll life-gain).
function offline_battle:HealHero(actor, amount)
    if not self.hero_mode or not actor or not amount or amount <= 0 then return 0 end
    local healed = 0
    if actor == self.own then
        healed = math.min(amount, self.own_max_hp - self.own_hp)
        self.own_hp = self.own_hp + healed
    else
        healed = math.min(amount, self.enemy_max_hp - self.enemy_hp)
        self.enemy_hp = self.enemy_hp + healed
    end
    if healed > 0 then
        self.hero_dirty = true
    end
    return healed
end

-- push the current commander HP totals to the client (cmd_battle_hero)
function offline_battle:PushHeroSync()
    if not self.hero_mode then return end
    self.hero_dirty = false
    self:PushCommand("cmd_battle_hero", {
        own_user_id = self.own.user_id,
        own_hp = self.own_hp,
        own_max_hp = self.own_max_hp,
        enemy_user_id = self.enemy.user_id,
        enemy_hp = self.enemy_hp,
        enemy_max_hp = self.enemy_max_hp,
    })
end

-- full board re-sync (used to reveal tokens the scripted powers summon)
function offline_battle:PushBoardSync(cur_user_id)
    local function actor_info(actor)
        local slots = {}
        for i = 1, BATTLE_SLOT_MAX do
            local s = actor.battle_slot[i]
            if s and s.monster then
                table.insert(slots, {
                    pos = i,
                    monster = s.monster,
                    item = s.item,
                    cur_hp = s.cur_hp,
                    cur_ad = s.cur_ad,
                })
            end
        end
        local hand = {}
        for i = 1, 4 do
            local c = actor.hand_card[i]
            if c then table.insert(hand, c) end
        end
        return {
            user_id = actor.user_id,
            crystal = actor.cur_crystal,
            monster_size = actor.monster_len,
            item_size = actor.item_len,
            hand_card_list = hand,
            battle_slot_list = slots,
        }
    end
    self:PushCommand("cmd_battle_sync", {
        cur_oper_user_id = cur_user_id or self.enemy.user_id,
        last_oper_time = os.time(),
        is_sacrifice = false,
        sync_actor_list = { actor_info(self.own), actor_info(self.enemy) },
    })
end

-- summon a scripted token into an empty enemy lane (or any actor's lane)
function offline_battle:SummonToken(actor, token_key)
    local campaign_data = require "manager.campaign_data"
    local cfg = campaign_data.TOKENS[token_key]
    if not cfg then return false end
    local pos = actor:GetCurMonsterSlotPos()
    if pos == 0 then return false end
    local uid = "tok_" .. token_key .. "_" .. self.round .. "_" .. math.random(1000, 9999)
    local card = offline_battle.BuildCardInfo(cfg, uid, nil, actor.user_id)
    self:DeployMonster(actor, card, pos)
    return true
end

-- permanently raise every enemy creature's attack by `amount`
function offline_battle:AddEnemyBoardAttack(amount)
    local n = 0
    for i = 1, BATTLE_SLOT_MAX do
        local s = self.enemy.battle_slot[i]
        if s and s.monster then
            s:AddAttack(amount)
            n = n + 1
        end
    end
    return n
end

-- =====================================================================
-- Public flow
-- =====================================================================

-- Start a battle. Emits the initial command sequence.
function offline_battle:Start()
    self.round = 1
    self.own.cur_crystal = self.round
    self.enemy.cur_crystal = self.round

    self:PushCommand("cmd_battle_start", {
        room_id = "offline",
        map_id = 0,
        battle_id = self.battle_id,
        start_type = nil,
        battle_type = self.opts.battle_type or "pve",
        battle_status = 3,
        battle_object_type = self.opts.battle_object_type or "pve",
        pve_battle_info = {
            play_id = self.opts.pve_info and self.opts.pve_info.play_id or 0,
            difficulty = self.opts.pve_info and self.opts.pve_info.difficulty or 1,
            pve_win_cur_value = self.pve_win_cur_value,
            -- campaign battles carry the canonical node id through the
            -- start command so the client can render the encounter header
            campaign_node_id = self.opts.pve_info and self.opts.pve_info.campaign_node_id or nil,
        },
    })

    self:PushCommand("cmd_battle_init", {
        first_actor = "player",
        player1 = self:BuildActorMessage(self.own),
        player2 = self:BuildActorMessage(self.enemy),
    })

    self:PushCommand("cmd_battle_round", { round = self.round, effect_list = {} })

    -- campaign hero-HP duel: reveal both commanders' HP before the first prep
    if self.hero_mode then
        self:PushHeroSync()
    end

    self:BeginPrep("player")
end

function offline_battle:BuildActorMessage(actor)
    local hand = {}
    for i = 1, 4 do
        local c = actor.hand_card[i]
        if c then
            c.hand_pos = i
            table.insert(hand, c)
        end
    end
    return {
        user_id = actor.user_id,
        user_name = actor.user_name,
        arena_level = actor.arena_level,
        strength = actor.strength,
        monster_len = actor.monster_len,
        item_len = actor.item_len,
        hand_card = hand,
    }
end

-- Begin the preparation phase for a player ("player" or "enemy")
function offline_battle:BeginPrep(user_id)
    local actor = user_id == self.own.user_id and self.own or self.enemy
    actor.is_sacrifice = true
    -- No turn countdown in the player APK (battle.lua ignores last_oper_time
    -- unless DEV_MODE). Keep a modest deadline so debug HUDs don't show 59:59.
    local deadline = os.time() + (_G["DEV_MODE"] and 90 or 0)
    self:PushCommand("cmd_battle_prepa", {
        user_id = actor.user_id,
        sync_crystal = actor.cur_crystal,
        last_oper_time = deadline,
        is_sacrifice = true,
    })
end

-- Check win/loss. Returns true when battle is over.
function offline_battle:CheckGameOver()
    if self.is_over then
        return true
    end

    -- Campaign hero-HP duel: only commander HP decides the battle.
    if self.hero_mode then
        if self.enemy_hp <= 0 then
            self:FinishBattle("player")
            return true
        end
        if self.own_hp <= 0 then
            self:FinishBattle("enemy")
            return true
        end
        return false
    end

    -- PvE win condition: kill target reached
    if self.opts.battle_object_type == "pve" and self.pve_win_target and self.pve_win_target > 0 then
        if self.pve_win_cur_value >= self.pve_win_target then
            self:FinishBattle("player")
            return true
        end
    end

    -- Player lost all monsters
    if self.own:GetMonsterTotal() == 0 then
        self:FinishBattle("enemy")
        return true
    end
    -- Enemy lost all monsters (non-pve win condition)
    if self.enemy:GetMonsterTotal() == 0 then
        self:FinishBattle("player")
        return true
    end
    return false
end

function offline_battle:FinishBattle(winner_id)
    self.is_over = true
    self.win_user_id = winner_id
    local cmd_over = {
        win_user_id = winner_id,
        arena_info = nil,
        reward_info = {},
        pve_info = nil,
        adventure_info = nil,
        mvp_card_info = nil,
    }
    if self.opts.on_battle_over then
        self.opts.on_battle_over(self, cmd_over)
    end
    self:PushCommand("cmd_battle_over", cmd_over)
end

-- =====================================================================
-- Player requests
-- =====================================================================

-- deploy / use a hand card; returns error string or nil on success
function offline_battle:HandleMove(req)
    if self.is_over then
        return "battle_is_null"
    end
    local src_pos = req.src_pos
    local is_enemy = req.is_enemy
    local target_pos = req.target_pos
    local actor = self.own
    local card = actor:GetHandCard(src_pos)
    if not card then
        return "battle_deploy_hand_null"
    end
    if actor.cur_crystal < card.cost then
        return "battle_crystal_not_enough"
    end
    -- safety: clamp target_pos to valid range
    if target_pos and (target_pos < 1 or target_pos > BATTLE_SLOT_MAX) then
        return "battle_deploy_slot_full"
    end

    if card.type == CARD_TYPE.monster then
        local allow_pos = actor:GetCurMonsterSlotPos()
        if allow_pos == 0 or target_pos > allow_pos then
            return "battle_deploy_slot_full"
        end
        -- deploy
        local slot = self:DeployMonster(actor, card, target_pos)
        -- spend crystal
        actor.cur_crystal = actor.cur_crystal - card.cost
        -- draw replacement
        local new_card = actor:DrawCard(CARD_TYPE.monster)
        actor:SetHandCard(src_pos, new_card)
        self:PushCommand("cmd_battle_move", {
            src_user_id = actor.user_id,
            src_hand_pos = src_pos,
            desc_user_id = actor.user_id,
            desc_slot_pos = target_pos,
            sync_crystal = actor.cur_crystal,
            new_card = new_card,
        })
        return nil

    elseif card.type == CARD_TYPE.equip or card.type == CARD_TYPE.armor then
        local target_slot = nil
        if is_enemy then
            target_slot = self.enemy:GetBattleCard(target_pos)
        else
            target_slot = self.own:GetBattleCard(target_pos)
        end
        if not target_slot or not target_slot.monster then
            return "equip_target_card_is_null"
        end
        -- kind check: "all" kind (6) equips anyone
        local kind = card.kind
        local all_flag = bit_lshift(1, 6)  -- bit 6
        if bit_band(kind, all_flag) == 0 then
            -- must match monster kind bit
            local mkind = target_slot.monster.kind
            if bit_band(mkind, kind) ~= kind then
                return "battle_monster_kind_not_match"
            end
        end
        self:EquipItem(target_slot, card)
        actor.cur_crystal = actor.cur_crystal - card.cost
        local new_card = actor:DrawCard(CARD_TYPE.item)
        actor:SetHandCard(src_pos, new_card)
        self:PushCommand("cmd_battle_move", {
            src_user_id = actor.user_id,
            src_hand_pos = src_pos,
            desc_user_id = target_slot.actor.user_id,
            desc_slot_pos = target_slot.pos,
            sync_crystal = actor.cur_crystal,
            new_card = new_card,
        })
        return nil

    elseif card.type == CARD_TYPE.consume then
        local target_slot = nil
        if is_enemy then
            target_slot = self.enemy:GetBattleCard(target_pos)
        else
            target_slot = self.own:GetBattleCard(target_pos)
        end
        if not target_slot or not target_slot.monster then
            return "battle_consume_deploy_target_fail"
        end
        -- immunity
        if target_slot:HasPower(POWER_NAME.immunity) then
            return "battle_immunity_consume_card"
        end
        local effects = self:ApplyCardPowers(card, target_slot, self.own, target_slot.actor.user_id)
        actor.cur_crystal = actor.cur_crystal - card.cost
        local new_card = actor:DrawCard(CARD_TYPE.item)
        actor:SetHandCard(src_pos, new_card)
        self:PushCommand("cmd_battle_move", {
            src_user_id = actor.user_id,
            src_hand_pos = src_pos,
            desc_user_id = target_slot.actor.user_id,
            desc_slot_pos = target_slot.pos,
            sync_crystal = actor.cur_crystal,
            new_card = new_card,
        })
        -- apply effect events (damage/heal/status...) as attack commands
        self:PushCommand("cmd_battle_attack", { event_list = effects, is_fight_stage = false })
        self:CheckGameOver()
        return nil
    end
    -- crystal floor safety
    if actor.cur_crystal < 0 then actor.cur_crystal = 0 end
    return "battle_deploy_hand_null"
end

-- sacrifice a card: is_hand=true => hand card, false => battle slot card
function offline_battle:HandleSacrifice(req)
    if self.is_over then
        return "battle_is_null"
    end
    if not self.own.is_sacrifice then
        return "sacrifice_error"
    end
    local is_hand = req.is_hand
    local pos = req.pos
    local actor = self.own
    local discard_info_list = {}
    local crystal_gain = 0

    if is_hand then
        local card = actor:GetHandCard(pos)
        if not card then
            return "battle_deploy_hand_null"
        end
        crystal_gain = IMMOLATION[card.type] or 1
        for _, p in ipairs(card.power_list or {}) do
            if p.name == POWER_NAME.crystal then
                crystal_gain = crystal_gain + (tonumber(p.value) or 0)
            end
        end
        -- draw a replacement card into the freed hand slot (the client
        -- expects new_card and puts it at hand_card[pos])
        local new_card = actor:DrawCard(card.type)
        actor:SetHandCard(pos, new_card)
        table.insert(discard_info_list, { is_hand = true, pos = pos, new_card = new_card })
    else
        local slot = actor:GetBattleCard(pos)
        if not slot then
            return "battle_slot_null"
        end
        crystal_gain = IMMOLATION.battle or 1
        table.insert(discard_info_list, { is_hand = false, pos = pos, new_card = nil })
        actor.battle_slot[pos] = nil
        actor:CompactSlots()
    end

    actor.cur_crystal = actor.cur_crystal + crystal_gain
    actor.is_sacrifice = false
    self:PushCommand("cmd_battle_discard", {
        src_user_id = actor.user_id,
        discard_info_list = discard_info_list,
        sync_crystal = actor.cur_crystal,
        effect_list = {},
        is_sacrifice = false,
    })
    self:CheckGameOver()
    return nil
end

-- end the player's turn: enemy acts, then combat runs
function offline_battle:HandleAttack(req)
    if self.is_over then
        return "battle_is_null"
    end
    -- early game-over guard (defense-in-depth)
    if self:CheckGameOver() then
        return nil
    end
    -- safety: force game over if max rounds exceeded
    if self.round >= MAX_ROUNDS then
        if self.hero_mode then
            -- long wars are decided by whoever kept more HP (fraction)
            local p_pct = self.own_hp / math.max(1, self.own_max_hp)
            local e_pct = self.enemy_hp / math.max(1, self.enemy_max_hp)
            if p_pct >= e_pct then
                self:FinishBattle("player")
            else
                self:FinishBattle("enemy")
            end
            return nil
        end
        local own_count = 0
        for i = 1, BATTLE_SLOT_MAX do
            if self.own.battle_slot[i] and self.own.battle_slot[i].monster then
                own_count = own_count + 1
            end
        end
        local enemy_count = 0
        for i = 1, BATTLE_SLOT_MAX do
            if self.enemy.battle_slot[i] and self.enemy.battle_slot[i].monster then
                enemy_count = enemy_count + 1
            end
        end
        if own_count >= enemy_count then
            self:FinishBattle("player")
        else
            self:FinishBattle("enemy")
        end
        return nil
    end
    -- enemy prep: +1 crystal this round was already granted at round start
    self.enemy.is_sacrifice = true
    -- Deadline = now so the "Let me see..." think bubble is not waiting on
    -- a PvP clock that never ticks in offline mode.
    self:PushCommand("cmd_battle_prepa", {
        user_id = self.enemy.user_id,
        sync_crystal = self.enemy.cur_crystal,
        last_oper_time = os.time(),
        is_sacrifice = true,
    })

    -- scripted campaign powers fire at the start of the enemy turn
    if self.hero_mode then
        self:FireCampaignPower()
        if self.hero_dirty then
            self:PushHeroSync()
        end
        if self:CheckGameOver() then
            return nil
        end
    end

    -- AI deploys
    self:AIDoPrep()

    -- combat
    self:RunCombat()

    if self.is_over then
        return nil
    end

    -- reveal any commander HP changes this combat caused
    if self.hero_dirty then
        self:PushHeroSync()
    end

    -- next round
    self.round = self.round + 1
    self.own.cur_crystal = self.own.cur_crystal + 1
    self.enemy.cur_crystal = self.enemy.cur_crystal + 1
    self:PushCommand("cmd_battle_round", { round = self.round, effect_list = {} })
    self:BeginPrep("player")
    return nil
end

function offline_battle:HandleStandby()
    self:PushCommand("cmd_battle_standby", {})
    return nil
end

function offline_battle:HandleSurrender()
    if self.is_over then
        return "battle_is_null"
    end
    self:FinishBattle("enemy")
    return nil
end

-- =====================================================================
-- Deployment helpers
-- =====================================================================

function offline_battle:DeployMonster(actor, card, target_pos)
    local slot = actor.battle_slot[target_pos]
    if slot and slot.monster then
        -- shift existing slots right
        for i = BATTLE_SLOT_MAX - 1, target_pos, -1 do
            if actor.battle_slot[i] then
                actor.battle_slot[i].pos = i + 1
                actor.battle_slot[i + 1] = actor.battle_slot[i]
                actor.battle_slot[i] = nil
            end
        end
    end
    slot = Slot.New(actor, target_pos)
    slot:SetMonster(card)
    actor.battle_slot[target_pos] = slot
    return slot
end

function offline_battle:EquipItem(slot, card)
    slot:SetItem(card)
end

-- =====================================================================
-- Card powers (used by consume cards)
-- =====================================================================

-- Apply a consume card's powers. Returns a list of events.
function offline_battle:ApplyCardPowers(card, target_slot, caster_actor, target_user_id)
    local events = {}
    local power_list = card.power_list or {}
    for _, p in ipairs(power_list) do
        local name = p.name
        local value = tonumber(p.value) or 0
        local tid = target_slot.actor.user_id
        local tpos = target_slot.pos
        if name == POWER_NAME.damage then
            table.insert(events, { type = "anim", tar_user_id = tid, tar_pos = tpos, power_name = name, src_user_id = caster_actor.user_id, src_pos = 0, value = value })
            table.insert(events, { type = "damage", tar_user_id = tid, tar_pos = tpos, value = value })
            self:DamageSlot(target_slot, value, events)
        elseif name == POWER_NAME.damage_all then
            local targets = self:GetAllEnemySlots(target_slot.actor)
            for _, ts in ipairs(targets) do
                table.insert(events, { type = "anim", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, power_name = name, src_user_id = caster_actor.user_id, src_pos = 0, value = value })
                table.insert(events, { type = "damage", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, value = value })
                self:DamageSlot(ts, value, events)
            end
        elseif name == POWER_NAME.heal then
            table.insert(events, { type = "anim", tar_user_id = tid, tar_pos = tpos, power_name = name, src_user_id = caster_actor.user_id, src_pos = 0, value = value })
            self:HealSlot(target_slot, value, events)
        elseif name == POWER_NAME.heal_all then
            local targets = self:GetAllSlots(target_slot.actor)
            for _, ts in ipairs(targets) do
                table.insert(events, { type = "anim", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, power_name = name, src_user_id = caster_actor.user_id, src_pos = 0, value = value })
                self:HealSlot(ts, value, events)
            end
        elseif name == POWER_NAME.entangle then
            -- 50% entangle; prioritizes opposite slot
            if math.random(100) <= 50 and not target_slot:IsStatus(STATUS_TYPE.entangled) then
                target_slot:SetStatus(STATUS_TYPE.entangled, 1, 1)
                table.insert(events, { type = "anim", tar_user_id = tid, tar_pos = tpos, power_name = name, src_user_id = caster_actor.user_id, src_pos = 0, value = value })
                table.insert(events, { type = "status", tar_user_id = tid, tar_pos = tpos, power_name = STATUS_TYPE.entangled, round = 1, value = 1 })
            end
        elseif name == POWER_NAME.silence then
            local targets = self:GetAllEnemySlots(target_slot.actor)
            for _, ts in ipairs(targets) do
                if not ts:HasPower(POWER_NAME.immunity) then
                    ts:SetStatus(STATUS_TYPE.silenced, 1, 1)
                    table.insert(events, { type = "status", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, power_name = STATUS_TYPE.silenced, round = 1, value = 1 })
                end
            end
        elseif name == POWER_NAME.chance then
            local targets = self:GetAllEnemySlots(target_slot.actor)
            if #targets > 0 then
                local ts = targets[math.random(#targets)]
                local dmg = math.max(1, math.floor(value * (0.7 + math.random() * 0.6)))
                table.insert(events, { type = "anim", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, power_name = name, src_user_id = caster_actor.user_id, src_pos = 0, value = dmg })
                table.insert(events, { type = "damage", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, value = dmg })
                self:DamageSlot(ts, dmg, events)
            end
        elseif name == POWER_NAME.crystal then
            caster_actor.cur_crystal = caster_actor.cur_crystal + value
            table.insert(events, { type = "crystal", tar_user_id = caster_actor.user_id, value = value })
        elseif name == POWER_NAME.draft then
            caster_actor.cur_crystal = caster_actor.cur_crystal + value
            table.insert(events, { type = "crystal", tar_user_id = caster_actor.user_id, value = value })
        elseif name == POWER_NAME.swap then
            -- swap the middle enemy and a random back-row enemy
            local act = target_slot.actor
            local mid = act:GetBattleCard(1)
            local back = nil
            local candidates = { act:GetBattleCard(2), act:GetBattleCard(3) }
            local avail = {}
            for _, s in ipairs(candidates) do
                if s then table.insert(avail, s) end
            end
            if mid and #avail > 0 then
                back = avail[math.random(#avail)]
                act.battle_slot[1], act.battle_slot[back.pos] = act.battle_slot[back.pos], act.battle_slot[1]
                act.battle_slot[1].pos = 1
                act.battle_slot[back.pos].pos = back.pos
                table.insert(events, { type = "swap", tar_user_id = act.user_id, src_pos = 1, tar_pos = back.pos })
            end
        elseif name == POWER_NAME.destroy then
            if target_slot.cur_ad > 0 then
                local dmg = target_slot.cur_ad
                target_slot.cur_ad = 0
                target_slot:CleanItem()
                table.insert(events, { type = "destroy", tar_user_id = tid, tar_pos = tpos })
            end
        elseif name == POWER_NAME.unsummon then
            -- move target monster back to its owner's deck
            local act = target_slot.actor
            act.battle_slot[target_slot.pos] = nil
            act:CompactSlots()
            if target_slot.monster then
                table.insert(act.monster_card, target_slot.monster)
                act.monster_len = #act.monster_card
            end
            table.insert(events, { type = "unsummon", tar_user_id = tid, tar_pos = tpos, new_card = nil })
        elseif name == POWER_NAME.disarm then
            if target_slot.cur_ad > 0 then
                target_slot:CleanItem()
                table.insert(events, { type = "destroy", tar_user_id = tid, tar_pos = tpos })
            end
        elseif name == POWER_NAME.boost then
            target_slot.cur_ad = target_slot.cur_ad + value
            table.insert(events, { type = "armor", tar_user_id = tid, tar_pos = tpos, value = value })
        elseif name == POWER_NAME.armor then
            target_slot.cur_ad = target_slot.cur_ad + value
            table.insert(events, { type = "armor", tar_user_id = tid, tar_pos = tpos, value = value })
        end
    end
    return events
end

function offline_battle:GetAllSlots(actor)
    local list = {}
    for i = 1, BATTLE_SLOT_MAX do
        local s = actor.battle_slot[i]
        if s then table.insert(list, s) end
    end
    return list
end

function offline_battle:GetAllEnemySlots(actor)
    local other = actor == self.own and self.enemy or self.own
    return self:GetAllSlots(other)
end

function offline_battle:HealSlot(slot, value, events)
    if not slot or not slot.monster then return end
    local healed = math.min(value, slot.monster.hp - slot.cur_hp)
    if healed > 0 then
        slot.cur_hp = slot.cur_hp + healed
        table.insert(events, { type = "heal", tar_user_id = slot.actor.user_id, tar_pos = slot.pos, value = healed })
    end
end

-- deal damage to a slot; handles armor, death; emits events
function offline_battle:DamageSlot(slot, damage, events, src_slot, damage_type)
    damage_type = damage_type or "others"
    if not slot or not slot.monster or slot:IsDead() then
        return 0
    end
    local tid = slot.actor.user_id
    local tpos = slot.pos
    local dealt = 0

    -- magic damage: reflect chance
    if damage_type == "magic" then
        local reflect = slot:GetPowerValue(POWER_NAME.reflect)
        if reflect > 0 and math.random(100) <= 75 and src_slot then
            table.insert(events, { type = "anim", tar_user_id = tid, tar_pos = tpos, power_name = POWER_NAME.reflect, src_user_id = src_slot.actor.user_id, src_pos = src_slot.pos, value = damage })
            table.insert(events, { type = "damage", tar_user_id = src_slot.actor.user_id, tar_pos = src_slot.pos, value = damage })
            self:DamageSlot(src_slot, damage, events, nil, "magic")
            return damage
        end
        -- magic shield
        local mshield = slot:GetPowerValue(POWER_NAME.mshield)
        damage = math.max(0, damage - mshield)
    elseif damage_type == "melee" or damage_type == "ranged" then
        -- shield reduces physical damage
        local shield = slot:GetPowerValue(POWER_NAME.shield)
        damage = math.max(0, damage - shield)
    end

    -- campaign Warding: the Vault Sentinel's creatures shrug off 1 damage from
    -- blows of 3 or more (glancing blows still slip through).
    if self.hero_mode and self.power and self.power.id == "warding"
        and slot.actor == self.enemy and damage >= 3 then
        damage = damage - 1
    end

    -- armor absorbs physical damage
    if (damage_type == "melee" or damage_type == "ranged") and slot.cur_ad > 0 then
        local breaker = src_slot and src_slot:GetPowerValue(POWER_NAME.breaker) or 0
        local armor_dmg = damage
        if breaker > 0 then
            armor_dmg = math.floor(armor_dmg * 1.5)
        end
        local absorbed = math.min(slot.cur_ad, armor_dmg)
        slot.cur_ad = slot.cur_ad - absorbed
        table.insert(events, { type = "armor", tar_user_id = tid, tar_pos = tpos, value = -absorbed })
        dealt = dealt + absorbed
        if slot.cur_ad <= 0 then
            slot:CleanItem()
        end
        damage = damage - absorbed
        if damage <= 0 then
            return dealt
        end
    end

    slot.cur_hp = slot.cur_hp - damage
    table.insert(events, { type = "damage", tar_user_id = tid, tar_pos = tpos, value = damage })
    dealt = dealt + damage

    -- death
    if slot:IsDead() then
        -- regenerate: survive at 1 hp once
        if slot:HasPower(POWER_NAME.regenerate) and not slot.used_regenerate then
            slot.used_regenerate = true
            slot.cur_hp = 1
            return dealt
        end
        -- overkill carry-through: a killing blow's excess damage hits the
        -- defender's commander, so trades always progress the game.
        if self.hero_mode then
            local overkill = -slot.cur_hp
            if overkill > 0 then
                self:DamageHero(slot.actor, overkill)
            end
        end
        table.insert(events, { type = "dead", tar_user_id = tid, tar_pos = tpos })
        slot.actor.battle_slot[slot.pos] = nil
        slot.actor:CompactSlots()
        slot.actor.dead_num = slot.actor.dead_num + 1
        if src_slot then
            src_slot.actor.cur_crystal = src_slot.actor.cur_crystal + 1
            table.insert(events, { type = "crystal", tar_user_id = src_slot.actor.user_id, value = 1 })
        end
        -- pve kill count
        if slot.actor == self.enemy then
            self.pve_win_cur_value = self.pve_win_cur_value + 1
        end
    end
    return dealt
end

-- =====================================================================
-- Combat
-- =====================================================================

function offline_battle:RunCombat()
    local events = {}

    -- round-start powers
    self:ApplyRoundStartPowers()

    -- Build attacker list: snapshot which slots are occupied NOW.
    -- CompactSlots can shift slots mid-combat, so we take a snapshot
    -- of slot objects before the loop and re-check liveness each pass.
    local function collect_attackers(actor)
        local list = {}
        for i = 1, BATTLE_SLOT_MAX do
            local s = actor.battle_slot[i]
            if s and s.monster and not s:IsDead() then
                list[#list + 1] = s
            end
        end
        return list
    end

    local own_list = collect_attackers(self.own)
    local enemy_list = collect_attackers(self.enemy)

    -- Player slots attack first, then enemy slots
    for _, attacker in ipairs(own_list) do
        -- re-check: slot may have died from earlier thorns/counter
        if attacker.monster and not attacker:IsDead() then
            self:SlotAttack(attacker, events)
        end
        if self.is_over then break end
    end
    for _, attacker in ipairs(enemy_list) do
        if attacker.monster and not attacker:IsDead() then
            self:SlotAttack(attacker, events)
        end
        if self.is_over then break end
    end

    -- also check game-over during combat in case kill target reached
    if not self.is_over then
        self:CheckGameOver()
    end

    if #events > 0 and not self.is_over then
        self:PushCommand("cmd_battle_attack", { event_list = events, is_fight_stage = true })
    end
end

-- apply rally / demoralize / antimagic / charge / cautious at combat start
function offline_battle:ApplyRoundStartPowers()
    -- clear previous round buffs
    for _, actor in ipairs({ self.own, self.enemy }) do
        for i = 1, BATTLE_SLOT_MAX do
            local slot = actor.battle_slot[i]
            if slot then
                for _, st in ipairs({ STATUS_TYPE.rallied, STATUS_TYPE.demoralized, STATUS_TYPE.antimagicd, STATUS_TYPE.charged, STATUS_TYPE.cautious }) do
                    slot:DelStatus(st)
                end
                -- decrement persistent statuses
                for name, st in pairs(slot.status_map) do
                    st.round = st.round - 1
                    if st.round <= 0 then
                        slot.status_map[name] = nil
                    end
                end
            end
        end
    end

    local function apply(actor, enemy)
        for i = 1, BATTLE_SLOT_MAX do
            local slot = actor.battle_slot[i]
            if slot and slot.monster then
                if slot:HasPower(POWER_NAME.rally) then
                    local v = slot:GetPowerValue(POWER_NAME.rally)
                    for j = 1, BATTLE_SLOT_MAX do
                        local s = actor.battle_slot[j]
                        if s and s.monster then
                            s:SetStatus(STATUS_TYPE.rallied, 1, math.max(s:GetStatusValue(STATUS_TYPE.rallied), v))
                        end
                    end
                end
                if slot:HasPower(POWER_NAME.demoralize) then
                    local v = slot:GetPowerValue(POWER_NAME.demoralize)
                    for j = 1, BATTLE_SLOT_MAX do
                        local s = enemy.battle_slot[j]
                        if s and s.monster and not s:HasPower(POWER_NAME.immunity) then
                            s:SetStatus(STATUS_TYPE.demoralized, 1, math.max(s:GetStatusValue(STATUS_TYPE.demoralized), v))
                        end
                    end
                end
                if slot:HasPower(POWER_NAME.antimagic) then
                    local v = slot:GetPowerValue(POWER_NAME.antimagic)
                    for j = 1, BATTLE_SLOT_MAX do
                        local s = enemy.battle_slot[j]
                        if s and s.monster and not s:HasPower(POWER_NAME.immunity) then
                            s:SetStatus(STATUS_TYPE.antimagicd, 1, math.max(s:GetStatusValue(STATUS_TYPE.antimagicd), v))
                        end
                    end
                end
                if slot:HasPower(POWER_NAME.charge) and not slot.used_charge then
                    slot.used_charge = true
                    local v = slot:GetPowerValue(POWER_NAME.charge)
                    slot:SetStatus(STATUS_TYPE.charged, 1, math.max(slot:GetStatusValue(STATUS_TYPE.charged), v))
                end
                if slot:HasPower(POWER_NAME.cautious) then
                    slot:SetStatus(STATUS_TYPE.cautious, 1, 1)
                end
            end
        end
    end
    apply(self.own, self.enemy)
    apply(self.enemy, self.own)
end

-- one slot attacks using its powers
function offline_battle:SlotAttack(attacker, events)
    if not attacker.monster or attacker:IsDead() then
        return
    end
    local ok, reason = attacker:CanAttack()
    if not ok then
        return
    end

    local enemy = attacker.actor == self.own and self.enemy or self.own

    -- magic
    local magic = attacker:GetMagicStrength()
    if magic > 0 and not attacker:IsSilenced() then
        local target = enemy:GetBattleCard(attacker.pos)
        if not target then
            -- fallback to the front-most occupied slot
            target = self:GetFrontSlot(enemy)
        end
        if target and target.monster then
            table.insert(events, { type = "anim", tar_user_id = target.actor.user_id, tar_pos = target.pos, power_name = POWER_NAME.magic, src_user_id = attacker.actor.user_id, src_pos = attacker.pos, value = magic })
            self:DamageSlot(target, magic, events, attacker, "magic")
            self:AfterHit(attacker, target, events, "magic", magic)
        elseif self.hero_mode then
            -- no blocker: strike the enemy commander directly
            self:DamageHero(enemy, magic)
        end
        return
    end

    -- melee: front position only (or reach from back)
    local has_melee = attacker:GetMeleeStrength() > 0
    local can_melee = attacker.pos == 1 or attacker:HasPower(POWER_NAME.reach)
    if has_melee and can_melee then
        local target = enemy:GetBattleCard(1)
        if not target then
            target = self:GetFrontSlot(enemy)
        end
        if target and target.monster then
            local dmg = attacker:GetMeleeStrength()
            table.insert(events, { type = "anim", tar_user_id = target.actor.user_id, tar_pos = target.pos, power_name = POWER_NAME.melee, src_user_id = attacker.actor.user_id, src_pos = attacker.pos, value = dmg })
            self:DamageSlot(target, dmg, events, attacker, "melee")
            self:AfterHit(attacker, target, events, "melee", dmg)
            -- thrash: follow-up hit on a random back-row enemy
            if attacker:HasPower(POWER_NAME.thrash) then
                local backs = {}
                for i = 2, BATTLE_SLOT_MAX do
                    local s = enemy.battle_slot[i]
                    if s and s.monster then table.insert(backs, s) end
                end
                if #backs > 0 and target.monster and not target:IsDead() then
                    -- thrash triggers when melee hit lands
                    local ts = backs[math.random(#backs)]
                    local tdmg = attacker:GetPowerValue(POWER_NAME.thrash)
                    table.insert(events, { type = "anim", tar_user_id = ts.actor.user_id, tar_pos = ts.pos, power_name = POWER_NAME.thrash, src_user_id = attacker.actor.user_id, src_pos = attacker.pos, value = tdmg })
                    self:DamageSlot(ts, tdmg, events, attacker, "melee")
                end
            end
            -- trample: hit all back-row enemies after front melee hit
            if attacker:HasPower(POWER_NAME.trample) and attacker.pos == 1 then
                local tdmg = attacker:GetPowerValue(POWER_NAME.trample)
                for i = 2, BATTLE_SLOT_MAX do
                    local s = enemy.battle_slot[i]
                    if s and s.monster then
                        table.insert(events, { type = "anim", tar_user_id = s.actor.user_id, tar_pos = s.pos, power_name = POWER_NAME.trample, src_user_id = attacker.actor.user_id, src_pos = attacker.pos, value = tdmg })
                        self:DamageSlot(s, tdmg, events, attacker, "melee")
                    end
                end
            end
        elseif self.hero_mode then
            -- no blocker: strike the enemy commander directly
            self:DamageHero(enemy, attacker:GetMeleeStrength())
        end
        return
    end

    -- ranged: back position attacks diagonal
    local ranged = attacker:GetRangedStrength()
    if ranged > 0 and attacker.pos ~= 1 then
        local diag = attacker.pos == 2 and 3 or 2
        local target = enemy:GetBattleCard(diag)
        if not target or not target.monster then
            target = self:GetFrontSlot(enemy)
        end
        if target and target.monster then
            -- aggro: enemy taunt redirects
            local aggros = {}
            for i = 1, BATTLE_SLOT_MAX do
                local s = enemy.battle_slot[i]
                if s and s.monster and s:HasPower(POWER_NAME.aggro) then
                    table.insert(aggros, s)
                end
            end
            if #aggros > 0 then
                target = aggros[math.random(#aggros)]
            end
            -- stealth: back-row enemies cannot be targeted by ranged
            if target:HasPower(POWER_NAME.stealth) and target.pos ~= 1 then
                target = self:GetFrontSlot(enemy)
            end
            if target and target.monster then
                local dmg = attacker:GetRangedStrength()
                -- 25% chance blocked by armor
                local blocked = false
                if target.cur_ad > 0 and math.random(100) <= 25 and not attacker:HasPower(POWER_NAME.breaker) then
                    blocked = true
                    table.insert(events, { type = "armor_block", tar_user_id = target.actor.user_id, tar_pos = target.pos })
                end
                if not blocked then
                    table.insert(events, { type = "anim", tar_user_id = target.actor.user_id, tar_pos = target.pos, power_name = POWER_NAME.ranged, src_user_id = attacker.actor.user_id, src_pos = attacker.pos, value = dmg })
                    self:DamageSlot(target, dmg, events, attacker, "ranged")
                    self:AfterHit(attacker, target, events, "ranged", dmg)
                end
            end
        elseif self.hero_mode then
            -- no blocker: strike the enemy commander directly
            self:DamageHero(enemy, attacker:GetRangedStrength())
        end
        return
    end
end

function offline_battle:GetFrontSlot(actor)
    for i = 1, BATTLE_SLOT_MAX do
        local s = actor.battle_slot[i]
        if s and s.monster then
            return s
        end
    end
    return nil
end

-- after an attack lands: thorns, counter, disease, drain_crystal, cleave, opportunity
function offline_battle:AfterHit(attacker, target, events, attack_type, dmg)
    if not target.monster or target:IsDead() then
        -- drain crystal on kill
        if target.monster and target:IsDead() and attacker:HasPower(POWER_NAME.drain_crystal) then
            attacker.actor.cur_crystal = attacker.actor.cur_crystal + 1
            table.insert(events, { type = "crystal", tar_user_id = attacker.actor.user_id, value = 1 })
        end
        return
    end
    local target_cautious = target:IsCautious()

    -- thorns: melee attacker takes damage
    if not target_cautious and target:HasPower(POWER_NAME.thorns) and attack_type == "melee" then
        local td = target:GetPowerValue(POWER_NAME.thorns)
        table.insert(events, { type = "anim", tar_user_id = attacker.actor.user_id, tar_pos = attacker.pos, power_name = POWER_NAME.thorns, src_user_id = target.actor.user_id, src_pos = target.pos, value = td })
        self:DamageSlot(attacker, td, events, target, "melee")
    end

    -- counter: 50% reflect equal melee damage
    if not target_cautious and target:HasPower(POWER_NAME.counter) and attack_type == "melee" then
        if math.random(100) <= 50 and attacker.monster and not attacker:IsDead() then
            table.insert(events, { type = "anim", tar_user_id = attacker.actor.user_id, tar_pos = attacker.pos, power_name = POWER_NAME.counter, src_user_id = target.actor.user_id, src_pos = target.pos, value = dmg })
            self:DamageSlot(attacker, dmg, events, target, "melee")
        end
    end

    -- disease on physical hit
    if (attack_type == "melee" or attack_type == "ranged") and attacker:HasPower(POWER_NAME.disease) then
        if not target:HasPower(POWER_NAME.immunity) then
            target:SetStatus(STATUS_TYPE.diseased, 2, 1)
            table.insert(events, { type = "status", tar_user_id = target.actor.user_id, tar_pos = target.pos, power_name = STATUS_TYPE.diseased, round = 2, value = 1 })
        end
    end

    -- cleave: leftover damage hits hp after armor destroyed
    -- (armor overflow already handled in DamageSlot)

    -- disarm: destroy target weapon on hit
    if attacker:HasPower(POWER_NAME.disarm) and target.cur_ad > 0 then
        target:CleanItem()
        table.insert(events, { type = "destroy", tar_user_id = target.actor.user_id, tar_pos = target.pos })
    end

    -- drain crystal on kill (handled in DamageSlot caller path)
end

-- =====================================================================
-- Campaign scripted powers
-- =====================================================================

-- Fire a node's scripted power at the start of the enemy turn (mirrors the
-- web prototype's tickEnemyPower). Only runs in hero_mode.
function offline_battle:FireCampaignPower()
    if not self.hero_mode then return end
    local node_type = self.campaign and self.campaign.node_type or "skirmish"
    local round = self.round

    -- Apply a pending phase-2 trigger (ENRAGE / ECLIPSE) at the start of the
    -- enemy turn that follows the hit that dropped the boss below half HP.
    if self.power_phase2 and not self.phase2_applied then
        self.phase2_applied = true
        local power = self.power
        if power then
            local board_changed = false
            if power.id == "flamewave" then
                self:AddEnemyBoardAttack(1)
                board_changed = true
            elseif power.id == "toll" then
                if self:SummonToken(self.enemy, "wraith") then board_changed = true end
                if self:SummonToken(self.enemy, "wraith") then board_changed = true end
            end
            if board_changed then
                self:PushBoardSync()
            end
        end
    end

    -- GATHERING POWER (every boss): on turns 3,6,9,... the boss grows +1 and
    -- lashes the player directly. Walls can't save you.
    if node_type == "boss" and round >= 3 and round % 3 == 0 then
        self.gathering = self.gathering + 1
        self:DamageHero(self.own, self.gathering)
    end

    local power = self.power
    if not power then return end
    local id = power.id

    if id == "muster" then
        if round == 3 or round == 4 then
            if self:SummonToken(self.enemy, "whelp") then
                self:PushBoardSync()
            end
        end
    elseif id == "plunder" then
        -- faithful to the web prototype: Vex steals 1 of YOUR crystal each of
        -- his turns (the enemy's own crystal economy is untouched).
        if round >= 2 and self.own.cur_crystal > 0 then
            self.own.cur_crystal = self.own.cur_crystal - 1
            self:PushCommand("cmd_battle_attack", {
                event_list = {
                    { type = "crystal", tar_user_id = self.own.user_id, value = -1 },
                },
                is_fight_stage = false,
            })
        end
    elseif id == "bloodlust" then
        if round >= 4 and not self.power_used then
            self.power_used = true
            self:AddEnemyBoardAttack(1)
            self:PushBoardSync()
        end
    elseif id == "overgrowth" then
        -- "still fed" = any cards left in deck OR hand (matches the web)
        local hand_count = 0
        for i = 1, 4 do if self.enemy.hand_card[i] then hand_count = hand_count + 1 end end
        local still_fed = (#self.enemy.monster_card + #self.enemy.item_card + hand_count) > 0
        local count = still_fed and (round >= 5 and 2 or 1) or 0
        local summoned = false
        for _ = 1, count do
            if not self:SummonToken(self.enemy, "sapling") then break end
            summoned = true
        end
        if summoned then
            self:PushBoardSync()
        end
        local has_sapling = false
        for i = 1, BATTLE_SLOT_MAX do
            local s = self.enemy.battle_slot[i]
            if s and s.monster and s.monster.name == "Sapling" then has_sapling = true break end
        end
        if has_sapling then
            self:HealHero(self.enemy, 1)
        end
    elseif id == "hunger" then
        if round >= 4 then
            local events = {}
            local devoured = 0
            for i = 1, BATTLE_SLOT_MAX do
                local s = self.own.battle_slot[i]
                if s and s.monster then
                    self:DamageSlot(s, 1, events, nil, "others")
                    if not s.monster or s:IsDead() then devoured = devoured + 1 end
                end
            end
            if #events > 0 then
                self:PushCommand("cmd_battle_attack", { event_list = events, is_fight_stage = false })
            end
            if devoured > 0 then
                self:HealHero(self.enemy, devoured)
            end
        end
    elseif id == "flamewave" then
        if round >= 3 and round % 3 == 0 then
            local events = {}
            for i = 1, BATTLE_SLOT_MAX do
                local s = self.own.battle_slot[i]
                if s and s.monster then
                    self:DamageSlot(s, 2, events, nil, "others")
                end
            end
            if #events > 0 then
                self:PushCommand("cmd_battle_attack", { event_list = events, is_fight_stage = false })
            end
        end
    elseif id == "toll" then
        if round >= 3 then
            self:DamageHero(self.own, 1)
            self:HealHero(self.enemy, 1)
        end
    end
end

-- Phase-2 boss triggers (ENRAGE / ECLIPSE). Marked as soon as a boss drops
-- below half HP (from DamageHero); the actual board change is applied at the
-- start of the next enemy turn (FireCampaignPower) so the single board
-- re-sync lands cleanly between turns, not mid-combat.
function offline_battle:CheckCampaignPhase2()
    if not self.hero_mode then return end
    local power = self.power
    if not power or self.power_phase2 then return end
    if self.enemy_hp > (self.enemy_max_hp / 2) then return end
    self.power_phase2 = true
end

-- =====================================================================
-- AI
-- =====================================================================

function offline_battle:AIDoPrep()
    local actor = self.enemy
    local enemy_actor = self.own

    -- Phase 0: sacrifice high-cost hand cards if crystal is low
    -- (sacrifice the most expensive card we can't afford)
    local function ai_sacrifice()
        local max_iters = 4
        for _ = 1, max_iters do
            local sacrifice_idx = nil
            local sacrifice_cost = -1
            for i = 1, 4 do
                local c = actor.hand_card[i]
                if c and c.cost > actor.cur_crystal then
                    -- can't afford this card; sacrifice it
                    if c.cost > sacrifice_cost then
                        sacrifice_idx = i
                        sacrifice_cost = c.cost
                    end
                end
            end
            if not sacrifice_idx then break end
            local card = actor:GetHandCard(sacrifice_idx)
            local crystal_gain = IMMOLATION[card.type] or 1
            for _, p in ipairs(card.power_list or {}) do
                if p.name == POWER_NAME.crystal then
                    crystal_gain = crystal_gain + (tonumber(p.value) or 0)
                end
            end
            local new_card = actor:DrawCard(card.type)
            actor:SetHandCard(sacrifice_idx, new_card)
            actor.cur_crystal = actor.cur_crystal + crystal_gain
            self:PushCommand("cmd_battle_discard", {
                src_user_id = actor.user_id,
                discard_info_list = { { is_hand = true, pos = sacrifice_idx, new_card = new_card } },
                sync_crystal = actor.cur_crystal,
                effect_list = {},
                is_sacrifice = false,
            })
        end
    end
    ai_sacrifice()

    -- deploy monsters while affordable
    local max_iters = 8
    local iters = 0
    while iters < max_iters do
        iters = iters + 1
        local slot_pos = actor:GetCurMonsterSlotPos()
        if slot_pos == 0 then
            break
        end
        -- find cheapest affordable monster in hand
        local best_idx, best_cost = nil, nil
        for i = 1, 4 do
            local c = actor.hand_card[i]
            if c and c.type == CARD_TYPE.monster and c.cost <= actor.cur_crystal and actor.cur_crystal > 0 then
                if not best_cost or c.cost < best_cost then
                    best_idx, best_cost = i, c.cost
                end
            end
        end
        if not best_idx then
            break
        end
        local card = actor:GetHandCard(best_idx)
        local slot = self:DeployMonster(actor, card, slot_pos)
        actor.cur_crystal = actor.cur_crystal - card.cost
        if actor.cur_crystal < 0 then actor.cur_crystal = 0 end
        local new_card = actor:DrawCard(CARD_TYPE.monster)
        actor:SetHandCard(best_idx, new_card)
        self:PushCommand("cmd_battle_move", {
            src_user_id = actor.user_id,
            src_hand_pos = best_idx,
            desc_user_id = actor.user_id,
            desc_slot_pos = slot_pos,
            sync_crystal = actor.cur_crystal,
            new_card = new_card,
        })
    end

    -- equip items on monsters
    iters = 0
    while iters < max_iters do
        iters = iters + 1
        local best_idx, best_slot = nil, nil
        for i = 1, 4 do
            local c = actor.hand_card[i]
            if c and (c.type == CARD_TYPE.equip or c.type == CARD_TYPE.armor) and c.cost <= actor.cur_crystal and actor.cur_crystal > 0 then
                for j = 1, BATTLE_SLOT_MAX do
                    local s = actor.battle_slot[j]
                    if s and s.monster and not s.item then
                        -- kind match
                        local all_flag = bit_lshift(1, 6)
                        if bit_band(c.kind, all_flag) ~= 0 or bit_band(s.monster.kind, c.kind) == c.kind then
                            best_idx = i
                            best_slot = s
                            break
                        end
                    end
                end
                if best_idx then break end
            end
        end
        if not best_idx then
            break
        end
        local card = actor:GetHandCard(best_idx)
        self:EquipItem(best_slot, card)
        actor.cur_crystal = actor.cur_crystal - card.cost
        if actor.cur_crystal < 0 then actor.cur_crystal = 0 end
        local new_card = actor:DrawCard(CARD_TYPE.item)
        actor:SetHandCard(best_idx, new_card)
        self:PushCommand("cmd_battle_move", {
            src_user_id = actor.user_id,
            src_hand_pos = best_idx,
            desc_user_id = actor.user_id,
            desc_slot_pos = best_slot.pos,
            sync_crystal = actor.cur_crystal,
            new_card = new_card,
        })
    end

    -- use healing consume cards on damaged allies
    iters = 0
    while iters < max_iters do
        iters = iters + 1
        local use_idx, use_slot = nil, nil
        for i = 1, 4 do
            local c = actor.hand_card[i]
            if c and c.type == CARD_TYPE.consume and c.cost <= actor.cur_crystal and actor.cur_crystal > 0 then
                local is_heal = false
                for _, p in ipairs(c.power_list or {}) do
                    if p.name == POWER_NAME.heal or p.name == POWER_NAME.heal_all then
                        is_heal = true
                        break
                    end
                end
                if is_heal then
                    for j = 1, BATTLE_SLOT_MAX do
                        local s = actor.battle_slot[j]
                        if s and s.monster and s.cur_hp < s.monster.hp then
                            use_idx, use_slot = i, s
                            break
                        end
                    end
                    if use_idx then break end
                end
            end
        end
        if not use_idx then
            break
        end
        local card = actor:GetHandCard(use_idx)
        local effects = self:ApplyCardPowers(card, use_slot, actor, actor.user_id)
        actor.cur_crystal = actor.cur_crystal - card.cost
        if actor.cur_crystal < 0 then actor.cur_crystal = 0 end
        local new_card = actor:DrawCard(CARD_TYPE.item)
        actor:SetHandCard(use_idx, new_card)
        self:PushCommand("cmd_battle_move", {
            src_user_id = actor.user_id,
            src_hand_pos = use_idx,
            desc_user_id = actor.user_id,
            desc_slot_pos = use_slot.pos,
            sync_crystal = actor.cur_crystal,
            new_card = new_card,
        })
        if #effects > 0 then
            self:PushCommand("cmd_battle_attack", { event_list = effects, is_fight_stage = false })
        end
        self:CheckGameOver()
        if self.is_over then
            return
        end
    end
end

return offline_battle
