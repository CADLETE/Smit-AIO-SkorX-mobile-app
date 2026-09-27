# SkorX ARC: rating engine

Status as of 27 Sep 2026 (engine `arc-2.0`). The engine runs in the app (`lib/features/rating/`) on sample data; no server endpoint exists yet. `SkorX-Rating-System-Guide.pdf` still describes the old SkorX Points formula (arc-1.0) and needs a new edition.

## What players see: two numbers

Players see two numbers, and the app never mixes them up.

| Number | Code name | Meaning | Moves | Used for |
|---|---|---|---|---|
| **SkorX Rating** | SPI | Skill now, 0–100, one decimal ("42.6") | Up and down | Rankings, seeding, opponent strength, Explore's skill band |
| **SkorX Points** | SXP | The Career Score: built only from points scored | Only up (except audited reversals) | The 14 levels, points badges |

The principle: **play, score, earn, level up.** The points a player scores are the points that build their SkorX career, like a cricketer's career runs.

- **Bands** (`SkorxBand`): Beginner < 40 · Intermediate 40–55 · Advanced 55–70 · Pro ≥ 70. New players start at 35, which is Beginner. Explore's player "level" is the band.
- **Settling:** for the first 10 verified matches the rating is provisional. It moves faster and shows "Still settling: n of 10".
- **Heat** (recent form) is still computed (`arcHeat`) but not shown.
- **Level vs skill:** a level shows how far a career has come, not how well someone plays. Skill is the SkorX Rating. Rank, W/L, point win % and form are separate stats.
- Where each number lives: My Play has a SkorX Rating section (band ladder, 30-day change, graph, per format), then Ranking, then a SkorX Points section (total, earned in 30 days, level, per format). Home leads with the rating and has a Points tile. Match detail shows "Rating and Points": the rating move with a one-line reason, then the **SkorX Score update**. Match rows show "+0.55 SXP".

## SkorX Points (`arcRate` in `arc_engine.dart`)

```text
SXP_player = P_side ÷ D ÷ N

P_side = actual points the player's side scored, summed over every game played
D      = 20 casual (friendly, club) · 10 tournament (tournament, league, championship)
N      = players on the side: 1 singles · 2 doubles · 2 mixed doubles

Career Score = Σ SXP_player over every credited match (minus reversals)
```

Nothing else goes in. Opponent strength, winning, margin, stage, match quality, repeat opponents, matches per day and career size have no effect.

| Match | Casual | Tournament |
|---|---|---|
| Singles 11–8 | 0.55 / 0.40 | 1.10 / 0.80 |
| Doubles 11–8, each player | 0.275 / 0.20 | 0.55 / 0.40 |
| Mixed 11–9, each player | 0.275 / 0.225 | 0.55 / 0.45 |
| Doubles best of 3 11–8, 8–11, 11–9 (30–28), each | 0.75 / 0.70 | 1.50 / 1.40 |

The full example tables (10 singles, 10 doubles, 5 mixed) are pinned in `test/features/rating/arc_engine_test.dart`.

**Trust.** SXP is all or nothing. Matches verified by a tournament (T1), an organiser (T2) or every player (T3) credit every point; self-reported (T4) and unverified (T5) credit none. Casual matches count only once every player confirms (docs/CASUAL-VERIFICATION.md).

**Precision.** SXP is kept in exact units of 1/40 point (`Sxp`): casual doubles, points ÷ 40, is the smallest step, so every contribution and every total is a whole number of units. Nothing is rounded until display, which is always 2 decimals, half up (0.275 shows 0.28). On the score update the change shown is new − previous as displayed, so the three numbers always add up; this can differ from the rounded exact gain by 0.01 (684.225 + 0.275 shows 684.23 → 684.50, +0.27).

## Edge cases

| Case | Rule |
|---|---|
| 11–0 | Winner 0.55 / 1.10. The loser earns 0 but the match still counts as played. |
| 11–1, 11–10, 15–13, 21-point, rally or side-out | Face value. No normalising by format: longer formats play more points and earn more. |
| Best of 3 / 5, several games | All valid points across every game played. |
| Tiebreak / super-tiebreak game | A game like any other; its points count. |
| Walkover, forfeit before play | 0 for both sides. Awarded scores are not actual points. |
| Retirement | Points actually played up to the retirement count for both sides; the rest is not awarded. The retiring side can earn more than the winner. |
| Abandoned, no result | 0. An organiser can mark a result as standing; if the match is replayed, only the replay counts. |
| Invalidated, cancelled after credit, duplicate | A reversal entry equal to the credit. The level can go down. |
| Score corrected | Reversal of the old credit, then a credit for the corrected score. |
| Casual match waiting for confirmation | Shown as pending; credited on verification. |

## Levels (`ArcLevel`)

Levels come from the Career Score alone, with no other gates. The steps widen as a career grows. Rough time to reach each level, by typical activity (casual doubles ≈ 0.23 a game, tournament best of 3 doubles ≈ 1.1 a match):

