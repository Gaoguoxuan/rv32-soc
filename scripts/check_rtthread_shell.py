#!/usr/bin/env python3
"""Exercise the RTL CPU's msh through a real terminal and a stdin pipe."""

import fcntl
import os
import pty
import re
import select
import signal
import subprocess
import sys
import termios
import time
from pathlib import Path


PROMPT = b"msh >"
GREETING = b"Hello from my RV32 CPU!"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def test_terminal(simulator, image):
    master, slave = pty.openpty()
    saved_settings = termios.tcgetattr(slave)
    saved_flags = fcntl.fcntl(slave, fcntl.F_GETFL)
    process = subprocess.Popen([simulator, f"+image={image}"],
                               stdin=slave, stdout=slave, stderr=slave)
    buffer = bytearray()
    transcript = bytearray()

    def read_prompt():
        deadline = time.monotonic() + 15
        while True:
            end = buffer.find(PROMPT)
            if end != -1:
                end += len(PROMPT)
                result = bytes(buffer[:end]).replace(b"\r", b"")
                del buffer[:end]
                return result
            require(time.monotonic() < deadline, "Timed out waiting for msh prompt")
            require(process.poll() is None, f"Simulator exited: {process.returncode}")
            if select.select([master], [], [], 0.1)[0]:
                data = os.read(master, 4096)
                require(data, "Terminal closed before prompt")
                buffer.extend(data)
                transcript.extend(data)

    def command(text):
        os.write(master, text)
        return read_prompt()

    def read_tick():
        response = command(b"ticks\n")
        match = re.search(rb"tick=(\d+)", response)
        require(match, f"Missing tick output: {response!r}")
        return int(match[1])

    def read_stats():
        response = command(b"stats\n")
        match = re.search(rb"tick=(\d+) running=([01]) count=(\d+)", response)
        require(match, f"Missing worker statistics: {response!r}")
        return tuple(int(value) for value in match.groups())

    def wait_stats(before, running, frozen_count=None):
        # Advance by guest ticks, so the check remains valid on slower hosts.
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            time.sleep(0.02)
            sample = read_stats()
            require(sample[1] == running, f"Wrong worker state: {sample}")
            require(sample[2] >= before[2], f"Worker count went backwards: {before} -> {sample}")
            if frozen_count is not None:
                require(sample[2] == frozen_count,
                        f"Count changed while paused: {frozen_count} -> {sample[2]}")
            if sample[0] - before[0] >= 40:
                return sample
        raise AssertionError(f"Guest tick did not advance by 40 from {before}")

    def check_growth(before, after):
        increment = after[2] - before[2]
        # A relative 10-tick delay permits at most this many increments;
        # shell activity may postpone the worker's actual execution.
        require(0 < increment <= (after[0] - before[0]) // 10 + 1,
                f"Wrong worker progress: {before} -> {after}")

    try:
        boot = read_prompt()
        require(b"4.1.1" in boot, "Missing RT-Thread version")
        require(not termios.tcgetattr(slave)[3] & (termios.ICANON | termios.ECHO),
                "Terminal input was not configured for individual keys")
        help_output = command(b"help\n")
        for name in [b"hello", b"ticks", b"ps", b"version", b"stats", b"pause", b"resume"]:
            require(re.search(rb"(?m)^" + name + rb"\s+-", help_output),
                    f"Command absent from help: {name!r}")
        require(command(b"hello\n").count(GREETING) == 1, "hello failed")
        processes = command(b"ps\n")
        require(re.search(rb"tshell\s+20\s+running", processes), "Missing running shell thread")
        require(re.search(rb"tidle0\s+31\s+ready", processes), "Missing ready idle thread")
        worker_rows = re.findall(rb"(?m)^worker\s+21\s+(?:ready|suspend)\s+0x[0-9a-f]+\s+0x00000800\s+", processes)
        require(len(worker_rows) == 1, "Missing worker thread with its 2 KiB stack")
        require(b"4.1.1" in command(b"version\n"), "version failed")
        first = read_tick()
        time.sleep(0.12)
        second = read_tick()
        require(second - first >= 3, f"Tick stopped while waiting for keys: {first} -> {second}")

        active_before = read_stats()
        require(active_before[1] == 1, f"Worker did not start enabled: {active_before}")
        active_after = wait_stats(active_before, running=1)
        check_growth(active_before, active_after)

        require(b"worker paused\n" in command(b"pause\n"), "pause failed")
        paused = read_stats()
        require(paused[1] == 0 and paused[2] >= active_after[2], "pause reset the count or failed")
        require(b"worker paused\n" in command(b"pause\n"), "Repeated pause failed")
        paused_after = wait_stats(paused, running=0, frozen_count=paused[2])

        require(b"worker resumed\n" in command(b"resume\n"), "resume failed")
        resumed = read_stats()
        require(resumed[1] == 1 and resumed[2] >= paused[2], "resume reset the count or failed")
        require(b"worker resumed\n" in command(b"resume\n"), "Repeated resume failed")
        resumed_after = wait_stats(resumed, running=1)
        check_growth(resumed, resumed_after)

        # Repeated control must preserve one worker and the accumulated count.
        previous_count = resumed_after[2]
        for _ in range(3):
            require(b"worker paused\n" in command(b"pause\n"), "Rapid pause failed")
            stopped = read_stats()
            require(stopped[1] == 0 and stopped[2] >= previous_count, "Rapid pause lost state")
            require(b"worker resumed\n" in command(b"resume\n"), "Rapid resume failed")
            restarted = read_stats()
            require(restarted[1] == 1 and restarted[2] >= stopped[2], "Rapid resume lost state")
            previous_count = restarted[2]
        processes = command(b"ps\n")
        require(len(re.findall(rb"(?m)^worker\s+21\s+", processes)) == 1,
                "Control commands created duplicate workers")
        print(f"[PASS] {image}: worker count {active_before[2]}->{active_after[2]}, "
              f"paused at {paused[2]} for {paused_after[0] - paused[0]} ticks, "
              f"resumed {resumed[2]}->{resumed_after[2]}, repeated control")

        require(b"command not found" in command(b"no_such_cmd\n"), "Unknown command was not rejected")
        require(command(b"hellx\x7fo\n").count(GREETING) == 1, "Backspace editing failed")
        # Completion and history redraw the prompt before Enter executes the
        # command. Consume that redraw separately from the final prompt.
        os.write(master, b"hell\t")
        read_prompt()
        require(command(b"\n").count(GREETING) == 1, "Tab completion failed")
        os.write(master, b"\x1b[A")
        read_prompt()
        require(command(b"\n").count(GREETING) == 1, "Command history failed")
        require(command(b"  hello a b\n").count(GREETING) == 1, "Command with arguments failed")
        require(command(b"\n") == b"\n" + PROMPT, "Empty line failed")

        process.send_signal(signal.SIGINT)
        require(process.wait(timeout=5) == 0, "Ctrl-C did not exit cleanly")
        require(termios.tcgetattr(slave) == saved_settings, "Terminal settings were not restored")
        require(fcntl.fcntl(slave, fcntl.F_GETFL) == saved_flags, "stdin flags were not restored")
        print(f"[PASS] {image}: help/hello/ps/version/ticks, idle tick {first}->{second}, editing, history, Ctrl-C")
    except Exception:
        print(transcript.decode(errors="replace"), file=sys.stderr)
        raise
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        os.close(master)
        os.close(slave)


