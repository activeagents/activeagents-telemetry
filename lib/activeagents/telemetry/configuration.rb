# frozen_string_literal: true

module ActiveAgents
  module Telemetry
    # Where traces go and how they get there.
    #
    # Every adapter takes one of these, so an app configures the destination
    # once and each adapter inherits it:
    #
    #   ActiveAgents::Telemetry.configure do |config|
    #     config.api_key      = ENV["ACTIVEAGENTS_API_KEY"]
    #     config.service_name = "my-app"
    #     config.environment  = Rails.env
    #   end
    #
    # A self-hosted ActiveAgent dashboard is the same thing with a different
    # endpoint — point it at "https://your-app.example.com/active_agent/api/traces".
    class Configuration
      # The hosted platform. Self-hosters override `endpoint`.
      DEFAULT_ENDPOINT = "https://api.activeagents.ai/v1/traces"

      # Path a mounted ActiveAgent::Dashboard::Engine serves traces on.
      LOCAL_ENDPOINT_PATH = "/active_agent/api/traces"

      # Attribute keys scrubbed from spans before delivery. Name-based — a
      # secret inside free text is not caught; see the wiki's privacy page.
      DEFAULT_REDACT_ATTRIBUTES = %w[password secret token key credential api_key].freeze

      attr_accessor :endpoint, :api_key, :service_name, :environment,
                    :resource_attributes, :logger, :timeout, :open_timeout,
                    :async, :sample_rate, :error_message_limit,
                    :enabled, :batch_size, :flush_interval,
                    :capture_bodies, :redact_attributes, :local_store

      def initialize
        @enabled = true
        @endpoint = DEFAULT_ENDPOINT
        @api_key = nil
        @service_name = nil
        @environment = nil
        @resource_attributes = {}
        @logger = nil
        @timeout = 10
        @open_timeout = 10
        @async = true
        @sample_rate = 1.0
        @error_message_limit = 200
        @batch_size = 100
        @flush_interval = 5
        @capture_bodies = false
        @redact_attributes = DEFAULT_REDACT_ATTRIBUTES.dup
        @local_store = nil
      end

      # Traces are only sent when there is somewhere to send them: an endpoint
      # plus something to authenticate with, or a local store that bypasses
      # HTTP entirely.
      def configured?
        local_store? || (!endpoint.to_s.empty? && !api_key.to_s.empty?)
      end

      # An explicit kill-switch over and above configured?. Defaults to true —
      # for adapters, the presence of an api_key remains the effective switch;
      # frameworks that want opt-in default this to false.
      def enabled?
        @enabled == true
      end

      # A callable (trace_hash, sdk_hash) that persists traces in-process —
      # the ActiveAgent dashboard wires this to its TelemetryTrace model.
      def local_store?
        !@local_store.nil?
      end

      def capture_bodies?
        @capture_bodies == true
      end

      def async?
        @async == true
      end

      # Head-based sampling: decided once per trace, at report time.
      def sample?
        return true if sample_rate >= 1.0
        return false if sample_rate <= 0.0

        rand < sample_rate
      end
      alias should_sample? sample?

      FLOAT_SETTINGS = %w[sample_rate].freeze
      INTEGER_SETTINGS = %w[batch_size flush_interval timeout open_timeout error_message_limit].freeze

      # Loads settings from a hash — how config/*.yml files reach here.
      # Unknown keys are ignored, so a newer config file works on an older
      # gem; numeric settings are coerced because ERB-interpolated YAML
      # values arrive as strings.
      def load_from_hash(hash)
        (hash || {}).each do |key, value|
          writer = "#{key}="
          next unless respond_to?(writer)

          value = value.to_f if FLOAT_SETTINGS.include?(key.to_s)
          value = value.to_i if INTEGER_SETTINGS.include?(key.to_s)
          public_send(writer, value)
        end
        self
      end

      # Falls back to the Rails application name, then to a generic label, so
      # traces are attributable even when the app never sets one.
      def resolved_service_name
        @service_name || rails_app_name || "ruby"
      end

      def resolved_environment
        @environment || rails_env || ENV.fetch("RACK_ENV", "production")
      end

      def resolved_logger
        @logger || rails_logger || Logger.new(File::NULL)
      end

      def to_h
        {
          enabled: enabled,
          endpoint: endpoint,
          api_key: api_key ? "[REDACTED]" : nil,
          service_name: resolved_service_name,
          environment: resolved_environment,
          sample_rate: sample_rate,
          async: async,
          batch_size: batch_size,
          flush_interval: flush_interval,
          capture_bodies: capture_bodies,
          local_store: local_store? ? "[CALLABLE]" : nil
        }
      end

      private

      def rails_app_name
        return nil unless defined?(Rails) && Rails.application

        Rails.application.class.module_parent_name.underscore
      rescue StandardError
        nil
      end

      def rails_env
        defined?(Rails) && Rails.respond_to?(:env) ? Rails.env.to_s : nil
      end

      def rails_logger
        defined?(Rails) && Rails.respond_to?(:logger) ? Rails.logger : nil
      end
    end
  end
end
