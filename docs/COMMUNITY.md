# SkorX Community

Status as of 27 Sep 2026. Phases 1 and 2 and the core of Phase 3 are built, in the app and in the NestJS API (`smit-dev-skorx-frontend/backend/src/community`), against a real PostgreSQL database. Debug builds use sample data unless run with `--dart-define=REAL_AUTH=true`; release builds use the API. Monetisation and business listings are not started (§7).

**The idea: the network layer of SkorX.** Community connects the people and places of pickleball (players, officials, organisers, coaches, clubs, academies, courts, media, businesses) and links every one of them back to what SkorX already knows: player stats, venues and bookings, tournaments. It is not a feed-first social network.

---

## 1. Where it lives

### 1.1 Navigation

The bottom bar is unchanged: Home · Matches · **Explore** · My Paddle · Account.

- **Community is a module inside Explore**, next to Tournaments, Scores, Players, Courts and Looking For. Its card shows what is waiting ("2 new"). It opens inside the Explore tab (`/player/community`), with a back arrow to the Explore hub.
- The Explore tab carries the Community badge: connection requests plus unread conversations and message requests.
- **Opportunities is Looking For** (`/player/looking-for`, built separately). The Community hub links to it.
- Account has a **Community** section: My roles, Connections, My communities, Messages, Saved.

### 1.2 Routes

| Route | Screen |
|---|---|
| `/player/community` | Community hub, inside the Explore tab |
| `/player/community/browse/:sector` | One sector, inside the tab: players, officials, organizers, training, places, media, business |
| `/player/community/search?q=` | Search (full screen) |
| `/player/community/people/:id` | Member profile |
| `/player/community/places/:id` | Club, academy, venue or business |
| `/player/community/groups`, `/groups/:id` | Communities, and one community |
| `/player/community/events`, `/events/new?placeId&groupId`, `/events/:id` | Clinics, open play and meetups; host one; one event |
| `/player/community/posts`, `/posts/:id?groupId&placeId` | My network's posts; one post and its comments |
| `/player/community/messages?tab=requests`, `/messages/:id?draft=` | Inbox, and one conversation |
| `/player/community/me` | My roles, verification, availability, languages, privacy |
| `/player/community/connections?tab=requests\|connected\|sent` | Connections |
| `/player/community/saved` | Saved people and places |

### 1.3 Code

| Layer | Path |
|---|---|
| App models | `lib/features/community/data/community.dart`, `content.dart` (events, posts, verification), `messages.dart` |
| Search and parsing | `data/community_query.dart` |
| Personalisation | `data/personalize.dart` |
| Repository contract | `data/community_repository.dart` |
| API repository and JSON | `data/api_community_repository.dart`, `data/community_json.dart` |
| Sample data (debug) with the server's rules | `data/sample_community.dart` |
| State | `community_controller.dart` |
| Screens | `ui/` |
| App tests | `test/features/community_test.dart`, `community_content_test.dart` |
| API | `backend/src/community/` (service, messages, content, admin, controller, rules) |
| Schema | `backend/prisma/schema.prisma` (`Community*` models), migrations `20260927162837_community`, `20260927170000_community_thread_key` |
| API tests | `backend/src/community/community.spec.ts` (rules), `backend/scripts/community-smoke.mjs` (61 end-to-end checks over HTTP) |

---

## 2. Information architecture

```text
Community hub
├── Search (plain sentences) · Location (a city or Anywhere) · Create / Join
├── Browse: seven sectors, ordered for the member's roles
│     Players · Officials · Organizers · Coaching · Clubs & courts · Media · Business
├── People you may know (each with why)
├── Communities near you
├── Places to play in <city>        → venue pages book through the courts module
├── Clinics, open play & meetups     → community events; RSVP and event chat
├── From your network                → posts; write one
├── Tournaments                      → TMS tournaments, never copied
├── Active this week                 → groups ranked by share of members active
└── Looking For                      → post or answer "referee needed", "partner wanted"…
```

Sectors hold **roles** (people) and **place kinds**:

| Sector | Roles | Places |
|---|---|---|
| Players | Player (tags: Doubles, Singles, Mixed, Competitive, Recreational, Junior, Senior) | |
| Officials | Referee, Scorekeeper, Tournament official | |
| Organizers | Tournament organizer, Event manager | |
| Coaching | Coach, Fitness trainer | Academy |
| Clubs & courts | | Club, Courts & grounds |
| Media | Commentator, Streamer, Photographer, Content creator | |
| Business | | Brands & services |

A member can hold **any number of roles** (§21 of the brief). Role ids are the Dart enum names (`player`, `referee`, `scorekeeper`, `official`, `organizer`, `eventManager`, `coach`, `trainer`, `commentator`, `streamer`, `photographer`, `creator`), the API's ids, and Looking For's (one shared `CommunityRole` table; a spec checks they match).

