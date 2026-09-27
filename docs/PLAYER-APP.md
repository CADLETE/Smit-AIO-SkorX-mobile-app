# SkorX Player App

Status as of 25 Sep 2026. This replaces `PLAYER-APP-REDESIGN.md`, whose direction was dropped: its screens were too dense for a first-time player. Organiser and Referee workspaces are out of scope, apart from the Player ⇄ Organiser switch.

**The principle: your whole pickleball journey in one place.**
Matches → tournaments → results → rating → ranking → achievements, all connected, with the **match** at the centre.

**The rule: one screen, one question.**

| Tab | The question it answers |
|---|---|
| Home | What matters to me right now? |
| Matches | What is being played across SkorX? (every match, not just mine; §6) |
| Explore | Which tournaments, courts, players and people are out there? (Community and Looking For are modules inside it; docs/COMMUNITY.md) |
| My Paddle | How is *my* journey going: my matches, my tournaments, my numbers? |
| Account | Who am I, and how do I control my account? |

Tapping any player (picture or name) anywhere opens their **Quick View**; *View full stats* opens their analytics (§6).

---

## 1. Audit of the previous build

### 1.1 What exists and is kept

| Layer | Kept as is |
|---|---|
| Auth | Phone + WhatsApp OTP, secure tokens, one shared refresh, offline launch from the cached account (`features/auth`, `core/api`). |
| Workspaces | One account, many modes (Player, each organisation, Referee), each with its own shell and remembered place (`features/workspace`). |
| Casual scoring | Create a match, score it offline with undo, resume after a crash (`features/casual_match`, `sports/`). |
| Organiser TMS | Tournaments, entries, draws, schedule, match console (`features/organizer`). Built in parallel; untouched here. |
| Data contracts | `TournamentRepository`, `CourtRepository`, `PlayerRepository`, notifications. Sample data in debug builds, honest empty data in release builds. |
| State / routing | Riverpod 3, go_router 17 with one stateful shell per workspace. |

### 1.2 What the data looked like

- **Match** (`PlayerMatch`): seen from the player's side (`mine`, `theirs`, games as `(mine, theirs)`), status live / upcoming / finished, with the tournament and round **as display strings only**.
- **Tournament**: categories, dates, venue, fees, registration window. The player's registration is a separate `Registration`.
- **Player**: `PlayerOverview` (rating, history, rankings, insights, activity); achievements; leaderboards. The rating and the match deltas were made up separately, so they did not add up.
- **APIs**: only auth and profile exist in the new NestJS API. Every other repository names the endpoint it will call (`GET /me/matches`, `GET /tournaments/:id`, …) and runs on sample data in debug builds.

### 1.3 Problems caused by the old UI architecture

| # | Problem | Effect on a new player |
|---|---|---|
| 1 | Home had seven sections: rating hero, four quick tiles, upcoming match, tournament carousel, performance, activity, insights. | Nothing stands out. It takes a long scroll to see a result. |
| 2 | "Matches" was a sub-tab inside My Paddle. | There was no obvious answer to "where are my matches?" |
| 3 | A match did not know its tournament's **id**, only its name. | You could not go from a match to its tournament or back. There was no tournament journey. |
| 4 | Tournament detail opened with seven info cells, two feature tiles and then categories. | There was no answer to "where am I in this tournament?" |
| 5 | Courts and Tournaments were two separate tabs. | Two tabs did the same job: finding a place to play. |
| 6 | Match history was a synchronous list with no paging. | It would not scale to hundreds of matches. |
| 7 | The rating, rank and record were each worked out in two or three places. | The numbers could disagree between screens. |
| 8 | ₹ was set in Barlow Condensed, which has no ₹ glyph. | Prices showed as "?500". |
| 9 | Dark mode was forced on by default, and light mode was a recolour of it. | Screens were hard to read outdoors, and light mode felt like an afterthought. |
| 10 | Pills, gradients, glows and italic headlines were used on every card. | The app looked busy, not premium. |

