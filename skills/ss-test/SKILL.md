---
name: ss-test
description: After development work is complete, run one full unit-test pass over the changes. Use when wrapping up a coding task ("补测试", "write tests for this", finishing development) — not during development.
---

# Final Test Pass

One pass, after development is done. No fixed process — only the result matters: changed behavior is covered and the suite passes.

1. Identify what changed in this session (git diff, files touched).
2. Detect the project's test framework and existing test layout; follow them exactly. If the project has no test setup, ask before introducing one.
3. Cover the changed public behavior: happy path plus the error and edge cases the change introduced. Skip trivial code (pure config, pass-through). Never assert on mock behavior; never add test-only methods to production code.
4. Run the relevant tests (the whole suite if it is cheap). Fix failures by root cause — a production bug fix beats a test adjustment.
5. Report: what is covered, what is deliberately not, and the passing test output.
