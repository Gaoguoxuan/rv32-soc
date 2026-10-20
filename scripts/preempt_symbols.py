#!/usr/bin/env python3
"""Export firmware entry points and RAM locations for the preemption monitor."""

import subprocess
import sys
from pathlib import Path


def main():
    nm, elf, destination = sys.argv[1:4]
    names = ("preempt_trap_entry", "trap_dispatch", "thread_entry", "thread_exit",
             "frames", "threads", "current", "stack_a", "stack_b", "main_stack_guard")
    symbols = {}
    for line in subprocess.check_output([nm, "-n", elf], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in names:
            symbols[fields[2]] = int(fields[0], 16)
    missing = set(names) - symbols.keys()
    if missing:
        raise SystemExit(f"Missing preempt-test symbols: {sorted(missing)}")
    Path(destination).write_text("".join(f"{symbols[name]:08x}\n" for name in names))


if __name__ == "__main__":
    main()
