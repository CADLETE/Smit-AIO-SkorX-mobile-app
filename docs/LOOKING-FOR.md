# Looking For: analysis and proposed architecture

Status as of 27 Sep 2026: **phases 1–3 built** (see §12). Phases 4–7 are not built. This document started as the "inspect first" step of the Looking For brief: what already exists in SkorX, what the feature reuses, what it adds, and the build order.

Decisions (27 Sep 2026): a separate dev PostgreSQL on `D:\dev` for real-data testing; in-app chat plus consent-based phone sharing after acceptance; the admin panel lives on the web at `/admin/looking-for`; this pass covers phases 1–3.

Looking For is the pickleball community's requirement network. Anyone can post what they need (players, a partner, a referee, a scorer, a court, a sponsor), the people it suits hear about it, and they respond through SkorX without exposing phone numbers.

---

## 1. Existing architecture

| Piece | Where | State that matters here |
|---|---|---|
| App | `SKORX -SMIT -DEV - APP` (Flutter, Riverpod 3, go_router, dio) | Player, Organizer and Referee workspaces. Every server feature is a repository interface with an API implementation and a sample stand-in, selected by `useRealApi` (`lib/features/auth/auth_controller.dart`). Debug builds use dev sign-in and sample data. |
| API | `smit-dev-skorx-frontend/backend` (NestJS 12, Prisma 6, PostgreSQL) | Module shape: DTO → service → mapper → controller. Global `JwtAuthGuard` (opt out with `@Public()`), `ValidationPipe`, `{ success, data, meta }` envelope, `DomainException` + `ErrorCode`. **No migration has ever run against a database.** Unit tests run against in-memory Prisma fakes. |
| Web + TMS | `smit-dev-skorx-frontend/frontend` (Next.js) | Organizer dashboard under `/dashboard/*`. Still reads mock data; not wired to the API. No platform-admin area. |
| Old player app | `Skorx_pickaball_Latest` | Had `/partner-suggestion` (the "Looking" tab). Its backend source is not on this machine. |

The closest precedent is **SkorX Pro** (`docs/SUBSCRIPTIONS.md`): a real NestJS module with its own models and tests, and an app feature with an API repository plus a Test Mode stand-in. Looking For follows the same pattern.

## 2. What can be reused

### App

| Need | Reuse |
|---|---|
| Entry point | Explore hub already lists **Looking For** and **Community** as coming-soon modules (`lib/features/explore/explore_modules.dart`). Switching them on is the intended path. |
| Design | `lib/design/` (`SxColors`, `SxButton`, `SxTabs`, `SxSection`, `SxSheet`, `EmptyBlock`, `Skeleton`, `SxAvatar`, `StateMark`), `lib/shared/ui/components.dart`. Status words follow the StateMark rules (§3.4 of PLAYER-APP.md). |
| Paged feeds | `matchFeedProvider` pattern (`AsyncNotifierProvider.autoDispose.family` keyed by a query, loaded a page at a time). |
| Filter UI | `lib/features/matches/ui/filter_widgets.dart`, `match_filter_sheet.dart`, removable filter chips. |
| Player facts on responses | `PlayerSummary` (level, city), `showPlayerQuickView`, `/player/players/:id`. |
| Notifications | `AppNotification` + notification centre (`lib/features/notifications/`), which already routes on tap. Needs a new `lookingFor` kind. |
| Sharing | `share_plus` (already a dependency). |
| Organisations and tournaments to post as | `workspaceProvider` / memberships from `GET /auth/me`, organizer tournaments. |

### API

| Need | Reuse |
|---|---|
| Identity | `User` + `PlayerProfile` (+ `SportPlayerProfile.skillLevel`). No second user system. |
| Posting on behalf of an organisation or tournament | `OrganizationMembership` + `OrganizationAccessService.assertCapability` / `assertTournamentCapability`. |
| Links to entities | `Tournament`, `Venue`, `Club`, `Organization`, `PlayerProfile`, `Referee`. |
| In-app notifications | `Notification` table (exists, no endpoints yet). |
| Admin | `PlatformAdminGuard` (`PLATFORM_ADMIN_EMAILS`) from commerce. |
| Audit | `AuditLog` for moderation actions. |
| Rate limits | `@Throttle` on create/respond/report. |

## 3. What does not exist yet (and the brief assumes)

