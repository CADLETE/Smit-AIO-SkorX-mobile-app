# SkorX Organiser (TMS): Mobile Workspace

Status as of 25 Sep 2026. Covers build step 6 (ARCHITECTURE.md §12): the Organiser workspace in the Flutter app, and the API contract the NestJS backend and the web TMS must implement for it. The backend and web repos are not in this workspace, so nothing here has run against a real server yet (see §9).

Principle: **tournament day, one thumb.** Every screen answers where am I, what is happening, what needs me, and what do I do next. It has one primary action.

---

## 1. What was built

| Area | Where | State |
|---|---|---|
| Domain model and life cycle | `lib/features/organizer/data/tms_models.dart` | Built, unit-tested |
| Draw engine (seeded / random knockout with byes, round robin, snake-seeded pools, swaps, winner advance) | `data/draw_engine.dart` | Built, unit-tested |
| Schedule engine (courts, match length, changeover and rest, break, knockout dependencies, no player double-booked across categories) | `data/schedule_engine.dart` | Built, unit-tested |
| Result validation (win by 2, point caps, games needed) | `validateResult` in `tms_models.dart` | Built, unit-tested |
| Repository contract, one method per endpoint | `data/organizer_repository.dart` | Contract final for v1; release build uses `EmptyOrganizerRepository` |
| Debug "server" shared with the Player app | `data/sample_organizer_repository.dart` | Enforces life cycle, versioned idempotent scoring, audit log |
| Local-first scoring with offline queue and conflict handling | `scoring/match_console_controller.dart` | Built, unit-tested |
| Screens (20) | `lib/features/organizer/ui/` | Built; every screen lays out at 360×690 in tests |
| Routes | `lib/features/organizer/organizer_routes.dart` | Spliced into the app router |

## 2. Navigation

Bottom bar (spec §35): **Home · Tournaments · Live · Players · More**. Old saved locations `/dashboard`, `/matches` and `/schedule` redirect to Home, Live and Tournaments.

```text
Home        greeting · LIVE NOW command card · Needs attention · quick actions · at a glance · coming up
Tournaments Active / Drafts / Past  →  Tournament hub
              hub: status · life-cycle stepper · next-step card (one primary button) · overview metrics
                   Registrations · Check-in · Draws · Schedule · Courts · Live · Announcements · Results
              menu: copy link · duplicate · archive · cancel (confirmed, destructive)
            New → 5-step wizard: Basics · Categories · Format · Registration & fees · Review → Publish / Save draft
Live        control room for the live tournament: clock, done/courts live/waiting/delayed,
            court grid (Live / Ready / Delayed / Free / Break / Maintenance), up-next queue
              court sheet: Open score · Start match · Call next · Move a match here · Pause · court state · rename
              → Match console (full screen)
Players     registrations for the tournament in focus (switcher on top), filters, approve / waitlist / reject
More        Finance · Payments · Check-in · Draws · Courts · Announcements · Analytics · Staff & roles ·
            Activity log · Organiser profile (each hidden without its capability)
```

All routes live under `/org/:orgId/…`, so the workspace rules apply: membership check, remembered place, and one-tap back to Player. Full-screen pages are `new-tournament`, `t/:tid`, `t/:tid/{registrations,check-in,draw,schedule,courts,results,announce}`, `t/:tid/match/:mid`, `finance`, `analytics`, `staff`, `audit` and `profile`.

## 3. Data model: reuse, not duplicates

| Organiser concept | Maps to (NestJS / Prisma) | Notes |
|---|---|---|
| `OrgTournament` | `Tournament` | Adds `status` (§4), `checkInOpen`, `publishedDraws` |
| `OrgCategory` | Tournament division | Carries its own `MatchRules`, the same JSON as casual matches |
| `Entry` | Registration | Approval, payment, attendance, seed, ticket code |
| `PlayerRef` | `PlayerProfile` + `SportPlayerProfile` | **A reference, never a copy.** The organiser sees name, rating and city read-only. Only the player edits their profile. |
| `TmsMatch` | `Match` with `kind = tournament` | Same table as casual matches. Adds `round`, `number`, `sourceA/B` (bracket feed), `pool`, `courtId`, `scheduledAt`, `state` |
| Score | `ScoreEvent` | Same events and `scoreVersion` as casual scoring (ARCHITECTURE.md §6) |
| `TmsCourt` | New `Court` (per tournament, optionally from a saved `Venue`) | `mode`: open, break, maintenance, blocked. Live, ready and delayed are **derived** (`courtBoard`), never stored |
| `Announcement`, `AuditEntry` | New tables | Announcements fan out to the notification inbox and push |

