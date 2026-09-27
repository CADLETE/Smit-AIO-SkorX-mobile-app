# Casual Match Verification

Status: built 27 Sep 2026 (API + app). Applies to **casual matches only**; tournament matches keep the organizer's draw → referee/scorer → result flow and never enter it.

## The rule

A casual match counts toward statistics, win/loss, SkorX Rating, rankings, leaderboards and achievements **only after every registered player in it has confirmed the result**. The creator does not approve their own match. Guests (no SkorX account) can play, but can never confirm, so a match with a guest never counts.

The one definition of "counts" is `officialMatchWhere` / `isOfficialMatch` in `backend/src/matches/official-matches.ts`:

```text
tournament  → counts once completed
casual      → counts only when completed AND verificationStatus = verified
```

Every stats, rating, ranking, leaderboard or achievement query must filter with it. In the app the same gate is `Match.isOfficial`, applied by `PlayerRecord` (the only place the record is worked out).

## Lifecycle

| Status (server) | Lifecycle shown | Meaning | Counts |
|---|---|---|---|
| — | Draft | Scored on the phone, not yet sent (offline) | No |
| `pending` | Pending confirmation | Created; players have not all said they are in | No |
| `pending` | In progress | Everyone is in; no result yet | No |
| `pending` | Completed / Awaiting confirmation | Result in; waiting for players to confirm it | No |
| `verified` | Verified | Every registered player confirmed the current result | **Yes** |
| `disputed` | Disputed | A player says a detail is wrong (score, team, player, other) | No |
| `rejected` | Rejected | A player says it did not happen (did not play, not present, cancelled) | No |
| `cancelled` | Cancelled | The creator called it off before verification | No |
| `pending` | Expired | Nobody answered within 14 days | No |
| `pending` | Unofficial | Has a guest; can never be verified | No |

The server computes status and lifecycle (`matches/verification/casual-verification.rules.ts`). The client never sends a status; it sends answers.

## Rounds (why a stale screen cannot confirm the wrong score)

`Match.verificationRound` goes up whenever what the players confirm changes: the result is submitted, the score or line-up is edited, or a correction is proposed. A confirmation only counts for the round it was given in, and every accept/reject carries the round the player's screen showed. Answering an older round returns `409 STALE_CONFIRMATION` and the app reloads the new details. Each new round restarts the 14-day window.

Accepting before the result only says "I'm in" (joined). When the result arrives the joined players are asked once more to confirm the score.

## Flows

**Creator:** Create match → pick players (registered SkorX players by search or X code; guests allowed but flagged) → score on the phone → finish. The app sends the match to SkorX when play starts (so players are asked at once) and the result when it ends. Offline, both wait and retry; the phone's own id (`clientRef`) makes retries return the same match.

**Other players:** push/in-app notification → Match requests tab (or the notification) → review page → **Accept match** → confirm dialog → done. Or **Reject / Dispute** → pick a reason (required) and add details (optional).

**System:** the last confirmation verifies the match automatically and notifies every player.

## Score edits

- Before verification: a new score replaces the old one, is logged in `match_audit_log`, and everyone confirms again.
- After verification: a new score becomes a **correction**. The verified score keeps counting; the correction applies only when every other player accepts it. One player declining keeps the verified score.
- A verified match cannot be cancelled and keeps its players. A player disputing a verified match flags it for review (`flaggedAt`) but cannot erase it alone.
- `POST /matches/:id/complete` and `/edit-result` route casual matches through the same logic, so there is no side door.

## Data model (Prisma, migration `20260927180000_casual_match_verification`)

- `Match`: `verificationStatus`, `verificationRound`, `confirmBy`, `resultSubmittedAt`, `verifiedAt`, `cancelledAt`, `pendingCorrection`, `flaggedAt`, `clientRef` (unique per creator). Null status on tournament matches.
- `MatchParticipant`: `userId` (unique per match), `isCreator`, `acceptance` (`pending|accepted|rejected|guest`), `acceptedRound`, `joinedAt`, `respondedAt`, `rejectionReason`, `rejectionNote`.
- `MatchVerificationEvent`: append-only audit trail — actor, action (created, invited, joined, accepted, rejected, disputed, result_submitted, result_changed, lineup_changed, correction_*, verified, cancelled, reminded, flagged), round, reason, note, metadata (before/after scores, IP, user agent, `x-device-id`, result signals). Indexed by `(actorUserId, action, createdAt)` for later anti-fraud jobs.

