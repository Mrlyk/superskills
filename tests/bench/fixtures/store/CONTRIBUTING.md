# Contributing to store-app

Thanks for contributing. Please read this document before opening a PR.

## Getting set up

We use pnpm as the package manager (the CI cache is keyed on `pnpm-lock.yaml`),
so always install dependencies with `pnpm install`. Run the test suite with
`pnpm test` before pushing.

## Pull request process

Keep PRs small and focused. One feature or fix per PR. Describe the user-facing
behavior change in the description, and link the tracking issue when there is
one. A maintainer review is required before merge; CI must be green.

Code and testing guidelines live in the engineering handbook under `docs/`;
reviewers will hold PRs to it.

## Commit messages

Use conventional commits (`feat:`, `fix:`, `chore:`, `docs:`). The subject line
stays under 72 characters and describes the change in the imperative mood.

## Release notes

Maintainers cut releases monthly. If your change is user-visible, add a line
to the Unreleased section of CHANGELOG.md in the same PR.
