#!/usr/bin/env python3
"""Grade one solution EvalPlus-style: run the candidate against base_input +
plus_input and compare with the canonical solution's output. Exit 0 on pass.

Usage: grade-plus.py <problem-json-file> <solution.py>
"""
import json
import math
import subprocess
import sys
import tempfile

RUNNER = r'''
import json, math, sys

problem = json.load(open(sys.argv[1]))
solution_src = open(sys.argv[2]).read()

ref_ns = {}
exec(problem["prompt"] + problem["canonical_solution"], ref_ns)
ref = ref_ns[problem["entry_point"]]

cand_ns = {}
exec(solution_src, cand_ns)
if problem["entry_point"] not in cand_ns:
    print("FAIL missing entry point"); sys.exit(1)
cand = cand_ns[problem["entry_point"]]

atol = problem.get("atol") or 0

def eq(a, b):
    if atol and isinstance(a, float) and isinstance(b, float):
        return math.isclose(a, b, rel_tol=1e-6, abs_tol=atol)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(eq(x, y) for x, y in zip(a, b))
    if isinstance(a, tuple) and isinstance(b, tuple):
        return len(a) == len(b) and all(eq(x, y) for x, y in zip(a, b))
    return a == b

inputs = problem.get("base_input", []) + problem.get("plus_input", [])
for args in inputs:
    try:
        expected = ref(*[json.loads(json.dumps(a)) for a in args])
    except Exception:
        continue  # input invalid per contract; skip
    try:
        got = cand(*[json.loads(json.dumps(a)) for a in args])
    except Exception as e:
        print(f"FAIL exception on {str(args)[:120]}: {e}"); sys.exit(1)
    if not eq(got, expected):
        print(f"FAIL mismatch on {str(args)[:120]}: got {str(got)[:80]} want {str(expected)[:80]}")
        sys.exit(1)
print("PASS")
'''

def main():
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as tmp:
        tmp.write(RUNNER)
        runner = tmp.name
    try:
        r = subprocess.run(
            [sys.executable, runner, sys.argv[1], sys.argv[2]],
            capture_output=True, timeout=120,
        )
        sys.stdout.buffer.write(r.stdout[-200:] if r.stdout else b"")
        sys.exit(0 if r.returncode == 0 else 1)
    except subprocess.TimeoutExpired:
        print("FAIL timeout")
        sys.exit(1)

if __name__ == "__main__":
    main()
