# Offline Scoring and Automatic Sync

Status: designed and built 27 Sep 2026 (casual matches). Tournament scoring already had its own offline queue; section 2.6 covers how it fits.

> Internet or not, the game never stops.

A casual match can be created, scored and finished with no connection. Every tap is on the phone's disk before the screen changes. When SkorX can be reached again, the phone sends the whole match. The server replays the rallies through its own engine, then puts the result through the same player verification as an online match. The scorer never presses anything.

---

## 1. Assessment of what existed

| Area | Before this change | Gap |
|---|---|---|
| Scoring engine (`lib/sports/core/scoring_engine.dart`) | A pure fold over `RallyWon` / `ServeCorrected` events. Score is never stored; it is replayed. Undo means "replay without the last event". | None. It is already the event log the brief asks for. |
| Match model (`LocalMatch`) | Events carry a UUID and `recordedAt`. Pause, court fixes, end changes, scorer shifts and walkover/retirement are separate fields. | None for scoring. |
| Persistence | `ScoringController` wrote the whole match to SharedPreferences **before** updating the screen, so a crash at 10–8 resumed at 10–8. Finished matches were kept as **one JSON list of up to 200 matches in one key**. | One unreadable byte dropped the whole history, unsynced matches included. The 200 cap could drop matches that were never synced. Every tap rewrote the whole preferences file, history included. |
| Sync (`CasualSyncController`) | `POST /casual-matches` at start (idempotent by `clientRef`). `POST /casual-matches/:id/result` with game totals at the end. | The server never saw the rallies, so it could not check that 11–9 was actually played. Retries only ran when My Paddle opened. There was no connectivity awareness, no backoff, no sync status and no conflict detection. |
| Server engine (`backend/src/matches/rules/scoring-engine.ts`) | Copy of the app engines, and both pass `scoring-vectors.json`. | It existed so offline scores could be replayed, but nothing called it. |
| Player stats, rating, rankings | Read only verified casual matches (`officialMatchWhere`, `Match.isOfficial`). | None. An offline match reaches profiles through the same gate as an online one. |
| Players | Registered players by account id (search needs the network), "me", guests by name. Starred players were cached. | Search failed offline, and recently used players were not remembered. |
| TMS console (`match_console_controller.dart`) | Persisted per-match queue, `clientEventId` + `baseVersion`, conflict screen (use server score or add my taps). | Flushes only while that console is open. |
| Auth | Sign-out did not touch match data. | Pending matches had no owner, so another account could send them. |

## 2. Recommended architecture

```text
USER tap
  ↓
SCORING ENGINE          pure replay of events (unchanged)
  ↓
LOCAL MATCH STORE       one file per match, atomic write (tmp + flush + rename)
  ↓
SYNC LEDGER             per match: owner, server id, signature last acknowledged, phase, attempts
  ↓
CONNECTIVITY MONITOR    online / offline from real API reachability, not the Wi-Fi icon
  ↓ (online, app start, resume, 4 s after a change, 60 s safety tick, Sync now)
SYNC ENGINE             one batch request with every dirty match
  ↓
POST /casual-matches/sync
  ↓
SERVER                  create if new (clientRef) → lock → diff event log → replay → validate
  ↓                     → store events → write games → result → player verification
DATABASE                matches, match_sync_events, match_sync_batches
  ↓
VERIFIED BY PLAYERS     officialMatchWhere
  ↓
PROFILE / STATS / RATING / RANKINGS / ACHIEVEMENTS
```

### 2.1 Local match store (`lib/features/casual_match/offline/match_store.dart`)

- Files live under `<app support dir>/skorx_matches/`: `active.json` plus `played/<id>.json`.
- Every write goes to `<name>.tmp` with `flush: true`, then is renamed over the real file. Rename is atomic on Android and iOS, so a file is always either the old match or the new one, never half of each.
- A file that cannot be read is renamed to `*.corrupt` and reported. It is never deleted, and it never blocks the other matches.
- The first launch after the update moves the old preference keys into files. The keys are removed only after the files are written.
- A match that is not yet synced is never trimmed. Only synced matches beyond the newest 200 are dropped from the phone, and the server keeps them.
- Platforms without a file system (tests, some desktop builds) fall back to preferences with one key per match.

Why not SQLite? The workload is one small, append-mostly document per match that is always read whole, and the engine replays it anyway. Atomic per-match files give the same crash guarantees as a SQLite transaction without adding a native plugin or a schema to migrate. If queries across matches are needed later (for example, a phone that scores hundreds of tournament matches), `drift` is still the planned cache in ARCHITECTURE.md, and the store interface is where it plugs in.

