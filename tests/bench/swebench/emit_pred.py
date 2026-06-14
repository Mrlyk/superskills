#!/usr/bin/env python3
"""Emit one SWE-bench prediction JSON line (safely escaped) to stdout.

  emit_pred.py <instance_id> <model_name> <patch_file>
"""
import json
import sys


def main():
    iid, model, patch_file = sys.argv[1], sys.argv[2], sys.argv[3]
    with open(patch_file, "r", errors="replace") as f:
        patch = f.read()
    print(json.dumps({
        "instance_id": iid,
        "model_name_or_path": model,
        "model_patch": patch,
    }))


if __name__ == "__main__":
    main()
