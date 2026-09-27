# SkorX Notifications

Every action on SkorX that someone else should know about, and the words it arrives in.

The copy lives in code in one place: `backend/src/notifications/notification-copy.ts` (API). The app's sample feed (`lib/features/notifications/notifications.dart`) uses the same lines. When copy changes here, change it there too.

## 1. Voice

SkorX sounds like the friend at the club who knows everyone's score: quick, warm, a bit cheeky, and never wrong about the facts.

| Rule | Do | Don't |
|---|---|---|
| **The title is the news.** Read on a lock screen, it should be enough. | *You're up on Court 3* | *Match update* |
| **The person comes first** when a person did something. | *Riya raised a paddle* | *New response received from Riya* |
| **Numbers over adjectives.** | *6 spots left in Men's Doubles* | *Filling up fast!* |
| **One pun at most, and only when the news is good or neutral.** | *Through to the semis. Keep swinging.* | Puns about losses, money, cancellations or security. |
| **Say what to do next** when there is something to do. | *Check in before 8:30 AM, or it's a walkover.* | *Click here for more info.* |
| **No emoji, no ALL CAPS, no "!!!".** The icon carries the mood; one "!" is allowed for a win. | *Champion!* | *🏆🏆 CHAMPION!!!* |
| **Plain words.** | *Refund on its way* | *Your refund has been initiated* |

Tone by moment:

- **Wins, milestones, new stuff**: play. *Hot Streak unlocked. Somebody call the fire brigade.*
- **Logistics** (schedules, check-in, bookings): crisp. Time, place, court, one action.
- **Losses**: kind, short, forward-looking. *Tough one. Every rally still counts.*
- **Money, safety, cancellations**: straight. No jokes, no exclamation marks, always say what happens to the money.

Pickleball words we lean on (sparingly): *paddle up, first serve, rally, dink, kitchen, side out, on deck, baseline, third shot.*

## 2. Anatomy

| Part | Limit | Notes |
|---|---|---|
| Title | 40 characters | Survives the Android and iOS lock screen. Names go first so a cut title still says who. Text people wrote (post titles, headlines, group names) is shortened with "…" to fit. |
| Body | 110 characters | One or two short sentences. Facts joined with " · ". |
| Route | App route | Every notification opens the thing it is about. Never the home screen. |
| Type | `area.event` | The prefix picks the icon and the preference group. |
| Priority | high / normal / low | See below. |

Placeholders in this doc are `{like_this}`. Money is written `₹1,200`. Times are the player's local time: *Today 8:00 PM*, *Tomorrow 7:00 AM*, *Sat 4 Oct 9:30 AM*.

## 3. Delivery

| Priority | In-app | Push | Quiet hours (10 PM–7 AM) | Examples |
|---|---|---|---|---|
| **high** | Top, accent dot | Yes, heads-up | Delivered only on match day or for money and security | Match call, schedule change, partner invite, payment failed |
| **normal** | Listed | Yes, silent after the 4th of the day | Held until 7 AM | Results, bookings, connections |
| **low** | Grouped under *Earlier* | No | — | Tips, recaps, "someone went with another player" |

Rules:

- **Match day beats everything.** Match calls, on-deck and check-in ignore quiet hours and caps.
- **Bundle bursts.** Three or more of the same type within 10 minutes become one: *5 new entries in Men's Doubles*. Messages from one person collapse into one, showing the latest.
- **Caps** for non-transactional pushes (discovery, Looking For matches, Pro, re-engagement): 3 a day, 1 re-engagement a week, 1 Pro prompt a fortnight, none to Pro members.
- **Don't tell people what they did.** The actor never gets a notification for their own action, except receipts for money.
- **Replace, don't pile up.** A newer notification about the same match or booking replaces the older one's push (collapse key = the route).
- **Silent removals.** Declining a connection, removing a follower and withdrawing a request are never announced.

Preference groups (Settings → Notifications). *Match day* and *Payments and account* can't be turned off.

