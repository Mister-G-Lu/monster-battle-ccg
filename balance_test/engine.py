"""Faithful Python port of the native battle engine.

Ports src/manager/offline_battle.lua + offline_battle_model.lua + the relevant
constants from common/constants.lua.  The Lua runtime is not available in this
sandbox (no luajit, no network to fetch one), so this module re-implements the
same server-side rules so we can run head-to-head deck simulations.

Mechanics preserved 1:1:
  * Initial hand = 2 monsters + 2 items, drawn off the top of two separate,
    independently-shuffled piles (monster deck / item deck).
  * Crystal economy: +1 crystal per round to each side; sacrificing a monster
    in hand refunds 2 crystal (equip/armor/consume = 1); a killer gains +1.
  * Deployment: 3 slots; monsters deploy to the first empty slot; equipping an
    item on a monster merges its powers; armor soaks physical damage first.
  * Combat: player slots attack first, then enemy; melee hits front slot
    (or reach from back), ranged hits diagonally from the back row, magic hits
    the mirrored slot; statuses/powers (thorns, counter, disease, shield,
    mshield, reflect, regenerate, rally, demoralize, antimagic, charge, etc.)
    resolved identically.
  * Win/loss (constructed, non-hero): a side loses when its monster total
    (hand + deck + board) reaches 0.  MAX_ROUNDS=50 breaks ties by board count.
"""
import random
import constants as C

class Card:
    __slots__ = ("id","uid","name","hp","cost","type","quality","kind","power_list",
                 "level","strength","res_path","hand_pos","user_id")
    def __init__(self):
        self.hand_pos = 0
        self.user_id = None
        self.power_list = []

def build_card_info(config, uid, hand_pos=0, user_id=None):
    c = Card()
    c.id = int(config.get("uid") or config.get("ID") or uid or 0)
    c.uid = str(uid)
    c.name = config.get("name", "")
    c.hp = int(config.get("hp") or 0)
    c.cost = int(config.get("cost") or 0)
    c.type = config.get("type", "monster")
    c.quality = config.get("quality", "normal")
    c.kind = int(config.get("kind") or 0)
    c.level = int(config.get("level") or 1)
    c.strength = int(config.get("score") or 0)
    c.res_path = config.get("res_path", "")
    c.hand_pos = hand_pos
    if user_id:
        c.user_id = user_id
    pl = []
    for p in (config.get("power_list") or []):
        pl.append({
            "name": p["name"],
            "value": int(p.get("value") or 0),
            "target_type": p.get("target_type", ""),
            "type": p.get("type", "passive"),
        })
    c.power_list = pl
    return c


