# Milestone: nested agent scopes

- [x] Merge attributes and inherit `on_trace` / `synchronous` across nested `with_agent` scopes; `synchronous:` defaults to `nil` so an explicit `false` still overrides.
- [x] Add `pin: true` so an evaluation's scope keeps its identity, callback and delivery mode against the code under test's own scope.
- [x] Add `correlation_tracer(synchronous: true, pin: true)` for `ActiveAgent::Evals::Correlation`'s `tracer:`, without depending on activeagent.
- [x] Test merging, inheritance, replacement, pinning at depth, the explicit `false` override, restoration after a raise, and the tracer.
- [x] Document the nesting rules and the tracer; bump both gems to 0.3.2 with a changelog entry, so the merge is releasable.
- [ ] Merge the PR, then tag `v0.3.2` to publish both gems through the release workflow.
