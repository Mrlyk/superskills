# pyfix Conventions

## Commands
- install: `pip install -e .` (or `pip install -e ".[dev]"` if extras added)
- test: `pytest`
- no build step (pure Python utility)

## Structure
- `tests/` — pytest test files (configured in pyproject.toml)
- `pyproject.toml` — project metadata and tool config

## Conventions
- Python >= 3.9
- Commit style: Conventional Commits (`feat:`, `fix:`, `chore:`, etc.)
- Test discovery: pytest reads from `tests/` directory
