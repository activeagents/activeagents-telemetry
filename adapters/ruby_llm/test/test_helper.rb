# frozen_string_literal: true

require "minitest/autorun"
require "activeagents/telemetry/ruby_llm"

module RubyLLMTelemetryTestHelpers
  Adapter = ActiveAgents::Telemetry::RubyLLM

  Msg = Struct.new(:role, :input_tokens, :output_tokens, :thinking_tokens)

  def setup
    @posted = []
    subscribe
  end

  def teardown
    Adapter.unsubscribe!
    Adapter.clear_state
    Thread.current[Adapter::AGENT_KEY] = nil
  end

  attr_reader :posted

  # Captures the built payload instead of delivering it.
  def subscribe(**options)
    Adapter.unsubscribe!
    Adapter.subscribe!(
      api_key: "test-key", service_name: "test-app", environment: "test", async: false, **options
    )
    captured = @posted
    Adapter.reporter.define_singleton_method(:deliver) { |body| captured << body }
  end

  def instrument(name, payload, &block)
    ActiveSupport::Notifications.instrument(name, payload, &block)
  end

  def assistant(input:, output:, thinking: 0)
    Msg.new("assistant", input, output, thinking)
  end

  def chat_payload(input_messages: [ Msg.new("user") ], chat: default_chat, **extra)
    { chat: chat, provider: :openai, model: "gpt-4o", input_messages: input_messages, streaming: false }.merge(extra)
  end

  def default_chat
    @default_chat ||= Object.new
  end

  def traces
    posted.map { |body| body.fetch("traces").first }
  end

  def spans_of(trace, type)
    trace.fetch("spans").select { |span| span["type"] == type }
  end
end
