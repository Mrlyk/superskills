---
topic: Timestamps
tags: [conventions, time]
---
# Timestamps

**API responses & storage**: always produce timestamps as ISO-8601 UTC strings via `new Date().toISOString()`, never epoch milliseconds — the downstream analytics pipeline only parses ISO-8601.

Related: [[money]] (both are storage-format conventions).
