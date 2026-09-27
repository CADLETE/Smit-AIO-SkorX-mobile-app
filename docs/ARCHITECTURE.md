# SkorX Mobile: Architecture and Feature Inventory

Status as of 25 Sep 2026. Step 1 of the build (backend foundations) is done; the Flutter app itself has not been started. Open decisions are listed at the end and block the steps that depend on them.

## 1. What exists today

| Piece | Where | State |
|---|---|---|
| Player app (live on stores, `com.skorx.pickleball` and `com.skorx.badminton` from one codebase) | `d:\SkorX\Skorx_pickaball_Latest` (github.com/arbaz8dots/Skorx_pickaball_Latest) | Flutter, Provider + GetX. Phone number + 6-digit OTP delivered on WhatsApp. Talks to its own backend `https://app.skorx.in/api` (REST + Socket.IO) and Firebase (realtime database for live scores, push, crashlytics). |
| Old backend | `app.skorx.in`; source to be shared | Holds every existing user, match, tournament, subscription and booking. Being replaced by the NestJS API with a data migration (decided 25 Sep 2026). |
| New app | `D:\SkorX\SKORX -SMIT -DEV - APP` | Flutter 3.47.5 (SDK at `D:\dev\flutter`). Ships under the live ids (`com.skorx.pickleball`) so it installs as an update. |
| Web app + TMS | `d:\SkorX\smit-dev-skorx-frontend\frontend` | Next.js. Mostly mock data behind `lib/api/*` signatures. |
| API | `d:\SkorX\smit-dev-skorx-frontend\backend` | NestJS + Prisma + PostgreSQL. Partly built; never migrated against a real database. |
| Mobile brief | `smit-dev-skorx-frontend/docs/MOBILE-APP-BRIEF.md` | Full feature description of web, TMS and referee flows. |

The Flutter app and the TMS web are two clients of this one API. There is no separate mobile API, database or business logic.

## 2. Feature inventory

Action: **Keep** as is, **Improve**, **Move** to another workspace, **Replace** with a new implementation, **Deprecate**, **New**.

### From the existing player app

| Feature | Action | Workspace | Notes |
|---|---|---|---|
| Phone + WhatsApp OTP login (Android WhatsApp autofill handshake, clipboard fallback on iOS) | Keep unchanged | All | Decided. NestJS needs the same OTP endpoint behaviour; the old backend's implementation is the reference. |
| Referee booking (find, book, booking history, tournament referee bookings) | Keep | Player, Organizer | Old endpoints `/referee/*`. Not yet in NestJS. |
| Venues, court booking, reviews | Keep | Player | Old `/venue/*`, `/booking/*`, `/review/`. Not yet in NestJS. |
| Match invites: join, accept, reject, re-invite | Keep | Player | Old `match/accept-request` etc. Linking another player to a match needs this consent flow. |
| Partner suggestions | Keep | Player | Old `/partner-suggestion`; likely the "Looking" tab. |
| Local ranking, achievements, month stats, full stats | Keep | Player | Old `/leaderboard`, `/match/player-achievements`, `/match/month-stats`. |
| Player Pro subscription, payment history, invoices | Keep | Player | Old app uses Razorpay for it; store billing rules apply to digital subscriptions (brief section 8). |
| Casual match live streaming (api.video, YouTube key) | Keep | Player | Stream keys must stay server-side. |
| Bluetooth scoring device, Apple Watch / Wear OS | Keep | Player, Referee | `flutter_blue_plus`, `watch_connectivity`, `wear_plus`. |
| Voice score announcements (TTS) | Keep | Player, Referee | `flutter_tts`. |
| Badminton flavor | Replace | Player | Becomes a sport inside the one app instead of a separate store app. See decision D8. |
| Old tournament creation (stages, teams, allowed mobiles) | Replace | Organizer | Superseded by the TMS model in NestJS. |
| Onboarding ("You're ready to start") | Improve | Player | Add sport choice; one account, no role picker. |
| Start singles / doubles match | Keep | Player | Now `POST /casual-matches`. Categories come from the sport, not code. |
| Starting server on a court diagram | Keep | Player | `firstServer` on create. |
| Match settings: games 1/3/5, rally or side out, play to 11/15/21, win by 1 or 2 | Keep | Player | Stored as the match's own rules, validated server-side. Kept behind "Customize". |
| Live scoring: point, side out, change service, undo | Keep | Player, Referee | Point and undo are on the server. Side-out and serve order move into the shared scoring engine (step 2). |
| Rulebook, match settings in scoring menu | Keep | Player, Referee | |
| Match history with game-by-game scores, duration, location | Keep | Player | `GET /casual-matches`; duration from `startedAt`/`completedAt`. |
| My Paddle: matches and tournaments, singles/doubles/mixed filter | Keep | Player | Tournament matches join via `MatchParticipant`, not by name matching. |
| Player card: performance rating, played/won/win% per category | Keep | Player | Per sport (`SportPlayerProfile`). Rating formula to be confirmed. |
| Achievements (85, e.g. First Victory, Hot Streak) | Keep | Player | Needs a backend definition table; not modeled yet. |
| Profile: photo, name, city, gender, date of birth, bio, player title | Keep | Player | Gender and date of birth are needed to validate men's, women's and mixed categories. Not on `PlayerProfile` yet. |
| Discover | Improve | Player | Becomes tournament discovery (brief section 5). |
| Looking | Confirm | Player | Purpose not visible in screenshots. See decision D6. |
| Apple Watch scoring | Keep | Player, Referee | Native watch app plus Wear OS; talks to the phone, which syncs. |
| Schedule a game | Keep | Player | Casual match with a future time; needs `matchTime` on casual create. |