---

## 2. Information architecture

### 2.1 Entities

```text
Player ──plays──► Match ◄──contains── Tournament
  │                 │                     │
  │                 ├─ Side A / Side B    ├─ Category (the player's entry)
  │                 ├─ Games              ├─ Rounds / pools
  │                 ├─ Rating change      ├─ Standings
  │                 └─ Timeline           └─ Journey (the player's path through the rounds)
  │
  ├─ Rating  = the sum of rating changes from matches
  ├─ Record  = worked out from finished matches
  ├─ Ranking = rating compared with others (city / state / country / global)
  └─ Achievements = milestones reached through matches, tournaments and rating
```

- A **Match** is the core record. It has an id, a kind (tournament, league or friendly), a format (singles, doubles or mixed), two sides, games, a status, where and when it is played, and a `TournamentRef` (id, name, category, round).
- A **Tournament journey** is worked out from the player's registration plus their matches in that tournament, plus the rounds still to come. It is not stored separately, so it can never disagree with the match list.
- The **Rating** is `ratingBefore + ratingChange` on each rated match, so the rating graph, a match's rating change and the header number all come from the same data.

### 2.2 Navigation

```text
┌ Home ─────────── Matches ────────── Explore ──────────── My Paddle ───────── Profile ┐
│ Now card         Live               Search               Identity + rating    ID card │
│ Last result      Upcoming           Tournaments ⇄ Courts Rating graph         Mode     │
│ 3 actions        Results (grouped)  Your tournaments     Record               Settings │
│ Snapshot         ⤷ My tournaments                        Ranking ⤷ Rankings   Sign out │
│                                                          Badges ⤷ Achievements         │
└──────────────────────────────────────────────────────────────────────────────────────┘
Detail screens (full screen, above the tabs):
  Match ─► Tournament (Journey · Matches · Standings · About) ─► Match …
  Venue ─► time & court sheet ─► Confirm booking ─► Booked
  Notifications · Settings · Edit profile · Rankings · Achievements · My tournaments · My bookings
```

The connected path the brief asks for, and where each step is tapped:

`Home › Next match` → **Match** → `View tournament` → **Tournament › My journey** → `tap any step` → **Match** → `rating change` → **My Paddle** → `Ranking` → **Rankings**

### 2.3 Routes

| Route | Screen |
|---|---|
| `/player/home` | Home (tab) |
| `/player/matches?view=live\|upcoming\|results` | Matches (tab) |
| `/player/explore` | Explore (tab): the hub |
| `/player/explore/tournaments\|players\|courts` | An Explore module, inside the tab (old `?view=` links redirect here) |
| `/player/explore/<coming-soon id>` | Coming-soon page for a module not built yet |
| `/player/paddle` | My Paddle (tab) |
| `/player/profile` | Profile (tab) |
| `/player/matches/:id` | Match detail |
| `/player/tournament/:id?view=journey\|matches\|standings\|about` | Tournament hub |
| `/player/tournament/:id/registered` | Registration confirmed |
| `/player/tournaments/mine` | My tournaments |
| `/player/venue/:id` → `/player/venue/:id/confirm?date&hour&court` | Venue → Confirm booking |
| `/player/bookings` | My bookings |
| `/player/rankings`, `/player/achievements` | Rankings, Achievements |
| `/player/notifications`, `/player/settings`, `/player/edit-profile` | Utility screens |
| `/player/match/new`, `/player/match` | Casual match: create, then score |

Old saved locations (`/player/paddle?tab=matches`, `/player/tournaments`, `/player/courts`, `/player/leaderboard`, `/player/venue/:id/review`) redirect to their new homes.

### 2.4 Screen specs

**Home.** Header: avatar, first name, rating and bell. Then **one Now card**, chosen in this order:

