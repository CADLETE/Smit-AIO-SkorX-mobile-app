# SkorX module map

One row per business module: what it is for, where its code lives, and the rules that are easy to break. Paths starting `lib/` or `test/` are in this repo. Paths starting `backend/` or `frontend/` are in `smit-dev-skorx-frontend`. Update the row when you change a module.

Status as of 28 Sep 2026. "Sample" means the debug build uses in-memory sample data and the module has no API yet.

## Cross-cutting

| Piece | App | Server | Notes |
|---|---|---|---|
| API client | `lib/core/api/api_client.dart` (+ `api_exception.dart`) | `backend/src/main.ts` (prefix `/api/v1`, global validation pipe, exception filter) | One `ApiException` type in the app. Server errors use codes in `backend/src/common/constants/error-codes.ts`. |
| Auth tokens | `lib/core/auth/token_store.dart` | `backend/src/auth/` | Access JWT (15 min) + refresh token (30 days), rotated and stored hashed in `RefreshToken`. |
| Permissions | `lib/core/app_permissions.dart` | `backend/src/organizations/permissions.ts`, `organization-access.service.ts` | The app hides actions; the server enforces them. |
| Platform admin | web `/admin/*` | `backend/src/commerce/commerce.guards.ts` (`PlatformAdminGuard`) | Admin = email listed in `PLATFORM_ADMIN_EMAILS` **and** verified (`User.emailVerifiedAt`, set with `backend/scripts/verify-admin-email.js`). |
| Connectivity | `lib/core/sync/connectivity.dart` | – | Real reachability probe; gated off under `FLUTTER_TEST`. |
| Sports | `lib/sports/<sport>/` | `backend/src/sports/`, table `Sport` | A sport is data plus an engine. See ARCHITECTURE.md §4. |

## Modules

### Authentication and onboarding
- **Purpose**: phone number + 6-digit WhatsApp OTP sign-in, then profile setup and sport choice.
- **Roles**: guest, any user.
- **App**: `lib/features/auth/` (`auth_controller.dart` picks real or dev auth), `lib/features/onboarding/`.
- **Server**: `backend/src/auth/` (`otp/` holds providers and the challenge logic). Email/password `register`/`login` exist for the web.
- **Tables**: `User`, `OtpChallenge`, `RefreshToken`, `PlayerProfile`.
- **APIs**: `POST /auth/otp/send` (5/min), `POST /auth/otp/verify` (10/min), `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me`, `GET|PATCH /me/profile`.
- **Rules**: production refuses to start with `OTP_PROVIDER=console` or `OTP_DEV_CODE` set. Refresh tokens rotate atomically (one winner per token); replaying a token rotated more than a minute ago revokes every session of that user. OTP: 5 wrong guesses lock a code; 5 sends per number per hour.
- **Tests**: `test/features/onboarding_flow_test.dart`, `test/app/redirect_test.dart`, `backend/src/auth/otp/otp.spec.ts`, `backend/src/profile/profile.spec.ts`, `backend/scripts/e2e-security-audit.js`.
- **Spec**: [ONBOARDING.md](ONBOARDING.md).

### Workspaces
- **Purpose**: one login, separate Player / Organizer / Referee shells chosen from `GET /auth/me` memberships.
- **App**: `lib/features/workspace/`, `lib/features/shell/`, `lib/app/routing/router.dart`.
- **Server**: `backend/src/organizations/`; table `OrganizationMembership` (`OrgRole`).
- **Tests**: `test/features/workspace_test.dart`.

### Casual matches: create, live scoring, result
- **Purpose**: a player creates a singles/doubles match, scores it live (offline or online) and records the result.
- **Roles**: creator scores; the other registered players confirm.
- **App**: `lib/features/casual_match/` — `data/match_setup.dart` (lineup), `scoring_controller.dart`, `ui/`, `live/` and `handover/` (hand scoring to another device).
- **Engine**: `lib/sports/core/` + `lib/sports/pickleball/`; server twin `backend/src/matches/rules/` (`match-rules.ts`, `scoring-engine.ts`).
- **Server**: `backend/src/matches/casual-matches.controller.ts` / `.service.ts`, `casual-lineup.ts` (who may be in a lineup).
- **Tables**: `Match` (`kind = casual`), `MatchParticipant`, `MatchGame`, `ScoreEvent`, `MatchAuditLog`.
- **APIs**: `POST /casual-matches` (30/min), `GET /casual-matches[/:id]`, `GET /casual-matches/players`, `PUT /:id/lineup`, `POST /:id/result`, `POST /:id/cancel`.
- **Rules**: rules are validated server-side (`match-rules.ts`); a player may appear once per match; scores must be reachable under the match's rules.
- **Tests**: `test/features/casual_match_test.dart`, `live_scoring_test.dart`, `test/sports/*`, shared vectors `test/fixtures/scoring_vectors.json`; `backend/src/matches/*.spec.ts`.

