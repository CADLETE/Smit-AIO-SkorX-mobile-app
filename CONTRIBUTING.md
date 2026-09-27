# Contributing to SkorX

SkorX has one standing rule: **any competent developer should be able to understand the code without the original developer explaining it.** When two approaches both work, pick the one that is easier to read, test, debug and extend, and that matches what the codebase already does.

This file covers the Flutter app. The API and web TMS follow the same rules; see `CONTRIBUTING.md` in `smit-dev-skorx-frontend`.

## Before you write code

1. Find the owning module in [docs/MODULES.md](docs/MODULES.md). If a feature has no row, add one before you add the feature.
2. Read the feature's spec (`docs/<FEATURE>.md`) and the existing code in its folder.
3. Search for similar logic (`grep` the domain word). Reuse it; don't write a second version.
4. List what the change touches: API endpoints, tables, permissions, other features that read the same data.
5. Decide which tests prove it works, and which existing tests could break.

## Where code goes

| Kind of code | Location | Rule |
|---|---|---|
| Screens, widgets | `lib/features/<f>/ui/` | UI only. No `ApiClient`, no `SharedPreferences`, no business rules. |
| Models, repositories, controllers | `lib/features/<f>/data/` | Repository = data access (API or sample). Controller/notifier = state + rules. |
| Scoring and match rules | `lib/sports/` | One engine per sport. Never `if (sport == pickleball)` in a screen. |
| API client, tokens, sync plumbing | `lib/core/` | Shared by every feature; no feature-specific logic. |
| Reusable visual components | `lib/design/`, `lib/shared/ui/` | No feature imports from here. |
| Routes | `lib/app/routing/router.dart` | Re-read before editing; other work edits it concurrently. |

Each repository has an abstract interface, an API implementation and (for debug builds) a sample implementation, selected in one provider. Follow that shape for new data sources.

## Rules that are easy to break

- **Casual matches count only when verified.** Stats, rating, rankings and achievements must read matches through `Match.isOfficial` / `PlayerRecord` (server: `officialMatchWhere`). See [docs/CASUAL-VERIFICATION.md](docs/CASUAL-VERIFICATION.md).
- **Every casual match change goes through the ledger.** Use `ScoringController` / `PlayedMatchesController.record`; never write match data to preferences directly. See [docs/OFFLINE-SCORING.md](docs/OFFLINE-SCORING.md).
- **The server is authoritative.** Hiding a button is a convenience, not security. Every permission must also be checked by the API.
- **Community and Looking For live inside Explore.** Don't add bottom tabs for Explore-type features.

## Style

- Names say what the thing does: `submitCasualResult`, not `handleData`.
- A file does one job. If a screen grows past roughly 800 lines, split out widgets or move logic into `data/`. Don't split working files only for style.
- Comments explain **why**: a scoring rule, a sync edge case, a permission decision. Don't narrate the code.
- No silent `catch (_) {}`. Either handle the error, show a message, or log it with `debugPrint` and a reason why it is safe to continue.
- No secrets in the app. Build-time values go through `--dart-define` (see README); anything in the APK is public.
- Prefer plain Riverpod providers and simple state. Add a package only when it removes real work, and note why in the PR.

## Changing existing code

- Understand it first, then make the smallest safe change. Keep behaviour unchanged unless changing it is the task.
- Refactor only what you need to touch. Explain any larger restructure in the PR description.
- Every bug fix gets a regression test where practical.

## Tests

- `flutter test` must pass before you push.
- Business logic (scoring, rating, verification, sync, draws) gets unit tests that don't depend on widgets.
- Shared scoring behaviour goes into `test/fixtures/scoring_vectors.json` so the app and the server check the same cases.
- Widget tests must not touch real files or the network; gate those on `FLUTTER_TEST`.

## Before you call a change done

- Can someone new follow it? Are the names clear?
- Is it in the right module, with no duplicated logic?
- Does the server enforce every permission it relies on?
- What happens offline, on a double tap, on a 401/409/500, and with bad input?
- Are the important paths tested?
- Is `docs/MODULES.md` (and the feature spec) still accurate?
