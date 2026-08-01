# frozen_string_literal: true

require "logger"

require_relative "telemetry/version"
require_relative "telemetry/configuration"
require_relative "telemetry/span"
require_relative "telemetry/trace"
require_relative "telemetry/reporter"

# Shared core for reporting LLM traces to ActiveAgents.
#
# This gem carries no integration of its own — it owns the wire format, the
# configuration, and delivery. Install an adapter for whatever your app calls
# the model through:
#
#   gem "activeagents-telemetry-ruby_llm"   # apps built on RubyLLM
#
# Configure the destination once and every adapter inherits it:
#
#   ActiveAgents::Telemetry.configure do |config|
#     config.api_key      = ENV["ACTIVEAGENTS_API_KEY"]
#     config.service_name = "my-app"
#   end
module ActiveAgents
  module Telemetry
    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration) if block_given?
        configuration
      end

      # Replaces configuration wholesale; mostly useful in tests.
      attr_writer :configuration

      def reset!
        @configuration = Configuration.new
        @reporter = nil
      end

      def reporter
        @reporter ||= Reporter.new(configuration)
      end

      attr_writer :reporter

      def enabled?
        configuration.configured?
      end
    end
  end
end
