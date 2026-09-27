# SkorX Pro: player subscriptions and billing

Status as of 27 Sep 2026. The pricing source is page 2 ("For Players") of the SkorX 2026 pricing document:

| Plan | Price | Includes |
|---|---|---|
| Free | ₹0, forever | Live Match Scoring · Match & Tournament History on My Paddle · Court Booking · Achievements |
| Pro monthly | ₹99 + GST / month | Everything in Free, plus Live Streaming of Casual Matches · Rival Player Stats & Match History · Match Analytics · Leaderboards · Local Rankings |
| Pro annual | ₹999 + GST / year (saves ₹189) | Same as monthly |

Prices exclude GST. GST is `GST_RATE` on the server (default 0.18) and is charged on the price **after** any coupon, the same rule the TMS checkout already used.

## Where it lives

| Layer | Code |
|---|---|
| Server (source of truth) | `smit-dev-skorx-frontend/backend/src/subscriptions/` (plans, entitlement rules, service, guard, controllers), plus the shared commerce pipeline in `src/commerce/` (orders, coupons, Razorpay gateway, `markPaid`) and the webhook in `src/payments/`. |
| App | `lib/features/subscription/`: `data/` (plans, models, API repository, the Test Mode stand-in), `subscription_controller.dart` (the global state), `ui/` (plans, checkout, results, subscription, billing, invoice, Pro badges and gates). |

## How access is decided

- Every account is **Free** until it has a paid period that covers now. There is no plan column to get out of step.
- A Pro purchase is one `Order` (the payment and invoice record) with one `PlayerSubscription` period (`pending → active / cancelled / expired / payment_failed`).
- `entitlementsAt(periods, now)` on the server gives each feature `true/false`. `EntitlementGuard` with `@RequiresFeature('LEADERBOARD')` protects Pro API routes and returns 403 `PRO_REQUIRED`.
- In the app, `subscriptionProvider` holds the server's answer. Screens use `isProProvider`, `canAccessProvider(ProFeature.x)`, `ProGate`, `ProButton`, `whenPro` and `showProUpsell`, and never work access out themselves. The provider reloads on sign-in changes, when the app resumes, and when the running period ends.

### Where the gates are

| Feature | Screens |
|---|---|
| Match Analytics | Match result charts (after scoring), live match momentum / game flow / head-to-head, my trend and splits on My stats |
| Rival Player Stats | Another player's full stats page, head-to-head page, Quick View "View full stats" and head-to-head, Rivals on My stats |
| Leaderboards | The leaderboard list on Rankings |
| Local Rankings | Scope tiles on Rankings, the ranking section on My Paddle, the city rank on the Account ID card |
| Casual Live Streaming | The video on a live **casual** match (tournament streams stay free) |

Locked features stay visible, marked PRO. Tapping one opens the upgrade prompt.

## Payment flow

```text
Plans → Checkout (plan + coupon)
  → POST /me/subscription/quote          server price: plan, coupon, GST, total
  → POST /me/subscription/checkout       Order + pending period + Razorpay order
  → Razorpay Checkout (or Test Mode sheet → POST …/:orderId/simulate)
  → POST …/:orderId/verify               HMAC signature check (+ Razorpay payment lookup with live keys)
  → OrdersService.markPaid               row lock · activate period · invoice SKX-INV-YYYY-00001
  → app applies the returned summary     Pro everywhere, no sign-out
```

- A failed or closed checkout goes to `POST …/:orderId/fail`. It never touches a paid order.
- The webhook `payment.captured` runs the same `markPaid`, so a player who pays and closes the app still gets Pro exactly once. `GET /me/subscription` also asks Razorpay about pending orders (live keys) and closes checkouts left unpaid for 24 hours.
- A lost connection after paying shows "Confirming your payment" with "Check again". Pro is never shown on the app's word alone.
- Buying while Pro is running (renewing early, or switching monthly ↔ annual) queues the new period to start when the current one ends. Only one queued period is allowed.
- Turning auto-renew off is "cancel at period end": Pro stays until the paid period ends.

## APIs

