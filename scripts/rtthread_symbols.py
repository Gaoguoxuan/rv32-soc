#!/usr/bin/env python3
"""Check the linked firmware ISA and export RT-Thread test symbols."""

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
    elif mode == "sched":
        names = ("rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_system_scheduler_start",
                 "rt_thread_yield", "sched_entry", "finish_entry", "_thread_exit",
                 "thread_locations", "stack_a", "stack_b", "stack_check", "rounds",
                 "normal_returns", "critical_passes", "trace", "trace_count",
                 "data_cookie", "stack_guard", "__stack_bottom", "__stack_top",
                 "rt_current_thread", "rt_interrupt_nest", "rt_interrupt_from_thread",
                 "rt_interrupt_to_thread", "rt_thread_switch_interrupt_flag",
                 "rt_schedule", "rt_thread_init", "rt_thread_startup", "arguments")
        strong = ("rt_hw_context_switch_to", "rt_hw_context_switch",
                  "rt_hw_context_switch_interrupt", "rt_system_scheduler_start",
                  "rt_thread_yield", "rt_schedule", "rt_thread_init", "rt_thread_startup")
    elif mode == "tick":
        names = ("rt_hw_trap_entry", "rt_hw_trap_dispatch", "rt_hw_context_restore",
                 "rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_hw_tick_init", "rt_hw_tick_rearm",
                 "rt_interrupt_enter", "rt_interrupt_leave", "rt_tick_increase", "rt_tick",
                 "tick_entry", "finish_entry", "_thread_exit", "thread_locations",
                 "stack_a", "stack_b", "stack_check", "arguments", "progress", "checksums",
                 "normal_returns", "stopped_tick", "data_cookie", "stack_guard",
                 "__stack_bottom", "__stack_top", "rt_current_thread", "rt_interrupt_nest",
                 "rt_interrupt_from_thread", "rt_interrupt_to_thread",
                 "rt_thread_switch_interrupt_flag", "rt_thread_init", "rt_thread_startup")
        strong = names[:11]
    elif mode == "delay":
        names = ("rt_hw_trap_entry", "rt_hw_trap_dispatch", "rt_hw_context_restore",
                 "rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_hw_tick_init", "rt_hw_tick_rearm",
                 "rt_interrupt_enter", "rt_interrupt_leave", "rt_tick_increase", "rt_tick",
                 "delay_entry", "finish_entry", "_thread_exit", "thread_locations",
                 "stack_a", "stack_b", "stack_check", "arguments", "wake_count",
                 "sleep_tick", "wake_tick", "normal_returns", "cleanup_mask", "idle_hits",
                 "data_cookie", "stack_guard", "__stack_bottom", "__stack_top",
                 "rt_current_thread", "rt_interrupt_nest", "rt_interrupt_from_thread",
                 "rt_interrupt_to_thread", "rt_thread_switch_interrupt_flag", "rt_thread_init",
                 "rt_thread_startup", "rt_thread_idle_entry", "rt_thread_stack", "idle_hook",
                 "thread_cleanup", "rt_thread_delay", "_thread_timeout")
        strong = names[:11] + ("rt_thread_delay",)
    elif mode == "sem":
        names = ("rt_hw_trap_entry", "rt_hw_trap_dispatch", "rt_hw_context_restore",
                 "rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_hw_tick_init", "rt_hw_tick_rearm",
                 "rt_interrupt_enter", "rt_interrupt_leave", "rt_tick_increase", "rt_tick",
                 "consumer_entry", "producer_entry", "finish_entry", "_thread_exit",
                 "thread_locations", "sem_locations", "event_sem", "stack_a", "stack_b",
                 "stack_check", "produced", "consumed", "release_returned", "timeout_ok",
                 "credit_ok", "normal_returns", "cleanup_mask", "idle_hits", "data_cookie",
                 "stack_guard", "__stack_bottom", "__stack_top", "rt_current_thread",
                 "rt_interrupt_nest", "rt_interrupt_from_thread", "rt_interrupt_to_thread",
                 "rt_thread_switch_interrupt_flag", "rt_thread_idle_entry", "rt_thread_stack",
                 "idle_hook", "thread_cleanup", "rt_sem_init", "rt_sem_take", "rt_sem_release",
                 "rt_sem_detach", "rt_thread_delay", "_thread_timeout")
        strong = names[:11] + ("rt_sem_init", "rt_sem_take", "rt_sem_release", "rt_sem_detach")
    elif mode == "mutex":
        names = ("rt_hw_trap_entry", "rt_hw_trap_dispatch", "rt_hw_context_restore",
                 "rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_hw_tick_init", "rt_hw_tick_rearm",
                 "rt_interrupt_enter", "rt_interrupt_leave", "rt_tick_increase", "rt_tick",
                 "high_entry", "low_entry", "finish_entry", "_thread_exit",
                 "thread_locations", "mutex_locations", "resource_lock", "stack_a", "stack_b",
                 "stack_check", "high_waiting", "inherit_ok", "high_done", "medium_runs",
                 "low_release_returned", "normal_returns", "cleanup_mask", "idle_hits", "data_cookie",
                 "stack_guard", "__stack_bottom", "__stack_top", "rt_current_thread",
                 "rt_interrupt_nest", "rt_interrupt_from_thread", "rt_interrupt_to_thread",
                 "rt_thread_switch_interrupt_flag", "rt_thread_idle_entry", "rt_thread_stack",
                 "idle_hook", "thread_cleanup", "rt_mutex_init", "rt_mutex_take", "rt_mutex_release",
                 "rt_mutex_detach", "rt_thread_delay", "_thread_timeout", "rt_thread_control")
        strong = names[:11] + ("rt_mutex_init", "rt_mutex_take", "rt_mutex_release",
                               "rt_mutex_detach", "rt_thread_control")
    elif mode == "demo":
        names = ("rt_hw_trap_entry", "rt_hw_trap_dispatch", "rt_hw_context_restore",
                 "rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_hw_tick_init", "rt_hw_tick_rearm",
                 "rt_interrupt_enter", "rt_interrupt_leave", "rt_tick_increase", "rt_tick",
                 "consumer_entry", "producer_entry", "heartbeat_entry", "_thread_exit",
                 "thread_locations", "mutex_locations", "app_lock", "stack_a", "stack_b",
                 "stack_check", "produced", "consumed", "heartbeats", "sample_slot",
                 "sem_locations", "empty_slot", "full_slot", "idle_hits", "data_cookie",
                 "stack_guard", "__stack_bottom", "__stack_top", "rt_current_thread",
                 "rt_interrupt_nest", "rt_interrupt_from_thread", "rt_interrupt_to_thread",
                 "rt_thread_switch_interrupt_flag", "rt_thread_idle_entry", "rt_thread_stack",
                 "idle_hook", "rt_kprintf", "rt_sem_init", "rt_sem_take", "rt_sem_release",
                 "rt_mutex_init", "rt_mutex_take", "rt_mutex_release", "rt_thread_delay_until",
                 "_thread_timeout", "fail", "rt_hw_console_output", "rt_thread_suspend",
                 "rt_thread_resume")
        strong = names[:11] + ("rt_sem_init", "rt_sem_take", "rt_sem_release",
                               "rt_mutex_init", "rt_mutex_take", "rt_mutex_release",
                               "rt_thread_delay_until", "rt_hw_console_output")
    elif mode == "input":
        names = ("rt_hw_console_getchar", "rt_thread_delay", "rt_tick",
                 "rt_current_thread", "rt_interrupt_nest", "input_locations",
                 "received", "received_bytes", "received_ticks", "heartbeats",
                 "before_input_beats", "gap_beats", "idle_hits", "receiver_done",
                 "cleanup_done", "rt_hw_trap_entry", "rt_hw_trap_dispatch",
                 "rt_hw_context_restore", "rt_hw_context_switch_to",
                 "rt_hw_context_switch", "rt_hw_context_switch_interrupt",
                 "rt_hw_tick_init", "rt_hw_tick_rearm", "rt_hw_console_output")
        strong = (names[0], names[1]) + names[15:]
    elif mode == "shell":
        names = ("finsh_system_init", "finsh_thread_entry", "msh_exec", "msh_help",
                 "cmd_ps", "list_thread", "hello", "ticks", "__fsymtab_start",
                 "__fsymtab_end", "rt_hw_console_getchar", "rt_hw_console_output",
                 "rt_hw_trap_entry", "rt_hw_trap_dispatch", "rt_hw_context_restore",
                 "rt_hw_context_switch_to", "rt_hw_context_switch",
                 "rt_hw_context_switch_interrupt", "rt_hw_tick_init", "rt_hw_tick_rearm")
        strong = names[:6] + names[10:]
        names += ("worker_entry", "stats", "pause_work", "resume_work",
                  "worker_thread", "worker_stack", "worker_running", "work_count",
                  "worker_wakeup", "worker_waiting", "rt_sem_init", "rt_sem_take",
                  "rt_sem_release")
        strong += ("rt_sem_init", "rt_sem_take", "rt_sem_release")
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

    if mode == "shell":
        start, end = symbols["__fsymtab_start"], symbols["__fsymtab_end"]
        if not 0 <= start < end <= 65536 or (end - start) % 12:
            raise SystemExit("Invalid RV32 FinSH command table")
        print(f"[PASS] {elf}: {(end - start) // 12} retained FinSH commands")

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