### From the web TMS and brief

| Feature | Action | Workspace |
|---|---|---|
| Tournament discovery, detail, registration, Razorpay payment, my registrations | New on mobile | Player |
| Live match view, rankings, stats, rival analytics | New on mobile | Player |
| Referee home and 4-phase match console | New on mobile | Referee |
| Dashboard, tournaments, matches, schedule, draws, check-in, players, teams, courts, referees | Replace (mobile-native redesign, not a copy of desktop) | Organizer |
| Payments, orders, streaming, announcements, add-ons, analytics, roles, settings | Replace, under "More" | Organizer |
| Buying TMS plans and add-ons | Keep on web | See decision D4 |

## 3. Workspaces and navigation

One account, one login. Workspaces come from `GET /auth/me` memberships:

- **Player**: always present.
- **Organizer**: one entry per organization with a non-referee role.
- **Referee**: present when any membership has the `referee` role.

Each workspace is its own navigation shell. Switching replaces the whole shell; it never adds tabs to another workspace's navigation.

| Workspace | Bottom navigation | Accent |
|---|---|---|
| Player | Home · Matches · Explore · My Paddle · Account (see PLAYER-APP.md; Community is a module inside Explore, docs/COMMUNITY.md) | Ink / volt (SkorX player design system) |
| Organizer | Dashboard · Tournaments · Matches · Schedule · More | Lime / blue |
| Referee | Current · Upcoming · Completed · Profile | Lime / blue |

**Switcher**: a workspace chip (avatar + workspace name) at the top left of every shell. It opens a bottom sheet listing Player, each organization with its role, and Referee. It is also under Profile › Workspaces. In Organizer, the chip shows the organization, so changing organization is the same gesture.

**Persistence**: the last workspace, organization, tournament and tab are stored per account on the device and restored on the next switch or launch. They reset only if the membership is gone.

**Permissions** in the UI come from the same capability list the server enforces (`backend/src/organizations/permissions.ts`). The app hides what the role cannot do; the server still rejects it if a request is made.

## 4. Multi-sport

A sport is data plus an engine. It is never an `if (sport == pickleball)` branch in a screen.

- **Server**: the `sports` table (id, name, enabled, default rules, match categories) and `src/sports/sport-registry.ts`, which maps a sport to its scoring family. A sport is playable only when it is enabled and has an engine.
- **Client**: a `SportEngine` per sport providing default rules, categories, terminology ("game" or "set"), rule validation, and a `ScoringEngine` that turns a rally result into score and serve changes.
- **Player data**: `PlayerProfile` holds what is shared across sports; `SportPlayerProfile` holds skill, rating and stats per sport. Stats and history are always filtered by sport.

Today pickleball is enabled. Badminton (21, cap 30, rally) and table tennis (11, best of 3, rally) are seeded and use the existing points engine; enabling one is a data change plus its client engine and assets. Padel is seeded but disabled until a games-and-sets engine exists.

Adding a sport:

1. Add the row to `backend/prisma/reference-data.ts`.
2. Register its scoring family on the server; add a new family only if the scoring shape is new.
3. Add its `SportEngine` and assets in the app.
4. Add the sport to the shared scoring test vectors (section 6).

No screen, navigation, auth or tournament code changes.

## 5. Data model changes made in step 1

- `Sport`, `SportPlayerProfile` added. `Tournament.sport` is now `sportId`, a foreign key to `Sport`.
- `Match` serves both tournament and casual matches: `kind`, `sportId`, optional `tournamentId`/`divisionId`, `createdByUserId`, own `matchRules`, `category`, `locationName`, `scoreVersion`, `winnerSide`, `startedAt`, `completedAt`.
- `MatchParticipant`: who played on each side, linked to a player profile when known.
- `ScoreEvent`: `matchId`, `kind` (point or undo), `sequence` (unique per match), `revertsEventId`, `clientEventId` (unique per match), `deviceId`, `recordedAt`.

