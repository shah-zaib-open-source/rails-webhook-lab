# frozen_string_literal: true

module RailsWebhookLab
  class Scenario
    attr_reader :name, :events

    def initialize(name:, events:)
      raise ArgumentError, "scenario name must be a non-empty string" unless name.is_a?(String) && !name.strip.empty?
      raise ArgumentError, "scenario events must be a non-empty array" unless events.is_a?(Array) && !events.empty?

      @name = name.dup.freeze
      @events = Payload.copy(events, freeze_result: true)
      freeze
    end

    def self.single(event, name: "single delivery")
      new(name: name, events: [event])
    end

    def self.duplicate(event, deliveries: 2, name: "duplicate delivery")
      raise ArgumentError, "deliveries must be an integer of at least 2" unless deliveries.is_a?(Integer) && deliveries >= 2

      new(name: name, events: Array.new(deliveries, event))
    end

    def self.reverse(events, name: "reverse order")
      raise ArgumentError, "reverse order requires at least 2 events" unless events.is_a?(Array) && events.length >= 2

      new(name: name, events: events.reverse)
    end
  end
end
