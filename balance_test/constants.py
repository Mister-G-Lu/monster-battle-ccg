"""Constants mirrored from decrypted/common/constants.lua."""
CARD_TYPE = {"monster": "monster", "armor": "armor", "equip": "equip", "consume": "consume"}

CARD_KIND = {"war": 1, "fortune": 2, "balance": 3, "nature": 4, "chaos": 5, "all": 6}

POWER_NAME = set("""melee ranged magic magic_aoe shield mshield rally demoralize antimagic
heal heal_all thrash thorns resonate explode damage damage_all chance crystal reach poison
disease disease_all flying counter armor antidote disarm doom deathstrike stoneskin revive
invincible breaker entangle regenerate reflect boost swipe aggro stealth swap paint trample
charge critical berserk backstab stun silence unsummon decoy antiair immunity cleave draft
destroy repair opportunity cautious drain_crystal""".split())

STATUS_TYPE = {"entangled": "entangled", "diseased": "diseased", "silenced": "silenced",
    "painted": "painted", "demoralized": "demoralized", "antimagicd": "antimagicd",
    "rallied": "rallied", "charged": "charged", "cautious": "cautious"}

CARD_IMMOLATION_CRYSTAL = {
    CARD_TYPE["monster"]: 2, CARD_TYPE["armor"]: 1,
    CARD_TYPE["equip"]: 1, CARD_TYPE["consume"]: 1, "battle": 1,
}

BATTLE_SLOT_MAX = 3
MAX_ROUNDS = 50
