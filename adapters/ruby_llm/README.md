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

Tool arguments and results are never sent; error messages are truncated.

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
