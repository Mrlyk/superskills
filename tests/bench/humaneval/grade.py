#!/usr/bin/env python3
"""Grade one HumanEval solution: exit 0 when the canonical tests pass.

Usage: grade.py <problem-json-file> <solution.py>
"""
import json
import subprocess
import sys
import tempfile

def main():
    with open(sys.argv[1]) as f:
        problem = json.load(f)
    with open(sys.argv[2]) as f:
        solution = f.read()

    program = (
        solution
        + "\n\n"
        + problem["test"]
        + f"\n\ncheck({problem['entry_point']})\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as tmp:
        tmp.write(program)
        path = tmp.name

    try:
        result = subprocess.run(
            [sys.executable, path], capture_output=True, timeout=15
        )
        sys.exit(0 if result.returncode == 0 else 1)
    except subprocess.TimeoutExpired:
        sys.exit(1)

if __name__ == "__main__":
    main()
