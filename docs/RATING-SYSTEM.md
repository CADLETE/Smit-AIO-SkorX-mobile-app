# SkorX ARC: rating engine

Status as of 27 Sep 2026. The engine runs in the app (`lib/features/rating/`) on sample data; no server endpoint exists yet. The full product spec (naming, 21 simulations, schema, API, admin controls) is the SkorX ARC spec doc; the plain-language guide is `SkorX-Rating-System-Guide.pdf`.

## The three numbers

| Number | Meaning | Moves |
|---|---|---|
| SkorX Points (SXP) | Career total; drives the 12 levels | Only up (except audited reversals) |
| Power Index (SPI) | Skill now, 0–100; drives rank and opponent strength | Up and down |
| Heat | Recent form: % the player's point share beat expectation, last 10 rated matches | Up and down |

## Per match (`arcRate` in `arc_engine.dart`)

```text
PWR = points won / points played          (all games summed)
E   = 1 / (1 + e^(−0.5 · (θ_me − θ_them))),  θ = ln(SPI / (100 − SPI))
      doubles: θ_team = 0.55 · weaker + 0.45 · stronger

Raw  = 2 + 10·PWR + (won ? 4 + 4·(PF−PA)/(PF+PA) : 0) + 25·max(0, PWR − E)
ΔSXP = min(60, Raw · OD · MW · TF · RF · DF · G)
  OD = 0.4 + 1.2 · SPI_opponent / 100
  MW = type (casual 0.6, club 0.8, league 1.0, tournament 1.2, championship 1.4)
       × stage (pool 1.00, QF 1.05, SF 1.10, final 1.15), max 1.6
  TF = trust (T1 1.0, T2 0.95, T3 0.8, T4 0.6, T5 0)
  RF = 0.7^(earlier matches vs same line-up in 30 days), min 0.15
  DF = 0.5 from the 7th match of a day
  G  = 1, or 0.5^((SXP − Cap)/100) above Cap = 200 + 10 · SPI

Δθ  = clip(K · V · C · (PWR − E), ±0.45 provisional / ±0.20 confirmed)
  K = 0.6 + 2.4 · e^(−matches/10)
  V = SPI trust (T1 1.0, T2 0.95, T3 0.8, T4/T5 0) × 0.7 casual × 0.5 retired
  C = mean over other players of 0.4 + 0.6 · (1 − e^(−matches/10))
```

## In the app

| Piece | Where |
|---|---|
| Engine, levels, Heat | `lib/features/rating/arc_engine.dart` |
| Match → engine, career replay, `ArcSummary` | `lib/features/rating/arc_career.dart` |
| Level bar, Power/Heat tiles, formats, breakdown, explainer | `lib/features/rating/ui/arc_widgets.dart` |
| Result-screen estimate after a friendly | `lib/features/rating/ui/arc_match_result.dart` |
| Each match's impact | `Match.arc`; `ratingBefore`/`ratingChange` are its rounded SXP |
| Sample season replayed through the engine | `SampleSeason` in `match_repository.dart` |
| Tests pinned to the spec's numbers | `test/features/rating/arc_engine_test.dart` |

Until verification is stored per match, trust is inferred from the match kind: tournament T1, league T2, friendly T3.

## Still to build

- Server: the same engine on `POST /match/complete`, the score ledger, and `GET /player/:id/skorx`.
- Store verification (confirm/dispute) per match; self-reported matches at T4.
- Leaderboards ranked by Power Index (sample boards still list sample values on the SXP scale).
- Archetypes and the 40 achievements from the spec.
