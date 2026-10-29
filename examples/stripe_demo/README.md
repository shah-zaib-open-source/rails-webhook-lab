# Signed Stripe-style webhook demo

This standalone Rails integration test uses the Stripe Ruby SDK to verify signed
requests containing synthetic Stripe-shaped events. It uses a hard-coded
**test-only** signing secret and an in-memory SQLite database; no Stripe account,
network access, real payment data, or production credentials are needed to run
the tests after installing the dependencies.

```sh
bundle install
bundle exec ruby test/stripe_webhook_test.rb
```

The test sends each request to a local Rails controller. It checks that altered,
invalidly signed requests are rejected without changing database state. It then
runs duplicate payment and reversed subscription/payment scenarios against two
example handlers: a naive handler fails the business-state assertions, while a
second handler passes these specific sequential cases.

The shortened fixtures use the Stripe v1 snapshot-event shape and the invoice
`subscription` field from API version `2024-10-28.acacia`; later API versions
may have different fields. Adapt the fixture and handler to your endpoint's
actual event version. The test-signing helper signs the same raw
JSON bytes sent to the controller, which verifies them with
`Stripe::Webhook.construct_event`. It does not contact Stripe or test the Stripe
CLI. The credit amount is an arbitrary demo invariant, not billing logic. These
handlers are not production payment code: the example does not model concurrent
requests, external API lookups, background jobs, failures between side effects,
or every way duplicate or reordered events can occur.

## What the library adds

The test file includes both `run_scenario` examples and two `plain Rails
comparison` tests. Both use the same fixtures, request helper, database reset,
and business assertions. The plain tests loop over an array and are shorter for
these two cases. Rails Webhook Lab adds named, reusable scenarios, snapshots,
per-delivery payload copies, and context for callback errors. It does not write
the reset, signed requests, or business assertions for you. This comparison has
not established that the library saves time in a real application.