### 2.2 Connectivity monitor (`lib/core/sync/connectivity.dart`)

- The monitor measures **reachability, not radio state**. Wi-Fi without internet, captive portals and a server outage all count as offline.
- **Probe**: `GET /health/live` against the API. Sample builds, which have no server, do a DNS lookup instead, so turning on airplane mode on a test phone behaves like the real thing.
- **Offline**: the monitor re-probes at 5, 10, 20, then every 30 seconds. It probes at once when the app returns to the foreground.
- **Sync results feed the monitor**: a network failure means offline, and any server answer means online.
- States: `unknown`, `online`, `offline`.

### 2.3 Sync ledger and match states

Each local match has a `CasualSync` record, persisted in its own key:

| Field | Purpose |
|---|---|
| `ownerUserId` | Who scored it. It syncs only while that account is signed in. |
| `serverId` | SkorX's match id once created. |
| `syncedSignature` | Fingerprint of the state the server last acknowledged: rules, event count, last event id, outcome, finish time and timeline counts. `dirty` means the current signature is different. |
| `serverVersion` | The server's `syncVersion` at the last acknowledgement. Sent back as `baseVersion`. |
| `phase` | `pending` · `syncing` · `synced` · `failed` · `conflict` |
| `attempts`, `lastAttemptAt`, `nextAttemptAt`, `lastSyncedAt`, `error` | Retry, backoff and the Offline Matches screen. |

The status the user sees is derived from the match's phase plus connectivity:

| Shown | When |
|---|---|
| **Online** | Reachable, and a change is about to be sent |
| **Offline · Saved on this phone** | Not reachable, and changes are waiting |
| **Syncing…** | A request is in flight |
| **✓ Synced** | The server has exactly what the phone has |
| **Sync failed** | The server refused. Retried with backoff (1, 5, 15, 60 minutes) and by **Retry failed sync** |
| **Sync needs attention** | Another device changed this match. Nothing is overwritten until the scorer chooses. |

Local data is never deleted because of a sync outcome.

### 2.4 Event log

The phone's list of events is the log. On the wire, each event is sent with the fields from the brief:

