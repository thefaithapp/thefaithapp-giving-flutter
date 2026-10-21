# Changelog

## Unreleased

- Distinguish expired sign-in, plan-access denial and other forbidden requests.
- Expose allowlisted server error and plan identifiers without retaining raw
  response data. Add the new error categories to exhaustive error handlers.

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
