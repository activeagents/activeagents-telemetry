# A nested with_agent scope replaces the evaluation's scope

`RubyLLM.with_agent` set the thread-local scope to a fresh hash and restored
the previous one on exit, and a turn captures whichever scope is active on its
first round. When an evaluation replay wrapped the code under test in an outer
scope (the evaluation's name, `eval.*` attributes, an `on_trace` recording the
trace id, `synchronous: true`) and that code opened its own scope around the
actual `chat.ask` (its own name and action, `sparkle.role`-style attributes),
the inner scope silently replaced the outer one: the `eval.*` attributes were
gone from the trace, the callback never ran, delivery went back to the
background thread, and no spec noticed.

Nested scopes now compose: attributes merge with the nested keys winning,
`on_trace` and `synchronous` are inherited unless passed, and a scope opened
with `pin: true` keeps its name, action, callback and delivery mode against
nested scopes, which may only add attributes. `correlation_tracer` returns the
`tracer:` lambda `ActiveAgent::Evals::Correlation` expects, opening a pinned,
synchronous scope.