### Casual match verification (anti-fraud)
- **Purpose**: a casual match counts toward stats, rating and rankings only after every registered player confirms it.
- **App**: `lib/features/casual_match/verification/`.
- **Server**: `backend/src/matches/verification/` (rules + service), `backend/src/matches/official-matches.ts` (`officialMatchWhere`).
- **Tables**: `Match.verificationStatus`, `MatchParticipant.acceptance`, `MatchVerificationEvent`.
- **APIs**: `GET /casual-matches/requests`, `/summary`, `/:id/verification`, `POST /:id/accept|reject|remind`, `POST /casual-matches/requests/accept-all`.
- **Rules**: every stats reader must use `officialMatchWhere` / `Match.isOfficial`. Result writes go through `CasualVerificationService` only.
- **Tests**: `test/features/casual_verification_test.dart`, `backend/src/matches/verification/casual-verification.rules.spec.ts`, `backend/scripts/e2e-casual-verification.js`.
- **Spec**: [CASUAL-VERIFICATION.md](CASUAL-VERIFICATION.md).

### Offline scoring and sync
- **Purpose**: scoring never stops without internet; the phone syncs whole matches later and the server replays and validates them.
- **App**: `lib/features/casual_match/offline/` (`MatchStore`, `sync_engine.dart`, `ui/`).
- **Server**: `backend/src/matches/sync/` (`casual-sync.controller.ts`, `sync-log.ts` replay), DTO `matches/dto/sync.dto.ts`.
- **Tables**: `MatchSyncBatch`, `MatchSyncEvent` (idempotency by client ids).
- **APIs**: `POST /casual-matches/sync` (30/min), `GET /casual-matches/sync/status`, `GET /casual-matches/sync/metrics` (admin).
- **Rules**: sync is idempotent; replay rejects illegal transitions; results still end in `CasualVerificationService.applyResultInTx`.
- **Tests**: `test/features/offline_sync_test.dart`, `backend/src/matches/sync/sync-log.spec.ts`, `backend/scripts/e2e-offline-sync.js`.
- **Spec**: [OFFLINE-SCORING.md](OFFLINE-SCORING.md).

### Tournament match scoring (referee / organizer console)
- **Purpose**: point-by-point scoring of tournament matches by assigned officials.
- **App**: `lib/features/organizer/scoring/`, `lib/features/organizer/ui/match_console_page.dart`.
- **Server**: `backend/src/matches/matches.controller.ts` / `matches.service.ts`, `scoring-access.ts` (who may score).
- **APIs**: `GET /matches/:id` (public), `POST /matches/:id/score|undo|complete|edit-result`, `GET /tournaments/:id/matches`.
- **Rules**: `scoreVersion` gives optimistic concurrency; `clientEventId` makes a point idempotent. Every write row-locks the match. Cancelled matches cannot be scored, completed or edited; a non-casual match with no tournament cannot be edited by anyone.
- **Tests**: `backend/src/matches/matches.service.spec.ts`, `scoring-access.spec.ts`, `backend/scripts/e2e-security-audit.js`, `test/features/organizer/`.

### Matches feed, match detail, live view
- **App**: `lib/features/matches/` (`data/match_repository.dart`, `match_feed.dart`, `live_feed.dart`; `ui/`).
- **Status**: feed and live view use sample data in debug builds (`sample_universe.dart`).
- **Tests**: `test/features/match_universe_test.dart`, `live_match_test.dart`.

### Player profile, My Paddle, rating
- **Purpose**: player card, stats per category, match history, SkorX Rating (ARC).
- **App**: `lib/features/player/`, `lib/features/profile/`, `lib/features/paddle/`, `lib/features/rating/` (`arc_engine.dart` computes the rating).
- **Server**: `backend/src/profile/`; tables `PlayerProfile`, `SportPlayerProfile`.
- **Rules**: stats count official matches only (`PlayerRecord`). The rating is computed on the device today; the server has no rating endpoint yet.
- **Tests**: `test/features/rating/`, `player_app_test.dart`, `player_extras_test.dart`, `x_code_test.dart`.
- **Spec**: [RATING-SYSTEM.md](RATING-SYSTEM.md), [PLAYER-APP.md](PLAYER-APP.md).

### Explore
- **Purpose**: hub of modules (Tournaments, Scores, Players, Courts, Community, Looking For, then coming-soon modules).
- **App**: `lib/features/explore/` (`explore_modules.dart` is the list).
- **Rules**: new Explore-type features are entries here, never new bottom tabs.
- **Tests**: `test/features/explore_test.dart`.

