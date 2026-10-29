# frozen_string_literal: true

require "minitest/autorun"
require "rails_webhook_lab"

class RailsWebhookLabTest < Minitest::Test
  Scenario = RailsWebhookLab::Scenario
  Runner = RailsWebhookLab::Runner

  def test_duplicate_deliveries_retain_id_and_are_isolated_from_mutations
    original = { "id" => "evt_123", "body" => "\xFF\x00".b, "headers" => { "X-Test" => ["value"] } }
    scenario = Scenario.duplicate(original)
    original["id"] = "changed after scenario creation"
    observed = []
    reset_calls = 0

    result = Runner.run(scenario,
      reset: -> { reset_calls += 1 },
      deliver: lambda { |event|
        observed << [event["id"].dup, event["body"].dup, event["headers"]["X-Test"].dup]
        event["id"].replace("mutated")
        event["body"].clear
        event["headers"]["X-Test"] << "changed"
      },
      verify: ->(name) { assert_equal "duplicate delivery", name; true })

    assert_equal true, result
    assert_equal 1, reset_calls
    assert_equal [["evt_123", "\xFF\x00".b, ["value"]]] * 2, observed
  end

  def test_reversal_keeps_ids_and_dispatches_in_order
    scenario = Scenario.reverse([{ id: "evt_1" }, { id: "evt_2" }, { id: "evt_3" }])
    observed = []
    Runner.run(scenario, reset: -> { observed.clear }, deliver: ->(event) { observed << event[:id] },
      verify: ->(_name) { assert_equal %w[evt_3 evt_2 evt_1], observed; true })
  end

  def test_each_scenario_resets_before_delivering_and_verifying
    calls = []
    callbacks = {
      reset: -> { calls << :reset },
      deliver: ->(event) { calls << event },
      verify: ->(name) { calls << name; true }
    }
    Runner.run(Scenario.single("a"), **callbacks)
    Runner.run(Scenario.duplicate("b"), **callbacks)
    assert_equal [:reset, "a", "single delivery", :reset, "b", "b", "duplicate delivery"], calls
  end

  def test_custom_scenario_retains_caller_specified_sequence
    observed = []
    scenario = Scenario.new(name: "invoice before subscription", events: ["invoice", "subscription", "invoice"])
    Runner.run(scenario, reset: -> {}, deliver: ->(event) { observed << event },
      verify: ->(name) { assert_equal "invoice before subscription", name; true })
    assert_equal %w[invoice subscription invoice], observed
  end

  def test_reset_failure_stops_delivery_and_verification
    calls = []
    error = assert_raises(RailsWebhookLab::ScenarioError) do
      Runner.run(Scenario.single("event"), reset: -> { raise "reset failed" },
        deliver: ->(_event) { calls << :delivered }, verify: ->(_name) { calls << :verified; true })
    end
    assert_equal "reset", error.phase
    assert_match(/single delivery.*reset failed/, error.message)
    assert_instance_of RuntimeError, error.cause
    assert_empty calls
  end

  def test_delivery_error_reports_index_and_does_not_verify
    calls = []
    error = assert_raises(RailsWebhookLab::ScenarioError) do
      Runner.run(Scenario.duplicate("event"), reset: -> {},
        deliver: ->(_event) { calls << :delivered; raise IOError, "request failed" if calls.length == 2 },
        verify: ->(_name) { calls << :verified; true })
    end
    assert_equal "delivery 2", error.phase
    assert_equal "request failed", error.cause.message
    assert_equal [:delivered, :delivered], calls
  end

  def test_assertion_failures_are_not_masked
    error = assert_raises(Minitest::Assertion) do
      Runner.run(Scenario.single("event"), reset: -> {}, deliver: ->(_event) {},
        verify: ->(_name) { flunk "expected state mismatch" })
    end
    assert_match(/expected state mismatch/, error.message)
  end

  def test_verification_must_explicitly_return_true
    [nil, false, "yes"].each do |value|
      error = assert_raises(RailsWebhookLab::ScenarioError) do
        Runner.run(Scenario.single("event"), reset: -> {}, deliver: ->(_event) {}, verify: ->(_name) { value })
      end
      assert_equal "verification", error.phase
      assert_match(/must return true/, error.message)
    end
  end

  def test_scenario_rejects_invalid_or_empty_inputs
    assert_raises(ArgumentError) { Scenario.new(name: "", events: ["event"]) }
    assert_raises(ArgumentError) { Scenario.new(name: "test", events: []) }
    assert_raises(ArgumentError) { Scenario.duplicate("event", deliveries: 1) }
    assert_raises(ArgumentError) { Scenario.reverse(["only one"]) }
    assert_raises(ArgumentError) { Scenario.single(Object.new) }
    assert_raises(ArgumentError) { Scenario.single({ 1 => "bad key" }) }
    cyclic = []
    cyclic << cyclic
    assert_raises(ArgumentError) { Scenario.single(cyclic) }
  end

  def test_scenarios_expose_immutable_snapshots
    scenario = Scenario.single({ "data" => ["value"] })
    assert_raises(FrozenError) { scenario.events.first["data"] << "another" }
    assert_raises(FrozenError) { scenario.events.first["data"].first.replace("another") }
    assert_raises(FrozenError) { scenario.events << "another" }
  end

  def test_runner_rejects_missing_or_noncallable_callbacks
    assert_raises(ArgumentError) { Runner.run("not a scenario", reset: -> {}, deliver: ->(_e) {}, verify: ->(_n) { true }) }
    assert_raises(ArgumentError) { Runner.run(Scenario.single("event"), reset: nil, deliver: ->(_e) {}, verify: ->(_n) { true }) }
  end
end
