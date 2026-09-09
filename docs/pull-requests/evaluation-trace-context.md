# Draft PR: evaluation trace context

Branch `codex/evaluation-trace-context` proposes scoped correlation attributes,
completed trace callbacks, and blocking delivery attempts for RubyLLM calls.
It keeps existing agent resolvers and ordinary asynchronous application tracing
compatible. Consumers can distinguish evaluation judges from application agents
and link report results to their actual response and judge traces.

Core and adapter suites pass: 51 tests, 139 assertions, zero failures. Changed
Ruby files pass the Omakase lint configuration. No provider or collector network
requests are made by the tests. Merge/release is intentionally pending review.
