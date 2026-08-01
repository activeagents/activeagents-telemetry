# frozen_string_literal: true

require "securerandom"

module ActiveAgents
  module Telemetry
    # A single operation inside a trace, serialized to the `/v1/traces` wire
    # format. Adapters build these rather than hand-rolling hashes, so a span
    # from the RubyLLM adapter and a span from any future adapter are shaped
    # identically on the wire.
    class Span
      TYPES = %w[root prompt llm tool thinking embedding error].freeze

      OK = "OK"
      ERROR = "ERROR"
      UNSET = "UNSET"

      ZERO_TOKENS = { "input" => 0, "output" => 0, "thinking" => 0, "total" => 0 }.freeze

      attr_reader :span_id, :name, :type, :attributes, :events, :children, :status_message
      attr_accessor :parent_span_id, :start_time, :end_time, :status

      def initialize(name, type:, trace_id: nil, parent_span_id: nil, span_id: nil, attributes: {}, start_time: nil)
        @span_id = span_id || SecureRandom.hex(8)
        @trace_id = trace_id
        @parent_span_id = parent_span_id
        @name = name.to_s
        @type = type.to_s
        @attributes = stringify(attributes)
        @start_time = start_time || Time.now
        @end_time = nil
        @status = UNSET
        @status_message = nil
        @tokens = ZERO_TOKENS.dup
        @events = []
        @children = []
      end

      attr_reader :trace_id

      # Stamping a trace_id propagates to children, so a subtree built before
      # its trace exists still lands in one piece.
      def trace_id=(value)
        @trace_id = value
        @children.each { |child| child.trace_id = value }
      end

      # Builds a child span sharing this span's trace. Instrumentation that
      # holds only a span — not the enclosing trace — nests through this;
      # Trace#to_h flattens the tree back out for the wire.
      def add_span(name, type: "root", **options)
        child = Span.new(name, type: type, trace_id: trace_id, parent_span_id: span_id, **options)
        @children << child
        child
      end

      def set_attribute(key, value)
        @attributes[key.to_s] = value
        self
      end

      def set_attributes(attrs)
        @attributes.merge!(stringify(attrs))
        self
      end

      def set_tokens(input: 0, output: 0, thinking: 0)
        @tokens = {
          "input" => input.to_i,
          "output" => output.to_i,
          "thinking" => thinking.to_i,
          "total" => input.to_i + output.to_i + thinking.to_i
        }
        self
      end

      def tokens
        @tokens.dup
      end

      # Adds another span's token counts to this one — how a turn-level llm
      # span accumulates the rounds it covers.
      def add_tokens(other)
        counts = other.respond_to?(:tokens) ? other.tokens : other
        @tokens = @tokens.merge(stringify(counts)) { |_key, carried, added| carried.to_i + added.to_i }
        self
      end

      def add_event(name, attributes = {})
        @events << { "name" => name.to_s, "timestamp" => iso8601(Time.now), "attributes" => stringify(attributes) }
        self
      end

      # @param code [Symbol, String] :ok, :error, or :unset
      def set_status(code, message = nil)
        @status = { ok: OK, error: ERROR, unset: UNSET }.fetch(code.to_s.downcase.to_sym, UNSET)
        @status_message = message
        self
      end

      # Records an error without ever putting a backtrace or an untruncated
      # message on the wire — telemetry payloads leave the app's trust boundary.
      def record_error(error, message_limit: 200)
        @status = ERROR
        @status_message = truncate(error.message.to_s, message_limit)
        set_attribute("error.type", error.class.name)
        set_attribute("error.message", truncate(error.message.to_s, message_limit))
        self
      end

      def finish(at: nil)
        @end_time = at || Time.now
        @status = OK if @status == UNSET
        self
      end

      def finished?
        !@end_time.nil?
      end

      def duration_ms
        return nil unless finished?

        ((@end_time - @start_time) * 1000).round(2)
      end

      def to_h
        {
          "span_id" => span_id,
          "trace_id" => trace_id,
          "parent_span_id" => parent_span_id,
          "name" => name,
          "type" => type,
          "start_time" => iso8601(start_time),
          "end_time" => end_time ? iso8601(end_time) : nil,
          "duration_ms" => duration_ms,
          "status" => status,
          "status_message" => status_message,
          "attributes" => attributes,
          "tokens" => tokens,
          "events" => events
        }
      end

      # Runs the block, recording its outcome and timing on the span.
      def measure
        result = yield(self)
        set_status(:ok) if @status == UNSET
        result
      rescue StandardError => e
        record_error(e)
        raise
      ensure
        finish
      end

      private

      def stringify(hash)
        (hash || {}).each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end

      def truncate(string, limit)
        string.length > limit ? "#{string[0, limit - 1]}…" : string
      end

      def iso8601(time)
        time.utc.strftime("%Y-%m-%dT%H:%M:%S.%6N%:z")
      end
    end
  end
end
