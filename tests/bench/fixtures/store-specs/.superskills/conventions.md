# Conventions — store-app

## Commands
- Install: `pnpm install` (CI cache keyed on pnpm-lock.yaml; never use npm/yarn)
- Test: `pnpm test` (runs `node --test`)
- Lint: `pnpm lint` (runs `eslint src/`)

## Structure
- `src/` — source modules; `src/index.js` is the public barrel
- `test/` — test files, named `<module>.test.js`
- `docs/engineering-handbook.md` — authoritative coding rules

## Conventions
- ESM throughout (`"type": "module"`); all imports use explicit `.js` extensions
- Every public export must also be re-exported from `src/index.js`; tests import from barrel only, never from deep paths
- Every exported function carries JSDoc with `@param` and `@returns`; internal helpers skip JSDoc
- Money is always integer cents; never use floats; round fractions with `Math.round` at the boundary
- Percentage params must be validated to inclusive 0..100; throw `AppError('E_RANGE', ...)` on violation
- Invalid argument types throw `AppError('E_TYPE', ...)`; never throw bare strings or generic `Error` for expected failures
- ESLint enforces `no-var` and `prefer-const`

## Testing
- Use `node:test` + `node:assert/strict`
- Error-path assertions check `.code` on the thrown `AppError`, not message text

## Commits
- Conventional commits: `feat:`, `fix:`, `chore:`, `docs:`
- Subject ≤ 72 chars, imperative mood
- One feature/fix per PR; user-visible changes add a line to CHANGELOG.md Unreleased section
