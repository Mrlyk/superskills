#!/usr/bin/env python3
"""Dump SWE-bench Lite instance fields + the swebench env spec for one or more
instance ids, so the bash harness can build a local runnable checkout.

  swe_instance.py dump <outdir> <instance_id> [<instance_id> ...]

Writes, per instance, <outdir>/<instance_id>/{problem_statement.txt,meta.json}.
meta.json carries the repo, base_commit, the python version + install commands
swebench uses for that (repo, version), and the held-out FAIL_TO_PASS /
PASS_TO_PASS test ids (used only by the grader, never shown to the model).
"""
import json
import os
import sys

from datasets import load_dataset

from swebench.harness.constants import MAP_REPO_VERSION_TO_SPECS

DATASET = os.environ.get("SWE_DATASET", "SWE-bench/SWE-bench_Lite")
SPLIT = os.environ.get("SWE_SPLIT", "test")


def write_instance(record, spec, outdir):
    iid = record["instance_id"]
    d = os.path.join(outdir, iid)
    os.makedirs(d, exist_ok=True)
    meta = {
        "instance_id": iid,
        "repo": record["repo"],
        "base_commit": record["base_commit"],
        "version": record["version"],
        "python": spec.get("python"),
        "install": spec.get("install"),
        "pip_packages": spec.get("pip_packages", []),
        "pre_install": spec.get("pre_install", []),
        "packages": spec.get("packages", ""),
        "FAIL_TO_PASS": json.loads(record["FAIL_TO_PASS"]),
        "PASS_TO_PASS": json.loads(record["PASS_TO_PASS"]),
    }
    with open(os.path.join(d, "problem_statement.txt"), "w") as f:
        f.write(record["problem_statement"])
    with open(os.path.join(d, "meta.json"), "w") as f:
        json.dump(meta, f, indent=2)
    print(f"{iid}\t{meta['repo']}\t{meta['base_commit'][:10]}\tpy{meta['python']}")


def main():
    if len(sys.argv) < 4 or sys.argv[1] != "dump":
        print(__doc__, file=sys.stderr)
        raise SystemExit(2)
    outdir, ids = sys.argv[2], set(sys.argv[3:])
    ds = load_dataset(DATASET, split=SPLIT)
    found = set()
    for r in ds:
        if r["instance_id"] in ids:
            spec = MAP_REPO_VERSION_TO_SPECS[r["repo"]][r["version"]]
            write_instance(r, spec, outdir)
            found.add(r["instance_id"])
    missing = ids - found
    if missing:
        print(f"NOT FOUND: {sorted(missing)}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
