# Changelog

## [Unreleased]

### Added

- `activeagents-telemetry` — shared core extracted from the ActiveAgent gem's
  telemetry and the RubyLLM adapter: `Configuration`, `Span`, `Trace`, and
  `Reporter`, which together own the `POST /v1/traces` wire format.
- `activeagents-telemetry-ruby_llm` — the RubyLLM adapter, moved out of the
  activeagents monorepo (`ruby_llm_telemetry/`) and ported onto the shared core.

### Changed

- The adapter's namespace moved from `ActiveAgents::RubyLLMTelemetry` to
  `ActiveAgents::Telemetry::RubyLLM`, and the gem name from
  `active_agents-ruby_llm_telemetry` to `activeagents-telemetry-ruby_llm`. The
  predecessor was never published to RubyGems, so there is no upgrade path to
  maintain.
- `subscribe!` now inherits its destination from
  `ActiveAgents::Telemetry.configuration` when arguments are omitted, so an app
  configures the endpoint once for every adapter.
- Errors are reported through `Span#record_error`, which truncates the message
  and never transmits a backtrace.