### 2.1 Personalisation

`sectorsFor(roles)` orders the sector strip, `hubPrompt(roles)` sets the hub's subtitle and `rolesOfInterest(roles)` steers suggestions (the same table is in the API's `community.rules.ts`). For each role, its first interest weighs most:

| I am a… | I see first |
|---|---|
| Player | Players, Coaching, Clubs & courts |
| Organizer | Officials, Media, Clubs & courts |
| Referee / Scorekeeper | Organizers, Officials |
| Coach | Players, Coaching |
| Streamer / Commentator | Organizers, Media |

Every sector stays; only the order changes. A first-visit card asks *What do you do in pickleball?* until roles are saved.

### 2.2 Search

`CommunityQuery.parse` reads sentences into filters on the phone, and words it does not recognise stay as free text:

| Typed | Understood as |
|---|---|
| Find a referee near Ahmedabad | role referee, city Ahmedabad |
| Scorekeepers in Gujarat | role scorekeeper, state Gujarat |
| Pickleball academy near me | kind academy, *near me* → the chosen location (dropped if none; permission is never asked) |
| Indoor pickleball courts Ahmedabad | kind courts, indoor, city |
| Coach for beginner training | role coach, level Beginner |
| Doubles partner Surat | role player, tag Doubles, city |

Filters: location, role, place kind, verified only, available now, language, level, indoor/outdoor, player tag. **A professional is found in every city they serve** (service area), and a state search reaches every city in it. Gender and fees are not filters yet (§8).

---

## 3. Screens

