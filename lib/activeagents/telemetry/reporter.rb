# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module ActiveAgents
  module Telemetry
    # Delivers traces to the configured endpoint.
    #
    # Telemetry is never worth breaking an app over, so every failure path here
    # ends in a log line: a bad endpoint, a down collector, a serialization bug
    # in an adapter, and a nil api_key all degrade to "no traces" rather than an
    # exception in the caller's request cycle.
    #
    # Delivery is fire-and-forget on a thread by default. Pass `async: false`
    # for tests, or for scripts short enough that the process may exit before a
    # background thread flushes.
    class Reporter
      SDK_NAME = "activeagents-telemetry"

      attr_reader :configuration

      # @param sdk_name [String] overridden by adapters so ingest can tell
      #   which integration produced a trace.
      def initialize(configuration, sdk_name: SDK_NAME, sdk_version: VERSION)
        @configuration = configuration
        @sdk_name = sdk_name
        @sdk_version = sdk_version
      end

      # @param traces [Trace, Array<Trace>] traces to deliver
      # @return [void]
      def report(traces)
        traces = Array(traces).reject { |trace| trace.respond_to?(:empty?) && trace.empty? }
        return if traces.empty?
        return unless configuration.configured?
        return unless configuration.sample?

        body = payload_for(traces)
        configuration.async? ? Thread.new { deliver(body) } : deliver(body)
        nil
      rescue StandardError => e
        log("failed to build trace payload: #{e.class}: #{e.message}")
        nil
      end

      # Blocking delivery, for tests and for at-exit flushes.
      def report_now(traces)
        traces = Array(traces).reject { |trace| trace.respond_to?(:empty?) && trace.empty? }
        return if traces.empty?
        return unless configuration.configured?

        deliver(payload_for(traces))
      end

      private

      def payload_for(traces)
        {
          "traces" => traces.map { |trace| trace.respond_to?(:to_h) ? trace.to_h : trace },
          "sdk" => {
            "name" => @sdk_name,
            "version" => @sdk_version,
            "language" => "ruby",
            "runtime_version" => RUBY_VERSION
          }
        }
      end

      def deliver(body)
        uri = URI.parse(configuration.endpoint)

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = configuration.open_timeout
        http.read_timeout = configuration.timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{configuration.api_key}"
        request["User-Agent"] = "#{@sdk_name}/#{@sdk_version} Ruby/#{RUBY_VERSION}"
        request["X-Service-Name"] = configuration.resolved_service_name.to_s
        request["X-Environment"] = configuration.resolved_environment.to_s
        request.body = JSON.generate(body)

        response = http.request(request)
        log("ingest rejected traces: #{response.code} #{response.message}") unless response.is_a?(Net::HTTPSuccess)
        response
      rescue StandardError => e
        log("#{e.class}: #{e.message}")
        nil
      end

      def log(message)
        configuration.resolved_logger.error("[ActiveAgents::Telemetry] #{message}")
      rescue StandardError
        warn "[ActiveAgents::Telemetry] #{message}"
      end
    end
  end
end