| The brief assumes | Reality | Proposed handling |
|---|---|---|
| Real backend data end to end | No migration has run; the local Postgres on 5432 has unknown credentials; the API is not running. | Build the module for real and test it with the in-memory fakes like every other module. To verify against a database, run a separate Postgres on `D:\dev` (port 5433) and apply the first migration. **Decision needed.** |
| Chat | No chat or messaging anywhere. | A small **conversation** model scoped to accepted responses (one thread per accepted response), fetched by polling until realtime (build step 7) exists. **Decision needed.** |
| Push notifications | No FCM/APNs; push is build step 7. | Write every notification to `Notification` (in-app, works now) and to a delivery outbox that the push sender drains once FCM is set up. |
| Location radius (5/10/25/50 km) | No coordinates anywhere; `Venue` and `PlayerProfile` store a city only. No location package in the app. | Add `lat`/`lng` to posts and an alert "home" point per user. Filter by bounding box on indexed columns, then exact distance in the service. No PostGIS dependency. City match is the fallback when there is no point. |
| Community entities (teams, academies, grounds, scorers, commentators, streamers) | `Team` belongs to a tournament division (it is an entry, not a standing team). `Club` has no members or owner. No academy, scorer, commentator or streamer profiles. `Referee` is an organisation's staff row. | A `CommunityRole` table on the person (referee, scorer, commentator, streamer, camera, coach, volunteer), set by the user. Standing teams, clubs with owners and academies belong to the **Community** module, a separate build. Until then, Post As offers **Myself**, **my organisations** and **their tournaments** only. |
| Admin panel in "admin/TMS" | The TMS web is organisation-scoped and mock-only; there is no platform-admin UI. | Admin API first (it is the real control). UI: a `/admin/looking-for` area on the web, or an in-app admin screen for platform admins. **Decision needed.** |
| Deep links on web, iOS and Android | No App Links / Universal Links setup; the web has no Looking For page. | App route `/player/looking-for/:id`. Web page `skorx.in/looking-for/:id` (public summary + "Open in app"). Android App Links need `assetlinks.json` on the domain; iOS needs `apple-app-site-association`. |
| Scheduled jobs (expiry, digests) | No scheduler dependency. | Expiry is enforced on read (`expiresAt > now` in every active query) so it is always correct; a status sweep and the daily digest run from `@nestjs/schedule`. |

## 4. Conflicts with existing features

- **Two sessions are editing these repos.** Both have large uncommitted changes (SkorX Pro in the API; many app files). Looking For touches shared files only additively: `schema.prisma` (new models, new relation fields on `User`), `app.module.ts` (one import), `router.dart` (new routes), `explore_modules.dart` (move two modules to active), `notifications.dart` (one enum value).
- **"Players" in Explore** already offers "Find partners". Looking For is posted demand; Players is a directory. The Players view gets a "Post a Looking For" link rather than a second partner finder.
- **Match invites** (old app, "Keep") are a consent flow for linking players to a match. A filled "Looking for players" post can create the casual match and invite accepted responders later; not in v1.
- **Ratings.** The brief shows "3.2 SkorX Rating". The app shows the ARC level and SkorX Points. Responses show whatever the player profile has (self-declared skill level, ARC level, matches played), and never rank responders.
- **Notification kinds** are an enum used by the notification centre and its tests; adding `lookingFor` needs the icon/grouping mapping updated.

## 5. Data model (Prisma)

Names follow the brief; Prisma models map to snake_case tables.

