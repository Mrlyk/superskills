---
title: Benchmark graders must handle multilingual model output
date: 2026-06-13
tags: [bench, grading]
---
**Context**: writing deterministic graders that pattern-match model responses (e.g. detecting clarifying questions)
**Rule**: match fullwidth and ASCII punctuation (`/[?？]/`), include Chinese keywords alongside English, and match per-line so ternaries in code blocks do not false-positive
**Why**: the model answers in the user's language; an ASCII-only `includes('?')` misgraded correct Chinese clarifying questions in the S3 run
