---
title: Timestamps are ISO-8601 UTC strings
date: 2026-05-28
tags: [data]
---
**Context**: any field or API that records a point in time
**Rule**: store timestamps as ISO-8601 UTC strings (new Date().toISOString()); never epoch milliseconds
**Why**: downstream analytics pipeline parses ISO strings only