- **Member profile.** Name, place, availability, headline, role badges (sealed when verified), mutual connections. Connect · Message · Follow. *On court* links to the player's SkorX stats (`/player/players/:playerId`) rather than repeating them. Each professional role has its own block: *Verified by SkorX* or *Not verified yet*, years in the role, role numbers and portfolio lines. **Organisers see *Rate their work*** on officials, media and coaches: would you book them again, were they on time. About, clubs and academies, communities. ⋯ has Block and Report.
- **Place.** The primary action depends on the kind: **Book a court** (venue → the booking flow), **Enquire about training** (academy), **Ask to join** (club), Message (business). Enquiries open a conversation with a **draft** that is never sent without a tap. Facility (from the courts module), amenities, programmes, coaches and staff, tournaments from the TMS, **events held here** (anyone can host at a venue), and the place's **updates**.
- **Communities.** Near you · Joined · All. Public: join at once. Private: *Ask to join* → Requested; **admins approve or decline requests on the community page**. Verified: only verified organisations create them. Members get the group chat, the community's **events** (members host) and **posts** (members post; private communities show posts to members only).
- **Events.** Clinics, open play, meetups, camps, workshops, socials, club events. Not tournaments (those stay in the TMS; an event can point at one). *I'm going* (capacity enforced: a full event says so), *Interested*, event chat for people going, cancel for the host (everyone going is notified). *Host an event*: type, title, day, time, length, city, venue, spots, fee, level.
- **Posts.** Announcement, achievement, tip, event, news. Text plus a link that can only point inside SkorX (a tournament, match, venue). Like, comment, delete my own, report. Three distinct reports hide a post until a moderator looks; its author sees it marked as hidden.
- **Messages.** Chats · Requests. A message request shows Accept · Decline · Block; the sender is not told about a decline.
- **My Community.** Roles by sector; **Verification** per saved professional role (Not verified → evidence sheet → *With the SkorX team* → Verified, or *Needs more evidence* with the reviewer's note); headline; availability and cities worked; languages; *Messages from* everyone or connections only; *Show me in search*.

Design: the existing player design system (`lib/design/`) in both themes. Every Community screen, including the new-player state, is laid out at 390×844 light, 360×690 dark and 1180×820 in the test suite.

---

## 4. Data model (Prisma)

Community reuses what exists and adds only what is new. Nothing copies a player's stats, a venue's courts or a tournament.

```text
User ─1:1─ PlayerProfile ─── SportPlayerProfile (rating, stats)                 [exists]
  ├─1:n─ CommunityRole (userId, role)                                            [shared with Looking For]
  ├─1:1─ CommunityProfile (headline, bio, city, state, availability, languages[], serviceArea[],
  │                        tags[], messagesFrom, listed, rolesChosen, suspendedUntil)
  ├─1:n─ CommunityRoleDetail (userId, role, since, highlights[], verifiedAt, verifiedBy)
  ├─1:n─ CommunityConnection (requesterId, addresseeId, status pending|accepted)
  ├─1:n─ CommunityFollow / CommunitySaved (userId, targetType, targetId)
  ├─1:n─ CommunityBlock (blockerId, blockedId)
  └─1:n─ CommunityGroupMember (groupId, userId, status, role admin|member, lastActiveAt)

CommunityPlace (kind, about, verifiedAt, hours, amenities[])
  ├─ venueId → Venue · clubId → Club · organizationId → Organization            [exist]
  ├─ CommunityProgram (name, level, schedule, feeMonthly, juniors)
  └─ CommunityPlaceStaff (placeId, userId, title, manager)

CommunityGroup (name, nameKey unique, access, city, state, focusRole, managedByPlaceId, featuredAt)
CommunityConversation (kind, targetId, threadKey unique, initiatorId)
  ├─ CommunityConversationMember (state active|request|declined, lastReadAt, hiddenAt)
  └─ CommunityMessage (body ≤ 2000)
CommunityEvent (kind, title, startsAt, endsAt, city, placeId, groupId, tournamentId, capacity, feeInr, level)
  └─ CommunityEventRsvp (going|interested)
CommunityPost (kind, body ≤ 1000, link, placeId, groupId, eventId, likeCount, commentCount, hiddenAt)
  ├─ CommunityPostLike · CommunityComment (≤ 500, hiddenAt)
CommunityReport (target, reason, status open|actioned|dismissed) · CommunityVerificationRequest
CommunityFeedback (from organiser, to member, role, recommend, onTime, tournamentId)
```

**Threads** are keyed by `threadKey`: `dm:<a>:<b>` (sorted user ids, one per pair), `place:<placeId>:<userId>` (one per person per place), `group:<id>`, `event:<id>`.

**Reputation comes from SkorX records**: matches played and win rate (`MatchParticipant`), matches officiated (`Match.referee`), matches scored (`ScoreEvent.createdByUserId`), events completed and players hosted (`Tournament`, `Registration` of the organisations they run), academies and programmes, plus organiser feedback as "96% positive (n)" and "On time %". Never a star rating. The API returns `(label, value)` pairs per role, so new metrics need no app release.

## 5. API

All under `/api/v1`, signed in. Errors carry a code the app switches on: `BLOCKED`, `MESSAGES_RESTRICTED`, `AWAITING_REPLY`, `COMMUNITY_SUSPENDED`, `RATE_LIMITED`, `RESOURCE_CONFLICT`, `FORBIDDEN`, `RESOURCE_NOT_FOUND`, `VALIDATION_ERROR`.

| Endpoint | Notes |
|---|---|
| `GET /community/members?q&sector&roles&city&state&verified&available&language&level&tag&cursor` | Leaves out blocked members (either way), and unlisted members unless connected. Paged, `meta.nextCursor`. |
| `GET /community/members/:id` | Same visibility. Roles with metrics, mutual connections, places, communities. |
| `GET /community/places?…`, `GET /community/places/:id` | Joins venue courts; detail adds TMS tournament ids and followers. |
| `GET /community/groups?city&q`, `GET /community/groups/:id` | Featured first, then city, state, national; by weekly activity. |
| `POST /community/groups`, `POST …/:id/join`, `DELETE …/:id/membership` | Names unique ignoring case; `verified` only by verified-place managers; 3 a day. |
| `GET /community/groups/:id/requests`, `POST …/requests/:userId/approve\|decline` | Admins only. |
| `GET /community/suggestions?city` | Mutual connections, shared communities, the city, role interest; each with a reason. |
| `GET /me/community` | Connections, following, groups, `adminOf`, blocked, saved (typed). |
| `GET` / `PUT /me/community-profile` | At least one role; replaces the member's `CommunityRole` rows. |
| `POST /community/connections {memberId}`, `DELETE …/:memberId` | Accepts their request if there is one; 30 requests a day. |
| `PUT` / `DELETE /community/follows/:member\|place/:id`, `PUT` / `DELETE /me/saved/:type/:id` | |
| `POST` / `DELETE /community/blocks/:memberId` | Ends the connection and follows both ways and hides the thread. |
| `POST /community/reports` | One per person per target. Three open reports hide a post or comment. |
| `POST /community/feedback` | Owners and tournament admins only; for their own tournament when one is named; roles referee, scorekeeper, official, commentator, streamer, photographer, coach. |
| `GET` / `POST /me/community/verifications` | One pending request per role; only roles you hold. |
| `GET /community/events?city&kind&placeId&groupId`, `GET …/:id`, `POST /community/events` | Staff host for clubs and academies; anyone at venues; members for their community. Up to 14 days; 5 a day. |
| `POST /community/events/:id/rsvp {going\|interested\|none}`, `POST …/:id/cancel` | Capacity enforced (`RESOURCE_CONFLICT`); cancelling notifies attendees. |
| `GET /community/posts?groupId&placeId&authorId&before` | Network feed (connections, follows, my communities, public communities in my city) or one stream. |
| `POST /community/posts`, `DELETE …/:id`, `PUT` / `DELETE …/:id/like`, `GET` / `POST …/:id/comments`, `DELETE /community/comments/:id` | Links must start with `/player/`; 20 posts a day. |
| `GET /me/conversations`, `POST /conversations {kind, targetId}` | Direct: `MESSAGES_RESTRICTED` for connections-only strangers (an accepted Looking For response counts as an introduction); 10 new cold threads a day. |
| `GET` / `POST /conversations/:id/messages`, `POST …/:id/read`, `POST …/:id/accept`, `DELETE /conversations/:id` | `AWAITING_REPLY` after one cold message; replying accepts a request; deleting a request declines it silently. |

### 5.1 Permissions and privacy

- Phone numbers and emails are **never** returned by Community endpoints. Reaching someone means a SkorX message or a connection.
- Verification is set only by SkorX staff after reviewing evidence, per role. It is never earned through popularity, and members cannot set it.
- Group chats: members only. Event chats: the host and people who RSVP'd. Place chats: the person and the place's staff.
- A suspended member can read but not post, message, connect, follow, host or RSVP.

### 5.2 Notifications

Wording comes from the shared `notificationCopy` (app `docs/NOTIFICATIONS.md`): `community.connect_request`, `community.connected`, `community.message`, `community.message_request`, `community.follow`, `community.group_approved`. Also `community.group_request` (to admins), `community.comment`, `community.event_cancelled`, `community.feedback`, `community.verified`, `community.verification_declined`, `community.suspended`. Group chats do not notify. The app maps every `community.*` type to its Community icon.

---

## 6. Moderation and admin

Staff only (`PlatformAdminGuard`, `PLATFORM_ADMIN_EMAILS`), under `/api/v1/admin/community`:

| Endpoint | What it does |
|---|---|
| `GET overview` | Members, active this week, communities, new connections, open reports, pending verifications, posts and messages this week, upcoming events, suspended; spam signals (members with 3+ open reports, open reports by reason). |
| `GET reports?status` | Reports grouped by target, most reported first, with a preview. |
| `POST reports/:id/review {dismiss\|hide\|suspend, days}` | Dismiss brings an auto-hidden post back; hide takes it down (or closes the community, cancels the event); suspend also pauses its owner. Closes every open report on the target. |
| `GET verifications`, `POST verifications/:id/review {approve\|reject, note}` | Approve sets the role's (or place's) verified badge; reject sends the note. |
| `DELETE members/:userId/roles/:role/verification` | Revoke a badge. |
| `PUT groups/:id/featured/:on` | Feature a community (it leads the lists). |

