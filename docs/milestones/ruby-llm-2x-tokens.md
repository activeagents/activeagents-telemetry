# Milestone: RubyLLM 2.x token counts

- [x] Read the round's `Tokens` from the 2.x payload, then the messages with either generation's readers.
- [x] Test the 2.x payload, sibling rounds, the message-only fallback and an empty `Tokens`.
- [x] Prove the fix in a booted Rails app on RubyLLM 1.16 and 2.0, from the packaged gems.
- [x] Bump both gems to 0.3.1 with a changelog entry, so the merge is releasable.
- [ ] Merge the PR, then tag `v0.3.1` to publish both gems through the release workflow.
