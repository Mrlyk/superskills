# pyfix

Small Python utility project used as the control-group fixture for the superskills benchmark. Python >=3.9, managed via `pyproject.toml`.

## Key Commands
- Install: `pip install -e .`

## Spec Pointers
- Read `.superskills/conventions.md` before writing code.
- Check `.superskills/learnings/INDEX.md` for past learnings; read a linked entry when relevant.
- Before reporting any coding task as done you must have executed the changed code: run the documented examples plus boundary cases (empty, extreme, malformed, repeated/trailing input) via the test suite or a throwaway script you then delete, fix failures at root cause, and include the run output in your final reply. For larger changes apply the superskills test skill.