| Lv | From | Name | Weekend (~100/yr) | Regular (~200/yr) | Competitive (~300/yr) | Grinder (~500/yr) |
|---|---|---|---|---|---|---|
| 1 | 0 | First Serve | day 1 | day 1 | day 1 | day 1 |
| 2 | 10 | Baseliner | ~5 wk | ~3 wk | ~2 wk | ~1 wk |
| 3 | 25 | Kitchen Walker | ~3 mo | ~6 wk | ~1 mo | ~3 wk |
| 4 | 50 | Dinksmith | ~6 mo | ~3 mo | ~2 mo | ~5 wk |
| 5 | 100 | Centurion | ~1 yr | ~6 mo | ~4 mo | ~2.5 mo |
| 6 | 200 | Point Builder | ~2 yr | ~1 yr | ~8 mo | ~5 mo |
| 7 | 350 | Rally Forger | ~3.5 yr | ~1.8 yr | ~1.2 yr | ~8 mo |
| 8 | 600 | Net Raider | 6 yr | 3 yr | 2 yr | ~1.2 yr |
| 9 | 1,000 | Court Marshal | 10 yr | 5 yr | 3.3 yr | 2 yr |
| 10 | 1,750 | Clutch Caller | | ~9 yr | ~6 yr | 3.5 yr |
| 11 | 3,000 | Paddle Ronin | | 15 yr | 10 yr | 6 yr |
| 12 | 5,000 | Rally Monarch | | | ~17 yr | 10 yr |
| 13 | 7,500 | Evergreen | | | | 15 yr |
| 14 | 10,000 | SkorX Legend | | | | ~20 yr |

The score keeps counting past 10,000; there is no ceiling in the engine or the schema. Known consequences: singles earns twice what doubles earns per player for the same scoreline, and winning adds nothing beyond the points scored.

## SkorX Rating (unchanged from arc-1.0)

```text
PWR = points won / points played          (all games summed)
E   = 1 / (1 + e^(−0.5 · (θ_me − θ_them))),  θ = ln(SPI / (100 − SPI))
      doubles: θ_team = 0.55 · weaker + 0.45 · stronger

Δθ  = clip(K · V · C · (PWR − E), ±0.45 provisional / ±0.20 confirmed)
  K = 0.6 + 2.4 · e^(−matches/10)
  V = SPI trust (T1 1.0, T2 0.95, T3 0.8, T4/T5 0) × 0.7 casual × 0.5 retired
  C = mean over other players of 0.4 + 0.6 · (1 − e^(−matches/10))
```

Heat weights each recent match by type × stage (casual 0.6 … championship 1.4; pool 1.00 … final 1.15, capped at 1.2). Those weights never touch SXP.

## In the app

| Piece | Where |
|---|---|
| Engine, `Sxp` maths, levels, Heat | `lib/features/rating/arc_engine.dart` |
| Match → engine, career replay, `ArcSummary` | `lib/features/rating/arc_career.dart` |
| Rating panel, Points panel + level bar, `SxpUpdate` (the SkorX Score update), breakdown, explainer | `lib/features/rating/ui/arc_widgets.dart` |
| Result screen after a friendly: SXP earned, previous → new Career Score | `lib/features/rating/ui/arc_match_result.dart` |
| Each match's impact | `Match.arc`; `pointsBefore`/`pointsEarned` are its SXP to 2 decimals |
| Display text | `sxpText` / `sxpDeltaText` in `lib/shared/format.dart` |
| Sample season replayed through the engine (starts from 612.40 SXP) | `SampleSeason` in `match_repository.dart` |
| Tests pinned to the tables above | `test/features/rating/arc_engine_test.dart` |

Until verification is stored per match, trust is inferred from the match kind: tournament T1, league T2, friendly T3.

## Server: the Career ledger (to build)

The engine moves to NestJS on match completion (tournament) or verification (casual). The ledger stores actual points, not only the result, so every score can be audited and recalculated.

- **`career_ledger`**, append-only, one row per player per match event:
  - `id`, `playerId`, `sportId`, `matchId`, `tournamentId?`
  - `matchCategory` (casual | tournament), `playFormat` (singles | doubles | mixed)
  - `actualPoints Int`, `opponentPoints Int`, `playersOnSide Int`, `divisor Int`
  - `sxpUnits Int`, `sxp Decimal(12,4)`, `careerBefore Decimal(14,4)`, `careerAfter Decimal(14,4)`
  - `entryType` (credit | reversal), `reversesId?`, `reason?`, `engineVersion`
  - `matchCompletedAt`, `createdAt`
  - Unique on (playerId, matchId, entryType, reversesId), so a match is never credited twice.
- **`player_career`** cache: `careerScore Decimal(14,4)`, `careerUnits BigInt`, `level Int`, `matchesCounted Int`. It can always be rebuilt from the ledger.
- **`MatchGame`**: a played/awarded split, so a retirement's awarded points are never counted.
- **`Match`**: `careerStatus` (pending | credited | held | excluded | reversed), `careerNote`.
- **`Tournament`**: `careerEligible`. Only approved tournaments convert at ÷10; any other event converts as casual.
- `GET /player/:id/skorx` returns the rating, the Career Score, the level and the ledger.

## Anti-gaming: controls around the formula, never inside it

- Casual matches count only when every player has confirmed them.
- Players on a counted match must hold verified accounts. Self-created and guest names do not earn.
- Duplicates are detected by the creating phone's `clientRef`, then the same line-up and score close in time.
- Suspicious patterns are **held** for review, not reduced:
  - the same line-up repeated
  - more than 15 casual matches a day
  - impossible scores (11–10 in a win-by-2 game)
  - games too short for their score
- Tournament conversion needs `careerEligible`, which requires a verified organiser and published draws. Creating fake tournaments is the biggest loophole, and this closes it.

## Still to build

- Server: the same engine on `POST /match/complete`, the ledger above, and `GET /player/:id/skorx`.
- ~~Store verification (confirm/dispute) per match~~: built (docs/CASUAL-VERIFICATION.md). Only verified casual matches reach `PlayerRecord`; the server engine must read `officialMatchWhere`. Map verified casual to T3 and self-reported (unverified) to T4 when the engine moves server-side.
- Real leaderboards ranked by SkorX Rating (the sample boards already use the rating scale).
- Archetypes and the 40 achievements from the spec.