1. A live match: score, game and court → *Follow live*.
2. The next match within 60 minutes: *Starts in 28 min* → *View match*.
3. The next match.
4. No matches at all: the welcome card with *Find a tournament*, *Book a court* and *Score a match*.

After that: the latest result (verdict, games, opponent, rating change), three actions (Book court, Find tournament, My matches), and a snapshot of three numbers (Rating, Win rate, City rank) that opens My Paddle. Nothing else goes on Home.

**Matches.** The title and three tabs: **Live · Upcoming · Results**. Live is only shown when there is a live match. Upcoming is grouped by day (Today, Tomorrow, then dates). Results are grouped Today / This week / This month / Older and load 20 at a time. Top-right: *My tournaments*. Bottom: *Score a friendly match*.

**Match detail.** Header: status, tournament and round. Then the **scoreboard**: both sides on either side of the net line, game by game, and the overall score. Below it: rating before → after, match info (format, category, court, venue, date, duration), the timeline, and *View tournament*.

**Tournament hub.** A calm header: name, dates, venue and the player's status. Four views:

- **My journey** (the default once registered): the signature rail, from Registered through every round to the final.
- **Matches**: the category's matches grouped by round, with the player's own matches marked.
- **Standings**: pool tables.
- **About**: categories, fees, schedule, rules, organiser and the register button.

A player who is not registered lands on About, where the only primary action is *Register*.

**Explore.** A hub, not a list: open modules first (Tournaments, Scores, Players, Courts), two to a row, each with a true live fact when there is one ("2 live", "Live now"); then *Coming to SkorX* (Your Performance, Looking For, Community, Leaderboards, Associations), each marked SOON and opening a coming-soon sheet. Modules are configured in `features/explore/explore_modules.dart`: to switch one on, give it a `location` and make it active. Scores opens the Matches tab; the others open inside Explore with search and filters, as below.
- Tournaments: a strip of "Your tournaments" (only when there are any), simple chips (Near me, This week, Beginner, Doubles…) plus one filter button, then tournament cards. Each card shows only name, date, venue, format, fee, status and one button.
- Courts: city, date strip, then venues. **Booking takes five steps:** location → date → time → court → confirm. Time and court are picked in one bottom sheet.

**My Paddle.** Identity (photo, name, ID, level, preferred format), then:
- **Rating**: a big number, the 30-day change and the graph.
- **Record**: matches, won-lost bar, win %, streak, points.
- **Ranking**: the city rank in big type, with state / country / global in a row → Rankings.
- **Achievements**: count plus the last four badges → Achievements.

**Profile.** A sports ID card (photo, name, ID, rating, city rank). Then the **mode card** (Current mode: Player → *Switch to Organiser*; only shown with an organiser membership). Then the account rows (Edit profile, Settings, Notifications, Privacy, Help) and Sign out.

**Settings.** Account · App (Theme: System / Light / Dark, Language, Notifications) · Privacy · Security · Support · About.

**Notifications.** Unread first, grouped Today / Earlier. One line of body text each. Tapping one goes to the match, tournament or booking it is about.

### 2.5 First-time player

Every tab has an empty state that says what the tab is for and offers one action:

| Screen | Empty state |
|---|---|
| Home | "Welcome to SkorX. Your pickleball journey starts here." → Find a tournament · Book a court · Score a match |
| Matches | "No matches yet" → *Play your first match* |
| My Paddle | "Unrated", with the rating explained: *Play 3 rated matches to get your SkorX rating.* The record and ranking are hidden, and achievements show as locked goals. |
| Explore | Always has content; with no results: "No tournaments match" → *Clear filters* |

In debug builds, **Settings › Developer › Sample player** switches between *Regular player* and *New player*, so both states can be checked on a device.

---

## 3. Design language

### 3.1 Idea: the net line

Pickleball is played across a net, with a kitchen line either side of it. **Every match in SkorX is drawn the same way: your side, the net, their side.** The net is a thin line with a short solid centre mark. It sits:

