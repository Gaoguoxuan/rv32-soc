#!/usr/bin/env python3
"""Require the invalid-capacity simulations to fail for the intended reason."""

import resource
import subprocess


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    cases = (
        ("build/obj_memory_bad_rom/Vtb_soc_memory_params", "Invalid ROM_BYTES: 12"),
        ("build/obj_memory_bad_ram/Vtb_soc_memory_params", "Invalid RAM_BYTES: 12"),
    )
    for binary, diagnostic in cases:
        result = subprocess.run([binary], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, check=False)
        if result.returncode == 0 or diagnostic not in result.stdout:
            raise SystemExit(f"Expected rejection '{diagnostic}', exit={result.returncode}\n{result.stdout}")
        print(f"[PASS] rejected {diagnostic}")
    print("M10.1 MEMORY PARAMETER CHECKS PASS")


if __name__ == "__main__":
    main()
