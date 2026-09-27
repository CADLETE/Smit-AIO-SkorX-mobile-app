# SkorX Engagement and Lifecycle System

How SkorX turns a new sign-up into a player who records every match here, and the rules that stop it from ever feeling like spam.

Status: design, 27 Sep 2026. Nothing in this document is built yet except what §0 lists as existing. It extends [NOTIFICATIONS.md](NOTIFICATIONS.md) (voice, catalogue, delivery rules) and never overrides it; where this doc changes an existing notification, §0.2 says so.

**The one rule.** Every message has a *goal event* (the thing we want the player to do next) and *exit events* (the things that make the message pointless). A message with no goal is not sent. A message whose goal is already done is cancelled at send time, not at schedule time.

---

## 0. What exists, and what this changes

### 0.1 Building blocks already in place

| Piece | Where | Used here for |
|---|---|---|
| Voice, anatomy (title 40 / body 110 chars), priorities, quiet hours 10 PM–7 AM, caps, preference groups | [NOTIFICATIONS.md](NOTIFICATIONS.md) §1–3 | Every message in §08 follows them |
| Copy in one place, with a spec that fails on long titles or emoji | `backend/src/notifications/notification-copy.ts` + `.spec.ts` | New `journey.*`, `pro.*` and `stats.*` types go here |
| In-app notification rows | `Notification` model, `NotificationsService.notify()` | The in-app channel of the engine |
| Match link requests (someone scored you) | `MatchParticipant.acceptance`, `match.link_request` | Activation for players who arrive through someone else's match |
| Achievements, SkorX Points, ARC rating (3 rated matches to a rating, settles at 10) | [RATING-SYSTEM.md](RATING-SYSTEM.md), `/player/achievements`, `/player/paddle` | The progress hooks in §09 |
| Pro entitlements and gates (`ProGate`, `showProUpsell`, `@RequiresFeature`) | [SUBSCRIPTIONS.md](SUBSCRIPTIONS.md) | The contextual Pro moments in §11 |
| Home cards (`_Welcome`, `_HowItWorks`, `_NowCard`, `_NextCard`, `_QuickActions`, `_Snapshot`, `_RatingCard`) | `lib/features/player/home/player_home_page.dart` | Home gets one *Next move* card (§13) |
| Match complete screen | `lib/features/casual_match/ui/live/match_complete_view.dart` | The post-match prompt (§13) |
| App tour | `lib/features/onboarding/app_tour.dart` | Split into contextual tips (§03) |
| Looking For, Community connections, courts, tournaments | their feature folders | The reasons to come back in §10 |

### 0.2 Changes to existing notifications

| Type | Today | Change | Why |
|---|---|---|---|
| `account.welcome` | Push, normal | **In-app only** | The player is in the app when it fires. A push they can't see yet is noise. |
| `account.profile_nudge` | Day 2 with no photo | **Contextual:** when the player's first link request goes out and they have no photo (§08 `journey.add_photo`) | A photo matters when someone has to recognise you, not on day 2. |
| `stats.comeback` | "Your paddle misses you" | Replaced by the re-engagement ladder in §10 | It is "we miss you" in a costume. Each stage gets a real reason instead. |
| `subscription.nudge`, `ranking.moved_up_free` | `subscription.*` is in *Payments and account*, which can't be turned off | Rename to `pro.rival_edge` and `pro.rank_teaser`, in *News and tips* | A sales prompt must be switchable off. |
| New prefix `journey.*` | — | Add to `NotificationKind` (icon: a path/flag), preference group **Tips and progress** | One switch turns off every lifecycle nudge. |
| New prefix `pro.*` | — | `NotificationKind.subscription` icon, group **News and tips** | As above. |

---

## 01 — SkorX Lifecycle Strategy

### 1.1 What engagement means for SkorX

SkorX earns its place on a phone by being **the record of a player's game**. Engagement is not app opens. It is matches recorded. A player who opens SkorX twice a week and records both matches is healthier than one who opens it daily to browse.

**North star: Weekly Recording Players (WRP).** Players with at least one completed match added to their record in the week (scored by them, scored by someone else and confirmed, or a tournament match).

### 1.2 The three loops

| Loop | Cycle | What the engine does |
|---|---|---|
| **Record** | Play → score → see stats → want the next stat → play | Make scoring the default. After every match, show what changed and what the next match will unlock. |
| **Social** (growth) | Score a match with 3 others → they get a link request or a claim link → they join → they score *their* next match | Turn every guest in a scored match into a claim link on WhatsApp. Sent by the player, not by us. |
| **Competitive** | Rating → rank → rivals → tournaments | Show progress honestly (3 rated matches to a rating, 10 to settle), introduce tournaments at the right level, and offer Pro when the player is already reaching for the data. |

### 1.3 Principles

1. **One next move at a time.** Home, the post-match screen and any push all come from the same `nextMoves()` function (§13), so they never disagree.
2. **In-app first, push escalates.** A push is sent only when the same move has been waiting in-app and the player hasn't opened the app to see it.
3. **The server knows the state.** Every scheduled message is checked again at send time. If the player already did it, the message is cancelled and the player moves on.
4. **Pickleball has a rhythm.** People play 1–4 times a week, mostly 6–9 AM and 6–10 PM, and more at weekends. Nudges arrive before the player's own play window. Daily streaks and daily nudges are wrong for this sport.
5. **Relative inactivity.** "Inactive" means longer than *this player's* usual gap between matches, not a fixed number of days.
6. **Measure lift, not opens.** A holdout that gets no nudges tells us what the nudges actually changed (§17).

### 1.4 Stage model

Two independent values per player, kept in `user_lifecycle` (§14).

**Lifecycle stage.** Only moves forward.

| Stage | Entered when | The job at this stage |
|---|---|---|
| `new` | Profile set up (setup is required, so this is sign-up) | Get a match on their record |
| `match_started` | Created, joined or was linked to a match that isn't completed yet | Get it finished and confirmed |
| `activated` | First completed match on their record | Get the second match |
| `repeat` | Second completed match within 14 days of the first | Build a weekly rhythm |
| `habitual` | Played in at least 3 of the last 4 weeks | Deepen: rating, rivals, tournaments, community, Pro |

**Activity status.** Recomputed nightly from days since the last meaningful action (§10.1).

`active` → `cooling` → `dormant` → `lapsed` → `churned`

---

## 02 — New User Journey

### 2.1 Where the player came from decides the first move

SkorX users do not all arrive the same way. The first move depends on the `acquisition_source` recorded at sign-up.

| Source | How we know | Their first "aha" | First move |
|---|---|---|---|
| **Linked**: someone scored a match with them in it | They opened a claim link, or have a pending `match.link_request` | Their match is already here, with stats | *Confirm your match with {name}* |
| **Invited**: added to an upcoming match | Pending `match.invite` | Their spot is locked in | *Accept the invite* |
| **Tournament**: signed up to enter a tournament | Deep link from a tournament page, or a registration in progress | Entry confirmed, draw coming | Finish the entry checklist (partner, payment, gender and DOB for category checks) |
| **Organic**: store install, no context | None of the above | Their first scored match | *Score your next match* (plus *Find a game near you* if they have no regular group) |

### 2.2 The timeline

Every row is conditional. **Check** is what the engine checks at that moment. If the check fails, nothing is sent. Push counts are *lifecycle* pushes. Match-day and social pushes (someone invited you, your match starts in 1 hour) are separate and always allowed.

| When | Objective | Check (send only if…) | In-app | Push / other |
|---|---|---|---|---|
| **0 min** (sign-up) | Show the first move | — | Player card → Home with the *Next move* card for their source (§03) | None. `account.welcome` goes to the inbox only. |
| **5 min** | Start the first action | Still in the app | Contextual tip on the screen they're on (Score: "Tap the side that won the rally") | None |
| **30 min** | Nothing new. Don't interrupt. | — | If they come back: same Next move card, never a new one | None. 30 minutes after sign-up is too soon to chase. |
| **2 h** | Finish what they started | A match they started is unfinished | Resume card at top of Home | `journey.resume_first`, normal |
| | Confirm the linked match | Linked source, link still pending | Confirm card | `journey.confirm_first`, normal (the original `match.link_request` already went) |
| **6 h / their evening** | First match, organic players only | No match started or planned, signed up before 2 PM, no lifecycle push yet today | — | `journey.first_match_tonight` at 5:30 PM local. **Day 0 total: 1 lifecycle push at most.** |
| **24 h** | Ask one question, then offer one path | Next app open after 24 h | *When do you usually play?* (Mornings · Evenings · Weekends). One tap. Sets `play_window`. | Not activated: `journey.first_match_record` 1 h before their play window |
| **3 days** | Remove the "no one to play with" barrier | Not activated **and** Looking For has ≥1 open game near them in their window | *Games near you* card | `journey.find_game` (only with a real post to show) |
| | Put the other players on the record | Activated, has guests who haven't claimed | *Add {name} to your record* card | `journey.claim_nudge` (once per match) |
| **7 days** | Last activation push, or the first recap | Not activated | How scoring works (20-second card) | `journey.first_match_week` (final activation push; after this, monthly digest only) |
| | | Activated | *Your first week* recap card | `stats.first_week` (Monday 8 AM) |
| **14 days** | The second match | Activated, not repeat | *Rematch {opponent}* card | `journey.rematch` before their play window |
| | Introduce tournaments and rating | Repeat | Rating progress; one tournament at their level in their city | `journey.tournament_fit` (only if one exists) |
| **30 days** | Look back, look ahead | Activated or better | *Your first month* recap | `stats.first_month` |
| | | Habitual with Pro signals (§11) | Contextual Pro preview on the stats they use | `pro.*` within Pro caps |
| | | Never activated | — | Move to the monthly city digest. No more activation nudges. |

### 2.3 What we deliberately don't do in the first week

