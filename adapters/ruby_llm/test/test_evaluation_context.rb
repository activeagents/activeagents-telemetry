# frozen_string_literal: true

require "test_helper"

class TestEvaluationContext < Minitest::Test
  include RubyLLMTelemetryTestHelpers

  def test_correlates_the_actual_trace_and_separates_judge_identity
    ids = []
    Adapter.with_agent("EvaluationJudge", action: "score",
      attributes: { "eval.run_id" => "run-1", "eval.result_id" => "result-1", "agent.class" => "Wrong" },
      on_trace: ->(trace) { ids << trace.trace_id }) do
      instrument("chat.ruby_llm", chat_payload) { nil }
    end

    trace = traces.fetch(0)
    root = spans_of(trace, "root").fetch(0)
    assert_equal [ trace["trace_id"] ], ids
    assert_equal "EvaluationJudge.score", root["name"]
    assert_equal "EvaluationJudge", root["attributes"]["agent.class"]
    assert_equal "run-1", root["attributes"]["eval.run_id"]
    assert_equal "result-1", root["attributes"]["eval.result_id"]
  end

  def test_context_is_restored_after_nested_judge_and_exception
    Adapter.with_agent("Support", action: "respond", attributes: { "eval.run_id" => "outer" }) do
      assert_raises(RuntimeError) do
        Adapter.with_agent("Judge", action: "score", attributes: { "eval.run_id" => "inner" }) do
          instrument("chat.ruby_llm", chat_payload) { nil }
          raise "synthetic error"
        end
      end
      instrument("chat.ruby_llm", chat_payload) { nil }
    end
    instrument("chat.ruby_llm", chat_payload) { nil }

    roots = traces.map { |trace| spans_of(trace, "root").first }
    assert_equal [ "Judge.score", "Support.respond", "RubyLLM::Chat.chat" ], roots.map { |root| root["name"] }
    assert_equal [ "inner", "outer", nil ], roots.map { |root| root["attributes"]["eval.run_id"] }
  end

  def test_synchronous_scope_finishes_delivery_without_mutating_configuration
    subscribe(async: true)
    caller_thread = Thread.current
    delivery_threads = []
    original = Adapter.reporter.method(:report_now)
    Adapter.reporter.define_singleton_method(:report_now) do |trace|
      delivery_threads << Thread.current
      original.call(trace)
    end

    Adapter.with_agent("Support", synchronous: true) do
      instrument("chat.ruby_llm", chat_payload) { nil }
      assert_equal 1, posted.size
    end

    assert_equal [ caller_thread ], delivery_threads
    assert Adapter.configuration.async?
  end

  def test_callback_failure_does_not_discard_the_trace_or_expose_its_message
    _, stderr = capture_io do
      Adapter.with_agent("Support", on_trace: ->(_) { raise "private callback content" }) do
        instrument("chat.ruby_llm", chat_payload) { nil }
      end
    end

    assert_equal 1, posted.size
    assert_includes stderr, "on_trace failed: RuntimeError"
    refute_includes stderr, "private callback content"
  end
end