| Group | Types |
|---|---|
| Match day | `tournament.match_call`, `tournament.on_deck`, `tournament.checkin_open`, `tournament.schedule_changed`, `match.starting_soon` |
| Matches and results | `match.*`, `tournament.result_*` |
| Tournaments | `tournament.*`, `registration.*` |
| Courts and bookings | `booking.*`, `official.*` (as a booker) |
| Community and messages | `community.*` |
| Looking For | `looking_for.*` |
| Rating and achievements | `rating.*`, `points.*`, `ranking.*`, `achievement.*`, `stats.*` |
| Payments and account | `account.*`, `subscription.*`, payment and refund types |
| Organiser | `org.*`, `official.*` (as an official) |
| News and tips | `explore.*`, `system.*` |

## 4. Catalogue

Columns: **Type** · **When** · **Who gets it** · **Title** · **Body** · **Opens** · **Priority**.

### 4.1 Account

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `account.welcome` | Profile set up | Player | Welcome to the court, {first_name} | Your player card is live. Book a court, find a tournament or score your first rally. | `/player/explore` | normal |
| `account.profile_nudge` | Day 2 with no photo | Player | Your card is missing a face | Add a photo so partners know who to high-five. | `/player/edit-profile` | low |
| `account.new_sign_in` | Sign-in on a new phone | Player | New sign-in on {device} | {city} · {when}. Not you? Sign out of every device in Settings. | `/player/settings` | high |
| `account.phone_changed` | Number changed | Player | Your number is now {masked_phone} | Sign-in codes go to this number from now on. Not you? Contact support. | `/player/settings` | high |

### 4.2 Casual matches

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `match.invite` | Invited to a match | Invitee | {name} wants you on court | {format} · {venue} · {when}. Accept to lock in your spot. | `/player/matches/{id}` | high |
| `match.invite_accepted` | Invite accepted | Inviter | {name} is in. Game on. | {format} · {venue} · {when}. | `/player/matches/{id}` | normal |
| `match.invite_declined` | Invite declined | Inviter | {name} can't make this one | The court's still yours. Invite someone else. | `/player/matches/{id}` | low |
| `match.link_request` | Added to a scored match | Linked player | Were you on court with {name}? | They scored {score}. Confirm it to add the match to your record. | `/player/matches/{id}` | high |
| `match.link_confirmed` | Link confirmed | Scorer | {name} confirmed the match | {score} now counts for both of you. | `/player/matches/{id}` | normal |
| `match.link_rejected` | Link rejected | Scorer | {name} says that wasn't them | The match stays on your record only. Check the line-up. | `/player/matches/{id}` | normal |
| `match.reminder` | 1 hour before a scheduled match | Every player | Paddle up: first serve in 1 hour | {venue} · {format} with {names}. | `/player/matches/{id}` | high |
| `match.starting_soon` | 10 minutes before | Every player | 10 minutes to first serve | {venue} · Court {court}. Stretch those wrists. | `/player/matches/{id}` | high |
| `match.result_win` | Match completed, won | Each winner | W: {score} over {opponents} | +{points} SkorX Points. Keep that rally rolling. | `/player/matches/{id}` | normal |
| `match.result_loss` | Match completed, lost | Each loser | Tough one: {score} vs {opponents} | Every rally still counts: +{points} SkorX Points. | `/player/matches/{id}` | normal |
| `match.paused` | Left unfinished 2 hours | Scorer | Match saved at {score} | Pick it up from the next serve whenever you're back on court. | `/player/match` | low |
| `match.video_ready` | Stream recording processed | Every player | Your match video is ready | Relive {score} vs {opponents}, every rally of it. | `/player/matches/{id}` | normal |

#### Casual match verification (docs/CASUAL-VERIFICATION.md)

`match_request.*` asks for an answer and lists under **Match requests** in the app; one unread request per match (a newer one marks the older read). The rest report back.