`MatchState` is `pending → scheduled → called → live ⇄ paused → completed`. "Delayed" is a scheduled or called match more than 10 minutes past its time. It is derived, so it can never be stale. This implements the state machine planned in ARCHITECTURE.md §8.

## 4. Tournament life cycle

`TournamentLifecycle` is one table that both the app and the server use. Screens ask it what is allowed and never check a status by hand.

| Status | Allowed | Next step (hub button) |
|---|---|---|
| Draft | edit everything, publish, cancel, duplicate | Publish and open registration |
| Registration open | edit details and categories, manage entries, announce, close, cancel | Close registration |
| Registration closed | entries, check-in, generate draw, reopen, announce, cancel | Make the draws |
| Draw ready | entries (**warns**), check-in, regenerate (**warns**), publish draw, schedule | Make the schedule |
| Scheduled | entries (warns), check-in, publish draw, reschedule (warns), courts, start | Start the tournament |
| Live | check-in, courts, scoring, complete, announce, cancel. **No draw or entry changes** | Open live control room |
| Completed | correct results (needs override, audited), announce, archive | View results |
| Cancelled / Archived | archive / duplicate | — |

Confirmations (spec §54) cover: publish tournament, close registration, start, finish, publish draw, regenerate draw, rebuild schedule, approve all, check in all, close check-in, refund (destructive), cancel tournament (destructive, with "Keep tournament" as the safe choice), and emergency announcements.

## 5. Scoring on tournament day (offline-safe)

```text
tap → controller state (one synchronous update) → queue written to the phone (serialized)
    → sent in order: POST /matches/:id/score {clientEventId, baseVersion, kind, side|serve}
    → ack: confirmed += write and pending -= write in ONE state update
```

- **Never lose a point.** The queue is saved per match (`skorx.tmsScore.<matchId>`), and nothing is sent until it is on disk. The only exposure is the few milliseconds between a tap and its disk write.
- **Never double-count.** `clientEventId` is made on the phone, so the server ignores an id it has already applied. If an ack's version is not base+1, the phone takes the server's `GET /matches/:id/score-events` log instead of guessing.
- **Never overwrite.** A stale `baseVersion` gets `SCORE_CONFLICT`. The console then shows both scores, and the official chooses **Use theirs** or **Add mine**.
- **Always visible.** A sync bar reads *Synced*, *Syncing n…*, *Offline · n points saved on this phone* or *Score changed on another device*. Offline retries run every 5 s, and *Retry now* is always available.
- **Confirming.** A result can be confirmed only after every tap has synced, so the server confirms exactly what the official saw. Typed-in results and corrections go through `validateResult` on both sides and are audited.
- Undoing a tap that has not been sent yet just drops it locally. The double-tap guard (400 ms), wakelock and haptics are the same as casual scoring.

Debug builds have **Go offline (test)** in the console menu, to try this without leaving the app.

## 6. API contract (to implement in NestJS)

Every call is authorised on the server by capability. The app hiding a button is never the security.

| Method | Endpoint | Capability |
|---|---|---|
| `overview` | `GET /organizations/:orgId/overview` | any member |
| `tournaments` / `tournament` | `GET /organizations/:orgId/tournaments`, `GET /tournaments/:id` | any member |
| `createTournament` | `POST /organizations/:orgId/tournaments {draft, publish}` | editTournament |
| `transition` | `POST /tournaments/:id/transitions {action}` (checked against §4) | editTournament |
| `duplicate` | `POST /tournaments/:id/duplicate` | editTournament |
| `setCheckInOpen` | `PATCH /tournaments/:id {checkInOpen}` | manageCheckIn |
| `entries` / `updateEntry` | `GET /tournaments/:id/entries`, `PATCH /entries/:id` | managePlayers (attendance: manageCheckIn; payment: managePayments) |
| `checkInByCode` / `checkInAll` | `POST /tournaments/:id/check-in {code}`, `…/check-in/bulk` | manageCheckIn |
| `draw` / `generateDraw` / `swapInDraw` / `publishDraw` | `GET/POST/PATCH /tournaments/:id/categories/:cid/draw`, `…/draw/publish` | editTournament |
| `matches` / `match` | `GET /tournaments/:id/matches`, `GET /matches/:id` | any member |
| `generateSchedule` | `POST /tournaments/:id/schedule {settings}` | manageSchedule |
| `courts` / `updateCourt` / `moveMatch` | `GET /tournaments/:id/courts`, `PATCH /courts/:id`, `PATCH /matches/:id {courtId}` | manageSchedule |
| `command` | `POST /matches/:id/{call,start,pause,resume}` | scoreMatch |
| `scoreLog` / `score` | `GET /matches/:id/score-events`, `POST /matches/:id/score` (**exists**; add `rally` and `serve` kinds) | scoreMatch |
| `confirmResult` / `enterResult` | `POST /matches/:id/complete` (**exists**), `POST /matches/:id/result {games, reason}` | scoreMatch; after completion also the override |
| `announcements` / `announce` | `GET/POST /tournaments/:id/announcements` | editTournament |
| `audit`, `finance`, `profile` | `GET /organizations/:orgId/{audit,finance,profile}` | manageSettings, managePayments, any member |
| `events` | `GET /realtime/stream?scope=org:<orgId>` (SSE, ARCHITECTURE.md §7) | membership |

