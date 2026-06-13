# Attribution

Vendored from the OpenAI HumanEval dataset, unmodified:

- `problems.jsonl` — the first 10 problems (HumanEval/0–9), used as the
  benchmark control group.
- `HumanEval.jsonl.gz` — the full 164-problem dataset, used by the
  hard-subset community benchmark (`tests/bench/heval-hard.sh`).

Source: https://github.com/openai/human-eval (MIT License, Copyright (c) 2021 OpenAI)

Vendored from the EvalPlus project, unmodified (stricter graders, ~80× the tests):

- `HumanEvalPlus.jsonl.gz` — HumanEval+ (used by `heval-hard.sh --plus`).
- `MbppPlus.jsonl.gz` — MBPP+ (used by `heval-hard.sh --mbpp`); the underlying
  MBPP problems are © Google, MIT.

Source: https://github.com/evalplus/evalplus (Apache-2.0)
