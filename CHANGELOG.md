# Changelog

## Unreleased

- Show recurring choices only when the server enables them; otherwise submit one-time gifts.
- Reject payment status responses for a different donation or provider.
- Load giving configuration and fund or campaign details concurrently.
- Keep fund, currency, and frequency selectors within narrow phone screens.
- Label the hosted checkout close button for assistive technology.

## 0.2.0

- Distinguish expired sign-in, plan-access denial and other forbidden requests.
- Expose allowlisted server error and plan identifiers without retaining raw
  response data. Add the new error categories to exhaustive error handlers.
- Decoded API errors with HTTP 403 no longer map to `notAuthenticated`: recognized plan denials use
  `planAccessDenied`, and other permission denials use `forbidden`. Keep sign-in
  recovery for missing sessions and HTTP 401.
- Expose `GivingCheckoutSession.paypalSubscriptionId` for PayPal recurring
  checkout responses.

### Migration from 0.1.0

- Update the giving dependency to `^0.2.0`.
- Add `GivingErrorCode.planAccessDenied` and `GivingErrorCode.forbidden` to
  exhaustive switches. Signing in again does not resolve a plan denial.
- Treat `serverErrorCode`, `planAccess` and the PayPal subscription ID as optional;
  do not assume every error or provider response includes them.

## 0.1.0

- Add authenticated general and campaign giving views.
- Add extensible Stripe, PayPal, and Flutterwave payment handlers.
- Add webhook-authoritative payment status polling.
- Add fund splitting, currencies, recurring frequency, memo, and fee-covering controls.
- Support exact loopback hosted-payment callbacks during local development.
- Render rich-text campaign descriptions as readable plain text in the built-in view.
- Report abandoned payment views and rely on server-side expiry cleanup for
  app crashes or offline cancellation callbacks.
- Request Stripe off-session payment-method saving only for recurring gifts.
- Preserve provider-confirmed failures when PaymentSheet is subsequently closed.
- List and securely cancel recurring general and campaign gifts.
- Persist campaign-gift memos and provider attribution.
- Render configured campaign donor fields and submit validated responses with
  cash-gift checkouts.
- Reject checkout sessions and extension-handler results whose provider or
  donation identity does not match the active checkout.
- Complete seller-scoped PayPal Partner Subscription approvals for recurring
  general and campaign gifts.