```prisma
enum LookingForStatus   { open  responses_received  partially_filled  filled  expired  cancelled  hidden  removed }
enum LookingForPostAs   { self  organization  tournament }
enum LookingForVisibility { public  followers  organization }
enum LfResponseStatus   { pending  accepted  declined  withdrawn }
enum LfReportStatus     { open  actioned  dismissed }
enum LfAlertMode        { instant  daily_digest  off }

model LookingForCategory {        // admin-managed; seeded from reference data
  id          String  @id          // "player", "referee", ...
  label       String
  group       String               // PLAYER, TEAM, MATCH, TOURNAMENT, VENUE, OFFICIALS, MEDIA, COMMUNITY
  icon        String
  enabled     Boolean @default(true)
  sortOrder   Int     @default(0)
  fields      Json                 // which form fields show, which are required
  subcategories LookingForSubcategory[]
}

model LookingForSubcategory { id String @id; categoryId String; label String; enabled Boolean; sortOrder Int }

model LookingForPost {
  id, creatorId (User), postAs, organizationId?, tournamentId?,
  categoryId, subcategoryId?, sportId (default "pickleball"),
  title, description,
  placeName, city, lat?, lng?, venueId?,
  startsAt?, endsAt?, durationMinutes?,
  quantityRequired Int @default(1), quantityFilled Int @default(0),
  skillMin?, skillMax?, gender?, ageGroup?,
  paid Boolean, budgetAmount?, budgetUnit?,   // per player / per hour / total
  details Json,                              // category-specific fields (courts, matches, indoor/outdoor ...)
  visibility, status, expiresAt,
  viewCount, responseCount,
  createdAt, updatedAt
  @@index([status, expiresAt])
  @@index([categoryId, status, expiresAt])
  @@index([city, status])
  @@index([lat, lng])
  @@index([creatorId])
}

model LookingForResponse { id, postId, userId, message, availabilityConfirmed Boolean, status, decidedAt?, createdAt, updatedAt  @@unique([postId, userId]) }
model LookingForConversation { id, responseId @unique, createdAt }        // opened on accept
model LookingForMessage { id, conversationId, senderId, body, createdAt, readAt?  @@index([conversationId, createdAt]) }
model LookingForContactShare { id, responseId, fromUserId, kind (phone|whatsapp), createdAt }  // consent record
model LookingForMatch  { id, postId, userId, score Int, reasons Json, notificationStatus, notifiedAt?  @@unique([postId, userId]) }
model LookingForSaved  { postId, userId, createdAt  @@id([postId, userId]) }
model LookingForReport { id, postId, reporterId, reason, description?, status, reviewedById?, action?, createdAt  @@unique([postId, reporterId]) }
model LookingForAlertPreference { userId @id, mode LfAlertMode, categories String[], radiusKm Int?, lat?, lng?, city?, quietHours Json?, dailyCap Int @default(5) }
model LookingForEvent  { id, postId?, userId?, type, metadata Json?, createdAt  @@index([type, createdAt]) }   // analytics
model CommunityRole    { userId, role, level?, bio?, createdAt  @@id([userId, role]) }
model LookingForSanction { userId @id, postingSuspendedUntil?, warnings Int, note? }
```

`NotificationDelivery` (outbox for push: `notificationId`, `channel`, `status`, `attempts`) is added once, for the whole app, not just Looking For.

## 6. API

All under `/api/v1`. Lists are cursor-paged (`cursor`, `limit`, max 50).

| Method | Path | Auth | Purpose |
|---|---|---|---|
| GET | `/looking-for/categories` | Public | Enabled categories, subcategories and their form fields. |
| GET | `/looking-for?tab=for_you\|nearby\|latest&category&sub&city&lat&lng&radiusKm&from&to&skill&gender&paid&tournamentId&clubId&postedBy&sort=new\|expiring&q&cursor` | Public (signed-in gets For You) | Active feed. Never returns expired, cancelled, hidden or removed posts. |
| GET | `/looking-for/:id` | Public (summary) / signed in (full) | Detail. Records a view event. |
| POST | `/looking-for/parse` | Signed in | Natural-language text → draft fields (rule-based, no LLM). |
| POST | `/looking-for` | Signed in, not suspended, throttled | Create. Validates fields per category; checks `postAs` permission; runs matching. Returns the post and "N people may match". |
| PATCH | `/looking-for/:id` | Owner | Edit while open. |
| POST | `/looking-for/:id/cancel` · `/fill` · `/reopen` | Owner | Status changes. |
| GET | `/looking-for/:id/matches` | Owner | Count and factual reasons (no names until they respond). |
| POST | `/looking-for/:id/responses` | Signed in, not owner | I'm Interested. One per person; can withdraw. |
| GET | `/looking-for/:id/responses` | Owner | Responders with factual profile data. |
| POST | `/looking-for/responses/:rid/accept` · `/decline` | Owner | Accept updates `quantityFilled` and status in one transaction; opens a conversation. |
| POST | `/looking-for/responses/:rid/withdraw` | Responder | |
| GET/POST | `/looking-for/responses/:rid/messages` | The two parties, accepted only | Chat. |
| POST | `/looking-for/responses/:rid/share-contact` | Either party, accepted only | Shares the sender's phone/WhatsApp with the other party only. |
| POST/DELETE | `/looking-for/:id/save` | Signed in | |
| POST | `/looking-for/:id/report` | Signed in, throttled | |
| GET | `/me/looking-for?tab=posted\|interested\|responses\|saved\|completed` | Signed in | My Looking For. |
| GET/PUT | `/me/looking-for/alerts` | Signed in | Alert preferences. |
| GET/PUT | `/me/community-roles` | Signed in | Referee / scorer / commentator / streamer etc. |
| GET | `/me/notifications`, POST `/me/notifications/read` | Signed in | In-app notifications (all kinds; first endpoints for the existing table). |
| GET | `/admin/looking-for/stats` | Platform admin | Totals, active, filled, expired, reports, top locations and categories, response rate, fill rate. |
| GET/PATCH | `/admin/looking-for/posts`, `/:id` (hide, remove) | Platform admin | Audited. |
| GET/PATCH | `/admin/looking-for/reports` | Platform admin | Review queue. |
| POST | `/admin/looking-for/users/:id/warn` · `/suspend` | Platform admin | |
| CRUD | `/admin/looking-for/categories`, `/subcategories`, `/rules` | Platform admin | Categories, expiry defaults, notification caps. |

