---
title: Timestamps are ISO-8601 UTC
date: 2026-05-01
tags: [conventions, time]
---
**Context**: any timestamp stored or returned by the API
**Rule**: always produce timestamps as ISO-8601 UTC strings via new Date().toISOString(), never epoch milliseconds
**Why**: the downstream analytics pipeline only parses ISO-8601
