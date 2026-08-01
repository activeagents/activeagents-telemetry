# frozen_string_literal: true

require "minitest/autorun"
require "activeagents/telemetry"

module TelemetryTestHelpers
  def fresh_configuration(**overrides)
    config = ActiveAgents::Telemetry::Configuration.new
    config.api_key = "test-key"
    config.service_name = "test-app"
    config.environment = "test"
    config.async = false
    overrides.each { |key, value| config.public_send("#{key}=", value) }
    config
  end

  # A reporter that captures payloads instead of delivering them.
  def capturing_reporter(configuration = fresh_configuration)
    reporter = ActiveAgents::Telemetry::Reporter.new(configuration)
    captured = []
    reporter.define_singleton_method(:deliver) { |body| captured << body }
    [ reporter, captured ]
  end

  def build_trace(service_name: "test-app")
    trace = ActiveAgents::Telemetry::Trace.new(service_name: service_name, environment: "test")
    root = trace.span("Agent.action", type: "root")
    root.finish
    trace
  end
end
