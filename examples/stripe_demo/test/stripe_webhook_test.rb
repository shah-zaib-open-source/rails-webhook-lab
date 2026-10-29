# frozen_string_literal: true

# This example is test-only. It uses fictional events, a public test-only secret,
# and an in-memory database. It is not a production payment implementation.
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require "json"
require "openssl"
require "stripe"
require_relative "../../../lib/rails_webhook_lab"

class StripeWebhookDemo < Rails::Application
  config.eager_load = false
  config.secret_key_base = "stripe-webhook-demo-only-key-base"
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.active_record.maintain_test_schema = false
end

Rails.application.initialize!
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
require "rails/test_help"

ActiveRecord::Schema.define do
  suppress_messages do
    create_table :stripe_demo_subscriptions, force: true do |table|
      table.string :external_id, null: false
      table.integer :credits, null: false, default: 0
      table.boolean :created_event_seen, null: false, default: false
      table.index :external_id, unique: true
    end
    create_table :stripe_demo_processed_events, force: true do |table|
      table.string :external_id, null: false
      table.index :external_id, unique: true
    end
  end
end

class StripeDemoSubscription < ActiveRecord::Base; end
class StripeDemoProcessedEvent < ActiveRecord::Base; end

class StripeDemoWebhooksController < ActionController::Base
  skip_forgery_protection
  TEST_SIGNING_SECRET = "whsec_example_test_only".freeze

  def naive
    event = verified_event
    return head :bad_request unless event

    object = event.data.object
    case event.type
    when "customer.subscription.created"
      StripeDemoSubscription.create!(external_id: object.id, created_event_seen: true)
    when "invoice.paid"
      subscription = StripeDemoSubscription.find_by(external_id: object.subscription)
      subscription&.increment!(:credits, 100)
    end
    head :ok
  end

  def sequential_example
    event = verified_event
    return head :bad_request unless event

    ActiveRecord::Base.transaction do
      unless StripeDemoProcessedEvent.exists?(external_id: event.id)
        object = event.data.object
        subscription_id = event.type == "invoice.paid" ? object.subscription : object.id
        subscription = StripeDemoSubscription.find_or_create_by!(external_id: subscription_id)
        case event.type
        when "customer.subscription.created"
          subscription.update!(created_event_seen: true)
        when "invoice.paid"
          subscription.increment!(:credits, 100)
        end
        StripeDemoProcessedEvent.create!(external_id: event.id)
      end
    end
    head :ok
  end

  private

  def verified_event
    Stripe::Webhook.construct_event(
      request.raw_post, request.headers["Stripe-Signature"], TEST_SIGNING_SECRET
    )
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    nil
  end
end

Rails.application.routes.draw do
  post "/webhooks/stripe/naive", to: "stripe_demo_webhooks#naive"
  post "/webhooks/stripe/sequential", to: "stripe_demo_webhooks#sequential_example"
end

class StripeWebhookTest < ActionDispatch::IntegrationTest
  SUBSCRIPTION = {
    id: "evt_subscription_demo", object: "event", api_version: "2024-10-28.acacia",
    livemode: false, type: "customer.subscription.created",
    data: { object: { id: "sub_demo", object: "subscription" } }
  }.freeze
  PAID = {
    id: "evt_invoice_demo", object: "event", api_version: "2024-10-28.acacia",
    livemode: false, type: "invoice.paid",
    data: { object: { id: "in_demo", object: "invoice", subscription: "sub_demo", paid: true } }
  }.freeze

  def signature_for(payload)
    timestamp = Time.now.to_i
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest("SHA256", StripeDemoWebhooksController::TEST_SIGNING_SECRET, signed_payload)
    "t=#{timestamp},v1=#{signature}"
  end

  def post_signed(path, payload, signature: signature_for(payload))
    post path, params: payload, headers: {
      "CONTENT_TYPE" => "application/json", "HTTP_STRIPE_SIGNATURE" => signature
    }
  end

  def reset_state
    StripeDemoProcessedEvent.delete_all
    StripeDemoSubscription.delete_all
  end

  def deliver_event(path, event)
    post_signed(path, event.to_json)
    assert_response :success
  end

  def assert_business_state
    subscription = StripeDemoSubscription.find_by!(external_id: "sub_demo")
    assert_equal 100, subscription.credits
    assert subscription.created_event_seen
    assert_equal 1, StripeDemoSubscription.count
    assert_equal 2, StripeDemoProcessedEvent.count
  end

  def run_scenario(scenario, path:)
    RailsWebhookLab::Runner.run(
      scenario,
      reset: -> { reset_state },
      deliver: ->(event) { deliver_event(path, event) },
      verify: ->(_name) {
        assert_business_state
        true
      }
    )
  end

  test "invalid signature rejects a modified request without processing it" do
    reset_state
    original = PAID.to_json
    modified = original.sub("evt_invoice_demo", "evt_tampered")
    post_signed "/webhooks/stripe/sequential", modified, signature: signature_for(original)
    assert_response :bad_request
    assert_equal 0, StripeDemoSubscription.count
    assert_equal 0, StripeDemoProcessedEvent.count
  end

  test "duplicate payment exposes the naive handler" do
    scenario = RailsWebhookLab::Scenario.new(name: "duplicate payment", events: [SUBSCRIPTION, PAID, PAID])
    error = assert_raises(Minitest::Assertion) { run_scenario(scenario, path: "/webhooks/stripe/naive") }
    assert_match(/Expected: 100.*Actual: 200/m, error.message)
  end

  test "reversed events expose the naive handler" do
    scenario = RailsWebhookLab::Scenario.reverse([SUBSCRIPTION, PAID])
    error = assert_raises(Minitest::Assertion) { run_scenario(scenario, path: "/webhooks/stripe/naive") }
    assert_match(/Expected: 100.*Actual: 0/m, error.message)
  end

  test "sequential example handles a duplicate payment event" do
    scenario = RailsWebhookLab::Scenario.new(name: "duplicate payment", events: [SUBSCRIPTION, PAID, PAID])
    run_scenario(scenario, path: "/webhooks/stripe/sequential")
  end

  test "sequential example handles reversed events" do
    scenario = RailsWebhookLab::Scenario.reverse([SUBSCRIPTION, PAID])
    run_scenario(scenario, path: "/webhooks/stripe/sequential")
  end

  test "plain Rails comparison handles duplicate delivery" do
    reset_state
    [SUBSCRIPTION, PAID, PAID].each { |event| deliver_event("/webhooks/stripe/sequential", event) }
    assert_business_state
  end

  test "plain Rails comparison handles reversed delivery" do
    reset_state
    [SUBSCRIPTION, PAID].reverse_each { |event| deliver_event("/webhooks/stripe/sequential", event) }
    assert_business_state
  end
end