Still to model: the match state machine (section 8), gender and date of birth on profiles, achievements, device sessions, push tokens, and the event outbox for realtime.

**Before the first migration**: no migration has been generated yet. Run `npx prisma migrate dev --name init` against a dev database, then `npm run prisma:reference` to insert the sports. Run `prisma:reference` on every deploy.

## 6. Scoring and offline sync

Casual matches: built 27 Sep 2026 as described in [OFFLINE-SCORING.md](OFFLINE-SCORING.md) (whole-match batch sync through `POST /casual-matches/sync`, server replay and validation, atomic per-match files on the phone). The per-event flow below is the TMS console's.

Contract (built): `POST /matches/:id/score`, `/undo`, `/complete`. See `backend/API_ARCHITECTURE.md` › Scoring writes.

Referee and player scoring on the device:

```text
Tap → local ScoringEngine → local DB (event + new score) → UI updates immediately
                                      ↓
                          sync queue (in order, one match at a time)
                                      ↓
         POST with clientEventId + baseVersion → server applies or no-ops
```

- Every event gets a client id (UUID) when it is created on the device, so resends are always safe.
- The queue sends events in order and stops at the first failure. `SCORE_CONFLICT` means another device or the TMS scored first: the app fetches the server match and shows both scores to the official. It never overwrites automatically.
- Status chip: **Offline** (queue waiting, no network) → **Syncing** → **Synced**.
- The screen stays awake during scoring. Haptics fire on each point; accidental double taps are guarded.

The server is the authority for the final score. The client engine exists so scoring works with no network. Both engines must pass the same test vectors: a shared JSON file of rally sequences and expected scores, run by Jest on the server and by `flutter test` in the app.

## 7. Realtime (not built yet)

- **Transport**: Server-Sent Events, `GET /realtime/stream?scope=...`. One connection per app while it is in the foreground. It reconnects with `Last-Event-ID` so no event is missed.
- **Source**: services write domain events to an outbox table in the same transaction as the change. A dispatcher publishes them. Events are never faked on the client.
- **Scoping**: the server decides what a connection may receive.
  - Organizer: organization and tournament scopes they are a member of.
  - Referee: their assigned matches.
  - Player: their own matches and tournaments, plus public live matches they open.
- **Event envelope**: `{ id, type, organizationId?, tournamentId?, matchId?, version, payload }`. Types are those in the product spec (MATCH_CREATED … STREAM_STOPPED).
- **Updates**: each event invalidates or patches exactly the Riverpod providers it affects, so one score change rebuilds one scoreboard, not the screen.
- **Push notifications** (FCM/APNs) are separate. They carry a small routing payload (user, workspace, organization, tournament, match) for match calls, schedule changes, results, registrations, payments and announcements. They are not used for live scores.

## 8. Match state machine (to build)

`unscheduled → scheduled → ready → in_progress → completed`, with `delayed`, `rescheduled`, `no_show` and `cancelled` as side states. It replaces today's `MatchStatus` (scheduled/called/live/upcoming/completed) and `MatchLifecycleStatus`. Transitions are allowed only through one server function, which also emits the realtime event. The web frontend's status names need mapping in the same change.

## 9. Flutter app structure (planned)

```text
lib/
  app/            bootstrap, router (one shell route per workspace), theme per workspace
  core/           api client, auth tokens, local db, sync queue, realtime client, connectivity
  sports/         SportEngine interface, pickleball/, badminton/, table_tennis/
  features/
    player/       home, my_paddle, casual_match, tournaments, profile
    organizer/    dashboard, tournaments, matches, schedule, more/...
    referee/      assignments, match_console
    shared/       live_match, scoreboard, workspace_switcher
```

- **State**: Riverpod, with separate providers for auth, workspace, sport, organization, tournament, match, realtime, offline queue, payments and notifications.
- **Libraries**: go_router (navigation), dio (HTTP), drift (local SQLite for cache and sync queue), flutter_secure_storage (tokens), firebase_messaging (push), wakelock_plus (screen on while scoring).
- **Design**: tokens come from the web design system (brief section 4).

## 10. Security

Fixed in step 1:

- Any signed-in user could score any match (`/score` checked only for sign-in).
- Any signed-in user could complete any match with any outcome (`/complete` checked nothing).
- Both now require a match official. Referees can score only matches assigned to them.
- Casual matches are private to their players.
- Casual matches can link only the caller's own profile, so nobody can add matches to someone else's stats.

Still open:

- Mobile needs refresh-token rotation in the request body; today it is cookie only.
- Device and session management.
- Commerce still checks role names; move it to capabilities.
- Stream-key handling once the streaming endpoints exist.

