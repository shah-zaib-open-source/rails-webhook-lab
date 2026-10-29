# frozen_string_literal: true

# This standalone integration test uses only a temporary in-memory database and
# synthetic events. The handlers illustrate the failure mode, not a complete
# payment integration: no real provider signature or concurrency is modeled.
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3::memory:"

require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require "json"
require_relative "../../../lib/rails_webhook_lab"

class WebhookDemo < Rails::Application
  config.eager_load = false
  config.secret_key_base = "demo-only-secret-key-base"
  config.hosts.clear
  config.logger = Logger.new(File::NULL)
  config.active_record.maintain_test_schema = false
end

Rails.application.initialize!
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
require "rails/test_help"

ActiveRecord::Schema.define do
  suppress_messages do
    create_table :demo_subscriptions, force: true do |table|
      table.string :external_id, null: false
      table.integer :credits, null: false, default: 0
      table.boolean :created_event_seen, null: false, default: false
      table.index :external_id, unique: true
    end
    create_table :demo_processed_events, force: true do |table|
      table.string :external_id, null: false
      table.index :external_id, unique: true
    end
  end
end

class DemoSubscription < ActiveRecord::Base; end
class DemoProcessedEvent < ActiveRecord::Base; end

class DemoWebhooksController < ActionController::Base
  skip_forgery_protection

  def naive
    case params[:type]
    when "subscription.created"
      DemoSubscription.create!(external_id: params[:subscription_id], created_event_seen: true)
    when "invoice.paid"
      subscription = DemoSubscription.find_by(external_id: params[:subscription_id])
      subscription&.increment!(:credits, 100)
    end
    head :ok
  end

  def resilient
    ActiveRecord::Base.transaction do
      unless DemoProcessedEvent.exists?(external_id: params[:id])
        subscription = DemoSubscription.find_or_create_by!(external_id: params[:subscription_id])
        case params[:type]
        when "subscription.created"
          subscription.update!(created_event_seen: true)
        when "invoice.paid"
          subscription.increment!(:credits, 100)
        end
        DemoProcessedEvent.create!(external_id: params[:id])
      end
    end
    head :ok
  end
end

Rails.application.routes.draw do
  post "/webhooks/naive", to: "demo_webhooks#naive"
  post "/webhooks/resilient", to: "demo_webhooks#resilient"
end

class WebhookDeliveryTest < ActionDispatch::IntegrationTest
  SUBSCRIPTION = { id: "evt_created", type: "subscription.created", subscription_id: "sub_demo" }.freeze
  PAID = { id: "evt_paid", type: "invoice.paid", subscription_id: "sub_demo" }.freeze

  def run_scenario(scenario, path:, with_subscription: false)
    reset = lambda do
      DemoProcessedEvent.delete_all
      DemoSubscription.delete_all
      DemoSubscription.create!(external_id: "sub_demo", created_event_seen: true) if with_subscription
    end
    deliver = lambda do |event|
      post path, params: event.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      assert_response :success
    end
    verify = lambda do |_scenario_name|
      subscription = DemoSubscription.find_by!(external_id: "sub_demo")
      assert_equal 100, subscription.credits
      assert subscription.created_event_seen
      true
    end
    RailsWebhookLab::Runner.run(scenario, reset: reset, deliver: deliver, verify: verify)
  end

  test "duplicate-delivery scenario catches the naive handler" do
    error = assert_raises(Minitest::Assertion) do
      run_scenario(RailsWebhookLab::Scenario.duplicate(PAID), path: "/webhooks/naive", with_subscription: true)
    end
    assert_match(/Expected: 100.*Actual: 200/m, error.message)
  end

  test "out-of-order scenario catches the naive handler" do
    error = assert_raises(Minitest::Assertion) do
      run_scenario(RailsWebhookLab::Scenario.reverse([SUBSCRIPTION, PAID]), path: "/webhooks/naive")
    end
    assert_match(/Expected: 100.*Actual: 0/m, error.message)
  end

  test "example resilient handler passes duplicate delivery" do
    run_scenario(RailsWebhookLab::Scenario.duplicate(PAID), path: "/webhooks/resilient", with_subscription: true)
  end

  test "example resilient handler passes out-of-order delivery" do
    run_scenario(RailsWebhookLab::Scenario.reverse([SUBSCRIPTION, PAID]), path: "/webhooks/resilient")
  end
end