def test_pipe(simulator, image):
    commands = [b"hello", b"pause", b"stats", b"resume", b"stats", b"ps"]
    result = subprocess.run([simulator, f"+image={image}"], input=b"\n".join(commands) + b"\n",
                            capture_output=True, timeout=20)
    require(result.returncode == 0, f"Pipe run failed: {result.stderr!r}")
    require(result.stdout.count(GREETING) == 1, "Pipe input was lost or repeated")
    require(b"tshell" in result.stdout and b"worker" in result.stdout and
            result.stdout.count(PROMPT) == len(commands) + 1,
            f"Pipe commands did not finish: {result.stdout!r}")
    states = re.findall(rb"tick=\d+ running=([01]) count=(\d+)", result.stdout)
    require(len(states) == 2 and states[0][0] == b"0" and states[1][0] == b"1",
            f"Pipe control commands failed: {result.stdout!r}")
    require(int(states[1][1]) >= int(states[0][1]), "Pipe resume reset the count")
    print(f"[PASS] {image}: pipe input, buffered control commands and EOF exit")


def main():
    require(len(sys.argv) >= 3, "Usage: check_rtthread_shell.py simulator image [image ...]")
    simulator = str(Path(sys.argv[1]).resolve())
    for image in sys.argv[2:]:
        test_terminal(simulator, image)
        test_pipe(simulator, image)
    print("RT-THREAD SHELL O0/O2 CHECKS PASS")


if __name__ == "__main__":
    main()