The screens for these belong in the web admin, not the player app; the API is ready for them.

## 7. Build order

| Phase | Scope | Status |
|---|---|---|
| 1 | Hub, sectors, directory, role-based profiles, sentence search, connect and follow, messaging with requests and spam protection, block and report, clubs, academies and venues linked to courts and TMS, roles and privacy, Account section, badge | **Built** (app + API) |
| 2 | Communities with admin approvals, events (clinics, open play, meetups) with RSVPs and chats, posts with likes and comments, Opportunities (= Looking For) | **Built** (app + API) |
| 3 | Verification workflow, reputation from SkorX records and organiser feedback, moderation API, featured communities | **Built** (app + API; admin screens are for the web) |
| 3 | Business listings, promotion and monetisation, analytics dashboards, push delivery | Not started |

**Verified:** 22 API rule specs; the 61-check HTTP smoke run against the dev database (signs in real accounts, exercises every rule above, cleans up after itself); 53 app tests; every screen at three sizes.

**To run the smoke test:** start the API with `OTP_PROVIDER=console OTP_DEV_CODE=123456 PLATFORM_ADMIN_EMAILS=community-smoke-admin@skorx.test`, then `API=http://localhost:<port>/api/v1 node scripts/community-smoke.mjs`.

## 8. Known gaps

- **Photos and videos** for places, profiles and posts need upload and storage.
- **Places are created by staff or seeding** for now; there is no "add your club" flow in the app yet.
- **Directions** need `url_launcher` (not a dependency yet); addresses are shown.
- **Reviews** show the venue's rating and count only.
- **Gender** and **service fees** are not filters (not modelled).
- **Distance**: "near" means the same city (or a city the professional serves), not kilometres.
- **Onboarding**: roles are chosen from the Community first-visit card or Account › My roles, not in the sign-up flow.
- **Mentions** in posts and group invitations have notification copy but no UI yet.