Error codes the app switches on: `SCORE_CONFLICT`, `TOURNAMENT_STATE`, `MATCH_STATE`, `CATEGORY_FULL`, `CHECK_IN_CLOSED`, `CODE_NOT_FOUND`, `NOT_APPROVED`, `DRAW_LOCKED`, `INVALID_RESULT`, `RESULT_LOCKED`, `NO_COURT`, `NOT_SCHEDULED`, `MATCHES_ON_COURT`, `TOO_FEW_ENTRIES`, `NOT_PAID`. Messages are written for people and shown as they are. Anything unexpected shows *"Something went wrong. Nothing was changed; try again."*

**New capability:** `scoreMatch` (score any match in the organisation). It resolves decision D5 as "any match", and referees keep `scoreAssignedMatch`. Add it to `backend/src/organizations/permissions.ts`.

## 7. Realtime and the Player connection

`tmsRealtimeProvider` listens to `events(orgId)`. It refreshes only the providers each event touches: tournament, entries, draw, matches or score, courts, announcements. The organiser shell and every full-screen organiser page keep it alive.

In debug builds the organiser store *is* the player's backend for organiser-run tournaments:

- A tournament published here appears in **Player › Explore**. Drafts never do.
- A player's registration there lands in the organiser's queue as pending (paid at checkout).
- Player tournament screens refresh on organiser events.

With the real API, the same thing happens through one database and the SSE stream.

## 8. Roles

`OrgPermissions` (`ui/org_widgets.dart`) maps capabilities to what the UI shows. Money (amounts, payment pills, Finance, revenue tiles) needs `managePayments`. Staff and the activity log need `manageSettings`. Scoring needs `scoreMatch` or `editTournament`. A direct link to a page a role can't use shows "Your role cannot …". It never shows data, and the server refuses it anyway.

## 9. Verified and not verified

Verified (`flutter test`, 136 tests, all passing; 62 are new):

- Life-cycle table and transitions; the draw engine (bracket order, byes to top seeds, seeds protected in random draws, round robin with nobody twice per round, snake pools, swaps); the scheduler (no court or player double-booking across categories, knockout dependencies, the break); result validation.
- The sample server: idempotent resends, stale-version conflicts, winner advance, audit log, life-cycle refusals, player registration reaching the organiser.
- The offline queue: taps offline appear at once and sync in order; they survive the app closing; a conflict is chosen by the official; undo of an unsent tap; a result is confirmed only after sync.
- Widgets: all 27 organiser screens at 360×690 with no overflow. The wizard publishes a tournament that the Player side can read. Approving a registration, generating and publishing a draw, scoring a live match through to a confirmed result, scorer role limits, and sending an announcement.

Not verified or not built:

- **No real backend.** Every endpoint in §6 except `/score` and `/complete` needs building in NestJS, plus the `Court`, `Announcement` and `AuditEntry` tables and `scoreMatch`.
- **Web PMS (Next.js)** is not in this workspace. It should call the same endpoints. The desktop sidebar IA from the spec is unchanged.
- **Not in the app yet:** QR camera scanning (check-in uses the 5-character ticket code under the QR; add `mobile_scanner` when a device is available for testing), the public TV scoreboard page, streaming control, certificate PDFs, WhatsApp/SMS channels, venue and sponsor editing, review replies, staff invites, and a knockout stage generated from pool results.
- **Player side of check-in** ("CHECK-IN OPEN · Check in" in the Player app) is not built. The Player UI is being rebuilt in parallel; the endpoint is `POST /tournaments/:id/check-in` with the player's own entry.
- Nothing has run on a phone yet (see ARCHITECTURE.md §13).