- between the two sides of a match row,
- across the scoreboard in match detail,
- under the live score on Home,
- and as the spine of the tournament journey, where each round is a point on the line.

Nothing else is decorated. Screens get their sporty feel from big numbers and type, not from gradients, photos or glows.

### 3.2 Colour

| Token | Dark | Light | Use |
|---|---|---|---|
| `canvas` | `#08090B` | `#F5F5F1` | Page |
| `surface` | `#111316` | `#FFFFFF` | Raised blocks, sheets |
| `surfaceAlt` | `#181B1F` | `#EEEEE8` | Inputs, pressed states, tracks |
| `line` | `#23272D` | `#E2E1DA` | Hairlines and the net |
| `ink` | `#F4F5F2` | `#0E1013` | Primary text and numbers |
| `inkMuted` | `#8D939B` | `#666B72` | Secondary text |
| `inkFaint` | `#5A6068` | `#A0A3A8` | Losing scores, disabled |
| `volt` | `#D4F53C` | `#5B7A00` (text) / `#CDEF3A` (fill) | Wins, your side, the brand accent |
| `onVolt` | `#0E1013` | `#0E1013` | Text on volt |
| `live` | `#FF4B3E` | `#E5362A` | LIVE only |
| `info` | `#6CB6FF` | `#1F6FD1` | Upcoming, registered, links |
| `caution` | `#F5B83D` | `#A86500` | Closing soon, few spots left |

- **Primary action:** volt fill with dark text in dark mode; solid ink with white text in light mode. Light mode is designed separately, not inverted: warm off-white paper, black type, and volt kept to small marks.
- **A loss is not red.** Losses use neutral ink. Red means LIVE and nothing else, so a live match can never be mistaken for a loss.

### 3.3 Type

| Role | Face | Size / weight |
|---|---|---|
| Hero number (rating, live score) | Barlow Condensed, tabular | 64–88 / 800 |
| Score | Barlow Condensed, tabular | 22–40 / 700–800 |
| Screen title | Barlow Condensed, upright caps | 32 / 800 |
| Section label | Barlow Condensed caps, tracked 1.4 | 12 / 700 |
| Verdict (WON / LOST) | Barlow Condensed italic caps | 14–40 / 800 |
| Title | Platform | 16 / 600 |
| Body | Platform | 15 / 400 |
| Caption | Platform | 13 / 500, muted |

Prices and anything else with ₹ use the platform face, which has the glyph.

### 3.4 Status

Each status is a small shape plus a word in tracked caps, with no pill background. The shape still tells statuses apart in grayscale.

| Status | Mark |
|---|---|
| LIVE | ● filled dot, `live`, pulsing |
| UPCOMING | ○ ring, `info` |
| WON | ▲ filled triangle, `volt` |
| LOST | ▽ hollow triangle, `inkMuted` |
| COMPLETED | ■ filled square, `inkMuted` |
| CANCELLED | — dash, `inkFaint`, word struck through |
| REGISTERED | ◆ diamond, `info` |

### 3.5 Components (`lib/design/`)

| Component | What it is |
|---|---|
| `NetLine` | The brand divider. |
| `StateMark` | A status mark with its word. |
| `MatchRow` | Result, upcoming or live. Left: verdict or time. Middle: you ‖ net ‖ them. Right: games in columns (the winning number in ink, the losing one faint) and the rating change. One line of context: tournament · round · date. |
| `Scoreboard` | The match detail score, game by game. |
| `LiveScore` | Home and Matches live block: a big score across the net. |
| `JourneyRail` | Tournament path along the net line. Done steps are filled, the current one pulses, future ones are rings. |
| `RatingFigure` | Big number and change. `RatingGraph`: a line with an end dot, no grid. |
| `RecordBar` | One bar split into wins and losses. |
| `Badge` | Achievement coin. The tier is shown by ring count (1–4), not by colour alone. |
| `SxButton` | Primary / secondary / quiet. |
| `SxTabs` | Underline tabs with counts. |
| `SxSection` | Tracked label and an optional link. |
| `SxRow` | Settings or list row. |
| `Skeleton` | Loading placeholder. |
| `EmptyBlock` | Empty state. |
| `SxAvatar` | Player photo or initials. |
| `SxSheet` | Bottom sheet. |