| Type | Trigger | To | Title | Body | Route | Priority |
|---|---|---|---|---|---|---|
| `match_request.added` | Added to someone's casual match | Each registered player | {name} added you to a casual match | {lineup} · {when}. Confirm you played so it counts. | `/player/match-requests/{id}` | high |
| `match_request.result` | Result submitted or changed | Each other player | Confirm the result: {score} | {lineup}. {name} submitted it; it counts once everyone confirms. | `/player/match-requests/{id}` | high |
| `match_request.correction` | New score on a verified match | Each other player | {name} wants to correct a score | {from} → {to}. The old score counts until everyone agrees. | `/player/match-requests/{id}` | high |
| `match_request.reminder` | Creator taps Remind (once a day) | Players who have not answered | {name} is waiting on you | {lineup}. One tap to confirm the match. | `/player/match-requests/{id}` | normal |
| `match.verified` | Last confirmation | Every player | Verified: {score} | {lineup}. It now counts toward stats, rating and rankings. | `/player/match-requests/{id}` | normal |
| `match.rejected` | A player rejects (did not play, not present, cancelled) | Creator | {name} rejected your match | Reason: {reason}. It won't count. Fix the line-up to send it again. | `/player/match-requests/{id}` | high |
| `match.disputed` | A player disputes a detail | Creator | {name} disputed your match | Reason: {reason}. Fix the details to send it again. | `/player/match-requests/{id}` | high |
| `match.correction_applied` | Everyone accepted a correction | Every player | Score corrected | Everyone agreed: the match is now {score}. | `/player/match-requests/{id}` | normal |
| `match.correction_rejected` | A player keeps the original | Proposer | {name} kept the original score | The verified result stays as it was. | `/player/match-requests/{id}` | normal |
| `match.flagged` | Dispute after verification | Other players | {name} flagged a verified match | Reason: {reason}. SkorX will review it; the result stands for now. | `/player/match-requests/{id}` | normal |
| `match.removed` | Taken off the line-up | Removed player | {name} took you off a match | It won't appear on your record. | `/player/matches` | low |
| `match.cancelled` | Creator cancels | Players who had not rejected | {name} cancelled a match | {lineup}. Nothing to confirm. | `/player/match-requests/{id}` | low |

Tournament matches never send these.

### 4.3 Tournaments (player)

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `tournament.new_nearby` | Published in the player's city | Players in city, matching level | New in {city}: {tournament} | {dates} · {categories}. Entries are open. | `/player/tournament/{id}` | normal |
| `tournament.closing_soon` | 48 h before entries close | Followers, not entered | Last call: {tournament} | Entries close {when}. {category} has {spots} spots left. | `/player/tournament/{id}` | high |
| `tournament.draw_published` | Draw published | Entrants | The draw is out | You open against {opponent} in the {round}. Time to scout. | `/player/tournament/{id}` | high |
| `tournament.schedule_published` | Schedule published | Entrants | Your first match: {when} | {tournament} · Court {court}. Arrive 20 minutes early. | `/player/tournament/{id}` | normal |
| `tournament.schedule_changed` | Match time or court moved | Both sides | Heads up: your match moved | {round} vs {opponent} is now {when} on Court {court}. | `/player/matches/{match_id}` | high |
| `tournament.checkin_open` | Check-in opens | Entrants not checked in | Check in for {category} | Tap to check in before {when}, or it's a walkover. | `/player/tournament/{id}` | high |
| `tournament.checked_in` | Checked in | Player (and partner) | You're checked in | {category} · first serve {when}. Go warm up. | `/player/tournament/{id}` | low |
| `tournament.on_deck` | Previous match on court is in its last game | Next pair | You're on deck | Next on Court {court} vs {opponent}. Stay close. | `/player/matches/{match_id}` | high |
| `tournament.match_call` | Match called | Both sides | You're up on Court {court} | {round} vs {opponent}. The referee is waiting. | `/player/matches/{match_id}` | high |
| `tournament.result_win` | Won, not the final | Winners | Through to the {next_round}! | Won {score} vs {opponent}. Next up: {next_opponent}, {when}. | `/player/matches/{match_id}` | normal |
| `tournament.result_loss` | Knocked out | Losers | Your {tournament} run ends here | Lost {score} to {opponent} in the {round}. Plenty to build on. | `/player/matches/{match_id}` | normal |
| `tournament.walkover` | Opponent no-show | Winners | Walkover win vs {opponent} | They couldn't make it. You're through to the {next_round}. | `/player/tournament/{id}` | normal |
| `tournament.champion` | Won the final | Winners | Champion! {category} is yours | Gold at {tournament}. +{points} SkorX Points and a new badge. | `/player/tournament/{id}` | high |
| `tournament.runner_up` | Lost the final | Losers | Silver at {tournament} | Finalist in {category}. +{points} SkorX Points. Next year's gold is waiting. | `/player/tournament/{id}` | normal |
| `tournament.result_corrected` | Organiser corrected a result | Both sides | Your result was corrected | {round} vs {opponent} is now {score}. Think it's wrong? Contact the organiser. | `/player/matches/{match_id}` | high |
| `tournament.announcement` | Organiser announces | Entrants (or everyone following) | {headline} | {organiser}: {message} | `/player/tournament/{id}` | normal |
| `tournament.urgent` | Emergency announcement | Entrants | Urgent from {tournament} | {message} | `/player/tournament/{id}` | high |
| `tournament.postponed` | Dates change | Entrants | {tournament} has new dates | Now {dates}. Your entry carries over. Can't make it? Withdraw for a full refund. | `/player/tournament/{id}` | high |
| `tournament.cancelled` | Cancelled | Entrants | {tournament} is cancelled | Your ₹{amount} goes back to the original payment within 5–7 working days. | `/player/tournament/{id}` | high |
| `tournament.streaming` | Stream starts | Entrants and followers | {tournament} is live | Court {court}: {match}. Watch every rally. | `/player/matches/{match_id}` | low |

