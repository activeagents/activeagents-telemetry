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
      # @param sample [Boolean] pass false when the caller already applied
      #   head-based sampling at trace creation — sampling twice compounds
      #   the rate to rate².
      def initialize(configuration, sdk_name: SDK_NAME, sdk_version: VERSION, sample: true)
        @configuration = configuration
        @sdk_name = sdk_name
        @sdk_version = sdk_version
        @sample = sample
      end

      # @param traces [Trace, Hash, Array<Trace, Hash>] traces to deliver —
      #   Trace objects or already-serialized trace hashes
      # @return [void]
      def report(traces)
        traces = normalize(traces)
        return if traces.empty?
        return unless configuration.enabled? && configuration.configured?
        return unless sample_trace?

        body = payload_for(traces)
        configuration.async? ? Thread.new { deliver(body) } : deliver(body)
        nil
      rescue StandardError => e
        log("failed to build trace payload: #{e.class}: #{e.message}")
        nil
      end

      # Blocking delivery, for tests and for at-exit flushes.
      def report_now(traces)
        traces = normalize(traces)
        return if traces.empty?
        return unless configuration.enabled? && configuration.configured?

        deliver(payload_for(traces))
      end

      private

      # Array() is wrong here: it would explode a raw trace hash into
      # key/value pairs. Traces arrive as Trace objects or serialized hashes,
      # singly or in arrays.
      def normalize(traces)
        (traces.is_a?(Array) ? traces : [ traces ]).reject { |trace| trace.nil? || (trace.respond_to?(:empty?) && trace.empty?) }
      end

      # Trace#to_h is already string-keyed; raw hashes may arrive symbol-keyed
      # and both local stores and ingest read string keys.
      def serialize(trace)
        trace.is_a?(Trace) ? trace.to_h : deep_stringify(trace)
      end

      def deep_stringify(value)
        case value
        when Hash then value.each_with_object({}) { |(key, inner), out| out[key.to_s] = deep_stringify(inner) }
        when Array then value.map { |inner| deep_stringify(inner) }
        else value
        end
      end

      def sample_trace?
        !@sample || configuration.sample?
      end

      def payload_for(traces)
        {
          "traces" => traces.map { |trace| redact(serialize(trace)) },
          "sdk" => {
            "name" => @sdk_name,
            "version" => @sdk_version,
            "language" => "ruby",
            "runtime_version" => RUBY_VERSION
          }
        }
      end

      # Scrubs span attributes whose key matches the configured redaction
      # list. Matching is by attribute key segment ("api_key", "http.api_key"),
      # not by value — a secret inside free text is not caught here.
      def redact(trace_hash)
        redacted = Array(configuration.redact_attributes).map(&:to_s)
        return trace_hash if redacted.empty?

        spans = trace_hash["spans"] || trace_hash[:spans] || []
        spans.each do |span|
          attributes = span["attributes"] || span[:attributes]
          next unless attributes.is_a?(Hash)

          attributes.each_key do |key|
            segments = key.to_s.downcase.split(".")
            attributes[key] = "[REDACTED]" if segments.any? { |segment| redacted.include?(segment) }
          end
        end
        trace_hash
      end

      def deliver(body)
        return deliver_locally(body) if configuration.local_store?

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

      # Hands each trace to the configured local store instead of HTTP —
      # nothing leaves the process. Per-trace rescue: one bad row must not
      # drop its batch-mates.
      def deliver_locally(body)
        body["traces"].each do |trace|
          configuration.local_store.call(trace, body["sdk"])
        rescue StandardError => e
          log("local store failed: #{e.class}: #{e.message}")
        end
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
