#include "Vrtthread_shell.h"
#include "verilated.h"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <fcntl.h>
#include <fstream>
#include <iostream>
#include <poll.h>
#include <stdexcept>
#include <string>
#include <termios.h>
#include <thread>
#include <unistd.h>

static volatile std::sig_atomic_t stopping = 0;

static void stop_simulation(int)
{
    stopping = 1;
}

class Terminal {
    termios saved_{};
    bool changed_ = false;
    int flags_ = -1;

public:
    Terminal()
    {
        flags_ = fcntl(STDIN_FILENO, F_GETFL);
        if (flags_ == -1)
            throw std::runtime_error("Cannot read stdin flags");
        if (isatty(STDIN_FILENO)) {
            if (tcgetattr(STDIN_FILENO, &saved_) == -1)
                throw std::runtime_error("Cannot read terminal settings");
            termios settings = saved_;
            settings.c_lflag &= ~(ICANON | ECHO | IEXTEN);
            settings.c_iflag &= ~(IXON | IXOFF);
            settings.c_cc[VMIN] = 1;
            settings.c_cc[VTIME] = 0;
            if (tcsetattr(STDIN_FILENO, TCSANOW, &settings) == -1)
                throw std::runtime_error("Cannot configure terminal");
            changed_ = true;
        }
        if (fcntl(STDIN_FILENO, F_SETFL, flags_ | O_NONBLOCK) == -1) {
            restore();
            throw std::runtime_error("Cannot configure nonblocking stdin");
        }
    }

    void restore() const
    {
        if (flags_ != -1) (void)fcntl(STDIN_FILENO, F_SETFL, flags_);
        if (changed_) (void)tcsetattr(STDIN_FILENO, TCSANOW, &saved_);
    }

    ~Terminal() { restore(); }
    Terminal(const Terminal&) = delete;
    Terminal& operator=(const Terminal&) = delete;
};

static void read_input(std::deque<unsigned char>& pending, bool& eof)
{
    unsigned char buffer[256];
    constexpr std::size_t capacity = 4096;
    while (!eof && pending.size() < capacity && !stopping) {
        const auto count = read(STDIN_FILENO, buffer,
                                std::min(sizeof(buffer), capacity - pending.size()));
        if (count > 0) {
            pending.insert(pending.end(), buffer, buffer + count);
        } else if (count == 0) {
            eof = true;
        } else if (errno == EINTR) {
            continue;
        } else if (errno == EAGAIN || errno == EWOULDBLOCK) {
            break;
        } else {
            throw std::runtime_error("Cannot read stdin");
        }
    }
}

static void write_output(unsigned char byte)
{
    while (!stopping) {
        if (write(STDOUT_FILENO, &byte, 1) == 1) return;
        if (errno == EINTR) continue;
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            pollfd output{STDOUT_FILENO, POLLOUT, 0};
            (void)poll(&output, 1, 50);
            continue;
        }
        throw std::runtime_error("Cannot write console output");
    }
}

int main(int argc, char** argv)
{
    try {
        std::string image_path;
        for (int i = 1; i < argc; ++i) {
            const std::string argument = argv[i];
            if (argument.rfind("+image=", 0) == 0)
                image_path = argument.substr(7);
            else
                throw std::runtime_error("Usage: Vrtthread_shell +image=firmware.hex");
        }
        if (image_path.empty() || !std::ifstream(image_path).good())
            throw std::runtime_error("Supply +image= with an existing firmware image");

        std::signal(SIGINT, stop_simulation);
        std::signal(SIGTERM, stop_simulation);
        std::signal(SIGPIPE, SIG_IGN);
        VerilatedContext context;
        context.commandArgs(argc, argv);
        Vrtthread_shell soc{&context};
        soc.clk = 0;
        soc.rst = 1;
        soc.uart_rx_valid = 0;
        soc.uart_rx_data = 0;
        soc.eval();

        // The model uses 1 ps precision, with a 10 MHz CPU clock.
        for (int i = 0; i < 3; ++i) {
            context.timeInc(50000);
            soc.clk = 1;
            soc.eval();
            context.timeInc(50000);
            soc.clk = 0;
            soc.eval();
        }
        soc.rst = 0;
        soc.eval();
        Terminal terminal;
        if (isatty(STDIN_FILENO))
            std::cerr << "RISC-V RT-Thread shell (Ctrl-C to exit)\n";

        std::deque<unsigned char> pending;
        bool eof = false;
        std::uint64_t cycles = 0, drained_cycles = 0;
        const auto started = std::chrono::steady_clock::now();
        while (!stopping && !context.gotFinish()) {
            if (cycles % 1000 == 0) read_input(pending, eof);
            soc.uart_rx_valid = !pending.empty();
            soc.uart_rx_data = pending.empty() ? 0 : pending.front();
            soc.eval(); // Settle ready, including a possible CPU ACK write.
            const bool accepted = soc.uart_rx_valid && soc.uart_rx_ready;
            if (soc.fault)
                throw std::runtime_error("CPU fault at PC=" + std::to_string(soc.pc));

            context.timeInc(50000);
            soc.clk = 1;
            soc.eval();
            if (accepted) pending.pop_front();
            if (soc.uart_tx_valid) write_output(soc.uart_tx_data);
            context.timeInc(50000);
            soc.clk = 0;
            soc.eval();
            ++cycles;

            // On pipe EOF, allow 10 simulated milliseconds for the final
            // buffered byte and command output before closing the simulator.
            if (eof && pending.empty()) ++drained_cycles;
            else drained_cycles = 0;
            if (drained_cycles == 100000) break;

            // Continue ticking while the user thinks; cap simulation speed
            // to the board's nominal clock instead of busy-waiting at stdin.
            if (cycles % 10000 == 0)
                std::this_thread::sleep_until(started + std::chrono::nanoseconds(cycles * 100));
        }
        soc.final();
        if (stopping && isatty(STDIN_FILENO)) std::cerr << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Shell simulator: " << error.what() << '\n';
        return 1;
    }
}
