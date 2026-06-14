# Conventions

## Fixing a reported bug — cover the implied cases
- The issue describes one scenario, but the hidden acceptance test usually checks
  several related ones. Before finishing, enumerate the cases the issue implies —
  empty/None, zero/one/many, boundaries, negative and malformed input, interaction
  with related options/flags — and make sure your fix handles each, not only the
  single example.
- Reproduce the reported case, fix at the root cause, then run the module's tests.
- Keep the change minimal but complete across those implied cases.
