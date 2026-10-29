# frozen_string_literal: true

module RailsWebhookLab
  class ScenarioError < StandardError
    attr_reader :scenario_name, :phase

    def initialize(scenario_name, phase, detail)
      @scenario_name = scenario_name
      @phase = phase
      super("#{scenario_name} (#{phase}): #{detail}")
    end
  end

  class Runner
    # No transport, reset, or assertions are implicit. These callbacks are all
    # supplied by the caller; execution is synchronous and sequential.
    def self.run(scenario, reset:, deliver:, verify:)
      raise ArgumentError, "scenario must be a RailsWebhookLab::Scenario" unless scenario.is_a?(Scenario)
      { reset: reset, deliver: deliver, verify: verify }.each do |name, callback|
        raise ArgumentError, "#{name} must respond to call" unless callback.respond_to?(:call)
      end

      call_phase(scenario, "reset") { reset.call }
      scenario.events.each_with_index do |event, index|
        call_phase(scenario, "delivery #{index + 1}") { deliver.call(Payload.copy(event)) }
      end

      verified = call_phase(scenario, "verification") { verify.call(scenario.name) }
      unless verified == true
        raise ScenarioError.new(scenario.name, "verification", "verify must return true after checking the expected outcome")
      end

      true
    end

    def self.call_phase(scenario, phase)
      yield
    rescue StandardError => error
      raise ScenarioError.new(scenario.name, phase, "#{error.class}: #{error.message}"), cause: error
    end
    private_class_method :call_phase
  end
end
