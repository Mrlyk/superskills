---
title: Run node:test with bare `node --test`, never a directory argument
date: 2026-06-13
tags: [bench, node]
---
**Context**: any script or fixture that runs the node:test suite (graders, package.json test scripts)
**Rule**: use `node --test` with no path argument; node 22.22 treats `node --test test/` as a module entry and fails with MODULE_NOT_FOUND
**Why**: directory arguments to --test changed behavior across node 22.x; the no-arg form scans default test locations reliably
