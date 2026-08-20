# Deck-Size Balance Test — 4+4, 6+6, vs the current 8+8

*Date: 2026-08-20 · Engine: faithful Python port of `src/manager/offline_battle.lua` · Data: real `csv_data/all_card_config.csv` (601 monsters, 979 equip/armor)*

## What was tested

I asked the battle engine "what happens if the constructed deck holds **4 monsters + 4 equips**, **6 monsters + 6 equips**, versus the current **8 monsters + 8 equips**"? The `8+8` is what the shipped game actually builds — `offline_server:BuildPlayerDeck` reads 8 `monster_pos` + 8 `item_pos` slots.

**Why deck size matters mechanically.** The engine's constructed-mode win condition is *monster exhaustion*: a side loses when its monster total (hand + deck + board) hits zero. Deck size therefore sets the size of your **monster army** — the pool you grind through. Bigger deck = bigger army = longer attrition advantage. Equips/items are a secondary resource that armors/supports those monsters.

**Method.** Both sides are driven by the identical greedy AI, so a win-rate gap between two decks isolates the *deck design*, not skill. Matches were run in both orientations (each deck goes first half the time) to cancel the game's built-in first-mover advantage. Round-50 stalemates are tallied separately (they resolve to the first player). Baselines used the same card pools so decks differ only in size, not average card quality. The simulator lives in `balance_test/` (`engine.py` port + `run_sims.py`).

---

## Results

### Experiment A — Mirror matches (deck vs an identical copy): pacing & consistency

| deck | win split (P / E / draw) | avg rounds | decisive length | avg survivors |
|------|--------------------------|-----------|-----------------|---------------|
| **4+4** | 43 / 39 / **18%** | 15.3 ± 16.3 | 7.7 | 2.2 |
| **6+6** | 64 / 34 / **2%** | 11.3 ± 5.8 | 10.6 | 3.1 |
| **8+8** | 49 / 39 / **12%** | 21.4 ± 11.7 | 17.3 | 4.8 |

- **6+6 is the "cleanest" format**: shortest average game, lowest variance, almost no stalemates (2%).
- **4+4 is the most volatile**: decisive games end fast (~8 rounds), but a huge 18% of mirror games stall to the round-50 draw — tiny decks mean a handful of draws decide everything, so both the game *length* and the *outcome* swing wildly (σ = 16 rounds).
- **8+8 is the slowest and most grindy**: ~21 average rounds, 12% stalemates, biggest survivor counts.

### Experiment B — Cross-size matches, same card quality (both orientations averaged)

| matchup | A win% | avg rounds |
|---------|--------|-----------|
| 4+4 vs 6+6 | 0.0% | 9.5 |
| 4+4 vs 8+8 | 0.0% | 6.9 |
| 6+6 vs 8+8 | **37.1%** | 14.9 |

- **At equal card quality, deck size is a hard balance lever.** A 4+4 essentially cannot beat a 6+6 or 8+8 (~0% win) — it simply has too few monsters to out-attrition the bigger army. A 6+6 wins ~37% against an 8+8: competitive but visibly behind.
- The effect is monotonic and large: going from 8+8 → 6+6 costs ~13 points of win-rate against an 8+8; going 6+6 → 4+4 is catastrophic.

### Experiment C & D — Can stronger cards compensate? (power-equalized decks)

| smaller deck | card quality | win vs 8+8 |
|--------------|--------------|-----------|
| 4+4 | top-tier of whole set | **83%** |
| 6+6 | top-tier of whole set | **61%** |
| 6+6 | top ~20% of set | **~50% (break-even)** |
| 4+4 | (top ~5%) | ~41% but extremely noisy |

- **Card quality *can* restore balance.** Give a 6+6 cards drawn from the top ~20% of the whole set and it reaches ~50/50 against an average 8+8.
- **4+4 is hard to balance by quality alone** — the sweep is non-monotonic and noisy at every tier because four random cards completely dominate the outcome. It never cleanly finds a ~50% point; it jumps from 2% to 28% to 41% with small card-quality changes.

---

## What each deck size produces (the takeaway)

- **4 monsters + 4 equips** — a fast, brutal, *lottery* format. Decisive games are short, but it is wildly inconsistent (18% stalemates, huge variance) and is dominated by bigger decks at equal card quality. Player skill barely matters; the opening hand decides.
- **6 monsters + 6 equips** — the **best-balanced and best-paced** of the three. Lowest variance, fewest stalemates, shortest decisive games, and a real but narrow gap behind 8+8 that strong card picks can close.
- **8 monsters + 8 equips (current)** — the strongest and most consistent *in strength*, but the slowest and most attrition-grindy. It wins at equal quality purely by fielding a bigger army.

### How balance turns out
1. **Bigger decks are strictly stronger at equal card quality** (monster-exhaustion win condition rewards a bigger army). 4+4 < 6+6 < 8+8 in raw strength.
2. **Smaller decks buy speed but at the cost of stability**: 6+6 is the best trade-off (fast + consistent); 4+4 is fast but a coin-flip; 8+8 is reliable but slow/grindy.
3. **If the goal is to shrink the deck for faster games, 6+6 is the sweet spot** — but you must compensate with ~top-20% card quality to keep it fair against the 8+8 baseline.
4. **4+4 is not recommended as a drop-in format**: it can't be reliably rebalanced by card quality because variance dominates, and it's uncompetitive against any bigger deck.

## Files
- `balance_test/engine.py` — faithful Python port of the battle engine (battle + combat + AI).
- `balance_test/cardloader.py` — loads real card data into engine configs (mirrors `data_template`).
- `balance_test/run_sims.py` — the test harness; `python3 balance_test/run_sims.py`.
- `balance_test/sim_results.txt` — captured full output.
