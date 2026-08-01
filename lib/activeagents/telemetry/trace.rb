# frozen_string_literal: true

require "securerandom"

module ActiveAgents
  module Telemetry
    # A collection of spans sharing a trace_id, plus the service metadata the
    # ingest endpoint keys on. Adapters build one per unit of work — for chat
    # adapters, one per conversation turn.
    class Trace
      attr_reader :trace_id, :spans
      attr_accessor :service_name, :environment, :resource_attributes

      def initialize(trace_id: nil, service_name: nil, environment: nil, resource_attributes: {})
        @trace_id = trace_id || SecureRandom.hex(16)
        @service_name = service_name
        @environment = environment
        @resource_attributes = resource_attributes || {}
        @spans = []
      end

      # Adopts the span into this trace, stamping the trace_id so adapters
      # cannot emit a span that belongs to no trace.
      def add_span(span)
        span.trace_id = trace_id
        @spans << span
        span
      end

      # Builds and adopts a span in one step.
      def span(name, type:, parent: nil, **options)
        add_span(Span.new(name, type: type, parent_span_id: parent&.span_id, **options))
      end

      def root
        @spans.find { |span| span.type == "root" }
      end

      def empty?
        @spans.empty?
      end

      def to_h
        {
          "trace_id" => trace_id,
          "service_name" => service_name,
          "environment" => environment,
          "timestamp" => timestamp,
          "resource_attributes" => resource_attributes,
          "spans" => spans.flat_map { |span| flatten(span) }.map(&:to_h)
        }
      end

      private

      # Spans built through Span#add_span nest as children; the wire format is
      # flat, with parentage carried by parent_span_id.
      def flatten(span)
        [ span ] + span.children.flat_map { |child| flatten(child) }
      end

      # The trace's own end time, so out-of-order delivery still lands the
      # trace at the moment it actually finished.
      def timestamp
        finished = spans.map(&:end_time).compact.max || Time.now
        finished.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N%:z")
      end
    end
  end
end