### 3.6 Layout and motion

- Spacing: 4 · 8 · 12 · 16 · 24 · 32 · 48, with a 20 px page gutter and 32 px between sections.
- Cards only where they group something you can tap (the Now card, tournament cards, venue cards). Lists use hairlines, not cards.
- Content is centred at up to 640 px wide, and the tabs become a side rail at 840 px and wider (tablet and web).
- Motion lasts 150–300 ms and eases out. The live dot pulses and the rating counts up once. Nothing else loops, and everything follows the system "reduce motion" setting.

---

## 4. Where it lives in the code

| Layer | Path |
|---|---|
| Design system | `lib/design/` (`tokens`, `type`, `widgets`, `match_widgets`, `journey_rail`, `stats_widgets`) |
| Match data | `lib/features/matches/data/` (`match.dart`, `journey.dart`, `match_repository.dart`) |
| Screens | `features/player/home`, `features/matches/ui`, `features/tournaments/ui`, `features/explore`, `features/courts/ui`, `features/paddle`, `features/profile`, `features/notifications` |
| First-time states | `core/sample_persona.dart`: every sample repository returns nothing for the *New player* persona |

The theme adds `SxColors` next to the existing `SkorxThemeExtension`, so the organiser and referee screens keep their look.

## 5. UX test

The brief's final design test is an automated widget test (`test/features/player_app_test.dart`, group *a first-time player can*). Each task starts on Home with no instructions:

| # | Task | Path | Taps |
|---|---|---|---|
| 1 | Find my next match | Matches › Upcoming (Home already shows *Then: Semi-final*) | 1–2 |
| 2 | See my previous match | Home › Last result | 1 |
| 3 | Find the score | Match › Scoreboard (above the fold) | 0 |
| 4 | Find my tournament | Match › *View tournament* | 1 |
| 5 | See my tournament progress | The tournament opens on *My journey* | 0 |
| 6 | Find my rating | Home header; My Paddle | 0–1 |
| 7 | Find my ranking | My Paddle › Ranking | 1 |
| 8 | Find my achievements | My Paddle › Achievements › All | 2 |
| 9 | Find a tournament | Home › Find tournament; Explore | 1 |
| 10 | Book a court | Book court › day › venue › Book › time › court › Continue › Confirm | 7 |
| 11 | Find settings | Profile › ⚙ | 2 |
| 12 | Switch to Organiser | Profile › *Switch to Organiser* (in `app_flow_test.dart`) | 2 |

Other checks:

- **Screen sizes.** Every player screen, including every empty state, is laid out at 390×844 (light), 360×690 (dark) and 1180×820 (tablet rail). The test font draws each glyph a full em wide, so this check is stricter than a real device.
- **One set of numbers.** The season's data is checked for consistency: the rating changes add up to the header rating, every tournament match belongs to a real round, and the journey, standings and record are all worked out from the same matches.
- **Screenshots reviewed.** Screenshots were rendered with the real fonts in both themes and reviewed. Fixes made from that review:
  - dates moved under the W/L so they are never cut off;
  - status words are no longer cut off on tournament cards;
  - info rows give their value two lines;
  - late at night, courts show "No more slots today" instead of "Fully booked".

---

## 6. Match universe, player analytics and My Paddle (27 Sep 2026)

This replaces the Matches row of §2.2: **Matches is now every match on SkorX**, and the player's own matches moved to My Paddle.

### 6.1 Screens