## 11. API still needed by the app

Grouped by the step that needs it:

- **Auth**: phone OTP; body-based refresh; `/me` returning workspaces and capabilities.
- **Player**:
  - profile read and update, including sport profiles
  - "my matches" across casual and tournament matches
  - stats per sport, rankings, rival head-to-head, achievements
- **Organizer**: matches CRUD, schedule and conflicts, draws, check-in, courts, referees and assignment, players, teams, announcements, streaming, analytics.
- **Platform**: realtime stream, push-token registration, notification preferences.

## 12. Build order

| Step | Scope | Status |
|---|---|---|
| 1 | Backend: permissions, match officials, score events for offline sync, sports, casual matches | **Done**. 65 backend tests pass; see section 13 for what was not run. |
| 2 | Flutter foundation: project, theme, router with workspace shells, auth, workspace and sport state, `SportEngine` + pickleball scoring engine with shared test vectors (server side-out enforcement lands here too) | **Mostly done.** Sport engines with shared vectors; phone OTP sign-in end to end (API `POST /auth/otp/send`, `/auth/otp/verify`, `/me/profile`); theme; Player / Organizer / Referee shells with the workspace switcher and remembered place per workspace; offline launch from the cached account. 52 app tests, 85 API tests. **Remaining:** real WhatsApp sending (needs the old backend's template settings), the Android WhatsApp autofill handshake (native code in the old app), server-side serve-order enforcement, and a first run on a device. |
| 3 | Player: home, create match, scoring, history, stats, profile | |
| 4 | Player tournaments: discover, detail, registration, payment, my tournaments, live | |
| 5 | Referee workspace and offline console | |
| 6 | Organizer workspace | **Mobile built against a sample server** (docs/ORGANIZER-TMS.md): tournaments, wizard, registrations, check-in, draws, schedule, courts, live control room, offline-safe scoring console, results, announcements, finance, analytics, roles, activity log. **Remaining:** the NestJS endpoints in ORGANIZER-TMS.md §6, the web PMS, the public scoreboard and streaming. |
| 7 | Realtime and push | |
| 8 | Finance, streaming, add-ons | |
| 9 | Enable further sports | |

Testing runs inside every step, not only at the end.

## 13. Verified and not verified

Verified:

- Schema validates.
- Backend type-checks, builds and lints clean.
- 85 API unit tests pass. They cover rules, permissions, the scoring service (replay, conflict, undo across games, decided matches, result submission) and phone sign-in (wrong codes, attempt limit, expiry, single use, resend limits, account creation, production config guards), against in-memory database fakes.
- 52 app tests pass: scoring engines and shared vectors, the API client (envelope, errors, one shared refresh, offline refresh keeps the session), redirect rules, workspace persistence, and widget tests of sign-in → profile setup → Player home and Player → Organizer → Referee → Player keeping each place (spec section 63).
- Planting bugs in replay, access control, the OTP attempt limit, single use, the first-server rule, the badminton cap, referee isolation and the workspace link guard each makes tests fail.

Not verified:

- Nothing has run against real PostgreSQL. The row lock and unique constraints are untested for real, and there is no migration yet.
- The app has not run on a phone or emulator yet: Android builds need JDK 17+ and the SDK command-line tools. Widget tests render every screen, but no one has looked at them on a device.
- No real WhatsApp message has been sent; development uses the console sender and `OTP_DEV_CODE`.
- The web frontend has not been updated for the new match fields or phone sign-in. It still reads mock data.

## 14. Open decisions

| # | Decision | Blocks |
|---|---|---|
| D1 | ~~Where is the old app?~~ Found; build on NestJS and migrate from `app.skorx.in`. **Still needed: the old backend's repo** for the OTP implementation and the data migration. | Auth, migration |
| D2 | ~~Login method~~ Decided: phone + WhatsApp OTP, same as the old app. | Done |
| D3 | ~~Flutter install~~ Installed at `D:\dev\flutter`. Android builds still need JDK 17+ and SDK command-line tools. | First APK |
| D8 | The badminton store app (`com.skorx.badminton`): retire it in favour of the unified app, or keep publishing it? Parked for now. | Step 9 |
| D9 | ~~Next-game first serve~~ Decided: the standard rule (the team that received first in the previous game serves first; every game starts on server 2). | Done |
| D4 | TMS plans and add-ons: web only, with the app pointing organizers to the website? Store rules limit in-app links for digital purchases. | Step 8 |
| D5 | Scorer role: score any match in the organization (current setting), or only assigned courts or matches? | Step 6 |
| D6 | What is the "Looking" tab in the current app (looking for partners or players)? | Step 3 navigation |
| D7 | Badminton and table tennis: enable at launch or later? | Step 9 |