## API (`/api/v1/casual-matches`)

| Endpoint | Purpose |
|---|---|
| `GET /players?q=` | Registered players by name or a whole mobile number (numbers never returned; partial numbers match nothing) |
| `POST /` | Create (`sideA/sideB` of `{isMe}` / `{userId}` / `{displayName}`, `clientRef`) |
| `GET /`, `?scope=verified\|pending` | My casual matches |
| `GET /:id`, `GET /:id/verification` | One match with its verification block |
| `GET /requests` | Requests waiting for me |
| `GET /summary` | Verified / pending / disputed / requests counts |
| `POST /:id/accept {round}` | Confirm |
| `POST /:id/reject {round, reason, note?}` | Reject or dispute |
| `POST /requests/accept-all {items:[{matchId, round}]}` | Each accepted independently |
| `POST /:id/result {sideAScores, sideBScores, outcome?, winnerSide?}` | Submit or change the result |
| `PUT /:id/lineup` | Creator replaces players before verification (everyone asked again) |
| `POST /:id/cancel` | Creator cancels before verification |
| `POST /:id/remind` | Creator nudges players who have not answered; once per 24 h |

The brief's `POST /matches/casual`, `GET /matches/pending` and `POST /matches/{id}/score` map to `POST /casual-matches`, `GET /casual-matches/requests` and `POST /casual-matches/:id/result` (the existing `/matches/:id/score` stays the per-point live scoring path).

## Fake-player protection

- Players who can confirm are registered accounts picked by the server-side search; their names come from the account, never the client.
- A guest makes the match unofficial forever (it can still be scored and shown).
- The same account cannot appear twice; deleted accounts cannot be added.
- An unfinished match with the same registered players (any creator, last 3 h) is refused as a duplicate.
- Remaining risk: one person controlling two real accounts. The event log and result signals (`fast`, `shutout`, `sameLineupLast7Days`) are stored for a later anti-fraud job; nothing blocks on them yet.

## Notifications

`match_request.added | result | correction | reminder` ask for action (Match requests tab, high priority, one unread per match — older ones are superseded). `match.verified | rejected | disputed | correction_applied | correction_rejected | flagged | removed | cancelled` report back. Copy: `backend/src/notifications/notification-copy.ts`; catalogue: `docs/NOTIFICATIONS.md`.

## App

| Piece | Where |
|---|---|
| Models, lifecycle | `lib/features/casual_match/verification/verification.dart` |
| API + debug stand-in (sample players answer ~20 s apart; three seeded requests) | `verification_repository.dart` |
| Providers, offline-safe sync of phone-scored matches | `verification_controller.dart` |
| Review page `/player/match-requests/:id` | `ui/match_request_page.dart` |
| Match requests tab (`/player/notifications?tab=requests`), Accept all | `ui/match_requests_list.dart` |
| Result-screen panel, match-detail banner, My Paddle pending section | `ui/local_verification_panel.dart`, `matches/ui/match_detail_page.dart`, `ui/pending_matches_section.dart` |
| Stats gate | `Match.isOfficial`, `PlayerRecord`, `playerRecordProvider`, `MatchHistory` |

Casual matches scored before this shipped were never confirmed, so they no longer count in the phone's record.

## Tests

- API unit: `casual-verification.rules.spec.ts`, `casual-lineup.spec.ts`, `matches.service.spec.ts` (casual results go through verification; tournament results never do), `notification-copy.spec.ts`.
- API end-to-end against a real database: `backend/scripts/e2e-casual-verification.js` (75 checks covering the brief's edge cases).
- App: `test/features/casual_verification_test.dart`.

## Not built yet

- Push delivery (FCM) — notifications are in-app rows today; push will deliver the same rows.
- Scheduled reminders (only the creator's manual nudge, once a day).
- Line-up editing UI in the app (the API supports it); date editing.
- A scoring handover to another phone does not carry the SkorX match id, so the new scorer's phone cannot submit the result.
- Server-side rating, rankings and achievements engines; they must read `officialMatchWhere`.