### 4.4 Registrations and entry payments

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `registration.confirmed` | Entry paid and accepted | Player (and partner) | You're in: {tournament} | {category} with {partner}. The draw drops {when}. | `/player/tournament/{id}` | normal |
| `registration.payment_pending` | Entry started, unpaid 1 h | Player | Your spot isn't locked yet | Pay ₹{amount} for {category} by {when} to confirm it. | `/player/tournament/{id}` | high |
| `registration.payment_failed` | Payment failed | Player | Payment didn't go through | Nothing was charged. Try again to keep your spot in {category}. | `/player/tournament/{id}` | high |
| `registration.partner_invite` | Named as partner | Partner | {name} wants you as their partner | {category} at {tournament}. Say yes before entries close {when}. | `/player/tournament/{id}` | high |
| `registration.partner_accepted` | Partner said yes | Registrant | {name} said yes. Team's set. | {category} at {tournament}. | `/player/tournament/{id}` | normal |
| `registration.partner_declined` | Partner said no | Registrant | {name} can't partner this time | Find another partner for {category} before {when}. | `/player/tournament/{id}` | high |
| `registration.approved` | Organiser approved | Player | Approved for {category} | {tournament}. See you on court. | `/player/tournament/{id}` | normal |
| `registration.rejected` | Organiser rejected | Player | Your entry wasn't approved | {reason}. Any payment is refunded within 5–7 working days. | `/player/tournament/{id}` | high |
| `registration.waitlisted` | Category full | Player | You're #{position} on the waitlist | We'll tell you the moment a spot opens in {category}. | `/player/tournament/{id}` | normal |
| `registration.spot_opened` | Waitlist spot freed | First on waitlist | A spot opened in {category} | You're first in line. Claim it before {when}. | `/player/tournament/{id}` | high |
| `registration.withdrawn` | Player withdrew | Player (and partner) | You've withdrawn from {category} | {refund_line} | `/player/tournament/{id}` | normal |
| `registration.refunded` | Refund sent | Player | Refund on its way: ₹{amount} | For {tournament}. Expect it in 5–7 working days. | `/player/tournament/{id}` | normal |

### 4.5 Courts and bookings

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `booking.confirmed` | Booking paid | Booker | Court {court} is yours | {venue} · {when}. See you on the baseline. | `/player/bookings` | normal |
| `booking.reminder` | 2 h before | Booker | Court time in 2 hours | {venue} · Court {court} at {time}. Paddle, balls, water. | `/player/bookings` | high |
| `booking.rescheduled` | Venue moved it | Booker | Your booking moved to {when} | {venue} · Court {court}. Doesn't work? Cancel for a full refund. | `/player/bookings` | high |
| `booking.cancelled_by_venue` | Venue cancelled | Booker | Your court was cancelled | {venue} · {when}. Your ₹{amount} is on its way back in 5–7 working days. | `/player/bookings` | high |
| `booking.cancelled` | Booker cancelled | Booker | Booking cancelled | {venue} · {when}. {refund_line} | `/player/bookings` | normal |
| `booking.slot_open` | A watched slot frees up | Players watching | A {time} slot just opened | {venue}: someone cancelled. Grab it before someone else does. | `/player/venue/{id}` | normal |
| `booking.review` | 1 h after the slot ends | Booker | How was {venue}? | Rate the courts in 10 seconds and help the next player choose. | `/player/venue/{id}` | low |

