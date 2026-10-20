#!/usr/bin/env python3
"""Check the linked firmware ISA and export console/start-test symbols."""

import re
import subprocess
import sys
from pathlib import Path


def main():
    prefix, elf, destination = sys.argv[1:4]
    mode = sys.argv[4] if len(sys.argv) > 4 else "console"
    if mode == "console":
        names = ("rt_show_version", "rt_kprintf", "rt_hw_console_output",
                 "rt_hw_interrupt_disable", "rt_hw_interrupt_enable", "data_cookie",
                 "test_stage", "stack_guard", "__stack_bottom", "__stack_top")
        strong = ("rt_hw_console_output", "rt_hw_interrupt_disable", "rt_hw_interrupt_enable")
    elif mode == "start":
        names = ("rt_hw_stack_init", "rt_hw_context_switch_to", "start_entry", "start_exit",
                 "probe", "stack_a", "stack_b", "arguments", "current", "entries", "exits",
                 "data_cookie", "stack_guard", "__stack_bottom", "__stack_top")
        strong = ("rt_hw_stack_init", "rt_hw_context_switch_to")
    else:
        raise SystemExit(f"Unknown RT-Thread test mode: {mode}")
    symbols = {}
    types = {}
    for line in subprocess.check_output([prefix + "nm", "-n", elf], text=True).splitlines():
        fields = line.split()
        if len(fields) == 3 and fields[2] in names:
            symbols[fields[2]] = int(fields[0], 16)
            types[fields[2]] = fields[1]
    missing = set(names) - symbols.keys()
    if missing:
        raise SystemExit(f"Missing RT-Thread test symbols: {sorted(missing)}")
    for name in strong:
        if types[name] != "T":
            raise SystemExit(f"Expected a strong port implementation: {name} ({types[name]})")

    # Include libgcc in this check: the CPU has no M/A/F/D/C instructions.
    allowed_opcodes = {0x03, 0x13, 0x17, 0x23, 0x33, 0x37, 0x63, 0x67, 0x6f, 0x73}
    count = 0
    dump = subprocess.check_output([prefix + "objdump", "-d", "-M", "no-aliases", elf], text=True)
    for line in dump.splitlines():
        match = re.match(r"\s*[0-9a-f]+:\s+([0-9a-f]+)\s+", line)
        if not match:
            continue
        raw = match[1]
        word = int(raw, 16)
        if (len(raw) != 8 or word & 3 != 3 or word & 0x7f not in allowed_opcodes or
                (word & 0x7f == 0x33 and (word >> 25) not in (0, 0x20))):
            raise SystemExit(f"Unsupported instruction in linked firmware: {line.strip()}")
        count += 1
    if count == 0:
        raise SystemExit("No executable instructions found")
    Path(destination).write_text("".join(f"{symbols[name]:08x}\n" for name in names))
    print(f"[PASS] {elf}: {count} RV32I/Zicsr instructions; strong port implementations")


if __name__ == "__main__":
    main()
