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

    try:
        boot = read_prompt()
        require(b"4.1.1" in boot, "Missing RT-Thread version")
        require(not termios.tcgetattr(slave)[3] & (termios.ICANON | termios.ECHO),
                "Terminal input was not configured for individual keys")
        help_output = command(b"help\n")
        for name in [b"hello", b"ticks", b"ps", b"version"]:
            require(re.search(rb"(?m)^" + name + rb"\s+-", help_output),
                    f"Command absent from help: {name!r}")
        require(command(b"hello\n").count(GREETING) == 1, "hello failed")
        processes = command(b"ps\n")
        require(re.search(rb"tshell\s+20\s+running", processes), "Missing running shell thread")
        require(re.search(rb"tidle0\s+31\s+ready", processes), "Missing ready idle thread")
        require(b"4.1.1" in command(b"version\n"), "version failed")
        first = read_tick()
        time.sleep(0.12)
        second = read_tick()
        require(second - first >= 3, f"Tick stopped while waiting for keys: {first} -> {second}")
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
    result = subprocess.run([simulator, f"+image={image}"], input=b"hello\nps\n",
                            capture_output=True, timeout=20)
    require(result.returncode == 0, f"Pipe run failed: {result.stderr!r}")
    require(result.stdout.count(GREETING) == 1, "Pipe input was lost or repeated")
    require(b"tshell" in result.stdout and result.stdout.count(PROMPT) == 3,
            f"Pipe commands did not finish: {result.stdout!r}")
    print(f"[PASS] {image}: pipe input, buffered commands and EOF exit")


def main():
    require(len(sys.argv) >= 3, "Usage: check_rtthread_shell.py simulator image [image ...]")
    simulator = str(Path(sys.argv[1]).resolve())
    for image in sys.argv[2:]:
        test_terminal(simulator, image)
        test_pipe(simulator, image)
    print("RT-THREAD SHELL O0/O2 CHECKS PASS")


if __name__ == "__main__":
    main()