### 4.6 Referees and officials

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `official.request` | Referee booked | Referee | New booking request | {event} · {when} · ₹{fee}. Reply within {hours} hours. | `/player/community/me` | high |
| `official.confirmed` | Referee accepted | Booker | {referee} will officiate | {event} · {when}. Fair play, guaranteed. | `/player/bookings` | normal |
| `official.declined` | Referee declined | Booker | {referee} can't make it | {event} · {when}. Find another official in Community. | `/player/community` | high |
| `official.assigned` | Assigned to a court | Referee | You're officiating Court {court} | {tournament} · {round} · {when}. | `/org/{org_id}/live` | normal |
| `official.match_ready` | Match called | Referee | Your match is ready to score | {teams} on Court {court}. Open the console. | `/org/{org_id}/t/{tournament_id}/match/{match_id}` | high |
| `official.score_conflict` | Two devices disagree | Referee, organiser | Two scores for one match | Court {court} has a different score on another device. Choose which one stands. | `/org/{org_id}/t/{tournament_id}/match/{match_id}` | high |

### 4.7 Rating, points, rankings, achievements

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `rating.up` | Rating rose ≥ 0.3 | Player | SkorX Rating up to {rating} | +{delta} from {reason}. Keep stacking. | `/player/paddle` | normal |
| `rating.down` | Rating fell ≥ 0.5 (weekly, not per match) | Player | Your rating is {rating} this week | {reason}. One good session turns it around. | `/player/paddle` | low |
| `rating.band_up` | Crossed a band | Player | Welcome to {band} | Your SkorX Rating crossed {threshold}. New band, tougher rallies. | `/player/paddle` | high |
| `rating.settled` | 10th verified match | Player | Your rating has settled | 10 verified matches in: {rating} is your number now. | `/player/paddle` | normal |
| `points.level_up` | New points level | Player | Level {level}: {level_name} | {points} SkorX Points and counting. | `/player/paddle` | normal |
| `ranking.moved_up` | Rose in city rankings (Pro) | Player | You're #{rank} in {city} | Up {places} this week. {next_name} is next in your sights. | `/player/rankings` | normal |
| `ranking.moved_up_free` | Same, Free player | Player | You climbed the {city} rankings | See exactly where you stand with SkorX Pro. | `/player/pro` | low |
| `ranking.overtaken` | Someone passed the player | Player | {name} just passed you | You're #{rank} in {city} now. Rematch? | `/player/rankings` | low |
| `achievement.unlocked` | Badge earned | Player | Unlocked: {badge} | {badge_line} | `/player/achievements` | normal |
| `achievement.close` | One step from a badge | Player | 1 {unit} from {badge} | {hint} | `/player/achievements` | low |
| `stats.monthly` | 1st of the month | Active players | Your {month} on court | {matches} matches · {wins} wins · {points} SkorX Points. See the recap. | `/player/paddle` | low |
| `stats.comeback` | 14 days without a match | Player | Your paddle misses you | {slots} courts are open near you tonight. | `/player/explore/courts` | low |

Badge lines (`achievement.unlocked` bodies):

| Badge | Body |
|---|---|
| First Victory | The first of many. Frame this one. |
| Hot Streak | 3 wins in a row. Somebody call the fire brigade. |
| On Fire | 5 wins in a row. The kitchen is officially yours. |
| Comeback Kid | Won from 2 games down. Never over till it's over. |
| Bagel Baker | Won a game 11–0. Fresh out of the oven. |
| Iron Paddle | 10 matches in one week. Your wrists deserve a day off. |
| Globetrotter | Played in 3 cities. Have paddle, will travel. |
| Podium Finish | First tournament medal. Many more to come. |