class Slot:
    def __init__(self, actor, pos):
        self.actor = actor
        self.pos = pos
        self.monster = None
        self.item = None
        self.cur_hp = 0
        self.cur_ad = 0
        self.status_map = {}   # name -> {"round","value"}
        self.power_map = {}
        self.attack_type = None
        self.used_opportunity = False
        self.used_charge = False
        self.used_regenerate = False

    def IsDead(self):
        return self.cur_hp <= 0

    def GetPower(self, name):
        return self.power_map.get(name)

    def GetPowerValue(self, name):
        return self.power_map.get(name, 0)

    def HasPower(self, name):
        return name in self.power_map

    def IsStatus(self, name):
        return name in self.status_map

    def GetStatusValue(self, name):
        s = self.status_map.get(name)
        return s["value"] if s else 0

    def SetStatus(self, name, rnd, value):
        self.status_map[name] = {"round": rnd, "value": value}

    def DelStatus(self, name):
        self.status_map.pop(name, None)

    def GetMeleeStrength(self):
        s = self.GetPowerValue("melee")
        s += self.GetStatusValue("rallied")
        s -= self.GetStatusValue("demoralized")
        s += self.GetStatusValue("charged")
        return max(0, s)

    def GetRangedStrength(self):
        s = self.GetPowerValue("ranged")
        s += self.GetStatusValue("rallied")
        s -= self.GetStatusValue("demoralized")
        s += self.GetStatusValue("charged")
        return max(0, s)

    def GetMagicStrength(self):
        s = self.GetPowerValue("magic")
        s -= self.GetStatusValue("antimagicd")
        return max(0, s)

    def CanAttack(self):
        if self.IsStatus("entangled"):
            return False
        return True

    def IsDiseased(self):
        return self.IsStatus("diseased")

    def IsSilenced(self):
        return self.IsStatus("silenced")

    def IsCautious(self):
        return self.IsStatus("cautious")

    def RebuildPowers(self):
        self.power_map = {}
        if self.monster and self.monster.power_list:
            for p in self.monster.power_list:
                self.power_map[p["name"]] = self.power_map.get(p["name"], 0) + p["value"]
        if self.item and self.item.power_list:
            for p in self.item.power_list:
                self.power_map[p["name"]] = self.power_map.get(p["name"], 0) + p["value"]
        if self.HasPower("magic"):
            self.attack_type = "magic"
        elif self.HasPower("melee"):
            self.attack_type = "melee"
        else:
            self.attack_type = "ranged"

    def SetMonster(self, card):
        self.monster = card
        self.cur_hp = card.hp
        self.item = None
        self.cur_ad = 0
        self.status_map = {}
        self.used_opportunity = False
        self.used_charge = False
        self.used_regenerate = False
        self.RebuildPowers()

    def SetItem(self, card):
        self.item = card
        self.cur_ad = card.hp
        self.RebuildPowers()
        boost = self.GetPowerValue("boost")
        if boost > 0:
            self.cur_ad += boost

    def CleanItem(self):
        self.item = None
        self.cur_ad = 0
        self.RebuildPowers()

    def AddAttack(self, amount):
        if not self.monster:
            return
        attack_name = self.attack_type or "melee"
        found = False
        for p in self.monster.power_list:
            if p["name"] == attack_name:
                p["value"] = int(p.get("value", 0)) + amount
                found = True
        if not found:
            self.monster.power_list.append(
                {"name": attack_name, "value": amount, "target_type": "enemy", "type": "passive"})
        self.RebuildPowers()


class Actor:
    def __init__(self, user_id, user_name=None, is_ai=False):
        self.user_id = user_id
        self.user_name = user_name or "Enemy"
        self.arena_level = 1
        self.strength = 0
        self.monster_len = 0
        self.item_len = 0
        self.cur_crystal = 0
        self.hand_card = [None, None, None, None]  # 1..4
        self.battle_slot = [None, None, None, None]  # 1..3
        self.monster_card = []
        self.item_card = []
        self.is_sacrifice = False
        self.is_ai = is_ai
        self.dead_num = 0

    def GetHandCard(self, pos):
        return self.hand_card[pos - 1]

    def SetHandCard(self, pos, card):
        self.hand_card[pos - 1] = card
        if card:
            card.hand_pos = pos

    def GetBattleCard(self, pos):
        return self.battle_slot[pos - 1]

    def GetMonsterTotal(self):
        total = 0
        for i in range(4):
            c = self.hand_card[i]
            if c and c.type == "monster":
                total += 1
        total += len(self.monster_card)
        for i in range(3):
            if self.battle_slot[i] and self.battle_slot[i].monster:
                total += 1
        return total

    def GetItemTotal(self):
        total = 0
        for i in range(4):
            c = self.hand_card[i]
            if c and c.type != "monster":
                total += 1
        total += len(self.item_card)
        for i in range(3):
            if self.battle_slot[i] and self.battle_slot[i].item:
                total += 1
        return total

    def GetCurMonsterSlotPos(self):
        for i in range(3):
            if not self.battle_slot[i]:
                return i + 1
        return 0

    def DrawCard(self, card_type):
        pile = self.monster_card if card_type == "monster" else self.item_card
        if not pile:
            return None
        card = pile[0]
        del pile[0]
        self.monster_len = len(self.monster_card)
        self.item_len = len(self.item_card)
        return card

    def CompactSlots(self):
        for _ in range(C.BATTLE_SLOT_MAX - 1):
            for i in range(C.BATTLE_SLOT_MAX - 1):
                if not self.battle_slot[i] and self.battle_slot[i + 1]:
                    self.battle_slot[i] = self.battle_slot[i + 1]
                    self.battle_slot[i].pos = i + 1
                    self.battle_slot[i + 1] = None


