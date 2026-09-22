# Draft PR: nested agent scopes

Branch `claude/nested-agent-scopes` makes nested `RubyLLM.with_agent` scopes
compose instead of replacing each other: attributes merge (nested keys win),
`on_trace` and `synchronous` are inherited unless passed, and `pin: true`
keeps a scope's name, action, callback and delivery mode in force while nested
scopes only add attributes. `correlation_tracer` returns the `tracer:` lambda
`ActiveAgent::Evals::Correlation` (activeagent >= 1.6.3) expects, opening a
pinned, synchronous scope, with no dependency on activeagent.

Core and adapter suites pass: 72 tests, 223 assertions, zero failures. Every
Ruby file passes the Omakase lint configuration. Versions and the changelog
are bumped to 0.3.2 on the branch (the core gem is republished unchanged so
the two stay on one version); tagging `v0.3.2` after the merge publishes both
gems.