### 4.8 Community

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `community.connect_request` | Request sent | Recipient | {name} wants to connect | {mutuals} mutual connections · {context}. | `/player/community/connections?tab=requests` | normal |
| `community.connected` | Request accepted | Requester | You and {name} are connected | Say hi, or invite them to a match. | `/player/community/people/{id}` | normal |
| `community.message` | New message | Recipient | {name} | {preview} | `/player/community/messages/{conversation_id}` | high |
| `community.message_request` | First message from a stranger | Recipient | Message request from {name} | {context}. Accept to reply. | `/player/community/messages?tab=requests` | normal |
| `community.follow` | Followed | Player | {name} started following you | They'll see your results and upcoming matches. | `/player/community/people/{id}` | low |
| `community.group_invite` | Invited to a group | Invitee | Join {group}? | {name} invited you · {members} members · {city}. | `/player/community/groups/{id}` | normal |
| `community.group_approved` | Join request approved | Requester | You're in {group} | {members} players are waiting to rally. Say hello. | `/player/community/groups/{id}` | normal |
| `community.group_post` | New post in a group | Members (who opted in) | New in {group} | {author}: {preview} | `/player/community/groups/{id}` | low |
| `community.mention` | Mentioned | Mentioned player | {name} mentioned you | "{snippet}" in {group}. | `/player/community/groups/{id}` | normal |
| `community.friend_live` | A connection starts a live match | Connections | {name} is live right now | vs {opponents} at {venue}. Watch every rally. | `/player/matches/{id}` | low |
| `community.friend_won` | A connection wins a tournament | Connections | {name} just won {tournament} | {category} champion. Send some love. | `/player/community/people/{id}` | low |

### 4.9 Looking For

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `looking_for.match` | Post matches the player | Matched players (top 50) | Wanted: {title} | {place} · {when}. Near you, and you fit the bill. Be the first to say yes. | `/player/looking-for/{id}` | high |
| `looking_for.digest` | Daily digest | Matched players | {n} requests picked for you | {first_title}, and {n-1} more. | `/player/looking-for?tab=for_you` | normal |
| `looking_for.response` | Someone responds | Poster | {name} raised a paddle | "{message}" · {title} | `/player/looking-for/{id}/responses` | high |
| `looking_for.accepted` | Poster accepts | Responder | You're in: {title} | {place} · {when}. Share numbers to sort the details. | `/player/looking-for/{id}` | high |
| `looking_for.declined` | Poster declines | Responder | They've found their match | {title} is sorted. There's plenty more on Looking For. | `/player/looking-for/{id}` | low |
| `looking_for.withdrawn` | Accepted responder drops | Poster | {name} had to drop out | {title} has a spot open again. | `/player/looking-for/{id}/responses` | high |
| `looking_for.contact` | Number shared | Other side | {name} shared their number | {title}. Give them a ring. | `/player/looking-for/{id}` | high |
| `looking_for.cancelled` | Poster closes it | Pending responders | {title} is off | The poster closed it. Nothing needed from you. | `/player/looking-for/{id}` | low |
| `looking_for.expiring` | 24 h before expiry | Poster | Your post ends tomorrow | {title} has {n} responses. Pick someone or extend it. | `/player/looking-for/{id}/responses` | normal |

### 4.10 SkorX Pro and billing

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `subscription.activated` | Pro paid | Player | You're Pro. Every stat unlocked. | Rival stats, rankings, match analytics and streaming until {date}. | `/player/subscription` | normal |
| `subscription.renewing` | 3 days before auto-renew | Player | Pro renews on {date} | ₹{amount} for {plan}. Change or cancel anytime. | `/player/subscription` | normal |
| `subscription.renewed` | Renewal paid | Player | Pro renewed until {date} | Invoice {invoice} is in Billing. | `/player/billing` | low |
| `subscription.payment_failed` | Renewal failed | Player | Your Pro payment failed | Nothing was charged. Update it by {date} to keep Pro. | `/player/subscription` | high |
| `subscription.ending` | 3 days before a cancelled plan ends | Player | Pro ends in 3 days | Your rivals' stats go dark on {date}. Renew to keep the edge. | `/player/pro` | normal |
| `subscription.ended` | Plan ended | Player | Pro has ended | Your matches and stats are safe. Pro is one tap away when you want it back. | `/player/pro` | low |
| `subscription.nudge` | A rival beat a Free player 3 times in a month (max 1 a fortnight) | Free player | {name} has your number | They've won {wins} of your last {played}. See their weak side with Pro. | `/player/pro` | low |