class Battle:
    def __init__(self, own_deck, enemy_deck, seed=None):
        """own_deck / enemy_deck = {'monster_list':[CardInfo], 'item_list':[CardInfo]}"""
        if seed is not None:
            random.seed(seed)
        self.round = 0
        self.is_over = False
        self.win_user_id = None
        self.own = Actor("player", "Player", is_ai=False)
        self.enemy = Actor("enemy", "Enemy", is_ai=True)
        self._load_actor(self.own, own_deck)
        self._load_actor(self.enemy, enemy_deck)
        self.own.strength = self._calc_strength(self.own)
        self.enemy.strength = self._calc_strength(self.enemy)

    def _shuffle(self, t):
        for i in range(len(t) - 1, 0, -1):
            j = random.randint(0, i)  # Lua math.random(i) is 1..i -> 0..i in 0-based
            t[i], t[j] = t[j], t[i]

    def _load_actor(self, actor, deck):
        deck = deck or {"monster_list": [], "item_list": []}
        actor.monster_card = list(deck.get("monster_list") or [])
        actor.item_card = list(deck.get("item_list") or [])
        actor.monster_len = len(actor.monster_card)
        actor.item_len = len(actor.item_card)
        self._shuffle(actor.monster_card)
        self._shuffle(actor.item_card)
        actor.SetHandCard(1, actor.DrawCard("monster"))
        actor.SetHandCard(2, actor.DrawCard("monster"))
        actor.SetHandCard(3, actor.DrawCard("item"))
        actor.SetHandCard(4, actor.DrawCard("item"))

    def _calc_strength(self, actor):
        s = 0
        for c in actor.monster_card:
            s += c.strength
        for c in actor.item_card:
            s += c.strength
        for i in range(4):
            c = actor.hand_card[i]
            if c:
                s += c.strength
        return s

    # --- flow ---
    def Start(self):
        self.round = 1
        self.own.cur_crystal = self.round
        self.enemy.cur_crystal = self.round

    def CheckGameOver(self):
        if self.is_over:
            return True
        if self.own.GetMonsterTotal() == 0:
            self.FinishBattle("enemy")
            return True
        if self.enemy.GetMonsterTotal() == 0:
            self.FinishBattle("player")
            return True
        return False

    def FinishBattle(self, winner):
        self.is_over = True
        self.win_user_id = winner

    def _max_rounds_decide(self):
        # replicate HandleAttack round-limit resolution (non-hero): board count
        own_count = sum(1 for i in range(3) if self.own.battle_slot[i] and self.own.battle_slot[i].monster)
        enemy_count = sum(1 for i in range(3) if self.enemy.battle_slot[i] and self.enemy.battle_slot[i].monster)
        if own_count >= enemy_count:
            self.FinishBattle("player")
        else:
            self.FinishBattle("enemy")

    def run_full_turn(self):
        """End the player's turn: enemy AI prep + combat + advance round.
        Mirrors offline_battle:HandleAttack (non-hero path)."""
        if self.is_over:
            return
        if self.CheckGameOver():
            return
        if self.round >= C.MAX_ROUNDS:
            self._max_rounds_decide()
            return
        # enemy prep + AI
        self.ai_do_prep(self.enemy, self.own)
        # combat
        self.RunCombat()
        if self.is_over:
            return
        # next round
        self.round += 1
        self.own.cur_crystal += 1
        self.enemy.cur_crystal += 1

    # --- deployment ---
    def DeployMonster(self, actor, card, target_pos):
        slot = actor.battle_slot[target_pos - 1]
        if slot and slot.monster:
            for i in range(C.BATTLE_SLOT_MAX - 1, target_pos - 1, -1):
                if actor.battle_slot[i]:
                    actor.battle_slot[i].pos = i + 2
                    actor.battle_slot[i + 1] = actor.battle_slot[i]
                    actor.battle_slot[i] = None
        slot = Slot(actor, target_pos)
        slot.SetMonster(card)
        actor.battle_slot[target_pos - 1] = slot
        return slot

    def EquipItem(self, slot, card):
        slot.SetItem(card)

    # --- card powers (consume cards) ---
    def ApplyCardPowers(self, card, target_slot, caster_actor):
        events = []
        tid = target_slot.actor.user_id
        tpos = target_slot.pos
        for p in card.power_list or []:
            name = p["name"]
            value = p["value"]
            if name == "damage":
                self.DamageSlot(target_slot, value, events)
            elif name == "damage_all":
                for ts in self.GetAllEnemySlots(target_slot.actor):
                    self.DamageSlot(ts, value, events)
            elif name == "heal":
                self.HealSlot(target_slot, value, events)
            elif name == "heal_all":
                for ts in self.GetAllSlots(target_slot.actor):
                    self.HealSlot(ts, value, events)
            elif name == "entangle":
                if random.randint(1, 100) <= 50 and not target_slot.IsStatus("entangled"):
                    target_slot.SetStatus("entangled", 1, 1)
            elif name == "silence":
                for ts in self.GetAllEnemySlots(target_slot.actor):
                    if not ts.HasPower("immunity"):
                        ts.SetStatus("silenced", 1, 1)
            elif name == "chance":
                targets = self.GetAllEnemySlots(target_slot.actor)
                if targets:
                    ts = targets[random.randrange(len(targets))]
                    dmg = max(1, int(value * (0.7 + random.random() * 0.6)))
                    self.DamageSlot(ts, dmg, events)
            elif name == "crystal" or name == "draft":
                caster_actor.cur_crystal += value
            elif name == "swap":
                act = target_slot.actor
                mid = act.GetBattleCard(1)
                avail = [s for s in (act.GetBattleCard(2), act.GetBattleCard(3)) if s]
                if mid and avail:
                    back = avail[random.randrange(len(avail))]
                    act.battle_slot[0], act.battle_slot[back.pos - 1] = act.battle_slot[back.pos - 1], act.battle_slot[0]
                    act.battle_slot[0].pos = 1
                    act.battle_slot[back.pos - 1].pos = back.pos
            elif name == "destroy":
                if target_slot.cur_ad > 0:
                    target_slot.cur_ad = 0
                    target_slot.CleanItem()
            elif name == "unsummon":
                act = target_slot.actor
                act.battle_slot[target_slot.pos - 1] = None
                act.CompactSlots()
                if target_slot.monster:
                    act.monster_card.append(target_slot.monster)
                    act.monster_len = len(act.monster_card)
            elif name == "disarm":
                if target_slot.cur_ad > 0:
                    target_slot.CleanItem()
            elif name == "boost" or name == "armor":
                target_slot.cur_ad += value
        return events

    def GetAllSlots(self, actor):
        return [s for i in range(3) if (s := actor.battle_slot[i])]

    def GetAllEnemySlots(self, actor):
        other = self.enemy if actor is self.own else self.own
        return self.GetAllSlots(other)

    def HealSlot(self, slot, value, events):
        if not slot or not slot.monster:
            return
        healed = min(value, slot.monster.hp - slot.cur_hp)
        if healed > 0:
            slot.cur_hp += healed

    def DamageSlot(self, slot, damage, events, src_slot=None, damage_type="others"):
        if not slot or not slot.monster or slot.IsDead():
            return 0
        dealt = 0
        if damage_type == "magic":
            reflect = slot.GetPowerValue("reflect")
            if reflect > 0 and random.randint(1, 100) <= 75 and src_slot:
                self.DamageSlot(src_slot, damage, events, None, "magic")
                return damage
            mshield = slot.GetPowerValue("mshield")
            damage = max(0, damage - mshield)
        elif damage_type in ("melee", "ranged"):
            shield = slot.GetPowerValue("shield")
            damage = max(0, damage - shield)

        # armor absorbs physical
        if damage_type in ("melee", "ranged") and slot.cur_ad > 0:
            breaker = src_slot.GetPowerValue("breaker") if src_slot else 0
            armor_dmg = damage
            if breaker > 0:
                armor_dmg = int(armor_dmg * 1.5)
            absorbed = min(slot.cur_ad, armor_dmg)
            slot.cur_ad -= absorbed
            dealt += absorbed
            if slot.cur_ad <= 0:
                slot.CleanItem()
            damage -= absorbed
            if damage <= 0:
                return dealt

        slot.cur_hp -= damage
        dealt += damage

        if slot.IsDead():
            if slot.HasPower("regenerate") and not slot.used_regenerate:
                slot.used_regenerate = True
                slot.cur_hp = 1
                return dealt
            slot.actor.battle_slot[slot.pos - 1] = None
            slot.actor.CompactSlots()
            slot.actor.dead_num += 1
            if src_slot:
                src_slot.actor.cur_crystal += 1
        return dealt

    # --- combat ---
    def RunCombat(self):
        self.ApplyRoundStartPowers()
        own_list = [s for i in range(3) if (s := self.own.battle_slot[i]) and s.monster and not s.IsDead()]
        enemy_list = [s for i in range(3) if (s := self.enemy.battle_slot[i]) and s.monster and not s.IsDead()]
        for attacker in own_list:
            if attacker.monster and not attacker.IsDead():
                self.SlotAttack(attacker)
            if self.is_over:
                break
        for attacker in enemy_list:
            if attacker.monster and not attacker.IsDead():
                self.SlotAttack(attacker)
            if self.is_over:
                break
        if not self.is_over:
            self.CheckGameOver()

    def ApplyRoundStartPowers(self):
        for actor in (self.own, self.enemy):
            for i in range(3):
                slot = actor.battle_slot[i]
                if slot:
                    for st in ("rallied", "demoralized", "antimagicd", "charged", "cautious"):
                        slot.DelStatus(st)
                    for name in list(slot.status_map):
                        st = slot.status_map[name]
                        st["round"] -= 1
                        if st["round"] <= 0:
                            del slot.status_map[name]

        def apply(actor, enemy):
            for i in range(3):
                slot = actor.battle_slot[i]
                if slot and slot.monster:
                    if slot.HasPower("rally"):
                        v = slot.GetPowerValue("rally")
                        for j in range(3):
                            s = actor.battle_slot[j]
                            if s and s.monster:
                                s.SetStatus("rallied", 1, max(s.GetStatusValue("rallied"), v))
                    if slot.HasPower("demoralize"):
                        v = slot.GetPowerValue("demoralize")
                        for j in range(3):
                            s = enemy.battle_slot[j]
                            if s and s.monster and not s.HasPower("immunity"):
                                s.SetStatus("demoralized", 1, max(s.GetStatusValue("demoralized"), v))
                    if slot.HasPower("antimagic"):
                        v = slot.GetPowerValue("antimagic")
                        for j in range(3):
                            s = enemy.battle_slot[j]
                            if s and s.monster and not s.HasPower("immunity"):
                                s.SetStatus("antimagicd", 1, max(s.GetStatusValue("antimagicd"), v))
                    if slot.HasPower("charge") and not slot.used_charge:
                        slot.used_charge = True
                        v = slot.GetPowerValue("charge")
                        slot.SetStatus("charged", 1, max(slot.GetStatusValue("charged"), v))
                    if slot.HasPower("cautious"):
                        slot.SetStatus("cautious", 1, 1)
        apply(self.own, self.enemy)
        apply(self.enemy, self.own)

    def SlotAttack(self, attacker):
        if not attacker.monster or attacker.IsDead():
            return
        if not attacker.CanAttack():
            return
        enemy = self.enemy if attacker.actor is self.own else self.own

        magic = attacker.GetMagicStrength()
        if magic > 0 and not attacker.IsSilenced():
            target = enemy.GetBattleCard(attacker.pos)
            if not target:
                target = self.GetFrontSlot(enemy)
            if target and target.monster:
                self.DamageSlot(target, magic, [], attacker, "magic")
                self.AfterHit(attacker, target, "magic", magic)
            return

        has_melee = attacker.GetMeleeStrength() > 0
        can_melee = attacker.pos == 1 or attacker.HasPower("reach")
        if has_melee and can_melee:
            target = enemy.GetBattleCard(1)
            if not target:
                target = self.GetFrontSlot(enemy)
            if target and target.monster:
                dmg = attacker.GetMeleeStrength()
                self.DamageSlot(target, dmg, [], attacker, "melee")
                self.AfterHit(attacker, target, "melee", dmg)
                if attacker.HasPower("thrash"):
                    backs = [s for i in range(1, 3) if (s := enemy.battle_slot[i]) and s.monster]
                    if backs and target.monster and not target.IsDead():
                        ts = backs[random.randrange(len(backs))]
                        tdmg = attacker.GetPowerValue("thrash")
                        self.DamageSlot(ts, tdmg, [], attacker, "melee")
                if attacker.HasPower("trample") and attacker.pos == 1:
                    tdmg = attacker.GetPowerValue("trample")
                    for i in range(1, 3):
                        s = enemy.battle_slot[i]
                        if s and s.monster:
                            self.DamageSlot(s, tdmg, [], attacker, "melee")
            return

        ranged = attacker.GetRangedStrength()
        if ranged > 0 and attacker.pos != 1:
            diag = 3 if attacker.pos == 2 else 2
            target = enemy.GetBattleCard(diag)
            if not target or not target.monster:
                target = self.GetFrontSlot(enemy)
            if target and target.monster:
                aggros = [s for i in range(3) if (s := enemy.battle_slot[i]) and s.monster and s.HasPower("aggro")]
                if aggros:
                    target = aggros[random.randrange(len(aggros))]
                if target.HasPower("stealth") and target.pos != 1:
                    target = self.GetFrontSlot(enemy)
                if target and target.monster:
                    dmg = attacker.GetRangedStrength()
                    blocked = False
                    if target.cur_ad > 0 and random.randint(1, 100) <= 25 and not attacker.HasPower("breaker"):
                        blocked = True
                    if not blocked:
                        self.DamageSlot(target, dmg, [], attacker, "ranged")
                        self.AfterHit(attacker, target, "ranged", dmg)
            return

    def GetFrontSlot(self, actor):
        for i in range(3):
            s = actor.battle_slot[i]
            if s and s.monster:
                return s
        return None

    def AfterHit(self, attacker, target, attack_type, dmg):
        if not target.monster or target.IsDead():
            if attacker.HasPower("drain_crystal"):
                attacker.actor.cur_crystal += 1
            return
        target_cautious = target.IsCautious()
        if not target_cautious and target.HasPower("thorns") and attack_type == "melee":
            td = target.GetPowerValue("thorns")
            self.DamageSlot(attacker, td, [], target, "melee")
        if not target_cautious and target.HasPower("counter") and attack_type == "melee":
            if random.randint(1, 100) <= 50 and attacker.monster and not attacker.IsDead():
                self.DamageSlot(attacker, dmg, [], target, "melee")
        if attack_type in ("melee", "ranged") and attacker.HasPower("disease"):
            if not target.HasPower("immunity"):
                target.SetStatus("diseased", 2, 1)
        if attacker.HasPower("disarm") and target.cur_ad > 0:
            target.CleanItem()

    # --- AI (mirrors offline_battle:AIDoPrep, generalized to any actor) ---
    def ai_do_prep(self, actor, enemy_actor):
        # Phase 0: sacrifice unaffordable hand cards (most expensive first)
        for _ in range(4):
            sacrifice_idx = None
            sacrifice_cost = -1
            for i in range(1, 5):
                c = actor.GetHandCard(i)
                if c and c.cost > actor.cur_crystal and c.cost > sacrifice_cost:
                    sacrifice_idx = i
                    sacrifice_cost = c.cost
            if not sacrifice_idx:
                break
            card = actor.GetHandCard(sacrifice_idx)
            crystal_gain = C.CARD_IMMOLATION_CRYSTAL.get(card.type, 1)
            for p in card.power_list or []:
                if p["name"] == "crystal":
                    crystal_gain += p["value"]
            new_card = actor.DrawCard(card.type)
            actor.SetHandCard(sacrifice_idx, new_card)
            actor.cur_crystal += crystal_gain

        # deploy monsters while affordable (cheapest first)
        for _ in range(8):
            slot_pos = actor.GetCurMonsterSlotPos()
            if slot_pos == 0:
                break
            best_idx, best_cost = None, None
            for i in range(1, 5):
                c = actor.GetHandCard(i)
                if c and c.type == "monster" and c.cost <= actor.cur_crystal and actor.cur_crystal > 0:
                    if best_cost is None or c.cost < best_cost:
                        best_idx, best_cost = i, c.cost
            if not best_idx:
                break
            card = actor.GetHandCard(best_idx)
            self.DeployMonster(actor, card, slot_pos)
            actor.cur_crystal -= card.cost
            if actor.cur_crystal < 0:
                actor.cur_crystal = 0
            new_card = actor.DrawCard("monster")
            actor.SetHandCard(best_idx, new_card)

        # equip items on monsters
        for _ in range(8):
            best_idx, best_slot = None, None
            for i in range(1, 5):
                c = actor.GetHandCard(i)
                if c and (c.type in ("equip", "armor")) and c.cost <= actor.cur_crystal and actor.cur_crystal > 0:
                    for j in range(3):
                        s = actor.battle_slot[j]
                        if s and s.monster and not s.item:
                            all_flag = 1 << 6
                            if (c.kind & all_flag) != 0 or (s.monster.kind & c.kind) == c.kind:
                                best_idx = i
                                best_slot = s
                                break
                    if best_idx:
                        break
            if not best_idx:
                break
            card = actor.GetHandCard(best_idx)
            self.EquipItem(best_slot, card)
            actor.cur_crystal -= card.cost
            if actor.cur_crystal < 0:
                actor.cur_crystal = 0
            new_card = actor.DrawCard("item")
            actor.SetHandCard(best_idx, new_card)

        # use healing consume cards on damaged allies
        for _ in range(8):
            use_idx, use_slot = None, None
            for i in range(1, 5):
                c = actor.GetHandCard(i)
                if c and c.type == "consume" and c.cost <= actor.cur_crystal and actor.cur_crystal > 0:
                    is_heal = any(p["name"] in ("heal", "heal_all") for p in c.power_list or [])
                    if is_heal:
                        for j in range(3):
                            s = actor.battle_slot[j]
                            if s and s.monster and s.cur_hp < s.monster.hp:
                                use_idx, use_slot = i, s
                                break
                    if use_idx:
                        break
            if not use_idx:
                break
            card = actor.GetHandCard(use_idx)
            self.ApplyCardPowers(card, use_slot, actor)
            actor.cur_crystal -= card.cost
            if actor.cur_crystal < 0:
                actor.cur_crystal = 0
            new_card = actor.DrawCard("item")
            actor.SetHandCard(use_idx, new_card)
            self.CheckGameOver()
            if self.is_over:
                return
