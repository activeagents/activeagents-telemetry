# PR: RubyLLM 2.x token counts

Branch `claude/ruby-llm-2x-tokens` makes the adapter read token counts from a
RubyLLM 2.x turn. 2.0 moved the per-message readers to `message.tokens` and
puts the round's `Tokens` on the `chat.ruby_llm` payload; the adapter only knew
the 1.x readers, so every 2.x trace reported 0 tokens. The payload's `tokens`
is read first, then the round's messages with either generation's readers, so
1.x traces are unchanged.

Core and adapter suites pass: 63 tests, 177 assertions, zero failures. The fix
was also run in a Rails 8.1 app mounting the dashboard, on RubyLLM 1.16.0 and
2.0.0, from the built gems: with the released adapter every 2.x trace stored
`0`/`0` tokens; with 0.3.1 a plain chat stores 11/7, and a two-round tool turn
22/14. Versions and the changelog are bumped to 0.3.1 on the branch (the core
gem is republished unchanged so the two stay on one version); tagging `v0.3.1`
after the merge publishes both gems.
