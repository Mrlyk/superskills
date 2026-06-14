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

Used at runtime, NOT vendored (loaded from Hugging Face by `tests/bench/swe-bench.sh`):

- SWE-bench Lite (`SWE-bench/SWE-bench_Lite`) — the third community benchmark,
  real multi-file repository bug fixes. Dataset © Princeton NLP / the SWE-bench
  authors (MIT). Graded by the official `swebench` harness (Apache-2.0) in Docker.