`event_id` (UUID), `match_id` (clientRef), `device_id`, `user_id` (the batch's caller), `recordedAt`, `seq` (local sequence number), `kind` (`rally` | `serve`), `side`, `serverNumber`, `gameNumber`, `scoreBefore`, `scoreAfter`, `serverBefore`, `serverAfter`.

"Game completed", "game started" and "match finished" are consequences of the rallies. The server derives them by replay rather than trusting them as separate facts, so they can never disagree with the points. Pauses, court fixes, end changes, scorer shifts and walkovers travel in `timeline`, which is stored with the match for the match timeline.

Undo is not an event on the phone: the last event is removed. The server records it as a **reversion**. Events the phone no longer has are marked `revertedAt` and never deleted, so the audit trail keeps every tap.

### 2.5 Player identity offline

- **Registered players** keep their account id. Every player seen in a search or a lineup is cached on the phone (`knownPlayersProvider`, up to 300, most recent first). Offline, the picker searches that cache and says so.
- **Starred players** were already cached.
- **New players offline** are added as **guests** by name. That is the existing temporary local identity. A match with a guest is unofficial, so it never counts toward stats.
- **Linking** happens after sync through the existing `PUT /casual-matches/:id/lineup`. The creator swaps the guest for the registered player, and that player must confirm the match. Nothing is ever merged by name.

| Cached, works offline | Needs the network |
|---|---|
| Starred players, players from recent matches and searches, "me" | Searching all SkorX players by name, mobile number or X code |
| Sports, categories, rules, last setup | Match requests from other players, confirmation state |
| The active match and every match not yet synced | Other players' profiles and stats |
| Scoring, undo, pause, court fixes, handover on the same phone | Handover to another phone, live streaming |

### 2.6 Tournament matches

Tournament scoring already works offline through the TMS console. Its queue is saved per match, every write carries `clientEventId` and `baseVersion`, and `SCORE_CONFLICT` opens a screen where the official chooses. Several scorer devices at a venue each queue their own matches and flush independently. Standings, brackets and results update on the server as each confirmed result lands, because those are derived from `Match` rows, not from the devices.

Still to do: the console flushes only while its screen is open. The next step is to register each console queue with the same sync engine, so a venue's queues also drain on app start, on resume and when the connection returns. The server side needs no change.

## 3. Database changes

Migration `20260927182148_offline_sync`:

```prisma
model Match {
  // …
  syncVersion      Int       @default(0)   // bumped by every applied sync
  scorerDeviceId   String?                 // last device that synced events
  lastSyncedAt     DateTime?
  syncTimeline     Json?                   // pauses, court fixes, end changes, scorers
  syncEvents       MatchSyncEvent[]
  syncBatches      MatchSyncBatch[]
}

/// Rallies and serve corrections as scored on the phone. Never deleted:
/// an undo marks the event reverted.
model MatchSyncEvent {
  id            String    @id @default(cuid())
  matchId       String
  clientEventId String                 // idempotency key
  position      Int?                   // index in the active log; null when reverted
  deviceId      String?
  userId        String?
  kind          String                 // rally | serve
  side          MatchSideKey
  serverNumber  Int?
  gameNumber    Int                    // server-computed
  scoreBefore   Json                   // server-computed [a, b]
  scoreAfter    Json
  serverBefore  Json
  serverAfter   Json
  clientClaim   Json?                  // what the phone said, for audit
  recordedAt    DateTime               // on the phone
  receivedAt    DateTime  @default(now())
  revertedAt    DateTime?
  revertReason  String?                // undo | conflict_overwrite
  @@unique([matchId, clientEventId])
  @@index([matchId, position])
}

/// One row per match per sync attempt that reached the server: analytics
/// and admin debugging.
model MatchSyncBatch {
  id, matchId?, userId, deviceId?, clientRef,
  status        String                 // SYNCED | ALREADY_PROCESSED | CONFLICT | REJECTED
  errorCode     String?
  received, accepted, duplicates, reverted Int
  durationMs    Int
  offlineMs     Int?                   // oldest new event's age on arrival
  anomalies     Json?                  // e.g. rallies logged implausibly fast
  client        Json?                  // app version, pending count, attempts
  createdAt     DateTime @default(now())
}
```

## 4. Sync flow

1. **Trigger**: app start, app resume, connectivity regained, 4 s after any change, a 60 s tick while anything is dirty, or **Sync now**.
2. **Select**: matches owned by the signed-in account whose signature differs from `syncedSignature`, or that were never created. Matches in `conflict` wait for the scorer. Matches in `failed` wait for their backoff.
3. **Upload**: one `POST /casual-matches/sync` with up to 10 matches. Larger backlogs go in further batches in the same run.
4. **Server, per match, in its own transaction** (one bad match never blocks the others):
   1. Create it if the `clientRef` is new, through the same create path as online: lineup validation, account checks and the duplicate check.
   2. Row-lock it and check that the caller is its creator or a player in it, and that it is not cancelled.
   3. Validate the events: unique UUIDs, known kinds, at most 1,500, times after the start and not in the future, in order.
   4. Replay them through the server engine under the match's rules. An event after the match is decided is rejected.
   5. Diff against the stored log (section 6): new, duplicate, reverted or conflict.
   6. Store new events with server-computed scores, mark removed ones reverted, and write `match_games` and the current server.
   7. Result, if present: it must equal the replayed score. It then goes through `CasualVerificationService.applyResultInTx`, which re-sends to players only when something changed.
   8. Bump `syncVersion` and write a `match_sync_batches` row.
5. **Acknowledge**: the phone stores `serverId`, `serverVersion` and the signature it sent. It marks the match `synced` only if nothing changed on the phone while the request was in flight. Otherwise the match stays dirty and goes out again in 4 s.
6. **Derived data**: stats, rating, rankings, achievements and history read verified matches only, exactly as for online matches. Once every registered player confirms, the offline match counts everywhere.

## 5. API

| Endpoint | Purpose |
|---|---|
| `POST /casual-matches/sync` | Batch upload of 1–10 matches: metadata, the full event log, timeline and optional result. Idempotent by content: resending the same body changes nothing and returns `ALREADY_PROCESSED`. Throttled at 30 per minute. |
| `GET /casual-matches/sync/status?refs=a,b` | The server's view of the phone's matches: id, `syncVersion`, active event count, result state and verification. Used to reconcile after a reinstall. |
| `GET /casual-matches/sync/metrics?days=7` | Platform admins only: sync rate, failures by code, duplicates prevented, conflicts, average duration and offline age, plus the latest failures. |

A separate `/retry` endpoint is not needed: a retry is the same idempotent POST.

The request:

```json
{
  "deviceId": "7c1…",
  "client": { "appVersion": "1.0.0+1", "pending": 3, "attempts": 2 },
  "matches": [{
    "clientRef": "b3e1…",
    "code": "SKX-PCMD-260927-7K3QX",
    "baseVersion": 4,
    "force": false,
    "match": { "sportId": "pickleball", "category": "mens_doubles", "sideA": […], "sideB": […],
               "rules": {…}, "startedAt": "…", "firstServer": "a", "locationName": "…" },
    "events": [{ "id": "…", "seq": 1, "kind": "rally", "side": "a", "recordedAt": "…",
                 "gameNumber": 1, "scoreBefore": [0,0], "scoreAfter": [1,0],
                 "serverBefore": {"side":"a","serverNumber":2}, "serverAfter": {…} }],
    "timeline": { "endChanges": {"1": true}, "adjustments": […], "scorers": […], "pausedAt": null },
    "result": { "outcome": "completed", "sideAScores": [11, 11], "sideBScores": [8, 9], "completedAt": "…" }
  }]
}
```

The response has one entry per match, in request order:

```json
{ "results": [{ "clientRef": "b3e1…", "status": "SYNCED", "matchId": "cm…", "syncVersion": 5,
                "accepted": 12, "duplicates": 30, "reverted": 1,
                "match": { …same shape as GET /casual-matches/:id… } }] }
```

`status` is one of `SYNCED`, `ALREADY_PROCESSED`, `CONFLICT` (with `server: { events, games, deviceId }`) or `REJECTED` (with `error: { code, message }`). The HTTP status is 200 whenever the batch was read, because each match succeeds or fails on its own.

## 6. Conflict resolution

The phone that creates a match is its scorer. Another device can score it only after a handover or from a second phone of a player in it.

Let `S` be the server's active log, `U` the upload, and `k` the first index where they differ:

| Case | Decision |
|---|---|
| `U == S` | `ALREADY_PROCESSED`. This is a retry. |
| `S` is a prefix of `U` | Fast-forward: append `U[k..]`. A retry after a lost acknowledgement also lands here. |
| They differ at `k`, and every event in `S[k..]` came from the uploading device | That device undid those events. Mark them reverted with reason `undo` and append the rest. |
| They differ at `k`, and `S[k..]` contains another device's events, but `baseVersion == syncVersion` | The uploader had already seen those events and removed them, so this is also an undo. |
| Anything else | `CONFLICT`. Nothing is written, and the server's log and games are returned. |

On the phone, a conflict shows **Match sync needs attention** with both scores side by side:

- **Keep this phone's score** resends with `force: true`. The server marks the other events reverted with reason `conflict_overwrite`. They stay in the table, and the batch row records who did it. Because the result still needs every player's confirmation, the other scorer can reject it.
- **Use SkorX's score** replaces the phone's events with the server's. The phone's version is saved first as a `*.superseded.json` file.

Rule changes after events exist are allowed only for the creator, and only before the result is verified. This matches the app, which restarts the scoring when rules change.

## 7. Security

Offline data is untrusted input:

- **Who**: only the match's creator or a player in it may sync it. The lineup goes through the same validation as online creation. Registered players are checked to exist, and the caller can only put their own account in as "me".
- **What**: events are replayed on the server. Scores, game numbers and servers are recomputed, and the phone's claims are kept only for audit. The result must equal the replay, so 11–0 cannot be sent for a match that was 7–11.
- **When**: event times must fall between the start (with 10 minutes of tolerance) and the moment of receipt (plus 5 minutes of clock skew), in order.
- **Volume**: at most 10 matches per request, 1,500 events per match, and 30 requests per minute per user.
- **Anomalies**: rallies logged faster than 1.5 s apart on average, or a whole match inside 60 s, are recorded in `anomalies` for review. They are not rejected, so a real fast game is never lost.
- **Counting**: nothing from sync counts until every registered player confirms. That verification gate is the real defence against inflated stats, ratings and rankings, and it is identical online and offline.
- **Audit**: events are never deleted, and every sync attempt is a batch row with its device id.

## 8. UI and UX

- **Scoring header chip**: replaces the static `SAVED` chip. It shows `ONLINE`, `OFFLINE · SAVED`, `SYNCING`, `✓ SYNCED` or `NEEDS ATTENTION`. Tapping it opens a short sheet that explains the state and has **Sync now**. No banners are shown over the court.
- **Snackbars** are short and float, and only one shows at a time:
  - "You're offline. Don't worry: scoring continues and your match syncs automatically when you're back online." (once per match)
  - "Back online · Syncing match…"
  - "✓ Match synced"
- **My Paddle › Offline matches**: a row that shows "3 matches waiting to sync" or "All matches synced". It opens **Offline Matches** (`/player/offline-matches`), which has:
  - a status summary with **Sync now** and **Retry failed sync**
  - one card per match: code, players, games, finished time and status
  - conflict cards with **Resolve**
  - a note about matches from another account on this phone
  - a collapsible **Sync diagnostics** panel with the client analytics from section 10 and the last error
- **Player picker**: offline, the search box searches players saved on the phone and says so.

## 9. Implementation plan

| # | Step | Where |
|---|---|---|
| 1 | Schema and migration | `backend/prisma` |
| 2 | Pure log diff and validation, with unit tests | `backend/src/matches/sync/sync-log.ts` |
| 3 | `CasualSyncService`, controller, admin metrics | `backend/src/matches/sync/` |
| 4 | End-to-end script against a running API | `backend/scripts/e2e-offline-sync.js` |
| 5 | Local match store with migration from preferences | `lib/features/casual_match/offline/match_store.dart` |
| 6 | Connectivity monitor | `lib/core/sync/connectivity.dart` |
| 7 | Sync engine: ledger, triggers, backoff, batch upload, conflict resolution | `verification_controller.dart` (`CasualSyncController`), `offline/sync_upload.dart` |
| 8 | Repository `sync()`: API and sample; the sample goes offline with the phone | `verification_repository.dart` |
| 9 | UI: header chip, snackbars, Offline Matches page, My Paddle row | `offline/ui/` |
| 10 | Offline player cache in the picker | `data/match_setup.dart` |
| 11 | Tests: store, signature, upload, engine states, widget chip | `test/features/offline_sync_test.dart` |

Deliberately not built yet:

- OS background sync while the app is closed (`workmanager`). Sync runs on the next launch or resume instead, which the brief allows.
- Moving the TMS console queue into the shared engine (section 2.6).
- A UI for linking a guest to an account. The API exists.

## 10. Test plan

**Automated**:
- Server unit tests for the log diff and validation.
- Server end-to-end script (`scripts/e2e-offline-sync.js`) for rows 1, 5, 13, 16, 21 and 25 below.
- App tests (`test/features/offline_sync_test.dart`) for the store, signatures, upload building, engine phases, conflict resolution and retention.

**Manual on device**: airplane mode on the OnePlus.

| # | Case | Expected |
|---|---|---|
| 1 | Internet drops mid-match | Chip turns `OFFLINE · SAVED` and a snackbar shows once. Scoring is unaffected. On reconnect: syncing, then synced. |
| 2 | Offline before creating the match | Setup works with starred and cached players and guests. The match is created on the server at the first sync. |
| 3 | Offline after the match finishes | The result is shown with "Waiting for internet". It syncs on reconnect, and players are asked to confirm then. |
| 4 | Internet returns mid-match | Sync starts within about 5 s. Points scored meanwhile follow within 4 s of the last tap. |
| 5 | Flapping connection | No duplicate points: resends are no-ops by UUID and the batch is `ALREADY_PROCESSED`. At most one request is in flight. |
| 6 | Force-close during scoring | Reopens on the same score. The atomic file is either the old or the new state. |
| 7 | Phone restarts mid-match | Same as case 6. Files are flushed to disk. |
| 8 | Battery dies mid-tap | The last completed write survives, and a torn `.tmp` is ignored. |
| 9 | 1-game match | Result validated against the replay. |
| 10 | Best of 3 going to 3 | Game transitions are derived on the server and all three games are stored. |
| 11 | Several offline matches | One batch carries them all, and each gets its own result. |
| 12 | Multiple devices, different matches | Independent: separate `clientRef`s and locks. |
| 13 | Duplicate sync request | `ALREADY_PROCESSED`, `duplicates = n`, and nothing else changes. |
| 14 | Server timeout | Treated as offline and retried. The server is idempotent if the first request did land. |
| 15 | Server 5xx | Phase `failed`, retried with backoff and by **Retry failed sync**. |
| 16 | Invalid event (after the match was decided, or a result that disagrees) | `REJECTED` with a reason. The local match is kept and shown as failed. |
| 17 | Corrupted local file | Quarantined as `.corrupt`. The other matches load. |
| 18 | Player not cached | Search says offline. The scorer adds them as a guest. |
| 19 | New player created offline | Guest. It can be linked later through a lineup change, and the player confirms. |
| 20 | Tournament match offline | The console queue persists and flushes on reconnect (existing behaviour). |
| 21 | Same match on two devices | Divergent logs return `CONFLICT`, "needs attention" shows, and the scorer chooses. Nothing is lost silently. |
| 22 | Log out while offline | Matches stay on the phone and sync after signing back in. |
| 23 | Different account signs in | Only that account's matches sync. The page notes matches from another account. |
| 24 | App updated with pending matches | Preferences migrate to files on first launch. Old matches without a ledger record stay unsent, as before. |
| 25 | Large backlog (50+) | Sent 10 per request in one run. Only synced matches are trimmed after 200. |
