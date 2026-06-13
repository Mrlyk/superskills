---
name: test
description: After development work is complete, run one full unit-test pass over the changes. Use when wrapping up a coding task ("补测试", "write tests for this", finishing development) — not during development.
---

# Final Test Pass

One pass, after development is done. No fixed process — only the result matters: changed behavior is covered and the suite passes.

1. Identify what changed in this session (git diff, files touched).
2. Detect the project's test framework and existing test layout; follow them exactly. If the project has no test setup, do not introduce one unasked — verify with a throwaway script instead (assert the documented or specified behavior, run it, then delete it) and offer to set up a real framework as a follow-up.
3. Cover the changed public behavior. Derive cases from the spec first: every documented example verbatim, then the boundaries the spec implies — empty/None, extremes, malformed input, repeated or trailing separators, off-by-one ranges. Skip trivial code (pure config, pass-through). Never assert on mock behavior; never add test-only methods to production code.
4. Run the relevant tests (the whole suite if it is cheap). Fix failures by root cause — a production bug fix beats a test adjustment.
5. Report: what is covered, what is deliberately not, and the passing test output.
