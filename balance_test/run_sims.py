"""Head-to-head deck-size balance tests.

Compares 4 monster + 4 equip, 6 monster + 6 equip, and the current 8 + 8
constructed deck using the real card data and a faithful port of the battle
engine (balance_test/engine.py).

Both sides are driven by the identical greedy AI, so any win-rate difference
between two decks isolates the deck design (size / composition / card quality).
Round-50 stalemates are reported separately (they go to the first player).

Experiments:
  A. Mirror matches  (deck_S vs deck_S): pacing, variance, stalemate rate.
  B. Cross matches    (deck_a vs deck_b): relative strength, both orientations
                     averaged so first-mover bias cancels out.
  C. Power-equalized  (smaller deck draws the strongest cards): how far card
                     quality can compensate for a smaller army.
"""
import sys, os, random, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cardloader
from engine import Battle, build_card_info


def _hp(card):
    return card.hp if hasattr(card, "hp") else int(card.get("hp") or 0)

def _cost(card):
    return card.cost if hasattr(card, "cost") else int(card.get("cost") or 0)

def _powers(card):
    return card.power_list if hasattr(card, "power_list") else card.get("power_list") or []


def attack_value(card):
    return max((p["value"] for p in _powers(card) if p["name"] in ("melee", "ranged", "magic")),
               default=0)


def power_score(card):
    # rough power proxy used to rank/equalize decks
    return attack_value(card) * 2 + _hp(card) + _cost(card)


def make_card(config, uid):
    return build_card_info(config, uid)


def run_match(deck_a, deck_b, seed):
    """deck_a as player (first), deck_b as enemy. Returns result dict."""
    b = Battle({"monster_list": list(deck_a[0]), "item_list": list(deck_a[1])},
               {"monster_list": list(deck_b[0]), "item_list": list(deck_b[1])},
               seed=seed)
    b.Start()
    for _ in range(200):
        if b.is_over:
            break
        b.ai_do_prep(b.own, b.enemy)
        b.run_full_turn()
    return {
        "winner": b.win_user_id,
        "rounds": b.round,
        "own_survive": b.own.GetMonsterTotal(),
        "enemy_survive": b.enemy.GetMonsterTotal(),
        "tiebreak": b.round >= 50,
    }


def mirror_stats(deck, n, start_seed=0):
    wins = {"player": 0, "enemy": 0, "draw": 0}
    rounds, surv, decisive = [], [], []
    for i in range(n):
        r = run_match(deck, deck, start_seed + i)
        rounds.append(r["rounds"])
        surv.append(max(r["own_survive"], r["enemy_survive"]))
        if r["tiebreak"]:
            wins["draw"] += 1
        else:
            wins[r["winner"]] += 1
            decisive.append(r["rounds"])
    dec = decisive if decisive else [0]
    return {"wins": wins, "n": n,
            "rounds_avg": statistics.mean(rounds), "rounds_stdev": statistics.stdev(rounds) if n > 1 else 0,
            "decisive_avg": statistics.mean(dec), "decisive_stdev": statistics.stdev(dec) if len(dec) > 1 else 0,
            "survive_avg": statistics.mean(surv), "survive_stdev": statistics.stdev(surv) if n > 1 else 0}