### 4.11 Organiser workspace

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `org.member_added` | Added to an organisation | New member | You've joined {org} | Role: {role}. Switch to Organiser to get started. | `/org/{org_id}/home` | normal |
| `org.published` | Tournament published | Owner, admins | {tournament} is live on SkorX | Players in {city} are hearing about it now. | `/org/{org_id}/t/{tournament_id}` | normal |
| `org.new_entry` | Entry (bundled after 3 in 10 min) | Owner, admins | New entry: {name} | {category} · {count} of {cap} filled. | `/org/{org_id}/t/{tournament_id}/registrations` | low |
| `org.entries_bundle` | 3+ entries in 10 min | Owner, admins | {n} new entries | {category_summary}. Momentum is on your side. | `/org/{org_id}/t/{tournament_id}/registrations` | normal |
| `org.category_full` | Category at capacity | Owner, admins | {category} is sold out | {cap} entries. Open a waitlist or add spots. | `/org/{org_id}/t/{tournament_id}/registrations` | normal |
| `org.payment_received` | Entry fee paid | Owner, finance | ₹{amount} received | {name} · {category}. | `/org/{org_id}/finance` | low |
| `org.refund_requested` | Player asks for a refund | Owner, finance | {name} asked for a refund | ₹{amount} · {category}. Approve or decline in Registrations. | `/org/{org_id}/t/{tournament_id}/registrations` | high |
| `org.partners_missing` | 48 h before the draw | Owner, admins | {n} players still need a partner | {category}. Pair them before you make the draw. | `/org/{org_id}/t/{tournament_id}/registrations` | normal |
| `org.checkin_progress` | Every 30 min during check-in | Owner, admins | {checked} of {total} checked in | Check-in closes at {time}. {missing} still to arrive. | `/org/{org_id}/t/{tournament_id}/check-in` | low |
| `org.court_idle` | A court idle 15 min | Owner, court managers | Court {court} has been idle 15 min | Next up: {teams}. Call them? | `/org/{org_id}/live` | high |
| `org.running_late` | Schedule 20+ min behind | Owner, admins | Running {minutes} minutes late | {courts} courts are behind. Players on later matches will be told. | `/org/{org_id}/t/{tournament_id}/schedule` | high |
| `org.official_declined` | Referee drops out | Owner, admins | {referee} dropped out | They can't officiate {when}. Find a replacement before {deadline}. | `/org/{org_id}/t/{tournament_id}/courts` | high |
| `org.completed` | Tournament completed | Owner, admins | {tournament} is a wrap | {matches} matches · {players} players. Results are published. | `/org/{org_id}/t/{tournament_id}` | normal |

### 4.12 Explore and SkorX

| Type | When | Who | Title | Body | Opens | P |
|---|---|---|---|---|---|---|
| `explore.weekend` | Friday 6 PM | Active players, city | This weekend in {city} | {tournaments} tournaments · {courts} open courts · {posts} games need players. | `/player/explore` | low |
| `explore.players_nearby` | New players at the same band join nearby | Player | {n} {band} players near you | New in {city} this week. Your next partner might be one of them. | `/player/explore/players` | low |
| `explore.new_venue` | Venue opens in the city | Players in city | New courts in {area} | {venue} · {courts} courts · from ₹{price} an hour. | `/player/venue/{id}` | low |
| `system.new_feature` | Feature ships | Everyone | New on SkorX: {feature} | {one_liner} | route of the feature | low |
| `system.maintenance` | Planned downtime | Everyone | SkorX takes a 20-minute break | {when}. Live scores keep saving on your phone and sync after. | — | normal |

## 5. What's built

| Piece | State |
|---|---|
| Copy for every type above | `backend/src/notifications/notification-copy.ts` (`notificationCopy.*`) |
| Looking For | Sends with `notificationCopy.lookingFor.*` |
| Other features | Call `notifications.notify(userId, notificationCopy.<area>.<event>({...}))` when their API lands. `looking_for.expiring` needs an expiry-warning job. |
| Copy rules | `notification-copy.spec.ts` renders every type with realistic names and fails on a title over 40, a body over 110, emoji, "!!", a missing route or an unknown prefix |
| App kinds and icons | `NotificationKind` covers every prefix: account, match, result, tournament, registration, booking, official, rating, achievement, community, lookingFor, subscription, organizer, explore, announcement |
| Push, bundling, caps, quiet hours, preferences | Not built (build step 7, with FCM). The rules in §3 are the spec. |
