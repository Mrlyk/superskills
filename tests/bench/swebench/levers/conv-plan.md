# Conventions

## Fixing a reported bug — diagnose before editing
- First restate, in one line, the exact behavior the issue expects vs what
  currently happens.
- List 2-3 concrete root-cause hypotheses. Probe each with a quick print/REPL
  check against the real code before committing to one.
- Fix the confirmed root cause with the minimal change; avoid symptom patches and
  special-case branches.
- Reproduce the issue scenario and run the touched module's tests before finishing.
