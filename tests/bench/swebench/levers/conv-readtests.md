# Conventions

## Fixing a reported bug — learn the expected contract from existing tests
- Before editing, find and read the existing tests and call sites for the
  function/class you will change. They encode the project's expected API shape,
  argument order, return types, and error behavior — match them exactly.
- Reproduce the issue, fix at the root cause, then run the module's existing
  tests so neighbouring behavior does not regress.
- Prefer the minimal change consistent with how the rest of the codebase is used.
