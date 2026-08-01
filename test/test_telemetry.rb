# frozen_string_literal: true

require "test_helper"

class TestConfiguration < Minitest::Test
  include TelemetryTestHelpers

  def test_is_unconfigured_without_an_api_key
    refute ActiveAgents::Telemetry::Configuration.new.configured?
    assert fresh_configuration.configured?
  end

  def test_redacts_the_api_key_when_inspected
    refute_includes fresh_configuration.to_h.to_s, "test-key"
  end

  def test_sample_rate_bounds_are_absolute
    assert fresh_configuration(sample_rate: 1.0).sample?
    refute fresh_configuration(sample_rate: 0.0).sample?
  end

  def test_falls_back_to_a_service_name
    assert_equal "ruby", ActiveAgents::Telemetry::Configuration.new.resolved_service_name
  end
end

class TestSpan < Minitest::Test
  include TelemetryTestHelpers

  def test_serializes_timing_and_status
    span = ActiveAgents::Telemetry::Span.new("llm.generate", type: "llm")
    span.finish

    hash = span.to_h
    assert_equal "OK", hash["status"]
    assert_equal "llm", hash["type"]
    assert_kind_of Float, hash["duration_ms"]
    assert_match(/\dT\d/, hash["start_time"])
  end

  def test_unfinished_spans_have_no_duration
    assert_nil ActiveAgents::Telemetry::Span.new("x", type: "llm").to_h["duration_ms"]
  end

  def test_tokens_total_themselves
    span = ActiveAgents::Telemetry::Span.new("llm.generate", type: "llm")
    span.set_tokens(input: 10, output: 5, thinking: 2)

    assert_equal({ "input" => 10, "output" => 5, "thinking" => 2, "total" => 17 }, span.tokens)
  end

  def test_tokens_accumulate_across_rounds
    span = ActiveAgents::Telemetry::Span.new("llm.generate", type: "llm")
    span.set_tokens(input: 10, output: 5)
    span.add_tokens({ "input" => 20, "output" => 7, "thinking" => 0, "total" => 27 })

    assert_equal({ "input" => 30, "output" => 12, "thinking" => 0, "total" => 42 }, span.tokens)
  end

  # Payloads leave the app's trust boundary, so a raw backtrace must never ride along.
  def test_recorded_errors_are_truncated_and_carry_no_backtrace
    error = ArgumentError.new("x" * 500)
    error.set_backtrace([ "/secret/path.rb:1" ])
    span = ActiveAgents::Telemetry::Span.new("llm.generate", type: "llm")
    span.record_error(error, message_limit: 200)
    span.finish

    hash = span.to_h
    assert_equal "ERROR", hash["status"]
    assert_equal "ArgumentError", hash["attributes"]["error.type"]
    assert_equal 200, hash["attributes"]["error.message"].length
    refute_includes hash.to_s, "/secret/path.rb"
  end

  def test_finish_does_not_overwrite_an_error_status
    span = ActiveAgents::Telemetry::Span.new("llm.generate", type: "llm")
    span.record_error(ArgumentError.new("boom"))
    span.finish

    assert_equal "ERROR", span.to_h["status"]
  end
end

class TestTrace < Minitest::Test
  include TelemetryTestHelpers

  def test_adopted_spans_inherit_the_trace_id
    trace = ActiveAgents::Telemetry::Trace.new
    root = trace.span("Agent.action", type: "root")
    child = trace.span("llm.generate", type: "llm", parent: root)

    assert_equal trace.trace_id, child.to_h["trace_id"]
    assert_equal root.span_id, child.to_h["parent_span_id"]
    assert_equal 32, trace.trace_id.length, "trace ids are 128-bit, like OpenTelemetry's"
  end

  def test_reports_its_root_and_emptiness
    trace = ActiveAgents::Telemetry::Trace.new
    assert trace.empty?

    trace.span("Agent.action", type: "root")
    refute trace.empty?
    assert_equal "root", trace.root.type
  end
end

class TestReporter < Minitest::Test
  include TelemetryTestHelpers

  def test_delivers_a_trace_with_sdk_metadata
    reporter, captured = capturing_reporter
    reporter.report(build_trace)

    body = captured.first
    assert_equal 1, captured.size
    assert_equal "activeagents-telemetry", body["sdk"]["name"]
    assert_equal "test-app", body["traces"].first["service_name"]
  end

  def test_skips_delivery_when_unconfigured
    reporter, captured = capturing_reporter(fresh_configuration(api_key: nil))
    reporter.report(build_trace)

    assert_empty captured
  end

  def test_skips_empty_traces
    reporter, captured = capturing_reporter
    reporter.report(ActiveAgents::Telemetry::Trace.new)

    assert_empty captured
  end

  def test_sampling_drops_traces
    reporter, captured = capturing_reporter(fresh_configuration(sample_rate: 0.0))
    reporter.report(build_trace)

    assert_empty captured
  end

  # Telemetry is never worth breaking a request over.
  def test_a_broken_endpoint_never_raises
    config = fresh_configuration(endpoint: "not a url", async: false)
    reporter = ActiveAgents::Telemetry::Reporter.new(config)
    config.logger = Logger.new(File::NULL)

    assert_nil reporter.report(build_trace)
  end
end