- No Pro prompts. PRO labels on locked features stay visible and work when tapped, but nothing is pushed.
- No leaderboards or rankings nudges. A new player ranks near the bottom, which is discouraging, not motivating.
- No tour of every feature. Community, Looking For, courts and tournaments each appear when there's a reason to (§03.4).
- No more than 4 lifecycle pushes in days 0–7, whatever happens.

---

## 03 — First 24-Hour Journey

### 3.1 Immediately after sign-up

Existing flow (unchanged): WhatsApp number → code → profile setup (name, photo, level, game, city) → permissions → **player card** (`ProfileCompleteScreen`) → Enter SkorX.

Changes:

| Screen | Change |
|---|---|
| `ProfileCompleteScreen` | Under the card, one line that sets up the first move: *Linked:* "{name} already scored a match with you." *Invited:* "You're invited to a match on {day}." *Tournament:* "Let's finish your {tournament} entry." *Organic:* "Your card fills up as you play. First match next." |
| Home (new player) | `_Welcome` and `_HowItWorks` are replaced by the **Next move card** (primary action) plus one secondary action. Nothing else competes above the fold. The rest of Home (live matches, quick actions) stays below. |
| App tour | Only the three tabs they need now (Home, Score, My Paddle). The rest become contextual tips, shown once each, when the player first reaches that screen. |

Next move card by source:

| Source | Card title | Primary | Secondary |
|---|---|---|---|
| Linked | {name} scored your match | Confirm {score} | Not me |
| Invited | {name} wants you on court | Accept · {day} {time} | See the match |
| Tournament | Finish your {tournament} entry | Next step: {step} | See the tournament |
| Organic | Score your first match | Start scoring | Find a game near you |

### 3.2 The first match: every step has a small, earned moment

