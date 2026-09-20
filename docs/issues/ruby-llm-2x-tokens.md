# RubyLLM 2.x turns report zero tokens

RubyLLM 2.0 moved the per-message token readers (`input_tokens`,
`output_tokens`, `thinking_tokens`) to `message.tokens` and put the round's
`Tokens` on the `chat.ruby_llm` payload. The adapter only knew the 1.x readers,
so every 2.x turn reported `0` input and output tokens while its spans, timings
and errors were correct. A dashboard fed by a RubyLLM 2.x app showed no token
usage and no cost.

The adapter now reads the payload's `tokens` first, then the round's messages
with either generation's readers. 1.x traces are unchanged.
