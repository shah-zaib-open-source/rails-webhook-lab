# frozen_string_literal: true

require_relative "lib/rails_webhook_lab/version"

Gem::Specification.new do |spec|
  spec.name = "rails-webhook-lab"
  spec.version = RailsWebhookLab::VERSION
  spec.authors = ["Shah Zaib"]
  spec.homepage = "https://github.com/shah-zaib-open-source/rails-webhook-lab"
  spec.summary = "Test webhook delivery scenarios in Ruby and Rails applications"
  spec.description = "Small, test-only helpers for exercising duplicate and reordered webhook deliveries."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"
  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"].sort
  spec.require_paths = ["lib"]
end