def cross_stats(deck_a, deck_b, n, seed_base):
    """Averaged over both orientations to cancel first-mover bias.
    Returns a dict keyed by 'a_win', 'b_win', 'draw' (counts), winrate of A,
    margin (a survive - b survive, A-first orientation), avg rounds."""
    wins = {"a": 0, "b": 0, "draw": 0}
    margins, rounds = [], []
    for i in range(n):
        r = run_match(deck_a, deck_b, seed_base + i)
        if r["tiebreak"]:
            wins["draw"] += 1
        else:
            wins["a" if r["winner"] == "player" else "b"] += 1
        margins.append(r["own_survive"] - r["enemy_survive"])
        rounds.append(r["rounds"])
    for i in range(n):
        r = run_match(deck_b, deck_a, seed_base + 100000 + i)
        if r["tiebreak"]:
            wins["draw"] += 1
        else:
            wins["b" if r["winner"] == "player" else "a"] += 1
        rounds.append(r["rounds"])
    total = wins["a"] + wins["b"] + wins["draw"]
    return {"wins": wins, "total": total,
            "a_winrate": wins["a"] / total if total else 0,
            "a_win_or_draw": (wins["a"] + wins["draw"]) / total if total else 0,
            "margin_avg": statistics.mean(margins),
            "rounds_avg": statistics.mean(rounds),
            "rounds_stdev": statistics.stdev(rounds) if 2 * n > 1 else 0}


def percentile_threshold(sorted_cards, pct):
    """Returns the power_score value at the top `pct`% of a descending-sorted card list."""
    if not sorted_cards:
        return 0
    cutoff = max(1, int(len(sorted_cards) * pct / 100.0))
    return power_score(sorted_cards[min(cutoff, len(sorted_cards)) - 1])


