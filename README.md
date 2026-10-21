# TheFaithApp Giving for Flutter

`thefaithapp_giving` renders authenticated general-giving and campaign-giving
flows backed by TheFaithApp. It includes the amount, fund, currency, recurring,
fee-covering, and memo UI, then presents the church's configured default
payment method.

The package currently includes handlers for:

- Stripe PaymentSheet
- PayPal hosted checkout
- Flutterwave hosted checkout

The shared checkout engine and `GivingPaymentHandler` interface allow another
payment method to be added without duplicating the general and campaign forms.

## Install

```yaml
dependencies:
  thefaithapp_auth: ^0.1.0
  thefaithapp_giving: ^0.1.0
```

Follow the native setup required by `flutter_stripe` and
`webview_flutter` for the platforms your application supports.

## Authenticate first

Giving requires a valid member session from `thefaithapp_auth`:

```dart
final auth = TheFaithAppAuth(apiKey: 'your-client-key');
await auth.signIn();

final giving = TheFaithAppGiving(auth: auth);
```

The giving package never accepts or sends a `member_id` or `client_id`. It uses
the auth package's origin-restricted authorized client. The API resolves the
member and church from the bearer token and client key, then scopes every fund,
campaign, checkout, capture, verification, and status request to that identity.

## Handle access failures

The expanded error categories and fields below are an **unreleased repository
update**. They are not yet a new pub.dev release; the package version remains
unchanged in this change.

A valid sign-in does not guarantee that the church's plan includes SDK access.
Handle `GivingException.code` according to the failure:

| Code | Meaning | Next step |
| --- | --- | --- |
| `GivingErrorCode.notAuthenticated` | No usable member session, or HTTP 401 | Follow your app's sign-in recovery path. |
| `GivingErrorCode.planAccessDenied` | HTTP 403 with a recognized plan denial | Ask the church administrator to review plan access. Signing in again does not change the plan. |
| `GivingErrorCode.forbidden` | Another HTTP 403 permission denial | Check the permitted resource/action with the church; do not assume the member needs to sign in again. |

`statusCode` retains the HTTP status. `serverErrorCode` retains a valid bounded
machine code, including `plan_product_unavailable` or
`plan_entitlement_required`. For those plan denials, optional `planAccess`
contains only typed identifiers: `type`, `product` or `entitlement`,
`currentPlan`, and `recommendedPlan`. Missing or malformed context is omitted;
it does not prevent recognizing a plan denial. No raw response or credentials
are retained in these fields.

When updating to this change, add the new cases to exhaustive
`GivingErrorCode` switches. The built-in view reports the error through
`onError` and displays its message; it does not sign the member out.

## General giving

```dart
GivingView.general(
  giving: giving,
  onCompleted: (result) {
    if (result.isSuccessful) {
      // The platform has confirmed the provider payment.
    }
  },
)
```

For giving launched from a prayer room, pass `prayerRoomId`. The platform
validates that the room belongs to the signed-in member's church and permits
giving.

## Campaign giving

```dart
GivingView.campaign(
  giving: giving,
  campaignId: 42,
  onCompleted: (result) {
    // Handle succeeded, pending, cancelled, or failed state.
  },
)
```

If the campaign has additional donor fields, the built-in view renders them,
validates required values, and includes the responses in the authenticated
checkout. Text, multiline text, number, email, telephone, select, radio,
checkbox, and date fields are supported. Headless/custom UIs can submit the
same data through `CampaignGivingRequest.formFields`.

Both views intentionally use the church's active/default method. Payment
methods have different account, currency, recurrence, and presentation rules,
so the platform owns method selection and configuration.

## Manage recurring gifts

Recurring general and campaign gifts use the same authenticated SDK:

```dart
final subscriptions = await giving.getSubscriptions();
final gift = subscriptions.first;

await giving.cancelSubscription(gift);
```

Each `GivingSubscription` includes its general or campaign target, so numeric
IDs from the two donation tables can never be confused. Cancellation is
rechecked against the signed-in member, church, and campaign by the platform.

## Add a payment method

Register a handler whose `provider` matches the value returned by the giving
configuration endpoint:

```dart
final giving = TheFaithAppGiving(
  auth: auth,
  paymentHandlers: [MyPaymentHandler()],
);
```

A handler receives a checkout-scoped `GivingCheckoutContext`. It can present
native UI or a hosted flow, then ask the platform for authoritative status.
It does not receive the member ID, client ID, bearer token, or API key. Never
log or persist checkout secrets from `GivingCheckoutSession`. New handlers can
read provider-specific response fields from `session.providerData` while the
shared typed fields remain stable. A handler must return the provider and
donation ID from its checkout session; the SDK rejects mismatched results and
reports the real checkout as abandoned.

## Payment security

- The platform creates amounts, destinations, references, and provider
  sessions after validating church-owned funds and campaigns.
- Checkout status is scoped to the authenticated member and church.
- Returning from PaymentSheet or a WebView is not treated as proof of payment.
- One-time Stripe gifts do not request future-use consent or save the payment
  method for off-session charges. Recurring gifts explicitly request it.
- If a failed Stripe attempt is followed by closing PaymentSheet, the SDK
  preserves the webhook-authoritative failed result instead of reporting a
  misleading cancellation.
- Closing a payment view reports the checkout as abandoned. The platform keeps
  a short webhook grace period, then cancels it; silent app terminations are
  covered by the checkout's server-side expiry.
- Hosted callbacks require HTTPS in production, the exact TheFaithApp API
  origin, the exact callback path, and the matching donation ID. Plain HTTP is
  accepted only for exact loopback origins during local development.
- The backend verifies stored provider IDs, amount, currency, and provider
  metadata. Webhooks remain the final authority and stay entirely on the
  platform.

Call `giving.dispose()` when the SDK is no longer needed. The application owns
the auth instance and should dispose it separately.

## Run the example

```shell
cd example
flutter run \
  --dart-define=THEFAITHAPP_API_KEY=your-client-key \
  --dart-define=THEFAITHAPP_CAMPAIGN_ID=42
```

Omit `THEFAITHAPP_CAMPAIGN_ID` to show only general giving. The example never
contains an API key, member identity, provider secret, or webhook secret in
source control.

## License

TheFaithApp Giving is available under the [MIT License](LICENSE).