## 7. Matching

`LookingForMatcher` is a pure function (easy to test, same inputs on server and in tests):

```text
candidates = users with alerts on for this category (or no preference yet and a relevant role/profile)
             within radius (bounding box, then haversine) or in the same city
             not the creator, not suspended, not already matched to this post
signals    = distance · date/time vs availability · category ↔ community role
             · skill within the post's band · gender/age where the post sets one
             · played in the linked tournament / at the linked venue · recently active
score      = weighted sum; below threshold → dropped
reasons    = facts only: "4.2 km away", "Intermediate (3.5)", "Registered referee", "Played at XYZ Club"
```

The creator sees the count and the reasons in aggregate, never a ranked list of names. Responders are listed by response time, not by score.

## 8. Notifications

- A match above threshold is stored in `LookingForMatch` (unique per post and user, so nobody is notified twice for one post).
- **Instant**: at most `dailyCap` (default 5) per user per day, none during quiet hours; overflow goes to the digest.
- **Daily digest**: one notification with the day's matches at the user's chosen hour.
- **Off**: matches are still stored (for the count) but never sent.
- Only the top N candidates per post are notified (default 50), so a broad post cannot message a whole city.
- Other events: new response (to creator), accepted/declined (to responder), filled, expiring in 1 hour (to creator), new message.
- Channels: in-app now; push via the outbox once FCM is configured.

## 9. App screens

| Route | Screen |
|---|---|
| `/player/looking-for` | Home: For You · Nearby · Latest · My Requests tabs, search, filter chips, **+ Post** (thumb-reach FAB). |
| `/player/looking-for/new` | Quick post: category grid → subcategory → quantity → when → where → review → Post. "Type it instead" box uses `/parse` and fills the same review screen. Post As picker when the user has organisations. |
| `/player/looking-for/:id` | Detail: facts, linked tournament/venue, poster, status (e.g. "1 of 2 filled"), I'm Interested / Save / Share / Report. Owner sees responses and matching summary. |
| `/player/looking-for/:id/responses` | Owner: responders with level, city, matches played, message; Accept / Decline / View profile. |
| `/player/looking-for/chat/:responseId` | Conversation + share contact. |
| `/player/looking-for/mine` | Posted · Interested · Responses · Saved · Completed. |
| `/player/looking-for/alerts` | Mode, categories, radius, location, community roles. Also linked from Settings. |
| Home | One Looking For card ("2 players needed near you tonight" or "Need a player? Post it") under quick actions. |
| Explore | Looking For module switched to active. |
| Organizer | "Find officials" action on a tournament → prefilled Referee/Scorer post linked to that tournament. |

## 10. Admin screens

Stats overview; posts table with filters and hide/remove; reports queue (post, reasons, reporter count, actions); user sanctions; categories and subcategories editor; rules (expiry defaults, daily cap, top-N, threshold).

## 11. Build phases

Each phase ends with: API unit tests, `tsc`/`nest build`/lint, `prisma validate` (and migrate, once a database is available), `flutter analyze`, `flutter test`, and a run on the phone.

| # | Scope |
|---|---|
| 1 | Schema + category reference data; posts CRUD, validation, expiry, statuses; feed with filters and paging; app repository (API + sample), Looking For home, detail, quick post, Explore/Home entry points. |
| 2 | Responses, accept/decline, filled counting, My Looking For, save, share (deep link route), report. |
| 3 | Matching engine, alert preferences, community roles, in-app notifications (`/me/notifications`), digest. |
| 4 | Conversations and contact sharing. |
| 5 | Natural-language parse, Post As organisation/tournament, organizer "Find officials". |
| 6 | Admin API + admin UI, moderation, sanctions, analytics events and stats. |
| 7 | Web landing page for shared links, App Links / Universal Links, push via FCM (with build step 7). |

## 12. What is built (phases 1–3)

### Where it lives