| Step | What the player sees | Event |
|---|---|---|
| Create match | Player picker with a clear "Add guest" option (name only is fine) | `match.created` |
| First point | Quiet confirmation on the scoreboard: *First rally on record*. No popup. | `match.scoring_started` (first ever: `first_score_at`) |
| Match ends | Match complete view, then the **post-match moves** block (§13.2) | `match.completed` |
| First completed match | Achievement *First Match* slides in once, over the result, dismissable. Rating progress: *1 of 3 rated matches*. | `achievement.unlocked` |
| Guests in the match | *Put {name} on the record*: share a claim link on WhatsApp (sent from the player's own WhatsApp, not by SkorX) | `invite.sent` |

### 3.3 Notification permission

If the player declined notifications during setup, ask again only when it helps them. After their first completed match with other players: *"Get a ping when {name} confirms?"* → system prompt. After a second decline, never ask again. The Settings switch stays available.

### 3.4 Progressive discovery: when each feature is introduced

| Feature | First shown | Trigger |
|---|---|---|
| Scoring | Day 0 | Always |
| My Paddle (stats, form) | After match 1 | `match.completed` |
| Rating | After match 1 (as progress), properly after match 3 | Rated match count |
| Connections (Community) | After playing someone registered twice | 2 matches with the same account |
| Looking For | Day 3, not activated, or when they tap "Find a game" | Real posts near them |
| Courts | When they have no venue on their matches, or search for one | No `venue` on first 2 matches |
| Tournaments | Repeat stage, or tournament source | A tournament at their level in their city |
| Rankings, leaderboards | Habitual stage | 5+ rated matches |
| Pro | §11 signals only | Never before day 7 or 3 completed matches |

### 3.5 Hour by hour

| Time | If they did… | They get |
|---|---|---|
| 0–30 min | Nothing yet | Next move card. Nothing else. |
| | Started a match | Scoring tips inline |
| | Finished a match | Post-match moves, First Match badge, claim links |
| 2 h | Left a match unfinished | `journey.resume_first` |
| | Linked, not confirmed | `journey.confirm_first` |
| 5:30 PM | Organic, did nothing, signed up in the morning | `journey.first_match_tonight` |
| 24 h | Opened the app | *When do you usually play?* |
| | Didn't open, not activated | `journey.first_match_record`, 1 h before their window (default 5:30 PM) |

---

## 04 — 30-Day Retention Journey

### 4.1 Strategy by horizon

| Horizon | Question | Main lever | Measured by |
|---|---|---|---|
| **Day 1** | Did SkorX do something useful yesterday? | A completed match with a visible result, stats and claimed opponents | D1 return (opened) and first-match rate |
| **Day 7** | Is SkorX part of how they play? | Second match, rating progress, the first weekly recap | D7 play retention (a match in days 1–7) |
| **Day 30** | Is SkorX where their game lives? | Weekly rhythm, rivals, rating settled, tournaments, community | D30 play retention (a match in days 22–30) |

### 4.2 Mechanisms we build, and why each one earns its place

| Mechanism | What it is | Who gets it | Why it adds value |
|---|---|---|---|
| **Match reminders** | Exists: `match.reminder` 1 h, `match.starting_soon` 10 min | Players in a scheduled match | Logistics. Always useful. |
| **Post-match moves** | Result → what changed → one next move (§13.2) | Everyone after every match | The moment of highest intent in the app |
| **Weekly recap: "Your week on court"** | Monday 8 AM: matches, W/L, SkorX Points gained, form, one highlight (best win, longest rally run, new rival) | Only players who played that week | A reason to look back. No recap if there's nothing to recap. |
| **Weeks-on-court streak** | Consecutive calendar weeks with a completed match. One free "rest week" per month. | Activated players | Fits the sport's rhythm. Daily streaks would punish normal behaviour. |
| **Rating progress** | *2 of 3 rated matches* → *Rating: 3.42* → *7 of 10 to settle* | Everyone who plays | It's real progress the player can't get elsewhere |
| **Rematch prompt** | After a close loss or a first meeting: set up the rematch with the same players in two taps | Activated | Rivalries are the strongest reason to play again |
| **Partner and rival insights** | "You and Riya: 4–1 as partners" / "Arjun leads you 3–2" | After 2+ matches with the same account | Personal, and true only on SkorX |
| **Tournament discovery** | Tournaments in their city whose categories fit their level, gender and age | Repeat or better, or tournament source | Only when entries are open and they're eligible |
| **Friend activity** | Exists: `community.friend_live`, `community.friend_won` | Connections only | Social proof from people they chose |
| **Milestones** | 5 / 10 / 25 / 50 / 100 matches; rating settled; first tournament | Everyone | Marks real progress (§09) |
| **Monthly recap** | Exists: `stats.monthly` | Players with ≥1 match that month | Season-level view |

Not built: daily streaks, "log in daily" rewards, spin wheels, coins, generic "check what's new" pushes, player comparisons between people who have never played each other (privacy, and meaningless). Public leaderboards stay Pro.

### 4.3 Day 1 → 30 at a glance

| Day | Not activated | Activated | Repeat / habitual |
|---|---|---|---|
| 0 | Next move card; ≤1 push | Post-match moves, claim links | — |
| 1 | Play-window question; `journey.first_match_record` | Rating progress card | — |
| 3 | `journey.find_game` if real games exist | `journey.claim_nudge` if guests unclaimed | — |
| 4–6 | — | `journey.rematch` before play window | — |
| 7 | `journey.first_match_week` (last) | `stats.first_week` | `stats.first_week` + streak starts |
| 10–14 | — | `journey.rematch` or `journey.second_match` | `journey.tournament_fit`, `journey.connect` |
| 21 | — | Re-engagement ladder if cooling (§10) | Rival insight, rating settling |
| 30 | Monthly city digest only | `stats.first_month` | `stats.first_month`; Pro only with signals |

---

## 05 — Event-Based Triggers

Server events come from the service that already does the work (§14.4). App events are UI-only things the server can't see (viewing a profile, hitting a Pro gate).

**Response** is what happens. *None* is a real answer: many events only update state.

| Event | Opportunity? | Response | Goal | Suppressed when |
|---|---|---|---|---|
| `user.signed_up` | Yes | Next move card by source (§03.1) | First match on record | — |
| `profile.completed` (setup) | Yes | Moves to `new` | — | — |
| Profile has no photo | Only in context | `journey.add_photo` when their first link request goes out | Photo added | Photo exists; already sent once |
| Profile missing gender or DOB | Only in context | Asked inside the tournament entry flow, where it's needed | Fields set | Never as a standalone nudge |
| `match.created` | Yes | Cancel every "first match" nudge. Scheduled: reminders (exist). Unscheduled: nothing. | Scoring starts | — |
| `match.joined` (invite accepted or link confirmed) | Yes | Same as created for the joiner; `match.invite_accepted` / `match.link_confirmed` to the other side (exist) | Match completed | — |
| No match 24 h after sign-up | Yes | `journey.first_match_record` | `match.created` | Pending invite or link (that's the move instead) |
| `match.scoring_started` (first ever) | In-app only | "First rally on record" on the scoreboard | Match completed | Never a push: they're holding the phone |
| Match unfinished 2 h | Yes | First ever: `journey.resume_first`. Later: `match.paused` (exists, low) | Completed or ended | Match ended or deleted |
| `match.completed` (first) | Yes | First Match badge, post-match moves, claim links, rating 1 of 3 | Second match; guests claimed | — |
| `match.completed` (any) | Yes | Result notification to linked players (exists), post-match moves, achievement checks, streak update | Next match | — |
| 2nd completed match | Yes | Stage → `repeat`. Form line appears. | — | — |
| 3+ matches in 7 days | In-app | "3 this week" highlight in the recap; `achievement.close` if a badge is near | — | No standalone push for counts |
| `match.invite` received | Yes | Exists, high | Accept | — |
| Added to a team (tournament partner) | Yes | `registration.partner_invite` (exists) | Accept | — |
| `player.profile_viewed` | For the viewer: in-app only | If they've played each other: "You vs {name}" card on the profile | Rematch / connect | **Never tell the viewed player.** |
| `tournament.viewed` (2+ times, not entered) | Yes | Follow the tournament automatically → `tournament.closing_soon` (exists) applies | Registration | Registered; entries closed; not eligible |
| `tournament.registered` | Yes | Segment → Tournament. Entry checklist (partner, payment). Existing registration notifications. | Draw published, checked in | — |
| Won a match | Yes | `match.result_win` (exists). First ever: First Victory badge. | Next match | — |
| Consecutive wins (3, 5) | Yes | Hot Streak / On Fire badges (exist) | — | — |
| Weeks-on-court streak at risk | Yes, if streak ≥ 2 | `journey.streak_risk` Saturday at their play window | Match this week | Already played; streak < 2; rest week available and they've been playing less (use it silently) |
| Days past the player's usual gap | Yes | Re-engagement ladder (§10) | A match | Pending social item exists (send that instead) |
| `achievement.unlocked` | Yes | In-app moment + `achievement.unlocked` (exists, normal) | Share, next badge | Bundle if 2+ unlock in one match |
| `rating.changed` | Only at thresholds | `rating.up` ≥0.3, `rating.band_up`, `rating.settled` (exist) | — | Small moves go in the recap |
| `ranking.changed` | Pro: yes; Free: rarely | `ranking.moved_up` (Pro); `pro.rank_teaser` (Free, Pro caps) | — | — |
| Match stats change | No | Recap only | — | Never its own notification |
| Opponent or partner plays a match | Connections only | `community.friend_live` (exists, low) | Watch, rematch | Not connected |
| **Friend joins SkorX** (claimed a guest slot from your match) | Yes | `journey.friend_joined` to the scorer | Connect, next match together | — |
| Claim link opened but not signed up | No | — | — | Never message people who haven't signed up |
| `looking_for.response` etc. | Yes | Existing Looking For types | — | — |
| `pro.gate_hit` | In-app only | Contextual upsell sheet (§11) | Pro | Pro member; 3rd hit of the same gate in a day shows the lock only |
| Uninstall (push token invalid) | No push | Stop push. WhatsApp only if opted in (§10) | — | — |

---

## 06 — User Segmentation

Segments are **tags**, not exclusive buckets. A player can be Active + Tournament + Potential Pro. The nightly job recomputes them. Lifecycle stage (§01.4) sits underneath.

| Segment | Rule | Goal | Message themes | Never gets |
|---|---|---|---|---|
| **A. New** | Stage `new` or `match_started`, signed up ≤ 14 days ago | First completed match | First move, finishing, confirming, finding a game | Pro, rankings, recaps |
| **B. Activated** | Stage `activated` | Second match within 14 days | Rematch, claim links, rating progress, first recap | Pro, leaderboards |
| **C. Active Player** | A match in 2 of the last 4 weeks | Weekly rhythm | Weekly recap, streak, rivals, rating | Activation nudges |
| **D. Tournament** | Registered for, or played in, a tournament in 90 days; or viewed 3+ tournaments in 30 days | Next entry | Tournaments that fit, draws, schedules, results, city series | Casual activation nudges during a live tournament week |
| **E. Social** | 3+ connections, or member of a group, or 3+ Looking For responses, or 3+ distinct registered partners in 30 days | Play with their network | Friend activity, group events, games near them, partners' results | Solo-framed messages ("play your first match") |
| **F. Dormant** | Was activated; now `dormant`, `lapsed` or `churned` (§10.1) | One match | The re-engagement ladder, social pending items first | Streak or recap messages (they'd point at the gap) |
| **G. Highly Engaged** | Habitual and top 10% of matches in their city over 30 days | Depth and advocacy | Rankings, tournaments, rivals, invites, early feature access | Anything basic. Fewer pushes: they're already here. |
| **H. Potential Pro** | Pro propensity ≥ 60 (§11.1) and not Pro | Pro when it helps them | The specific Pro feature they keep reaching for | Generic "upgrade" copy |
| **Pro** | Active Pro period | Get value from Pro | What's new in their stats, rival insights | Any Pro prompt |
| **Holdout** | 10% of new sign-ups, fixed at sign-up | Measurement | Transactional and social only | Every `journey.*`, `pro.*`, recap-driven push. In-app cards still show (§17.3). |

---

## 07 — Notification Matrix

### 7.1 Channel roles

| Channel | Use it for | Don't use it for | Notes |
|---|---|---|---|
| **In-app** (inbox + cards) | Everything. It's the record. | — | Every push also has an in-app row. Lifecycle moves appear first as Home cards. |
| **Push** | Time-sensitive or personal: match day, someone did something involving you, a result, a goal that's close | Things that can wait for the next open | Needs FCM (build step 7). Priorities from NOTIFICATIONS.md §3. |
| **WhatsApp** | Things that matter even when the app isn't installed: OTP (exists), match claim links (sent by the *player* from their WhatsApp), tournament entry and payment confirmations, match-day calls for tournament entrants, one re-engagement message at 30 days (opt-in only) | Nudges, recaps, Pro, anything frequent | Meta policy: utility templates for transactional; marketing templates only with explicit opt-in. Paid per conversation, so each one must be worth it. |
| **Email** | Invoices and receipts (exist in billing), monthly recap (if they gave an email), organiser communications | Anything time-sensitive | Email is optional in SkorX, so it's a secondary channel for players. |
| **SMS** | OTP fallback when WhatsApp fails; payment or security alerts if push and WhatsApp both fail | Anything else | India DLT registration per template. Marketing SMS is not used. |

### 7.2 Matrix

● primary · ○ fallback or opt-in · — never

| Message family | Examples | In-app | Push | WhatsApp | Email | SMS | Priority |
|---|---|---|---|---|---|---|---|
| Account security | new sign-in, number changed | ● | ● | ○ | — | ○ | high |
| Payments and receipts | payment failed, refund, invoice | ● | ● | ● (utility) | ● (invoice) | ○ | high |
| Match day | reminder, starting soon, match call, on deck | ● | ● | ○ tournament entrants only | — | — | high |
| Social actions | invite, link request, partner invite, message | ● | ● | — (the player's own share covers non-users) | — | — | high |
| Results | win, loss, tournament result | ● | ● | — | — | — | normal |
| Achievements and rating | badge, band up, settled | ● | ● | — | — | — | normal |
| Lifecycle nudges `journey.*` | first match, rematch, streak | ● (card) | ● (only if card unseen) | — | — | — | normal / low |
| Recaps `stats.*` | weekly, first week, monthly | ● | ● weekly first week only, then low | — | ○ monthly | — | low |
| Discovery `explore.*`, `tournament.new_nearby` | tournaments, courts, players | ● | ○ max 1 a week | — | — | — | low |
| Re-engagement | §10 ladder | ● | ● within caps | ○ day 30, opt-in, once | ○ day 30 if email | — | normal |
| Pro `pro.*` | rival edge, rank teaser | ● (at the gate) | ○ 1 a fortnight | — | — | — | low |
| System | maintenance, new feature | ● | ○ maintenance only | — | — | — | low |

### 7.3 Frequency limits

These add to NOTIFICATIONS.md §3 (3 non-transactional pushes a day, 1 re-engagement a week, 1 Pro a fortnight, none to Pro members).

| Segment | Lifecycle + discovery + Pro pushes | Per week | Notes |
|---|---|---|---|
| New (days 0–7) | 1 a day | 4 in the first 7 days | Day 0: 1 |
| Activated / Active | 1 a day | 3 | Recaps count |
| Highly Engaged | 1 a day | 2 | They're already in the app |
| Dormant | — | 1 | The ladder (§10) |
| Churned (60+ days) | — | 1 a month | Only with a concrete city event or a social item |
| Any player ignoring nudges | see §12 fatigue | halves | |

Transactional and social messages (someone did something involving you, match day, payments, security) have no lifecycle cap but still follow bundling and quiet hours from NOTIFICATIONS.md.

---

## 08 — Notification Copy Library

Rules: NOTIFICATIONS.md §1–2 (title ≤ 40, body ≤ 110, no emoji, one "!" only for a win, the title is the news, say what to do next). Every line was written for a reason in the **Goal** column. The same `notification-copy.spec.ts` checks will run over these.

Placeholders are filled from the player's own data. If a placeholder can't be filled (no opponent, no venue), the message is not sent; there are no generic fallbacks.

### 8.1 Activation

| Type | Goal | Title | Body | Opens |
|---|---|---|---|---|
| `journey.first_match_tonight` | First match | Playing tonight? Score it here. | Tap Score, add the players, and every rally lands on your SkorX record. | `/player/match/new` |
| `journey.first_match_record` | First match | Your record starts at 0–0 | Score your next game and your first stats, points and form appear the moment it ends. | `/player/match/new` |
| `journey.first_match_week` | First match (last push) | 3 rated matches to your SkorX Rating | The first one takes one tap to start. Score it and the rating maths is on us. | `/player/match/new` |
| `journey.find_game` | First match | {n} games near you need players | {first_title} · {when}. Raise a paddle and you're on court this week. | `/player/looking-for?tab=for_you` |
| `journey.confirm_first` | Confirm linked match | {name} scored your match: {score} | Confirm it and it's your first match on SkorX, stats and all. | `/player/matches/{id}` |
| `journey.resume_first` | Finish first match | Your first match is paused at {score} | Pick it up from the next serve, or end it there. Either way it counts. | `/player/match` |
| `journey.add_photo` | Photo | Help {name} spot you | They're confirming your match. A photo on your card makes it a one-second yes. | `/player/edit-profile` |

### 8.2 Second match and habit

| Type | Goal | Title | Body | Opens |
|---|---|---|---|---|
| `journey.claim_nudge` | Guests claim the match | Put {name} on the record | Send them your {score} match on WhatsApp. Once they join, it counts for both of you. | `/player/matches/{id}` |
| `journey.rematch` | Second match | Rematch {opponent}? | Last time: {score}. Set it up in two taps and the head-to-head starts counting. | `/player/match/new?rematch={id}` |
| `journey.second_match` | Second match (no named opponent) | Match 2 starts your form line | One more scored match and My Paddle starts showing how you're trending. | `/player/match/new` |
| `journey.rating_progress` | Rated match | {n} match from your SkorX Rating | Matches with confirmed opponents count. Your number lands after match 3. | `/player/paddle` |
| `journey.rating_progress_plural` | Rated match | {n} matches from your SkorX Rating | Matches with confirmed opponents count. Your number lands after match 3. | `/player/paddle` |
| `journey.streak_risk` | Match this week | {n} weeks straight. Make it {n+1}? | One match by Sunday keeps it going. {slots} courts near you have slots this weekend. | `/player/explore/courts` |
| `journey.connect` | Connection | You've played {name} {n} times | Connect on SkorX to follow their results and set up the next one faster. | `/player/community/people/{id}` |
| `journey.friend_joined` | Connection, next match | {name} joined from your match | Your {score} game is on both records now. Connect and set up the next one. | `/player/community/people/{id}` |
| `journey.tournament_fit` | First registration | {tournament} fits your level | {dates} · {category} at {venue}. Entries close {when}. | `/player/tournament/{id}` |
| `journey.partner_stats` | Next match with partner | You and {name}: {w}–{l} together | Your best partnership on SkorX so far. Book the next one. | `/player/players/{id}` |

### 8.3 Recaps

| Type | Goal | Title | Body | Opens |
|---|---|---|---|---|
| `stats.first_week` | Second week of play | Week one: {matches} matches on record | {wins} wins · +{points} SkorX Points · form {form}. See how it went. | `/player/paddle` |
| `stats.weekly` | Next match | Your week: {w}W {l}L | {matches} matches · +{points} SkorX Points · {highlight}. | `/player/paddle` |
| `stats.first_month` | Month two | Month one: {matches} matches, {wins} wins | Rating {rating_line}. Your best result: {best}. The full month is in My Paddle. | `/player/paddle` |
| `stats.monthly` | exists | | | |

`{highlight}` is one of, in order: a new badge, a rating band, the best win by opponent rating, a win streak, the longest rally run. If none apply, the body ends after the points.

### 8.4 Re-engagement (§10)

| Type | Goal | Title | Body | Opens |
|---|---|---|---|---|
| `journey.pending_confirm` | Confirm a pending match | {name} is waiting on you | Confirm {score} from {day} and it's added to both your records. | `/player/matches/{id}` |
| `journey.game_in_window` | A match | {n} games at your usual time | {first_title} · {when}. Your level, your side of town. | `/player/looking-for?tab=for_you` |
| `journey.rating_waiting` | A match | Your rating is 1 match from settling | 9 of 10 verified matches in. Match 10 locks in your number. | `/player/paddle` |
| `journey.rival_active` | Rematch | {name} has played {n} times since | Your last meeting: {score}. They've been busy. Your move. | `/player/players/{id}/vs/{me}` |
| `journey.city_tournaments` | Registration | {n} tournaments open in {city} | {first} · {dates}, and more at your level. Entries are open now. | `/player/explore/tournaments` |
| `journey.court_slots` | A match | Courts free near you on {day} | {venue} and {n} more have slots at {time}. Round up three and play. | `/player/explore/courts` |
| `journey.season_so_far` | A match | Your SkorX season so far | {matches} matches · {wins} wins · {points} points. It's all right where you left it. | `/player/paddle` |
| `journey.whats_new` | A match | {n} new players at your level nearby | New in {city} since you last played. Your next partner might be one of them. | `/player/explore/players` |

### 8.5 Pro (only after §11 eligibility)

| Type | Goal | Title | Body | Opens |
|---|---|---|---|---|
| `pro.rival_edge` (was `subscription.nudge`) | Pro | {name} has your number | They've won {wins} of your last {played}. Pro shows where the points go. | `/player/pro?feature=rival` |
| `pro.rank_teaser` (was `ranking.moved_up_free`) | Pro | You climbed the {city} rankings | Up {places} places this month. Pro shows your exact spot and who's next. | `/player/pro?feature=rankings` |
| `pro.analytics_after_settle` | Pro | What moved your rating to {rating}? | Match Analytics shows momentum and serve splits for every match you score. | `/player/pro?feature=analytics` |
| `pro.stream_ask` | Pro | Stream your next match live | Casual match streaming is on Pro. {name} and co. can watch every rally. | `/player/pro?feature=stream` |

### 8.6 In-app surfaces (cards, not pushes)

| Where | When | Headline | Line | Action |
|---|---|---|---|---|
| Home, new organic | No match yet | Score your first match | Every rally you score builds your SkorX record. | Start scoring |
| Home, linked | Link pending | {name} scored your match | {score} at {venue}, {day}. Was this you? | Confirm |
| Home, activated | 1 match | Match 2 starts your form line | Rematch {opponent}, or score your next game. | Rematch |
| Home, rating progress | 1–2 rated | {n} of 3 to your SkorX Rating | Matches with confirmed opponents count. | See how it works |
| Home, unfinished match | In progress | Match paused at {score} | Pick it up from the next serve. | Resume |
| Home, weekly | Monday–Tuesday | Last week: {w}W {l}L | {points} SkorX Points · {highlight} | See the week |
| Home, dormant return | First open after 14+ days | Welcome back, {first_name} | Last match: {score} vs {opponent}, {when}. | Rematch |
| Post-match | Guests in the match | Put {name} on the record | They'll get this match on SkorX when they join. | Send on WhatsApp |
| Post-match | Close loss (≤ 2 points) | That was close | {score}. Rematch while it's fresh? | Rematch |
| Post-match | Win | {streak_line} | +{points} SkorX Points. | See my stats |
| Empty: Matches | No matches | Nothing scored yet | Your matches, live and finished, will live here. | Score a match |
| Empty: My Paddle | No matches | Unrated, for now | 3 rated matches to your SkorX Rating. | Start scoring |
| Empty: Connections | None | Your SkorX circle starts on court | Play a scored match and connect with who you played. | Find players |
| Profile of someone you've played | 1+ meetings | You vs {name}: {w}–{l} | Last: {score}, {when}. | Rematch |

---

## 09 — Gamification System

**Style.** Achievements look like medals on a player card, not stickers. Metallic tiers (bronze / silver / gold / black), the SkorX net line, one line of copy with at most one pun. No confetti storms: a single restrained animation on unlock, then the badge sits on the card. Losses never unlock anything that sounds like a consolation prize.

**Rewards are status and data, not currency.** No coins or points shop. A badge shows on the player card, in Quick View, and in the share image. Some milestones unlock a real view (a recap, a stat). Any reward that costs money (a Pro preview) is a business decision, marked ⚑.

### 9.1 Achievement catalogue

Existing badges (NOTIFICATIONS.md §4.7) stay: First Victory, Hot Streak, On Fire, Comeback Kid, Bagel Baker, Iron Paddle, Globetrotter, Podium Finish.

| Achievement | Family | Trigger | Message (title · line) | Reward / benefit |
|---|---|---|---|---|
| **First Serve** | Milestone | First point scored on SkorX | First Serve · The first rally of many. | Starts the player card's match counter |
| **On the Record** | Milestone | First completed match | On the Record · Match one is in the books. | My Paddle opens with real stats; rating progress 1/3 |
| First Victory | Milestone | First win | exists | exists |
| **Regular** (bronze) | Volume | 5 completed matches | Regular · Five matches deep. The court knows your name. | Form line with 5 results on the card |
| **Club Player** (silver) | Volume | 25 matches | Club Player · 25 on record. That's a season. | Season stats view unlocked (all-time vs last 30 days) |
| **Centurion** (gold) | Volume | 100 matches | Centurion · 100 matches. Put that on the wall. | Gold card frame |
| **Rated** | Rating | SkorX Rating first shown (3 rated matches) | Rated · Your SkorX Rating is live: {rating}. | Rating on the card and in Quick View |
| **Settled** | Rating | Rating settled (10 verified) | exists as `rating.settled` | "Verified rating" tick on the card |
| **Band up** | Rating | Crossed a band | exists as `rating.band_up` | Band colour on the card |
| **Four Weeks Running** | Consistency | Weeks-on-court streak of 4 | Four Weeks Running · A match every week for a month. | Streak shown on the card |
| **Twelve Weeks Running** | Consistency | Streak of 12 | Twelve Weeks Running · Three months without missing a week. | Gold streak flame |
| **Partnership** | Social | 5 matches as partners with the same account | Partnership · You and {name}, five matches strong. | Partnership stats on both profiles |
| **Rivalry** | Social | 5 matches against the same account | Rivalry · {name} again. Five and counting. | Head-to-head pinned on both profiles |
| **Host** | Social | Scored matches for 10 different players | Host · 10 players have you to thank for their stats. | "Host" tag in Community |
| **Connector** | Social | 3 players joined through your claim links and played | Connector · Three players on SkorX because of you. | ⚑ 1 month of Pro (decision needed) |
| **First Entry** | Tournament | First tournament registration confirmed | First Entry · Your name is in the draw. | Tournament record section on the profile |
| Podium Finish | Tournament | exists | exists | exists |
| **Champion** | Tournament | First tournament win | Champion · Gold. The first of your career on SkorX. | Trophy on the card |
| **Scorer's Hand** | Scoring | Scored 500 rallies | Scorer's Hand · 500 rallies called, zero arguments. | — |

### 9.2 Near-miss nudges

`achievement.close` (exists, low) is sent only when the badge is one match away **and** the player has a match in the next 48 hours or plays within 2 days on their usual rhythm. It is never sent for Scorer's Hand or Host (they're side-effects, not goals).

### 9.3 Anti-gaming

Volume badges count **completed matches with at least one confirmed registered opponent or a tournament match**. Solo self-scored matches against guests count toward First Serve and On the Record only. This keeps badges meaningful and the rating honest.

---

## 10 — Re-engagement System

### 10.1 Inactivity is relative

A player who plays every Saturday is not "inactive" on Wednesday. The engine uses each player's own rhythm:

- `usual_gap` = median days between their last 6 completed matches (default 4 days until they have 3 matches).
- **Re-engagement day 0** = the day `days_since_last_meaningful > max(1.5 × usual_gap, 3)`.
- The day labels below (1, 3, 7, 14, 30) count from that point.

*Meaningful action* = completed or scored a match, confirmed a link, registered for a tournament, booked a court, or responded to a Looking For post. Opening the app is not meaningful by itself.

Activity status: `active` (not yet past the threshold) → `cooling` (day 1–6) → `dormant` (7–29) → `lapsed` (30–59) → `churned` (60+).

### 10.2 The ladder

Each stage has a **different reason**, not a louder version of the same one. Before any of these, the engine checks for a **social pending item** (an invite, an unconfirmed link, a message, a partner request). If one exists, that goes instead: it's the strongest reason there is.

| Stage | Reason to return | Uses | Channel | Example |
|---|---|---|---|---|
| **Day 1** | None worth a push | — | In-app only: next open shows their last result and the Next move | — |
| **Day 3** | Something is waiting on them, or a game fits their slot | Pending links, Looking For posts in their play window near them | Push, only with a concrete item | `journey.pending_confirm`, `journey.game_in_window` |
| **Day 7** | Progress they'd lose or finish | Rating 1 match from settling, streak, a badge 1 match away, a rival who's been playing | Push | `journey.rating_waiting`, `journey.rival_active` |
| **Day 14** | What's happening in their city | Open tournaments at their level; court slots in their window | Push (low) | `journey.city_tournaments`, `journey.court_slots` |
| **Day 30** | Their season, and what changed | Season totals; new players at their level; a feature that shipped | Push + one WhatsApp (opt-in) + email (if any) | `journey.season_so_far`, `journey.whats_new` |
| **Day 60** | Monthly city digest only, when the city has news | Tournaments, new courts | In-app + push (low), once a month | `explore.weekend` style |
| **Day 90+** | Silence | — | Only transactional and social (someone invites them) | These are the best win-backs anyway |

If a player returns and plays, the ladder stops immediately, status → `active`, and the next open shows a **Welcome back** card with their last match and a rematch (§08.6), never "we missed you".

### 10.3 Win-back measurement

`reengaged` = a meaningful action within 7 days of a ladder message. `reactivated` = two matches within 21 days of returning. Compare with the holdout at the same ladder stage.

---

## 11 — Pro Conversion Strategy

### 11.1 Signals

Pro's five features (Match Analytics, Rival Player Stats, Leaderboards, Local Rankings, Casual Live Streaming) each have a behaviour that shows the player wants them. **Pro propensity** (0–100) is computed nightly:

| Signal (last 30 days) | Points |
|---|---|
| Hit a Pro gate (`pro.gate_hit`), per distinct feature | +15 (max 45) |
| Hit the same gate 3+ times | +10 |
| 8+ completed matches | +15 |
| Viewed their own stats page 5+ times | +10 |
| Opened another player's stats or head-to-head 3+ times | +10 |
| Played the same opponent 3+ times | +10 |
| Tournament registration | +5 |
| Tried to stream a casual match | +15 |
| Rankings page visited 3+ times | +10 |
| Viewed the Pro plans page and left | +5 (once) |

Segment H = 60+. Propensity only changes *eligibility* and *which* feature to lead with; the trigger is always a moment (§11.3).

### 11.2 Eligibility rules

- Not before **day 7** and **3 completed matches**.
- Never to Pro members. Never during a checkout or payment-failure flow.
- **1 Pro push a fortnight** (existing cap); in-app gate sheets are not capped (the player tapped a locked thing), but the same sheet won't open twice in 10 minutes.
- Never within 2 hours of a loss notification. After a loss, the analytics upsell appears only in-app on the stats screen, where the player chose to look.
- After two ignored Pro pushes, stop Pro pushes for 60 days. In-app gates still work.

### 11.3 Contextual moments

| Moment | What the player sees | Why it's useful to them | Leads with |
|---|---|---|---|
| Taps a locked chart on the match result | Sheet: the chart, blurred, with their real match data shape visible | They just played this match; they want to know why | Match Analytics |
| Opens a rival's stats | Their record vs the rival is free; the rival's full breakdown is locked with "See where {name} wins points" | They're preparing for a rematch | Rival Player Stats |
| Rating settles (10th match) | In-app card after `rating.settled`: "What moved your rating?" | Their number just became real | Match Analytics |
| Rival beats them 3 times in a month | `pro.rival_edge` (existing rule) | A concrete problem Pro helps with | Rival Player Stats |
| Climbs in city rankings (Free) | `pro.rank_teaser`, max once a month | They're climbing and want the number | Local Rankings |
| Starts a casual match with a camera prompt | Stream toggle marked PRO | Friends want to watch | Casual Live Streaming |
| Habitual + propensity ≥ 60, no gate hit this month | Once, in the weekly recap: one line on the Pro feature matching their top signal | Low-pressure, in context | Their top signal |

### 11.4 How Pro copy works

Name the feature, the player's data, and what they'll see. Never "Upgrade now", "Unlock everything", or a countdown that isn't real.

- ✓ *Momentum and serve splits for your {score} win are ready. See them with Pro.*
- ✓ *Arjun wins 64% of his points at the kitchen. See the rest with Pro.* (only a teaser they can't act on is shown; never a real stat for free)
- ✗ *Go Pro and dominate the court!*

⚑ **Decisions for the business:** (1) a 7-day Pro preview when the rating settles, (2) Pro months as the Connector reward, (3) an annual-plan offer on the Pro page for habitual players. Test each with a holdout (§17) before rolling out.

---

## 12 — Anti-Spam Rules

Numbered so the dispatcher, tests and admin UI can refer to them. Rules 1–7 come from NOTIFICATIONS.md §3 and still apply.

| # | Rule |
|---|---|
| 1 | Match day beats everything: match calls, on deck, check-in ignore caps and quiet hours. |
| 2 | Bundle bursts: 3+ of the same type in 10 min become one. |
| 3 | Caps: 3 non-transactional pushes a day, 1 re-engagement a week, 1 Pro a fortnight, none to Pro members. |
| 4 | Don't tell people what they did. |
| 5 | Replace, don't pile up (collapse key = route). |
| 6 | Silent removals. |
| 7 | Quiet hours 10 PM–7 AM local; normal priority is held until 7 AM. |
| 8 | **Goal already met → cancel.** At send time, if the goal event happened since scheduling, the message is cancelled (`status = cancelled`, `reason = goal_met`). |
| 9 | **Exit events → cancel.** Each message lists exit events (e.g. `match.created` exits every "first match" nudge). |
| 10 | **In-app first.** A `journey.*` push is sent only if the same move's Home card was not seen since it appeared (`card_seen_at` is null) and the app hasn't been opened in the last 12 hours. |
| 11 | **One lifecycle push a day.** If two are due, the higher-priority one (§13.3) wins and the other is re-evaluated tomorrow. |
| 12 | **Segment caps** from §07.3 (4 in the first 7 days; 3 a week activated; 2 a week highly engaged). |
| 13 | **Fatigue.** `nudges_ignored_streak` counts lifecycle pushes not opened within 48 h. At 3: halve lifecycle frequency. At 5: pause lifecycle pushes for 14 days (in-app cards continue). Any open or goal met resets it to 0. |
| 14 | **Send in their window.** Lifecycle pushes go 60–90 min before the player's usual play time (learned from match start times; the 24 h question until then; default 5:30 PM). Recaps go Monday 8 AM. Never 10 PM–7 AM. |
| 15 | **No push within 2 h of another push** to the same player, except transactional and social. |
| 16 | **Social beats lifecycle.** If a pending social item exists, lifecycle messages that day are dropped. |
| 17 | **No nudges during an active match or tournament day** the player is part of (only match-day messages). |
| 18 | **No nudge about a thing they can't do.** No "find a game" if Looking For has nothing near them; no tournament if they aren't eligible; no court slots if none are open in their window. |
| 19 | **Dedupe key.** `{type}:{user}:{subject}` is unique: the same message about the same thing is never sent twice (a rematch prompt for match X, a claim nudge for match X). |
| 20 | **Preferences are absolute.** A group switched off in Settings is never sent on that channel, including by admin campaigns. |
| 21 | **Admin campaigns obey 1–20.** The campaign builder can't override caps or quiet hours. Only *Match day* and *Payments and account* types are exempt, and those can't be built as campaigns. |
| 22 | **Dead token → stop.** An invalid FCM token stops push immediately; WhatsApp is not a substitute unless the player opted in. |

---

## 13 — Notification Decision Engine

### 13.1 The tree

This runs in one place, `EngagementService.nextMoves(user)`. Home, the post-match screen and the nudge scheduler all call it.

```text
PLAYER
│
├─ Match day? (in a scheduled or tournament match in the next 12 h)
│   └─ YES → only match-day messages (reminders, check-in, calls). Stop.
│
├─ Social item pending? (invite, link request, partner request, message, Looking For response)
│   └─ YES → Next move = that item. Push if unseen and within caps. Stop.
│
├─ Match in progress, unfinished > 2 h?
│   └─ YES → Next move = resume. First ever: journey.resume_first. Stop.
│
├─ Has a completed match on record?
│   │
│   ├─ NO ─ Source = linked, link pending? → confirm (journey.confirm_first)
│   │      Source = invited, invite pending? → accept
│   │      Source = tournament, entry incomplete? → next checklist step
│   │      Has a match created/joined, not started? → scheduled: reminders; else nothing
│   │      Day 0 → first_match_tonight (organic, morning sign-up)
│   │      Day 1 → ask play window (in-app) / first_match_record
│   │      Day 3 → find_game IF real games near them, ELSE nothing
│   │      Day 7 → first_match_week (last push)
│   │      Day 8+ → monthly city digest only
│   │
│   └─ YES ─ Guests in their matches unclaimed? → claim_nudge (once per match)
│          │
│          ├─ Only 1 completed match?
│          │   ├─ Within 14 days → rematch (named opponent) or second_match
│          │   └─ Past 14 days → re-engagement ladder
│          │
│          └─ 2+ completed matches
│              ├─ Past their usual gap? → RE-ENGAGEMENT LADDER (§10)
│              ├─ Streak ≥ 2 and nothing this week, Saturday? → streak_risk
│              ├─ Rating 1 match from a milestone? → rating_progress / rating_waiting
│              ├─ Played a registered account 2+ times, not connected? → connect
│              ├─ Repeat stage, eligible tournament open in city? → tournament_fit
│              ├─ Monday? → weekly recap (if they played last week)
│              └─ Pro-eligible (§11.2) and a Pro moment happened? → pro.*
│
└─ Did the player return after a message?
    ├─ YES → mark converted if goal met, reset fatigue, re-run the tree
    └─ NO  → fatigue +1 (rule 13); next stage of the ladder when due
```

### 13.2 Post-match moves (the highest-intent moment)

After `match.completed`, `MatchCompleteView` shows up to three moves, in this order, skipping any that don't apply:

1. **Put the players on the record**: guests unclaimed → share claim links on WhatsApp.
2. **The one thing that changed**: new badge, rating progress (*2 of 3*), streak, rival record.
3. **The next match**: Rematch (same players, two taps) · Score another.

Never Pro here unless the player taps a locked chart.

### 13.3 Priority order when several moves apply

1. Match day → 2. Social pending → 3. Unfinished match → 4. Activation step → 5. Claim links → 6. Progress about to complete (rating, badge, streak) → 7. Second match / rematch → 8. Recaps → 9. Discovery (tournaments, courts, players) → 10. Pro.

Home shows moves 1–2 of the list; a push only ever carries the top one.

### 13.4 Send-time check (pseudocode)

```ts
async function dispatch(msg: ScheduledMessage) {
  const s = await lifecycle.get(msg.userId);
  const prefs = await preferences.get(msg.userId);

  if (s.holdout && msg.isLifecycle) return cancel(msg, 'holdout');
  if (await events.happenedSince(msg.userId, msg.goalEvent, msg.createdAt)) return cancel(msg, 'goal_met');   // rule 8
  if (await events.anySince(msg.userId, msg.exitEvents, msg.createdAt)) return cancel(msg, 'exit_event');     // rule 9
  if (!prefs.allows(msg.group, msg.channel)) return cancel(msg, 'preference');                                 // rule 20
  if (!(await msg.conditions(s))) return cancel(msg, 'condition_false');                                       // re-check "real games exist" etc.
  if (msg.isLifecycle && (await nextMoves(s))[0]?.type !== msg.type) return cancel(msg, 'outranked');         // §13.3

  const block = caps.check(s, msg);                          // rules 3, 7, 10–17
  if (block?.retryAt) return reschedule(msg, block.retryAt); // quiet hours, 2 h spacing, play window
  if (block) return cancel(msg, block.reason);

  const variant = experiments.variantFor(msg.userId, msg.experimentKey);
  await channels[msg.channel].send(msg.userId, copy.render(msg.type, variant, s));
  await markSent(msg, variant);
}
```

---

## 14 — Database / Backend Requirements

All in the NestJS API (`smit-dev-skorx-frontend/backend`). **Additive migrations only**: other features are migrating the same `schema.prisma` concurrently. Append new models at the end; never reset.

### 14.1 Data points

The fields the brief asked for, plus the ones the rules above need.

| Field | Table | Why |
|---|---|---|
| `user_id`, `signup_at`, `last_active_at` (= last app open) | `user_lifecycle` | Basics |
| `acquisition_source` (`linked` / `invited` / `tournament` / `organic` / `referral`), `invited_by_user_id`, `first_deep_link` | `user_lifecycle` | First move by source (§02.1), Connector badge |
| `profile_strength` (0–100), `has_photo`, `has_gender_dob` | `user_lifecycle` | Contextual profile prompts |
| `lifecycle_stage`, `stage_changed_at`, `activity_status`, `segments[]` | `user_lifecycle` | §01.4, §06 |
| `matches_created`, `matches_joined`, `matches_scored`, `matches_completed`, `verified_matches`, `tournament_matches`, `wins` | `user_lifecycle` | Stage and badge rules |
| `first_match_at`, `first_score_at`, `first_completed_at`, `second_completed_at`, `last_match_at`, `last_meaningful_at` | `user_lifecycle` | Funnel timing, re-engagement clock |
| `usual_gap_days`, `play_window` (`morning` / `evening` / `weekend` + learned hour), `timezone` (default Asia/Kolkata), `city` | `user_lifecycle` | Rules 14, §10.1 |
| `weeks_active_last_4`, `week_streak`, `best_week_streak`, `rest_week_used_month` | `user_lifecycle` | Habit, streak |
| `rated_matches`, `rating_state` (`unrated` / `provisional` / `settled`) | `user_lifecycle` (mirrors rating) | Progress nudges |
| `tournaments_viewed_30d`, `tournaments_registered`, `connections`, `groups`, `lf_responses_30d` | `user_lifecycle` | Segments D, E |
| `invites_sent`, `invites_converted` | `user_lifecycle` | Social loop |
| `pro_status`, `pro_propensity`, `pro_gate_hits_30d`, `last_pro_prompt_at`, `pro_pushes_ignored` | `user_lifecycle` | §11 |
| `last_nudge_at`, `nudges_ignored_streak`, `nudge_paused_until`, `lifecycle_pushes_7d` | `user_lifecycle` | Rules 11–15 |
| `push_enabled`, `whatsapp_marketing_opt_in` + `_at`, `email`, `email_verified` | `user_lifecycle` / `channel_consents` | Channel choice, consent proof |
| `holdout` | `user_lifecycle` | §17.3 |
| notification history, open history, click history | `engagement_messages` | Every send, open and conversion |
| everything the player did | `user_events` | Source of truth for goals and analytics |

### 14.2 Prisma models (to append)

```prisma
enum LifecycleStage { new match_started activated repeat habitual }
enum ActivityStatus { active cooling dormant lapsed churned }
enum AcquisitionSource { organic linked invited tournament referral }
enum MessageChannel { in_app push whatsapp email sms }
enum MessageStatus { scheduled cancelled sent delivered opened converted failed }
enum CampaignStatus { draft live paused archived }

// Append-only. Server events are written by the service that did the work;
// app events arrive in batches from POST /me/events.
model UserEvent {
  id            BigInt   @id @default(autoincrement())
  userId        String
  name          String   // "match.completed"
  props         Json?
  source        String   // "server" | "app"
  clientEventId String?  // dedupe for offline-queued app events
  occurredAt    DateTime // device time for app events (offline scoring)
  receivedAt    DateTime @default(now())

  @@unique([userId, clientEventId])
  @@index([userId, name, occurredAt])
  @@index([name, occurredAt])
  @@map("user_events")
}

// One row per player: the state every decision reads. Counters are updated
// in the same transaction as the event; rolling fields nightly.
model UserLifecycle {
  userId                 String            @id
  signupAt               DateTime
  acquisitionSource      AcquisitionSource @default(organic)
  invitedByUserId        String?
  stage                  LifecycleStage    @default(new)
  stageChangedAt         DateTime          @default(now())
  activityStatus         ActivityStatus    @default(active)
  segments               String[]
  profileStrength        Int               @default(0)
  hasPhoto               Boolean           @default(false)
  city                   String?
  timezone               String            @default("Asia/Kolkata")
  playWindow             String?
  playHour               Int?
  matchesCreated         Int               @default(0)
  matchesJoined          Int               @default(0)
  matchesScored          Int               @default(0)
  matchesCompleted       Int               @default(0)
  verifiedMatches        Int               @default(0)
  tournamentMatches      Int               @default(0)
  wins                   Int               @default(0)
  ratedMatches           Int               @default(0)
  ratingState            String            @default("unrated")
  firstMatchAt           DateTime?
  firstScoreAt           DateTime?
  firstCompletedAt       DateTime?
  secondCompletedAt      DateTime?
  lastMatchAt            DateTime?
  lastMeaningfulAt       DateTime?
  lastAppOpenAt          DateTime?
  usualGapDays           Float?
  weeksActiveLast4       Int               @default(0)
  weekStreak             Int               @default(0)
  bestWeekStreak         Int               @default(0)
  tournamentsViewed30d   Int               @default(0)
  tournamentsRegistered  Int               @default(0)
  connections            Int               @default(0)
  invitesSent            Int               @default(0)
  invitesConverted       Int               @default(0)
  proStatus              Boolean           @default(false)
  proPropensity          Int               @default(0)
  proGateHits30d         Int               @default(0)
  lastProPromptAt        DateTime?
  lastNudgeAt            DateTime?
  nudgesIgnoredStreak    Int               @default(0)
  nudgePausedUntil       DateTime?
  pushEnabled            Boolean           @default(false)
  whatsappOptIn          Boolean           @default(false)
  whatsappOptInAt        DateTime?
  holdout                Boolean           @default(false)
  updatedAt              DateTime          @updatedAt

  @@index([stage, activityStatus])
  @@index([lastMeaningfulAt])
  @@map("user_lifecycle")
}

model PushToken {
  id         String    @id @default(cuid())
  userId     String
  token      String    @unique
  platform   String    // android | ios
  appVersion String?
  lastSeenAt DateTime  @default(now())
  invalidAt  DateTime?

  @@index([userId])
  @@map("push_tokens")
}

model NotificationPreference {
  userId String
  group  String   // "tips_progress", "news_tips", …
  push   Boolean  @default(true)
  inApp  Boolean  @default(true)

  @@id([userId, group])
  @@map("notification_preferences")
}

// The outbox and the send log in one: scheduled → sent → opened → converted.
model EngagementMessage {
  id             String         @id @default(cuid())
  userId         String
  type           String         // "journey.rematch"
  channel        MessageChannel
  campaignId     String?
  stepId         String?
  experimentKey  String?
  variant        String?
  status         MessageStatus  @default(scheduled)
  reason         String?        // cancel / suppress reason (rule number)
  dedupeKey      String         @unique
  payload        Json           // placeholders
  goalEvent      String?
  exitEvents     String[]
  attributionHrs Int            @default(24)
  scheduledFor   DateTime
  sentAt         DateTime?
  deliveredAt    DateTime?
  openedAt       DateTime?
  convertedAt    DateTime?
  notificationId String?        // the in-app row it created
  createdAt      DateTime       @default(now())

  @@index([status, scheduledFor])
  @@index([userId, sentAt])
  @@index([campaignId, variant, status])
  @@map("engagement_messages")
}

model Campaign {
  id           String         @id @default(cuid())
  key          String         @unique
  name         String
  kind         String         // journey | triggered | recurring | broadcast
  status       CampaignStatus @default(draft)
  trigger      Json           // { event: "match.completed", where: {...} } or { schedule: "MON 08:00" }
  audience     Json           // segment / stage / city / source filters
  goalEvent    String
  holdoutPct   Int            @default(10)
  priority     Int            @default(50)
  createdBy    String
  createdAt    DateTime       @default(now())
  updatedAt    DateTime       @updatedAt
  steps        CampaignStep[]

  @@map("campaigns")
}

model CampaignStep {
  id           String   @id @default(cuid())
  campaignId   String
  campaign     Campaign @relation(fields: [campaignId], references: [id], onDelete: Cascade)
  order        Int
  delayMinutes Int
  sendWindow   Json?    // "play_window" | { from: "08:00", to: "20:00" }
  channel      MessageChannel
  conditions   Json     // evaluated at send time against UserLifecycle
  exitEvents   String[]
  copy         Json     // { A: {title, body, route}, B: {...} }

  @@unique([campaignId, order])
  @@map("campaign_steps")
}

model Experiment {
  id             String   @id @default(cuid())
  key            String   @unique
  hypothesis     String
  variants       Json     // [{ key: "A", weight: 50 }, …]
  primaryMetric  String   // goal event
  guardrails     String[]
  status         String   // draft | running | stopped | shipped
  startAt        DateTime?
  endAt          DateTime?

  @@map("experiments")
}

model ExperimentAssignment {
  experimentId String
  userId       String
  variant      String
  assignedAt   DateTime @default(now())

  @@id([experimentId, userId])
  @@map("experiment_assignments")
}

model Achievement {
  key      String  @id  // "regular"
  name     String
  family   String
  tier     String?
  line     String
  criteria Json
  active   Boolean @default(true)

  @@map("achievements")
}

model UserAchievement {
  userId         String
  achievementKey String
  progress       Int       @default(0)
  unlockedAt     DateTime?
  sourceMatchId  String?

  @@id([userId, achievementKey])
  @@map("user_achievements")
}

// One row per player per active day: makes cohort retention a cheap query.
model UserActivityDay {
  userId  String
  day     DateTime @db.Date
  opened  Boolean  @default(false)
  played  Boolean  @default(false)

  @@id([userId, day])
  @@index([day])
  @@map("user_activity_days")
}

// Casual-match guests claimed by a new account through a claim link.
model MatchClaimLink {
  id            String    @id @default(cuid())
  matchId       String
  side          String
  slot          Int
  createdBy     String
  token         String    @unique
  claimedBy     String?
  claimedAt     DateTime?
  expiresAt     DateTime

  @@unique([matchId, side, slot])
  @@map("match_claim_links")
}
```

`UserLifecycle` holds only derived state. If it's ever wrong, a rebuild job recomputes it from `user_events` and the match tables.

### 14.3 Module layout

```text
src/engagement/
  engagement.module.ts
  events.service.ts            // track(userId, name, props, db?) — used by every feature, in its transaction
  events.controller.ts         // POST /me/events (batched app events, allow-listed names)
  lifecycle.service.ts         // apply(event) → counters, stage transitions; rebuild(userId)
  next-moves.service.ts        // the §13 tree; GET /me/next-moves
  scheduler.service.ts         // enqueue messages from rules and campaigns
  dispatcher.service.ts        // every minute: due messages → §13.4 → channels
  caps.ts                      // rules 3, 7, 10–17 (pure, unit-tested)
  channels/
    in-app.channel.ts          // NotificationsService.notify
    push.channel.ts            // FCM HTTP v1
    whatsapp.channel.ts        // same provider as OTP; approved templates only
    email.channel.ts
  achievements.service.ts      // evaluate on match.completed etc.
  experiments.service.ts       // deterministic hash(userId, key) → variant
  jobs/
    nightly-lifecycle.job.ts   // 03:00 IST: rolling fields, segments, status, propensity, ladder
    weekly-recap.job.ts        // Mon 07:00 IST: enqueue recaps at 08:00 local
    rollups.job.ts             // hourly: campaign stats, activity days
  admin/
    engagement-admin.controller.ts  // /admin/engagement/*, PLATFORM_ADMIN_EMAILS
```

Scheduling uses `@nestjs/schedule` for the cron triggers and the `engagement_messages` table as the queue (`SELECT … FOR UPDATE SKIP LOCKED`). This avoids adding Redis until volume demands it. If it does, the dispatcher moves to BullMQ unchanged.

### 14.4 Where events are emitted

Each call goes next to the existing `notifications.notify(...)` or state change, inside the same transaction.

| Event | Emitted in |
|---|---|
| `user.signed_up`, `profile.completed` | `auth` (OTP verify creates the user), `profile.service` (setup saved) |
| `match.created`, `match.scoring_started`, `match.completed`, `match.abandoned` | `matches/casual-matches.service.ts` (+ score sync) |
| `match.joined`, `match.link_confirmed`, `match.link_rejected` | casual-matches verification flow |
| `match.claimed` | new claim-link endpoint |
| `tournament.registered`, `registration.*` | `registrations` |
| `booking.confirmed` | commerce / bookings |
| `community.connected`, `community.group_joined` | `community` |
| `looking_for.posted`, `looking_for.responded` | `looking-for` |
| `pro.purchased`, `pro.ended` | `subscriptions` (`markPaid`, expiry) |
| `rating.changed`, `achievement.unlocked` | rating update, `achievements.service` |
| `notification.opened` | `POST /me/notifications/:id/opened` (new) |

App-only events (allow-listed in `POST /me/events`): `app.opened`, `screen.viewed` (a short list of screens only), `player.profile_viewed`, `h2h.viewed`, `stats.viewed`, `tournament.viewed`, `pro.gate_hit {feature}`, `pro.plans_viewed`, `card.seen {type}`, `card.tapped {type}`, `card.dismissed {type}`, `invite.sent {channel}`, `share.result`.

### 14.5 API

| Method | Path | |
|---|---|---|
| POST | `/me/events` | Batch of up to 50 app events |
| GET | `/me/next-moves` | Ranked moves for Home (and post-match with `?after=match:{id}`) |
| POST | `/me/next-moves/{type}/dismiss` | Hides that move for 7 days |
| POST | `/me/push-tokens` · DELETE `/me/push-tokens/{token}` | FCM registration |
| GET/PUT | `/me/notification-preferences` | Groups × channels, WhatsApp opt-in |
| POST | `/me/notifications/{id}/opened` | Open tracking (also from push tap) |
| PUT | `/me/play-window` | The 24 h question |
| GET | `/me/achievements` | Unlocked + progress |
| POST | `/matches/{id}/claim-links` · GET `/claim/{token}` · POST `/claim/{token}` | Guest claim loop |
| GET/POST/PATCH | `/admin/engagement/*` | Dashboard, campaigns, experiments (§15) |

### 14.6 App changes (Flutter)

| Piece | Where |
|---|---|
| Event tracker: batched, offline queue in `SharedPreferences`, flushed on resume and every 30 s | `lib/core/analytics/event_tracker.dart` |
| Engagement data: `EngagementRepository` (API) and `SampleEngagementRepository` (debug, like the other sample repositories) | `lib/features/engagement/data/` |
| `nextMovesProvider`, `NextMoveCard` (`lib/design/`) | `lib/features/engagement/` |
| Home: `_Welcome` / `_HowItWorks` → `NextMoveCard` for new players; one `NextMoveCard` slot above `_QuickActions` for everyone else | `lib/features/player/home/player_home_page.dart` |
| Post-match moves block | `lib/features/casual_match/ui/live/match_complete_view.dart` |
| Achievement unlock overlay (once per badge) | `lib/features/engagement/ui/achievement_moment.dart` |
| Play-window question sheet | `lib/features/engagement/ui/play_window_sheet.dart` |
| Contextual tips replace the full tour for non-core tabs | `lib/features/onboarding/app_tour.dart` |
| Push: `firebase_messaging`, token registration on sign-in, tap → `route` via go_router, open tracking | `lib/core/push/` |
| `NotificationKind.journey` + icon; Settings › Notifications groups + WhatsApp updates switch | `lib/features/notifications/`, `lib/features/settings/` |
| `ProGate` / `showProUpsell` emit `pro.gate_hit {feature}` and show feature-specific copy (§11.3) | `lib/features/subscription/ui/` |
| Claim link landing: `/claim/:token` → sign-in (if needed) → claimed match | `lib/app/routing/router.dart` |

`router.dart`, `explore_modules.dart` and `notifications*.dart` are edited by other sessions too; re-read them just before changing them.

---

## 15 — Admin Marketing Dashboard

On the web at `/admin/engagement` (Next.js, `frontend/`), behind `PLATFORM_ADMIN_EMAILS`, the same gate as `/admin/looking-for`.

### 15.1 Pages

| Page | Shows |
|---|---|
| **Overview** | Today and 7-day: new sign-ups, activated, WRP (north star), D1/D7/D30 play retention (latest mature cohort), dormant count, re-engaged, Pro conversions. Each tile with the previous period and a sparkline. |
| **Activation funnel** | Sign-up → first match created/joined → first point → first completed → second match → habitual; by week of sign-up, split by acquisition source and city. Median time between steps. |
| **Cohorts** | Retention grid: sign-up week × week number, toggle *opened* / *played*. |
| **Segments** | Size of each segment over time, and flows between them (activated → dormant etc.). |
| **Campaigns** | Every campaign and built-in journey step: sent, delivered, opened, **goal conversion**, **lift vs holdout**, cancelled (by reason), opt-outs after. Sorted by lift, not opens. |
| **Messages** | Per type: volume, cancellation reasons (goal met / outranked / cap / preference). A high goal-met cancel rate means the timing is late. |
| **Experiments** | Running tests: variant split, primary metric with confidence interval, guardrails, sample size progress, "ship / stop" actions. |
| **Pro** | Propensity distribution, gate hits by feature, conversions by moment (§11.3), churn. |
| **Player lookup** | One player's lifecycle row, events timeline, and every message scheduled, sent or cancelled (with the rule that cancelled it). For support and debugging. |

### 15.2 Campaign builder

```text
TRIGGER    event (match.completed where …) · schedule (Mon 08:00) · state entry (stage → activated) · inactivity (past usual gap by N days)
   ↓
AUDIENCE   segments · stage · activity status · city · source · Pro/Free · has push · language
   ↓
DELAY      minutes/hours/days after trigger · or "next play window" · or fixed local time
   ↓
MESSAGE    type + copy variants (live preview with a real player's data; 40/110 check; voice lint)
   ↓
CHANNEL    in-app · push · WhatsApp template (utility/marketing) · email
   ↓
CONDITION  checked at send time: e.g. matches_completed = 0 AND no pending invite
   ↓
GOAL       the event that means it worked + attribution window (default 24 h)
   ↓
EXIT       events that cancel it (defaults filled from the goal)
   ↓
FOLLOW-UP  next step if goal not met after X (max 3 steps)
   ↓
HOLDOUT    % held back (default 10, can't be 0 for a new campaign)
```

Guardrails built into the builder: preview shows how many players would get it this week, after caps; the anti-spam rules (§12) can't be switched off; WhatsApp marketing steps can only target opted-in players; a campaign can't go live without a goal event; a new campaign starts at 20% of its audience for 7 days before full rollout.

---

## 16 — Analytics & KPIs

Measure a 4-week baseline before setting targets. Definitions below are the ones the dashboard computes.

### 16.1 Funnel and activation

| KPI | Definition |
|---|---|
| Sign-ups | Accounts that finished profile setup |
| First-match rate | % of sign-ups with a match created or joined within 7 days |
| First-score rate | % of sign-ups with `first_score_at` within 7 days |
| **Activation rate** | % of sign-ups with a completed match on record within 7 days |
| Time to activation | Median hours sign-up → first completed match |
| Match completion rate | Completed ÷ started (scoring started) matches |
| Second-match rate | % of activated with a second completed match within 14 days |
| Claim rate | % of guest slots claimed by a new account within 7 days |
| Viral coefficient (k) | New activated accounts from claim links ÷ activated accounts, per week |

### 16.2 Retention

| KPI | Definition |
|---|---|
| D1 / D7 / D30 retention (opened) | % of a sign-up cohort that opened on day 1 / in days 1–7 / in days 22–30 |
| **D7 / D30 play retention** | Same, but completed a match. The main retention numbers. |
| **WRP (north star)** | Players with ≥1 completed match on record this week |
| Weekly habit | % of last month's WRP who played in ≥3 of 4 weeks |
| Dormant | Count in `dormant` + `lapsed` |
| Re-engaged | Dormant players with a meaningful action within 7 days of a ladder message |
| Reactivated | Returned players with 2 matches within 21 days |

### 16.3 Messaging

| KPI | Definition | Note |
|---|---|---|
| Delivery rate | Delivered ÷ sent | FCM + WhatsApp receipts |
| Open rate | Opened ÷ delivered | Diagnostic only |
| **Goal conversion** | Goal event within attribution window ÷ delivered | The campaign's real success |
| **Lift** | Goal conversion (sent) − goal conversion (holdout) | What we optimise |
| Cancel-by-goal rate | Cancelled for goal met ÷ scheduled | High = the player didn't need it; send earlier or drop it |
| Push opt-out rate | Players who turned off a group or OS push within 24 h of a message | Guardrail |
| Uninstall-after-push | Token invalid within 48 h of a push | Guardrail |

### 16.4 Pro

Pro conversion (Free → Pro within 30 days of first Pro moment) · conversion by moment · 30-day Pro retention · Pro prompt dismiss rate (guardrail).

---

## 17 — A/B Testing Framework

### 17.1 How a test runs

1. Write the hypothesis: *"Naming the opponent in the rematch nudge raises second-match rate, because rivalries motivate more than generic prompts."*
2. Pick **one primary metric**: the campaign's goal event (a product action), never open rate.
3. Pick guardrails: opt-out rate, uninstall-after-push, and for Pro tests 30-day refund or cancel rate.
4. Assignment: `variant = hash(userId + experimentKey) mod 100` against the weights. Stable across devices, logged in `experiment_assignments` on first exposure.
5. Size it before starting (80% power, 5% significance). SkorX's volume is modest, so test **big differences** (timing, channel, framing), not word tweaks, and run for full weeks (the sport's weekly rhythm matters).
6. Stop early only for a guardrail breach. Ship the winner by making it the campaign default, and record the result in the experiment row.

### 17.2 Test backlog

| # | Campaign | Test | Primary metric | Guardrail |
|---|---|---|---|---|
| 1 | Post-match | Claim links shown first vs stats first | Claim rate (7 d) | Second-match rate |
| 2 | `journey.first_match_tonight` | 5:30 PM vs 1 h before learned window vs no push | Activation rate (7 d) | Push opt-out |
| 3 | `journey.rematch` | Named opponent vs generic `second_match` | Second-match rate (14 d) | — |
| 4 | Home card vs push | In-app card only vs card + push after 12 h | Goal conversion | Opt-out |
| 5 | Weekly recap | Push vs in-app only | Matches in the following week | Opt-out |
| 6 | Re-engagement day 7 | Progress framing (`rating_waiting`) vs social framing (`rival_active`) | Meaningful action (7 d) | Uninstall |
| 7 | Copy length | Short title only vs title + body | Goal conversion | — |
| 8 | Personalised vs generic | Placeholders filled vs template without names | Goal conversion | — |
| 9 | 24 h ask | Play-window question vs no question | D7 play retention | — |
| 10 | Pro after settle | Card vs 7-day preview ⚑ | Pro at 30 d | Pro refund/cancel at 60 d |
| 11 | Streak | Weeks-on-court streak shown vs hidden | Weekly habit | — |
| 12 | Find a game | Looking For card at day 3 vs day 1 | Activation rate | — |

### 17.3 The global holdout

10% of new sign-ups are fixed as `holdout` for their first 60 days. They get every transactional and social message and see in-app cards, but no `journey.*`, `pro.*` or recap pushes. Holdout vs rest on D30 play retention is the honest answer to "is the engagement engine worth it?". Review each quarter; shrink to 5% once lift is established.

---

## 18 — Implementation Roadmap

Each phase ships something useful on its own. Push (FCM) is already build step 7 in [ARCHITECTURE.md](ARCHITECTURE.md), so the in-app half comes first.

| Phase | What | Where | Depends on | Done when |
|---|---|---|---|---|
| **0. Measure** (1–2 wk) | `user_events`, `EventsService.track` at the §14.4 points, `POST /me/events` + app tracker, `user_lifecycle` counters and stages, `user_activity_days`, nightly job, rebuild job. Admin Overview + Funnel + Cohorts (read-only). | API `src/engagement/`, app `lib/core/analytics/`, web `/admin/engagement` | — | Funnel and cohorts show real numbers on the 5433 dev DB; lifecycle rebuild matches incremental state in tests |
| **1. In-app moves** (2 wk) | `GET /me/next-moves` (§13 tree, pure and unit-tested), `NextMoveCard` on Home, post-match moves, play-window question, contextual tips, empty states (§08.6), achievements service + unlock moment + new badges, `journey.*` kind and in-app copy | API + app | 0 | A new player on the phone sees the right first move per source; tree tests cover every branch |
| **2. Claim loop** (1–2 wk) | `match_claim_links`, share via WhatsApp from post-match, `/claim/:token` landing and sign-up with source `linked`, `journey.friend_joined`, Connector badge | API + app + App Links | 1 | A guest claims a match end-to-end on two phones |
| **3. Push + dispatcher** (2 wk) | FCM (build step 7), push tokens, preferences, `engagement_messages` outbox, dispatcher with §12 rules (pure `caps.ts`, tested), bundling and quiet hours from NOTIFICATIONS.md, open tracking, holdout flag. Turn on the first-week journey (§02) and match-day pushes. | API + app | 1 | Journey runs for new sign-ups; cancel reasons visible in Player lookup |
| **4. Retention** (2 wk) | Weekly/first-week/first-month recaps, streaks, re-engagement ladder with relative inactivity, rival/partner insights, tournament fit | API + app | 3 | Dormant → re-engaged tracked with holdout lift |
| **5. Campaigns + experiments** (2–3 wk) | Campaign builder, experiments, lift reporting, WhatsApp utility templates (claim reminders for tournament entrants, entry confirmations), WhatsApp opt-in + one day-30 marketing template | Web admin + API | 3 | Admin can build, preview and launch a campaign under caps; first 3 tests in §17.2 running |
| **6. Pro** (1–2 wk) | Propensity, gate-hit tracking, contextual sheets per feature, `pro.*` types, Pro dashboard; business decisions ⚑ | API + app | 0, 3 | Pro conversions attributed to moments |

### Decisions needed before building

| # | Question | Default if not decided |
|---|---|---|
| 1 | Pro rewards (Connector badge, 7-day preview at rating settle) | No money rewards; test later |
| 2 | WhatsApp marketing opt-in: ask at sign-up, or in Settings only | Settings only, plus a one-time ask after activation |
| 3 | Email collection for players | Optional field on the profile; used for invoices and the monthly recap only |
| 4 | Holdout size | 10% of new sign-ups for 60 days |
| 5 | Hindi / regional language copy | English first; copy keys are ready for translation |
