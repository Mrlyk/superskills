## Auto-learning generation (standard) — results

Does the Stop-hook instruction make the model persist the right learnings? Both arms see the same finished session (two corrections only stated in dialogue, invisible in code). Arm B appends the real stop-learn reason; arm A appends a neutral close.

| Metric | Baseline (no hook reason) | With superskills (stop-learn) |
|--------|---------------------------|-------------------------------|
| Mean score | 0% | 100% |
| generated | 0/3 | 3/3 |
| capturesIsoRule | 0/3 | 3/3 |
| capturesCentsRule | 0/3 | 3/3 |
| indexUpdated | 0/3 | 3/3 |
| formatOk | 0/3 | 3/3 |
| concise | 0/3 | 3/3 |

Trials: 3 baseline / 3 superskills.
