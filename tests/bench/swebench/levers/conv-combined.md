# Conventions

## Fixing a reported bug
- Restate the exact expected vs actual behavior from the issue in one line.
- Read the existing tests and call sites for the code you will change to learn the
  expected contract (argument order, return types, error behavior).
- Write a small test reproducing the issue's exact scenario; confirm it fails.
- Fix the root cause with the minimal change; no symptom patches.
- Cover the cases the issue implies (empty/None, boundaries, malformed input,
  interaction with related options), not just the one example.
- Run your repro plus the touched module's existing tests; fix any regression.
