# frozen_string_literal: true

require "test_helper"

# Features added for parity with the ActiveAgent framework's built-in
# telemetry, so the framework can depend on this gem instead of shipping
# its own copy.
class TestChildSpans < Minitest::Test
  include TelemetryTestHelpers

  def test_add_span_nests_and_trace_flattens
    trace = ActiveAgents::Telemetry::Trace.new(service_name: "test-app")
    root = trace.span("Agent.run", type: "root")
    llm = root.add_span("llm.generate", type: "llm")
    tool = llm.add_span("tool.search", type: "tool")
    [ tool, llm, root ].each(&:finish)

    spans = trace.to_h["spans"]
    assert_equal %w[root llm tool], spans.map { |span| span["type"] }
    assert_equal root.span_id, spans[1]["parent_span_id"]
    assert_equal llm.span_id, spans[2]["parent_span_id"]
    assert_equal [ trace.trace_id ], spans.map { |span| span["trace_id"] }.uniq
  end

  def test_children_built_before_the_trace_get_stamped_with_it
    root = ActiveAgents::Telemetry::Span.new("Agent.run", type: "root")
    root.add_span("llm.generate", type: "llm")

    trace = ActiveAgents::Telemetry::Trace.new
    trace.add_span(root)

    assert_equal [ trace.trace_id ], trace.to_h["spans"].map { |span| span["trace_id"] }.uniq
  end
end

class TestSpanStatus < Minitest::Test
  def test_set_status_records_code_and_message
    span = ActiveAgents::Telemetry::Span.new("x", type: "llm")
    span.set_status(:error, "we tried")

    assert_equal "ERROR", span.status
    assert_equal "we tried", span.to_h["status_message"]
  end

  def test_measure_times_the_block_and_records_the_outcome
    span = ActiveAgents::Telemetry::Span.new("x", type: "llm")
    result = span.measure { :done }
    assert_equal :done, result
    assert_equal "OK", span.status
    assert span.finished?

    failing = ActiveAgents::Telemetry::Span.new("y", type: "llm")
    assert_raises(ArgumentError) { failing.measure { raise ArgumentError, "boom" } }
    assert_equal "ERROR", failing.status
    assert failing.finished?
  end
end

class TestConfigurationParity < Minitest::Test
  include TelemetryTestHelpers

  def test_enabled_false_is_a_kill_switch_over_configured
    config = fresh_configuration(enabled: false)
    assert config.configured?
    refute config.enabled?

    reporter, captured = capturing_reporter(config)
    reporter.report(build_trace)
    assert_empty captured
  end

  def test_load_from_hash_applies_known_keys_and_ignores_unknown
    config = ActiveAgents::Telemetry::Configuration.new
    config.load_from_hash("api_key" => "k", "sample_rate" => 0.5, "someday_maybe" => true)

    assert_equal "k", config.api_key
    assert_equal 0.5, config.sample_rate
  end

  def test_a_local_store_counts_as_configured_without_endpoint_or_key
    config = ActiveAgents::Telemetry::Configuration.new
    refute config.configured?

    config.local_store = ->(_trace, _sdk) {}
    assert config.configured?
  end
end

class TestLocalStore < Minitest::Test
  include TelemetryTestHelpers

  def test_traces_deliver_to_the_store_not_http
    stored = []
    config = fresh_configuration(api_key: nil)
    config.local_store = ->(trace, sdk) { stored << [ trace, sdk ] }

    ActiveAgents::Telemetry::Reporter.new(config).report(build_trace)

    trace, sdk = stored.first
    assert_equal 1, stored.size
    assert_equal "test-app", trace["service_name"]
    assert_equal "activeagents-telemetry", sdk["name"]
  end

  def test_a_raising_store_is_contained_per_trace
    stored = []
    config = fresh_configuration(api_key: nil, logger: Logger.new(File::NULL))
    config.local_store = ->(trace, _sdk) { raise "db down" if trace["service_name"] == "bad"; stored << trace }

    reporter = ActiveAgents::Telemetry::Reporter.new(config)
    reporter.report([ build_trace(service_name: "bad"), build_trace ])

    assert_equal 1, stored.size, "the failing trace must not take down its batch-mates"
  end
end

class TestRedaction < Minitest::Test
  include TelemetryTestHelpers

  def test_matching_attribute_keys_are_scrubbed_before_delivery
    reporter, captured = capturing_reporter

    trace = ActiveAgents::Telemetry::Trace.new(service_name: "test-app")
    trace.span("Agent.run", type: "root", attributes: {
      "api_key" => "sk-live-123", "http.token" => "abc", "agent.model" => "gpt-4o"
    }).finish
    reporter.report(trace)

    attributes = captured.first["traces"].first["spans"].first["attributes"]
    assert_equal "[REDACTED]", attributes["api_key"]
    assert_equal "[REDACTED]", attributes["http.token"], "matches on key segments"
    assert_equal "gpt-4o", attributes["agent.model"]
    refute_includes captured.first.to_json, "sk-live-123"
  end

  def test_an_empty_redaction_list_passes_everything_through
    reporter, captured = capturing_reporter(fresh_configuration(redact_attributes: []))

    trace = ActiveAgents::Telemetry::Trace.new(service_name: "test-app")
    trace.span("Agent.run", type: "root", attributes: { "api_key" => "kept" }).finish
    reporter.report(trace)

    assert_equal "kept", captured.first["traces"].first["spans"].first["attributes"]["api_key"]
  end
end

class TestBatchingReporter < Minitest::Test
  include TelemetryTestHelpers

  def batching_reporter(config = fresh_configuration)
    reporter = ActiveAgents::Telemetry::BatchingReporter.new(config)
    captured = []
    reporter.define_singleton_method(:deliver) { |body| captured << body }
    [ reporter, captured ]
  end

  def test_buffers_until_batch_size_then_delivers_together
    reporter, captured = batching_reporter(fresh_configuration(batch_size: 3))

    2.times { reporter.report(build_trace) }
    assert_empty captured, "under batch_size stays buffered"

    reporter.report(build_trace)
    assert_equal 1, captured.size
    assert_equal 3, captured.first["traces"].size
  end

  def test_flush_delivers_a_partial_batch
    reporter, captured = batching_reporter
    reporter.report(build_trace)
    assert_empty captured

    reporter.flush
    assert_equal 1, captured.first["traces"].size
  end

  def test_shutdown_flushes_and_refuses_further_traces
    reporter, captured = batching_reporter
    reporter.report(build_trace)
    reporter.shutdown

    assert_equal 1, captured.size
    reporter.report(build_trace)
    reporter.flush
    assert_equal 1, captured.size, "post-shutdown traces are dropped"
  end

  def test_sampling_applies_on_enqueue
    reporter, captured = batching_reporter(fresh_configuration(sample_rate: 0.0, batch_size: 1))
    reporter.report(build_trace)
    reporter.flush

    assert_empty captured
  end
end