def main():
    cfg = cardloader.load_card_configs("../csv_data/all_card_config.csv")

    def atk(c):
        return max((p["value"] for p in c["power_list"] if p["name"] in ("melee", "ranged", "magic")), default=0)

    # Baseline pool: generic cost-2 monsters (4hp, ~2 atk) + all-kind equips cost 3-4.
    monster_pool = [c for c in cfg.values() if c["type"] == "monster" and c["cost"] == 2
                    and c["hp"] == 4 and atk(c) >= 1]
    equip_pool = [c for c in cfg.values() if c["type"] in ("equip", "armor")
                  and (c["kind"] & 64) and c["cost"] in (3, 4) and c["hp"] >= 3]
    # Strongest cards in the whole set (for experiment C equalization).
    all_mons = sorted((c for c in cfg.values() if c["type"] == "monster"),
                      key=power_score, reverse=True)
    all_eq = sorted((c for c in cfg.values() if c["type"] in ("equip", "armor")),
                    key=power_score, reverse=True)

    print("Pools: baseline monsters=%d equips=%d | strongest monsters=%d equips=%d"
          % (len(monster_pool), len(equip_pool), len(all_mons), len(all_eq)))
    print("=" * 80)

    def build(size, rng, mpool=None, epool=None):
        mpool = mpool or monster_pool
        epool = epool or equip_pool
        monsters = [make_card(mpool[rng.randrange(len(mpool))], "p%d_%d" % (i, size)) for i in range(size)]
        equips = [make_card(epool[rng.randrange(len(epool))], "e%d_%d" % (i, size)) for i in range(size)]
        return monsters, equips

    def build_top(size, mpool, epool, rng):
        # take top `size` distinct cards (deck_limit=2 => allow 2 copies of each of the top size/2)
        mtop = mpool[:size]
        etop = epool[:size]
        monsters = [make_card(m, "p%d_%s" % (i, m["uid"])) for i, m in enumerate(mtop)]
        equips = [make_card(e, "e%d_%s" % (i, e["uid"])) for i, e in enumerate(etop)]
        return monsters, equips

    decks = {}
    for size in (4, 6, 8):
        rng = random.Random(12345 + size)
        decks[size] = build(size, rng)
        ms = decks[size][0]
        es = decks[size][1]
        print("Deck %d+%d : atk avg=%.2f mhp=%.1f ecost=%.2f ehp=%.1f total_score=%.0f"
              % (size, size,
                 statistics.mean([attack_value(c) for c in ms]), statistics.mean([_hp(c) for c in ms]),
                 statistics.mean([_cost(c) for c in es]), statistics.mean([_hp(c) for c in es]),
                 sum(power_score(c) for c in ms) + sum(power_score(c) for c in es)))
    print("=" * 80)

    N = 1500

    print("EXPERIMENT A — MIRROR (deck vs identical):  pacing & consistency  (n=%d)" % N)
    print("%-8s %-22s %-12s %-14s %-12s" % ("deck", "win split (P/E/draw)", "avg rounds", "decisive len", "survive"))
    for size in (4, 6, 8):
        r = mirror_stats(decks[size], N, start_seed=1000 + size)
        w = r["wins"]
        print("%-8s %-22s %-12s %-14s %-12s" % (
            "%d+%d" % (size, size),
            "%d/%d/%d  (%.0f/%.0f/%.0f)" % (w["player"], w["enemy"], w["draw"],
                                            w["player"] / N * 100, w["enemy"] / N * 100, w["draw"] / N * 100),
            "%.1f ± %.1f" % (r["rounds_avg"], r["rounds_stdev"]),
            "%.1f ± %.1f" % (r["decisive_avg"], r["decisive_stdev"]),
            "%.1f ± %.1f" % (r["survive_avg"], r["survive_stdev"])))
    print()

    print("EXPERIMENT B — CROSS-SIZE (same card quality, both orientations averaged):  n=%d each way" % N)
    print("%-16s %-12s %-12s %-12s" % ("matchup", "A win%", "A win/draw%", "avg rounds"))
    for a, bsize in [(4, 6), (4, 8), (6, 8), (6, 4), (8, 4), (8, 6)]:
        r = cross_stats(decks[a], decks[bsize], N, seed_base=3000 + a * 100 + bsize)
        print("%-16s %-12s %-12s %-12s" % ("%d+%d vs %d+%d" % (a, a, bsize, bsize),
                                           "%.1f%%" % (r["a_winrate"] * 100),
                                           "%.1f%%" % (r["a_win_or_draw"] * 100),
                                           "%.1f" % r["rounds_avg"]))
    print()

    print("EXPERIMENT C — POWER-EQUALIZED:  smaller deck draws the STRONGEST cards in the whole set")
    print("(baseline 8+8 uses average pool; smaller deck uses top-tier cards)  n=%d each way" % N)
    base8 = decks[8]
    for small in (4, 6):
        small_deck = build_top(small, all_mons, all_eq, random.Random(9000 + small))
        r = cross_stats(small_deck, base8, N, seed_base=4000 + small)
        print("%d+%d top-tier vs 8+8 avg :  small-win %.1f%%  (draw %.1f%%, rounds %.1f)"
              % (small, small, r["a_winrate"] * 100,
                 r["wins"]["draw"] / r["total"] * 100, r["rounds_avg"]))
    print()

    print("EXPERIMENT D — STRENGTH SWEEP:  break-even card strength for smaller decks vs 8+8")
    print("(smaller deck samples only the top `pct`%% of cards by power; find where it hits ~50%%)")
    def build_percentile(size, pct, rng):
        mpool = [c for c in all_mons if power_score(c) >= percentile_threshold(all_mons, pct)]
        epool = [c for c in all_eq if power_score(c) >= percentile_threshold(all_eq, pct)]
        if not mpool: mpool = all_mons
        if not epool: epool = all_eq
        monsters = [make_card(mpool[rng.randrange(len(mpool))], "p%d_%d" % (i, size)) for i in range(size)]
        equips = [make_card(epool[rng.randrange(len(epool))], "e%d_%d" % (i, size)) for i in range(size)]
        return monsters, equips

    NS = 4000
    for small in (4, 6):
        print("--- %d+%d deck ---" % (small, small))
        for pct in (100, 50, 30, 20, 10, 5):
            d = build_percentile(small, pct, random.Random(7000 + small * 100 + pct))
            r = cross_stats(d, base8, NS, seed_base=5000 + small * 100 + pct)
            print("  top-%d%% : small-win %.1f%%   (rounds %.1f)" % (pct, r["a_winrate"] * 100, r["rounds_avg"]))
    print()


if __name__ == "__main__":
    main()