| Route | Screen |
|---|---|
| `/player/matches?view=all\|live\|upcoming\|completed\|tournaments` | Matches tab: search, filter sheet, removable filter chips. *All* = Live now strip, From tournaments strip, Coming up, Latest results strip (full list under Completed). `?view=results` still works (Completed). |
| `/player/players/:id` | Player analytics: overview (SkorX Points, W/L, formats), current form (last 5/10 %, streak, best run), W/L trend, SkorX Points graph (own stats), casual vs tournament, recent tournaments, rivals, recent matches (infinite scroll). `me` is the signed-in player. |
| `/player/players/:id/vs/:other` | Head-to-head: score, win %, last meeting, recent form, every meeting. |
| `/player/paddle/matches?category=casual\|tournament` | My matches, paged. |
| `/player/paddle/tournament/:id` | My matches in one tournament: only mine, numbered. |
| `/player/tournaments/mine` | My tournaments (entered or played) as banner cards with my W/L. |

Quick View (bottom sheet, `showPlayerQuickView`): picture, name, SkorX id, level, place; Matches / Win % / SkorX Points; W/L bar; one tile per format played; last-5 form and streak; *You vs X* when they have met; *View full stats*.

Tournament banners (`TournamentBanner`): the organiser's `bannerUrl` / `logoUrl` when set, otherwise art drawn from the tournament id (brand gradient, court, ball, monogram), so no two tournaments share an image.

### 6.2 Endpoints the app now calls (to build in the API)

All lists are cursor- or `before`-paged; nothing is filtered on the phone.

| Endpoint | Used by |
|---|---|
| `GET /matches?status&country&state&city&venue&format&category&tournament&from&to&q&cursor&limit` | Matches feed. Order: live (latest start), upcoming (soonest), completed (newest). `q` matches player, tournament, venue, city, match id. |
| `GET /tournaments/activity?country&state&city&format&from&to&q` | Tournaments with live / upcoming / completed match counts. |
| `GET /matches/places` | Countries → states → cities → venues with matches (location filter; never hard-coded). |
| `GET /search/suggest?q` | Search suggestions: players, tournaments, cities, venues, match ids. |
| `GET /players/:id`, `GET /players/lookup?name=` | Profile (Quick View header). Matches still carry names, so the app resolves a name until match sides carry player ids. |
| `GET /players/:id/stats` | Career, per-format, casual/tournament, last-10 form, streak, best run, tournament runs. Summed from finished matches on the server; cacheable. |
| `GET /players/:id/matches?before&limit` | A player's matches, each from their side. |
| `GET /players/:id/rivals?limit` | Opponents met most, with W/L and the last meeting. |
| `GET /players/:id/head-to-head/:otherId` | Every finished meeting between two players. |
| `GET /me/matches?category=casual\|tournament&status=completed&before&limit`, `GET /me/matches/summary?category=` | My Paddle. |
| `GET /me/tournaments?include=played`, `GET /me/tournaments/:id/matches` | My tournaments; my matches in one. |

**"My matches" is decided by the server** from the signed-in account: a match is mine only if my player id is on one of its sides. Never matches watched, searched, in my city, in my tournament without me, or involving friends. The sample repositories (`SampleMyPlayRepository`) apply the same rule and `test/features/match_universe_test.dart` checks it.

### 6.3 Data

- `Match` gained `place` (`MatchPlace`: city, state, country), `category` (casual / tournament), `seenBy(name)` (the match from another player's side) and `hasPlayer`.
- `Tournament` gained `region`, `country`, `series`, `bannerUrl`, `logoUrl`. Discovery filters gained place (`PlaceFilter`), status (`phases`) and date windows today / this week / this month / upcoming / past; they are saved on the phone.
- Debug builds read one `SampleUniverse` (the player's season plus casual and tournament play in 10 cities across India, Singapore and the UAE), so every screen agrees on every number.

### 6.4 Account

The X code row and the ID card's X code badge were removed from Account. X codes still work for finding players when adding them to a match (player picker, scorer hand-over, Explore search).
