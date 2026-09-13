# activeagents-telemetry-ruby_llm

Reports [RubyLLM](https://github.com/crmne/ruby_llm) chats to an
ActiveAgents-compatible trace endpoint — the hosted platform, or any
self-hosted ActiveAgent dashboard.

For apps built directly on RubyLLM. Apps that can adopt `ActiveAgent::Base`
should use the framework's `ruby_llm` provider instead, which reports telemetry
on its own.

**[Full guide → the wiki](https://github.com/activeagents/activeagents-telemetry/wiki/RubyLLM)**

## Install

```ruby
gem "activeagents-telemetry-ruby_llm"
```

## Use

```ruby
# config/initializers/telemetry.rb
RubyLLM.configure do |config|
  config.instrumenter = ActiveSupport::Notifications # RubyLLM 1.x; 2.x wires this up in Rails
end

ActiveAgents::Telemetry.configure do |config|
  config.api_key      = ENV["ACTIVEAGENTS_API_KEY"]
  config.service_name = "my-app"
end

ActiveAgents::Telemetry::RubyLLM.subscribe!
```

The key is a platform API key (Settings → API Keys) or an account's legacy
`telemetry_api_key`. Delivery is fire-and-forget on a background thread, and
failures are logged and swallowed — telemetry never raises into the app.

## What a turn looks like

One trace per conversation turn: a `root` span (`Agent.action`), one `llm`
span covering the whole provider loop with `llm.rounds` and token totals, and
a `tool` span per tool call with real timings.

RubyLLM emits a `chat.ruby_llm` event per provider round, and the two
generations arrange them differently — 1.x nests a tool round inside the
enclosing event, 2.x drives a flat `step until complete?` loop whose rounds
are siblings with tool calls between them. Rounds are accumulated and flushed
on the round that ends the turn, so both produce the same trace.

Prompts, completions, and tool arguments/results are sent only when the
configuration's `capture_bodies` is enabled (off by default, truncated to
4,000 characters); error messages are truncated.

## Naming the traffic

RubyLLM carries no application identity on the payload — neither a
`RubyLLM::Agent` class nor an `acts_as_chat` record reaches the instrumenter
— so unattributed traffic reports as `RubyLLM::Chat`:

```ruby
# Per call site
ActiveAgents::Telemetry::RubyLLM.with_agent("SupportBot", action: "respond") { chat.ask(...) }

# Or from the initializer, derived from the event payload
ActiveAgents::Telemetry::RubyLLM.subscribe!(
  agent_resolver: ->(payload) { { name: "SupportBot", action: payload[:tools].present? ? "respond" : "summarize" } }
)

# Or name every RubyLLM::Agent subclass by its class
module AgentTelemetryAttribution
  def ask(...) = ActiveAgents::Telemetry::RubyLLM.with_agent(self.class.name) { super }
end
RubyLLM::Agent.prepend(AgentTelemetryAttribution)
```

## Scope

Chat completions and tool calls. RubyLLM's `embedding`, `image`,
`moderation`, `speech`, `transcription`, `request`, and `models.refresh`
events are not reported yet — they carry their own token counts and are a
natural extension of the same subscriber.

Concurrent tool execution runs tools off the instrumented thread and is not
captured; sequential execution (the default) is fully covered. A turn left
open by a halted tool call, or by an app driving 2.x's `step`/`run_tools` by
hand, is flushed when the next chat reports, after `MAX_TURN_SECONDS`, or on
an explicit `flush!`.

## Tests

```bash
bundle exec rake test
```

## Correlating evaluation traces

Use a separate identity for judge calls and attach stable evaluation identifiers
without changing the application's default agent resolver:

```ruby
trace_ids = []
ActiveAgents::Telemetry::RubyLLM.with_agent(
  "EvaluationJudge", action: "score",
  attributes: { "eval.run_id" => run_id, "eval.result_id" => result_id },
  on_trace: ->(trace) { trace_ids << trace.trace_id },
  synchronous: true
) do
  judge_chat.ask(prompt)
end
```

The callback receives each trace the reporter accepted for delivery, so an
evaluation result can retain the trace ID of that delivery attempt. Acceptance is
not ingestion: the trace passed the enabled, configured and sampling checks, but
a delivery that then fails is logged by the reporter rather than announced here,
and an asynchronous delivery can outlive a process that exits right away. A trace
dropped by `sample_rate` or by a disabled configuration is never announced.
`synchronous: true` delivers in the calling thread for this scope only, through
the same sampling and configuration checks as ordinary delivery; it does not
mutate the shared async configuration. Normal reporter error logging still
applies: synchronous delivery does not turn telemetry failures into application
exceptions. A turn keeps the scope it started under, so a turn left open by a
pending tool call and closed later by `flush!` still reports with this agent,
attributes and callback, and a turn that started outside any scope never adopts
one. Context
is restored after the block, including when it raises, and nested scopes use
their own attributes. A callback error is logged by exception class without
dropping the trace. Attribute redaction and content-capture settings continue to
apply.

Report publication and trace ingestion are separate operations. Persist each run
and result ID in the evaluation report and attach the same IDs to its response and
judge trace attributes. The application chooses whether to publish full report
content; this API does not enable body capture or upload reports automatically.
