# activeagents-telemetry

LLM tracing for Ruby apps. Reports what your app asked the model, how long it
took, what it cost in tokens, and which tools ran — to the
[ActiveAgents](https://activeagents.ai) platform or any self-hosted ActiveAgent
dashboard.

**[Configuration guide → the wiki](https://github.com/activeagents/activeagents-telemetry/wiki)**

## Gems in this repo

| Gem | Use it when |
|-----|-------------|
| `activeagents-telemetry` | Shared core — wire format, configuration, delivery. Every adapter depends on it. |
| `activeagents-telemetry-ruby_llm` | Your app calls models through [RubyLLM](https://github.com/crmne/ruby_llm). |

Apps built on the [ActiveAgent](https://github.com/activeagents/activeagent)
framework don't need an adapter — the framework reports telemetry on its own.

## Quick start

```ruby
# Gemfile
gem "activeagents-telemetry-ruby_llm"
```

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

That's it. Every chat turn now reports as a trace.

## What a trace looks like

One trace per conversation turn:

```
root   SupportBot.respond              1,240ms   OK
└─ llm llm.generate    gpt-4o  2 rounds  1,180ms  42 tokens
   └─ tool tool.search_docs               310ms   OK
```

Tool arguments and results are never sent. Error messages are truncated and
backtraces are never transmitted.

## Self-hosting

Point the endpoint at your mounted dashboard — same gems, same wire format:

```ruby
config.endpoint = "https://your-app.example.com/active_agent/api/traces"
```

## Development

```bash
bundle install
bundle exec rake test_all   # core + every adapter
bundle exec rake build_all  # build all gems into pkg/
```

## License

MIT — see [LICENSE.txt](LICENSE.txt).
