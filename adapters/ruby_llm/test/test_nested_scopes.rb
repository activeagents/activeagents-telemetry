# frozen_string_literal: true

require "test_helper"

class TestNestedScopes < Minitest::Test
  include RubyLLMTelemetryTestHelpers

  def test_nested_scope_merges_attributes_and_inherits_on_trace_and_synchronous
    ids = []
    delivery_threads = deliver_recording_threads
    Adapter.with_agent("EvalReplay", action: "replay",
      attributes: { "eval.run_id" => "run-1", "eval.result_id" => "result-1" },
      on_trace: ->(trace) { ids << trace.trace_id }, synchronous: true) do
      Adapter.with_agent("Support", action: "respond", attributes: { "sparkle.role" => "assistant" }) do
        instrument("chat.ruby_llm", chat_payload) { nil }
      end
    end

    trace = traces.fetch(0)
    root = spans_of(trace, "root").fetch(0)
    assert_equal "run-1", root["attributes"]["eval.run_id"]
    assert_equal "result-1", root["attributes"]["eval.result_id"]
    assert_equal "assistant", root["attributes"]["sparkle.role"]
    assert_equal [ trace["trace_id"] ], ids, "the enclosing on_trace is inherited"
    assert_equal [ Thread.current ], delivery_threads, "synchronous delivery is inherited"
  end

  def test_nested_scope_replaces_name_and_action_when_the_enclosing_scope_is_not_pinned
    Adapter.with_agent("EvalReplay", action: "replay", attributes: { "eval.run_id" => "run-1", "shared" => "outer" }) do
      Adapter.with_agent("Support", action: "respond", attributes: { "shared" => "inner" }) do
        instrument("chat.ruby_llm", chat_payload) { nil }
      end
    end

    root = spans_of(traces.fetch(0), "root").fetch(0)
    assert_equal "Support.respond", root["name"]
    assert_equal "Support", root["attributes"]["agent.class"]
    assert_equal "respond", root["attributes"]["agent.action"]
    assert_equal "run-1", root["attributes"]["eval.run_id"]
    assert_equal "inner", root["attributes"]["shared"], "a nested key wins on collision"
  end

  def test_nested_scope_inside_a_pinned_scope_keeps_its_identity_callback_and_delivery
    ids = []
    delivery_threads = deliver_recording_threads
    nested_ids = []
    Adapter.with_agent("EvalReplay", action: "replay", attributes: { "eval.run_id" => "run-1" },
      on_trace: ->(trace) { ids << trace.trace_id }, synchronous: true, pin: true) do
      Adapter.with_agent("Support", action: "respond", attributes: { "sparkle.role" => "assistant" },
        on_trace: ->(trace) { nested_ids << trace.trace_id }, synchronous: false) do
        instrument("chat.ruby_llm", chat_payload) { nil }
      end
    end

    trace = traces.fetch(0)
    root = spans_of(trace, "root").fetch(0)
    assert_equal "EvalReplay.replay", root["name"]
    assert_equal "EvalReplay", root["attributes"]["agent.class"]
    assert_equal "replay", root["attributes"]["agent.action"]
    assert_equal "run-1", root["attributes"]["eval.run_id"]
    assert_equal "assistant", root["attributes"]["sparkle.role"], "the nested scope still adds attributes"
    assert_equal [ trace["trace_id"] ], ids, "the pinned on_trace stays in force"
    assert_empty nested_ids, "the nested on_trace does not replace the pinned one"
    assert_equal [ Thread.current ], delivery_threads, "the pinned synchronous delivery stays in force"
  end

  def test_pinned_scope_stays_pinned_two_levels_down
    Adapter.with_agent("EvalReplay", action: "replay", pin: true) do
      Adapter.with_agent("Support", action: "respond", attributes: { "depth" => "one" }) do
        Adapter.with_agent("Tool", action: "run", attributes: { "depth" => "two" }) do
          instrument("chat.ruby_llm", chat_payload) { nil }
        end
      end
    end

    root = spans_of(traces.fetch(0), "root").fetch(0)
    assert_equal "EvalReplay.replay", root["name"]
    assert_equal "two", root["attributes"]["depth"]
  end

  def test_explicit_synchronous_false_overrides_an_inherited_true
    subscribe(async: true)
    delivery_threads = Queue.new
    Adapter.reporter.define_singleton_method(:deliver) { |_body| delivery_threads << Thread.current }

    Adapter.with_agent("EvalReplay", synchronous: true) do
      Adapter.with_agent("Support", synchronous: false) do
        instrument("chat.ruby_llm", chat_payload) { nil }
      end
    end

    delivery_thread = delivery_threads.pop(timeout: 2)
    refute_nil delivery_thread, "the trace was still delivered"
    refute_equal Thread.current, delivery_thread, "delivery went to the reporter's background thread"
  end

  def test_scope_is_restored_after_the_block_and_when_it_raises
    outer_ids = []
    Adapter.with_agent("EvalReplay", action: "replay", attributes: { "eval.run_id" => "run-1" },
      on_trace: ->(trace) { outer_ids << trace.trace_id }, synchronous: true, pin: true) do
      outer_scope = Thread.current[Adapter::AGENT_KEY]
      Adapter.with_agent("Support", action: "respond", attributes: { "sparkle.role" => "assistant" }) do
        refute_equal outer_scope, Thread.current[Adapter::AGENT_KEY]
      end
      assert_same outer_scope, Thread.current[Adapter::AGENT_KEY]

      assert_raises(RuntimeError) do
        Adapter.with_agent("Support", action: "respond", attributes: { "sparkle.role" => "assistant" }) do
          raise "synthetic error"
        end
      end
      assert_same outer_scope, Thread.current[Adapter::AGENT_KEY]
      instrument("chat.ruby_llm", chat_payload) { nil }
    end
    assert_nil Thread.current[Adapter::AGENT_KEY]
    instrument("chat.ruby_llm", chat_payload) { nil }

    roots = traces.map { |trace| spans_of(trace, "root").first }
    assert_equal [ "EvalReplay.replay", "RubyLLM::Chat.chat" ], roots.map { |root| root["name"] }
    assert_equal [ "run-1", nil ], roots.map { |root| root["attributes"]["eval.run_id"] }
    assert_equal [ nil, nil ], roots.map { |root| root["attributes"]["sparkle.role"] },
      "the raised nested scope leaves nothing behind"
    assert_equal [ traces.fetch(0)["trace_id"] ], outer_ids
  end

  def test_top_level_scope_defaults_stay_unpinned_and_asynchronous
    Adapter.with_agent("Support") do
      scope = Thread.current[Adapter::AGENT_KEY]
      assert_equal false, scope[:synchronous]
      assert_equal false, scope[:pin]
    end
  end

  def test_correlation_tracer_opens_a_pinned_synchronous_scope_and_forwards_on_trace
    ids = []
    delivery_threads = deliver_recording_threads
    received = []
    tracer = Adapter.correlation_tracer
    result = tracer.call("SupportAgent", action: "replay", attributes: { "eval.run_id" => "run-1" },
      on_trace: ->(trace) { received << trace; ids << trace.trace_id }) do
      scope = Thread.current[Adapter::AGENT_KEY]
      assert_equal true, scope[:pin]
      assert_equal true, scope[:synchronous]
      Adapter.with_agent("SupportAgent", action: "respond", attributes: { "sparkle.role" => "assistant" }) do
        instrument("chat.ruby_llm", chat_payload) { :answer }
      end
    end

    assert_equal :answer, result, "the tracer returns the block's value"
    trace = traces.fetch(0)
    root = spans_of(trace, "root").fetch(0)
    assert_equal "SupportAgent.replay", root["name"]
    assert_equal "run-1", root["attributes"]["eval.run_id"]
    assert_equal "assistant", root["attributes"]["sparkle.role"]
    assert_equal [ trace["trace_id"] ], ids
    assert_respond_to received.fetch(0), :trace_id
    assert_equal [ Thread.current ], delivery_threads
  end

  def test_correlation_tracer_forwards_its_own_synchronous_and_pin_settings
    tracer = Adapter.correlation_tracer(synchronous: false, pin: false)
    tracer.call("SupportAgent", action: "replay", attributes: {}, on_trace: nil) do
      scope = Thread.current[Adapter::AGENT_KEY]
      assert_equal false, scope[:synchronous]
      assert_equal false, scope[:pin]
      Adapter.with_agent("Inner", action: "respond") { instrument("chat.ruby_llm", chat_payload) { nil } }
    end

    assert_equal "Inner.respond", spans_of(traces.fetch(0), "root").fetch(0)["name"]
  end

  private

  # Subscribes with async delivery and records the thread each delivery ran
  # on, so a spec can tell synchronous delivery from the background thread.
  def deliver_recording_threads
    subscribe(async: true)
    delivery_threads = []
    captured = posted
    Adapter.reporter.define_singleton_method(:deliver) do |body|
      delivery_threads << Thread.current
      captured << body
    end
    delivery_threads
  end
end
