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

      attr_accessor :endpoint, :api_key, :service_name, :environment,
                    :resource_attributes, :logger, :timeout, :open_timeout,
                    :async, :sample_rate, :error_message_limit

      def initialize
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
      end

      # Traces are only sent when there is somewhere to send them and
      # something to authenticate with.
      def configured?
        !endpoint.to_s.empty? && !api_key.to_s.empty?
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
          endpoint: endpoint,
          api_key: api_key ? "[REDACTED]" : nil,
          service_name: resolved_service_name,
          environment: resolved_environment,
          sample_rate: sample_rate,
          async: async
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
