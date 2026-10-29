# Rails Webhook Lab

Small, test-only Ruby helpers for exercising duplicate and out-of-order webhook deliveries in a Rails application's own test suite.

Webhook providers can deliver events more than once or in a different order than they were generated. For example, [Stripe documents both behaviors](https://docs.stripe.com/webhooks#event-ordering), and Rails developers have reported problems when a payment event arrives before a subscription event in [Pay's issue tracker](https://github.com/pay-rails/pay/discussions/1203). A successful HTTP response alone does not prove that your application recorded the right result.

Rails Webhook Lab helps you run a scenario and check the result that matters to your application. It does not implement a webhook endpoint, verify signatures, contact a provider, or make processing safe by itself. Your test supplies the reset, delivery, and verification callbacks.

## Try the example

The [Rails demo](examples/rails_demo/README.md) uses real Rails endpoints and an in-memory database with synthetic events. It shows a naive handler failing on duplicate and reversed deliveries, and a second example passing those particular sequential cases. The demo is illustrative, not production payment code; it does not verify signatures or address concurrent delivery.

## Use in your tests

This project has not yet been published to RubyGems. To try a local checkout, build and install the gem:

```sh
gem build rails-webhook-lab.gemspec
gem install --local rails-webhook-lab-0.1.0.gem
```

For a Rails project, you can instead add the checkout to your test group in your Gemfile:

```ruby
group :test do
  gem "rails-webhook-lab", path: "../rails-webhook-lab"
end
```

In an `ActionDispatch::IntegrationTest`, define synthetic events and the state your application should produce. The endpoint, payload format, reset and lookup methods below are placeholders that you must adapt to your application:

```ruby
require "rails_webhook_lab"

created = { id: "evt_created", type: "subscription.created", subscription_id: "sub_demo" }
paid = { id: "evt_paid", type: "invoice.paid", subscription_id: "sub_demo" }

scenarios = [
  RailsWebhookLab::Scenario.new(name: "duplicate payment", events: [created, paid, paid]),
  RailsWebhookLab::Scenario.reverse([created, paid])
]

scenarios.each do |scenario|
  RailsWebhookLab::Runner.run(
    scenario,
    reset: -> { reset_webhook_test_state },
    deliver: ->(event) {
      post "/webhooks/example", params: event.to_json,
        headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :success
    },
    verify: ->(name) {
      assert_equal 100, credits_for("sub_demo"), name
      true
    }
  )
end
```

Use a test database and synthetic data. `reset` runs once before each scenario; the library cannot ensure that your callback actually clears all relevant state. `deliver` runs once per event, sequentially, and must supply any request headers and test signatures your endpoint requires. `verify` runs after all deliveries, must check the expected business outcome, and must return `true` on success. Test assertions propagate; other callback errors are wrapped in a `RailsWebhookLab::ScenarioError` with the scenario and phase, retaining the original cause.

Additional scenario constructors are `Scenario.single(event)` and `Scenario.duplicate(event, deliveries: 2)`. Construct `Scenario.new(name:, events:)` for a custom sequence. Payloads use JSON-like values, with string or symbol keys; the library snapshots them and gives each delivery its own copy.

## Development

The library requires Ruby 3.1 or later and has no runtime gem dependencies. Its tests have been run with Ruby 3.3, 3.4, and 4.0. The Rails demo has been run with Rails 8.1 and Ruby 4.0.

```sh
ruby -Ilib test/rails_webhook_lab_test.rb
```

## License

[MIT](LICENSE).