| Layer | Code |
|---|---|
| Schema | `backend/prisma/schema.prisma` (LookingFor* models, `CommunityRole`); migrations `20260927131720_init` (the first migration ever run for this API) and `20260927132256_looking_for`. |
| Reference data | `npm run prisma:reference` upserts the 13 categories and their subcategories from `src/looking-for/looking-for.categories.ts`. |
| API | `backend/src/looking-for/`: categories + form validation, rules (status, expiry, skill bands, cursors), parser (sentence → fields, also used by search), matcher (pure scoring with factual reasons), matching service (candidates, caps, digest), service, controllers, jobs (expiry sweep + digest every 5 min). `backend/src/notifications/`: `GET /me/notifications`, `GET /me/notifications/unread-count`, `POST /me/notifications/read`. Capability `postLookingFor` (owner, tournament admin). |
| App | `lib/features/looking_for/`: `data/` (models, API repository, sample stand-in with the same rules), `looking_for_controller.dart` (providers + `LfActions`, which refresh exactly what each write changes), `ui/` (home with For You / Nearby / Latest / My Requests, quick post + sentence composer, detail, responses, alerts, Home card). |
| Integration | Explore module switched on; Home card; `NotificationKind.lookingFor`; notifications read the API when `useRealApi`; `ApiClient.put/delete/getPage`; routes `/player/looking-for…` and `/looking-for/:id` (shared links). |

### Differences from the plan above

- **Community is being built in parallel** (`lib/features/community/`, docs/COMMUNITY.md): people with roles, places, groups, connections and a conversations inbox. Looking For does not duplicate it:
  - role ids in `community_roles` are Community's `CommunityRole` enum names (referee, scorekeeper, official, organizer, eventManager, coach, trainer, commentator, streamer, photographer, creator); `/me/community-profile` should read and write the same table;
  - chat (phase 4) reuses Community's direct conversations; an accepted response counts as permission to message. The `LookingForConversation`/`Message` models in §5 are dropped;
  - Community's "Opportunities" tile points at `/player/looking-for`.
- **Distance** is measured between city centres (`src/looking-for/cities.ts`, ~50 cities) unless a post pins lat/lng; the app shows it as approximate. The app has no GPS permission yet.
- **Contact now**: after acceptance, each side can share their phone with the other side only (`/share-contact`). The number appears only for the side that received consent.
- **Safety now**: three distinct open reports hide a post until a moderator looks; posting and responding check `LookingForSanction`. The review UI is phase 6.
- **Push**: every alert is an in-app notification row; FCM delivery comes with build step 7.

### Verified

- API: 131 unit tests pass (21 for Looking For: status, expiry, skill bands, cursors, categories and detail validation, parser on the brief's sentences, matcher gates and reasons). `tsc`, `nest build` and eslint clean.
- End to end against PostgreSQL (`D:\dev\postgres-skorx`, port 5433) with four real OTP accounts: 54 checks, including validation, matching (referee posts reach only referees; Mumbai is not alerted for Ahmedabad), alerts written as notifications, For You reasons, Nearby radius, natural-language search ("players needed tonight", "referee ahmedabad"), paid filter, cursor paging, respond once, owner-only responses, partially filled → filled → no third acceptance, withdraw reopens a place, consent-only phone sharing, save, share link, public summary without ids, auto-hide after three reports, My Looking For tabs, fill / reopen / cancel. Script: `backend/scripts/looking-for-smoke.mjs`.
- App: `flutter analyze` clean; full suite 334 tests pass, 17 of them for Looking For (API JSON parsed from a fixture captured from the running API, sample rules, and widget flows: open from Explore and back, Home card, browse/search/empty state, I'm interested and withdraw, post in a few taps, sentence composer, accept until filled, alerts, every screen at 360×690).
- On the phone: hot-restarted into the shared debug session (dev sign-in, sample data). **Not yet run on the phone against the real API**: that needs a `REAL_AUTH=true` build pointed at the laptop (`adb reverse tcp:4000 tcp:4000`, `API_BASE_URL=http://localhost:4000/api/v1`).

### Running it for real

```bash
# Database (not a Windows service; start it after a reboot)
D:/dev/postgres/bin/pg_ctl -D 'D:\dev\postgres-skorx' -o "-p 5433" -l 'D:\dev\postgres-skorx.log' start
# API (backend/.env DATABASE_URL points at 5433; the old line is in D:\dev\backend.env.bak)
cd backend && npx prisma migrate deploy && npm run prisma:reference && npm run build && node dist/main.js
```

Sign-in codes are printed in the API log (console OTP provider).
