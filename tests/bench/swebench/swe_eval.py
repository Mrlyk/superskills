#!/usr/bin/env python3
"""Thin wrapper over `swebench.harness.run_evaluation` that forces the image
architecture (default arm64) so the harness builds NATIVE images on Apple
Silicon instead of x86_64-under-QEMU (which is unusably slow here).

swebench 4.1.0 hardcodes arch="x86_64" in make_test_spec and never threads a
host-arch override through the CLI, so we patch the function's default. For the
pure-python repos in our subset, arm64 test outcomes match x86_64 (validated
with the gold patch). Override with SWE_ARCH=x86_64 to fall back.

  swe_eval.py <same args as run_evaluation>
"""
import os
import runpy
import sys

import swebench.harness.test_spec.test_spec as ts

ARCH = os.environ.get("SWE_ARCH", "arm64")
_defaults = list(ts.make_test_spec.__defaults__)
_defaults[-1] = ARCH  # arch is the last keyword-defaulted param
ts.make_test_spec.__defaults__ = tuple(_defaults)

sys.argv = ["run_evaluation"] + sys.argv[1:]
runpy.run_module("swebench.harness.run_evaluation", run_name="__main__")
