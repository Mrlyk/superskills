## Results summary

| Scenario | Measures | Baseline (pure model) | With superskills | Δ | Mean time A → B |
|----------|----------|----------------------|------------------|---|------------------|
| S1 Convention adherence | mean check score | 100% | 100% | +0pp | 54s → 52s |
| S2 Cross-session memory | mean check score | 20% | 100% | +80pp | 39s → 38s |
| S3 Requirement clarification | asked-before-guessing rate | 0% | 67% | +67pp | 98s → 84s |
| S4 Final test pass | mean check score | 40% | 100% | +60pp | 35s → 62s |
| Control: HumanEval/0-9 | pass@1 | 100% | 100% | +0pp | 10s → 10s |

### S1 Convention adherence

superskills component under test: discover artifacts; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| implemented | 3/3 | 3/3 |
| barrelExport | 3/3 | 3/3 |
| jsdoc | 3/3 | 3/3 |
| integerCents | 3/3 | 3/3 |
| rangeError | 3/3 | 3/3 |
| typedError | 3/3 | 3/3 |
| testsCoverAndPass | 3/3 | 3/3 |

### S2 Cross-session memory

superskills component under test: learn + SessionStart hook; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| usesPnpm | 0/3 | 3/3 |
| noPlainNpm | 0/3 | 3/3 |
| isoTimestamp | 0/3 | 3/3 |
| readmeExample | 0/3 | 3/3 |
| testsPass | 3/3 | 3/3 |

### S3 Requirement clarification

superskills component under test: clarify; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| askedKeyQuestion | 0/3 | 2/3 |
| noPrematureCode | 0/3 | 2/3 |

### S4 Final test pass

superskills component under test: test; trials: 3 baseline / 3 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| testsCoverCoupon | 3/3 | 3/3 |
| suitePasses | 3/3 | 3/3 |
| floatBugFixed | 0/3 | 3/3 |
| rangeBugFixed | 0/3 | 3/3 |
| edgeCasesTested | 0/3 | 3/3 |

### Control: HumanEval/0-9

superskills component under test: none (regression check); trials: 10 baseline / 10 superskills.

| Check | Baseline | With superskills |
|-------|----------|------------------|
| pass | 10/10 | 10/10 |

Total model runtime across trials: 26 min.