| Method | Path | |
|---|---|---|
| GET | `/subscriptions/plans` | public price list and features |
| GET | `/me/subscription` | plan, status, dates, auto-renew, entitlements |
| GET | `/me/subscription/entitlements[/:feature]` | the map, or 200/403 for one feature |
| POST | `/me/subscription/quote` | `{planId, couponCode?}` → price breakdown or 422 `COUPON_INVALID` |
| POST | `/me/subscription/checkout` | creates the order |
| POST | `/me/subscription/checkout/:orderId/verify` | Razorpay response → verified summary + billing row |
| POST | `/me/subscription/checkout/:orderId/fail` | `{status: failed\|cancelled, reason?}` |
| POST | `/me/subscription/checkout/:orderId/simulate` | Test Mode only |
| PATCH | `/me/subscription/auto-renew` | `{autoRenew}` |
| POST | `/me/subscription/cancel` | auto-renew off |
| POST | `/me/subscription/dev/renew`, `/dev/expire` | Test Mode, non-production only |
| GET | `/me/billing`, `/me/billing/:orderId/invoice` | history and invoice |
| GET | `/subscriptions/admin/records` | every period with its order and payment (`PLATFORM_ADMIN_EMAILS`) |
| POST | `/webhooks/razorpay` | also handles `subscription.activated/charged/cancelled/completed/halted` |

## Testing it (no database editing)

Debug builds bill through `DevBillingRepository`, an on-phone stand-in for the server that uses the same rules, prices, coupons and messages. It keeps state per account on the phone, so Pro survives a restart. With `--dart-define=REAL_AUTH=true` the app uses the API instead, and the API runs Razorpay Test Mode while `RAZORPAY_KEY_ID`/`SECRET` are unset or placeholders.

**Test coupons** (development only, never offered with `NODE_ENV=production`): `SKORX50` ₹50 off · `PRO10` 10% (max ₹150) · `WELCOME` ₹100, once per player · `ANNUAL200` annual only · `MONTHLY20` monthly only · `EXPIRED10` expired · `SOLDOUT` used up. Any other code is invalid.

**Test Mode tools** are on Profile › Subscription: *Simulate renewal* and *Expire Pro now*.

Automated tests: `test/features/subscription_test.dart` in the app, and `src/subscriptions/player-plans.spec.ts` in the backend.

## Test Mode → Live

1. Server: set `RAZORPAY_KEY_ID=rzp_live_…`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET` and `NODE_ENV=production`. The gateway switches itself: real orders, a real payment lookup on verify, and simulate/dev routes return 404. Configure the webhook in the Razorpay dashboard to `/api/v1/webhooks/razorpay` with the `payment.*` and `subscription.*` events.
2. Set your production coupons in `SKORX_COUPONS` (the test list is off in production anyway). Fill `SKORX_LEGAL_NAME`, `SKORX_GSTIN` and `SKORX_ADDRESS` for invoices.
3. App: add `razorpay_flutter` and override `livePaymentGatewayProvider` with a `PaymentGateway` that opens Checkout with `session.keyId`, `session.razorpayOrderId`, `session.amountPaise` and the prefill, and returns `GatewayPaid(GatewayPayment(...))`, `GatewayFailed` or `GatewayDismissed`. Nothing else in the app changes, because the gateway is chosen per order from `session.testMode`. Until this step, a live order is refused in the app rather than half-paid.
4. Build the release with `API_BASE_URL` pointing at the live API. Release builds already use the API.

## Still to do for production

- Run the first Prisma migration against a real database (`npx prisma migrate dev --name init`). The schema has never been migrated in this environment. This change adds `player_subscriptions`, `orders.invoicePdfUrl`, the `player_subscription` product type and the `(series, year)` key on `invoice_sequences`.
- The Razorpay SDK adapter in the app (step 3 above).
- True auto-renewal: create Razorpay Plans and Subscriptions (store `razorpayCustomerId` and `razorpaySubscriptionId`). The webhook handlers for `subscription.*` are ready, but nothing creates the Razorpay subscription yet, so renewals are simulated only in Test Mode.
- PDF invoices (`orders.invoicePdfUrl`). The app shares the invoice as an image for now.
- Server routes for leaderboards, rival stats and analytics should carry `@RequiresFeature(...)` when they are built. Today that data is sample data in the app.
- Keep the Next.js mirror of `coupons.ts` in step if the web checkout should know the new `appliesTo` / `perUserLimit` fields.
