# frozen_string_literal: true

module RailsWebhookLab
  # Preserve the bytes and values supplied by the caller, while ensuring that
  # one delivery cannot mutate the payload used for a later delivery.
  module Payload
    module_function

    def copy(value, freeze_result: false, active: {})
      case value
      when String
        result = value.dup
      when Array, Hash
        raise ArgumentError, "cyclic payloads are not supported" if active[value.object_id]

        active[value.object_id] = true
        begin
          result = if value.is_a?(Array)
            value.map { |item| copy(item, freeze_result: freeze_result, active: active) }
          else
            value.each_with_object({}) do |(key, item), hash|
              raise ArgumentError, "payload hash keys must be strings or symbols" unless key.is_a?(String) || key.is_a?(Symbol)

              hash[copy(key, freeze_result: freeze_result, active: active)] = copy(item, freeze_result: freeze_result, active: active)
            end
          end
        ensure
          active.delete(value.object_id)
        end
      when Symbol, Integer, Float, TrueClass, FalseClass, NilClass
        result = value
      else
        raise ArgumentError, "unsupported payload type: #{value.class}"
      end

      freeze_result ? result.freeze : result
    end
  end
end
