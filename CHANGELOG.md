# Changelog

## [Unreleased]

### Added

- Feature parity with the ActiveAgent framework's built-in telemetry, so the
  framework can adopt this gem as a dependency: an `enabled` kill-switch,
  `load_from_hash` for YAML-driven config, child spans (`Span#add_span`,
  flattened by `Trace#to_h`), `Span#set_status`/`status_message`/`measure`,
  `BatchingReporter` (buffered delivery with `batch_size`/`flush_interval`),
  and a pluggable `local_store` for in-process persistence without HTTP.
- Attribute redaction is now actually applied at delivery: span attribute
  keys matching `redact_attributes` (by dot-separated segment) are scrubbed.
  The framework's previous implementation declared the option but never
  enforced it.

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
