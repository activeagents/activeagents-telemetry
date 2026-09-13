# Evaluation trace identity and completion

Tool-less evaluation judge calls previously inherited an application's generic
tool-less identity. Applications also had no supported callback for retaining the
actual emitted trace ID in a scenario result, and short-lived commands inherited
asynchronous delivery that could outlive the process.

`RubyLLM.with_agent` now accepts scope-local correlation attributes, an `on_trace`
callback and a synchronous delivery option. Existing calls remain compatible.
Nested/raising scopes restore their previous context; callback failures do not
drop traces or log callback message content. Body capture remains opt-in.

Validation: core 39 tests / 100 assertions and RubyLLM adapter 20 tests / 71
assertions pass on Ruby 4.0.2. New tests cover actual trace-ID correlation, judge
identity, nested context restoration, synchronous delivery under sampling, a
turn keeping the scope it started under, and callback failure.
Raw logs live in gitignored `tmp/`.
