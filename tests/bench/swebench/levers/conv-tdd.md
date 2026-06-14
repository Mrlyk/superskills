# Conventions

## Fixing a reported bug — test first
- Before touching the source, write a small test that reproduces the EXACT
  scenario in the issue (same inputs, asserting the behavior the issue says is
  correct). Run it and confirm it FAILS for the reason described.
- Only then change the source. Iterate until that test passes.
- Then run the existing tests for the touched module so the fix does not regress.
- Keep the change minimal and at the root cause.