### Community
- **Purpose**: members, places, groups, connections, events, posts, direct messages, moderation.
- **App**: `lib/features/community/` (`data/api_community_repository.dart`, `sample_community.dart`).
- **Server**: `backend/src/community/` (service split into content, messages, admin; rules in `community.rules.ts`).
- **Tables**: `Community*` (profile, connection, follow, block, place, group, conversation, message, report, verification, event, post, comment).
- **APIs**: `/community/*`, `/me/community*`, `/me/conversations`, `/conversations/:id/*`, admin `/admin/community/*`.
- **Tests**: `test/features/community_test.dart`, `community_content_test.dart`, `backend/src/community/community.spec.ts`, `backend/scripts/community-smoke.mjs`.
- **Spec**: [COMMUNITY.md](COMMUNITY.md).

### Looking For (opportunities)
- **Purpose**: posts such as "need a doubles partner" or "need a referee", with matching, alerts, responses and consent-based contact sharing.
- **App**: `lib/features/looking_for/`.
- **Server**: `backend/src/looking-for/` (parser, matcher, rules, jobs).
- **Tables**: `LookingFor*`, `CommunityRole`.
- **APIs**: `/looking-for/*`, `/me/looking-for/*`.
- **Tests**: `test/features/looking_for_test.dart`, `backend/src/looking-for/looking-for.spec.ts`, `backend/scripts/looking-for-smoke.mjs`.
- **Spec**: [LOOKING-FOR.md](LOOKING-FOR.md).

### Tournaments (player side) and registration
- **App**: `lib/features/tournaments/`.
- **Server**: `backend/src/tournaments/`, `backend/src/registrations/`, `backend/src/payments/` (Razorpay webhook).
- **Tables**: `Tournament`, `Division`, `Team`, `TeamMember`, `Registration`, `RegistrationAuditLog`, `Transaction`, `PaymentWebhookEvent`.
- **APIs**: `GET /tournaments[/:slug]` (`?status=upcoming,live`), `GET /tournaments/:id/divisions`, `POST /registrations`, `GET /registrations/:id`, `GET /registrations?tournamentId=` (organizer staff only), `POST /webhooks/razorpay`.
- **Rules**: payment status is set only by a verified webhook; webhook events are stored by event id for idempotency. The registration list needs `managePlayers`, `manageCheckIn` or `managePayments` in the tournament's organization (it carries players' email and phone).
- **Known gaps** (audit 2026-09-28): entry-fee payment is not wired to Razorpay (registration `orderId`s never match a webhook); capacity counts only paid entries, so the last slot can be oversold; one person can register twice.

### Organizer / TMS
- **Purpose**: create tournaments, registrations, draws, schedule, check-in, match console.
- **App**: `lib/features/organizer/` (`data/draw_engine.dart`, `tms_models.dart`; `ui/`). Web TMS: `frontend/`.
- **Server**: `backend/src/tournaments/` (create/patch, divisions), `backend/src/organizations/`.
- **Status**: the mobile organizer uses sample data in debug builds and an empty repository in release builds; draws and scheduling have no API yet.
- **Tests**: `test/features/organizer/`.
- **Spec**: [ORGANIZER-TMS.md](ORGANIZER-TMS.md).

### Courts and booking
- **App**: `lib/features/courts/`. **Status**: sample only; no booking API yet.

### Notifications
- **App**: `lib/features/notifications/`.
- **Server**: `backend/src/notifications/` (`notification-copy.ts` holds all message text).
- **APIs**: `GET /me/notifications`, `GET /me/notifications/unread-count`, `POST /me/notifications/read`.
- **Tests**: `test/features/notifications_test.dart`, `backend/src/notifications/notification-copy.spec.ts`.
- **Spec**: [NOTIFICATIONS.md](NOTIFICATIONS.md).

### Subscriptions (SkorX Pro) and commerce
- **App**: `lib/features/subscription/` (`billing_repository.dart`, `dev_billing_repository.dart`).
- **Server**: `backend/src/subscriptions/` (player Pro), `backend/src/commerce/` (TMS plans, add-ons, orders, coupons, Razorpay).
- **Tables**: `PlayerSubscription`, `Order`, `OrderItem`, `TmsEntitlement`, `InvoiceSequence`.
- **APIs**: `/subscriptions/plans`, `/me/subscription/*`, `/me/billing/*`, `/commerce/*`.
- **Rules**: prices and GST come from the server catalog; never trust an amount from the client. Payment success is verified with the Razorpay signature server-side.
- **Tests**: `test/features/subscription_test.dart`, `backend/src/commerce/pricing.spec.ts`, `backend/src/subscriptions/player-plans.spec.ts`.
- **Spec**: [SUBSCRIPTIONS.md](SUBSCRIPTIONS.md).

### Engagement
- **Spec**: [ENGAGEMENT.md](ENGAGEMENT.md).

## Not built yet

Live streaming, referee booking, venue reviews, achievements catalog, rankings/leaderboard API, realtime (WebSocket) score push, push notifications (FCM), and server-side rating. Each needs a row here when it starts.
