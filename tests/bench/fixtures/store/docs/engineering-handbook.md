# Engineering handbook

Team-wide engineering rules for store-app. Reviewers enforce these in every
PR; ESLint only covers a subset.

## Module structure

- Every public function exported from a module under `src/` must also be
  re-exported from the `src/index.js` barrel. Application code and tests
  import from the barrel, never from deep paths.
- Every exported function carries a JSDoc block with `@param` and `@returns`
  annotations. Internal helpers do not need JSDoc.

## Data rules

- Monetary amounts are always integer cents. Never represent money as floats;
  when a computation produces a fraction, round to the nearest cent at the
  boundary (`Math.round`).
- Functions that accept a percentage validate it to the inclusive range
  0..100 and throw `AppError('E_RANGE', ...)` on violation.
- Invalid argument types throw `AppError('E_TYPE', ...)`. We never throw bare
  strings or generic `Error` for expected failure modes.

## Testing

- Tests live in `test/` and use the built-in `node:test` runner with
  `node:assert/strict`. Name files `<module>.test.js`.
- Error-path assertions check the `code` property of the thrown `AppError`,
  not the message text, because messages are allowed to change.
