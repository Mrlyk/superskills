# Conventions

## Fixing a reported bug
- Reproduce the exact scenario from the issue before editing; keep a small repro
  and confirm the fix flips that specific behavior, not just that tests pass.
- Trace to the root cause; prefer the minimal change at the true source over a
  symptom patch or a special-case branch.
- Handle the edge cases the issue implies (empty/None, boundaries, error and type
  paths, interaction with related options), not only the happy path described.
- Run the existing tests that cover the changed code so the fix does not regress
  neighbouring behaviour.
