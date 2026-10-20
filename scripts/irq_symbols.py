#!/usr/bin/env python3
"""Export the IRQ API test's entry points, phases, and stack bounds."""

import subprocess
import sys
from pathlib import Path


def main():
    nm, elf, destination = sys.argv[1:4]
    names = ("trap_entry", "trap_handler", "phase", "irq_count", "isr_checks_done",
             "protected_value", "stack_guard", "__stack_bottom", "__stack_top")
    symbols = {}
    for line in subprocess.check_output([nm, "-n", elf], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in names:
            symbols[fields[2]] = int(fields[0], 16)
    missing = set(names) - symbols.keys()
    if missing:
        raise SystemExit(f"Missing irq-test symbols: {sorted(missing)}")
    Path(destination).write_text("".join(f"{symbols[name]:08x}\n" for name in names))


if __name__ == "__main__":
    main()
