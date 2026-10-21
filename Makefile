.RECIPEPREFIX := >

VERILATOR := verilator

TOP := tb_rv32i

SIM := obj_dir/Vtb_rv32i


RTL := \
    rtl/core/alu.sv \
    rtl/core/regfile.sv \
    rtl/core/pc.sv \
    rtl/core/imm_gen.sv \
    rtl/core/decoder.sv \
    rtl/core/branch_unit.sv \
    rtl/core/lsu.sv \
    rtl/core/csr_file.sv \
    rtl/core/cpu_core.sv

# ============================================================
# SoC RTL
# ============================================================

SOC_RTL := \
    rtl/soc/simple_ram.sv \
    rtl/soc/uart_mmio.sv \
    rtl/soc/simple_rom.sv \
    rtl/soc/timer_mmio.sv \
    rtl/soc/rv32_soc.sv

# ============================================================
# UART bare-metal software
# ============================================================

UART_DIR := build/uart

UART_START := sw/uart/start.S
UART_SRC   := sw/uart/main.c
UART_LDS   := sw/uart/link.ld

UART_ELF  := $(UART_DIR)/uart.elf
UART_BIN  := $(UART_DIR)/uart.bin
UART_HEX  := $(UART_DIR)/uart.hex
UART_DUMP := $(UART_DIR)/uart.dump
UART_MAP  := $(UART_DIR)/uart.map

UART_SIM := build/obj_uart/Vtb_soc_uart

UART_CFLAGS := \
    -march=rv32i \
    -mabi=ilp32 \
    -O0 \
    -g \
    -ffreestanding \
    -fno-builtin \
    -fno-pic \
    -msmall-data-limit=0 \
    -nostdlib \
    -nostartfiles

UART_LDFLAGS := \
    -Wl,-T,$(UART_LDS) \
    -Wl,--no-relax \
    -Wl,-Map,$(UART_MAP)

# ============================================================
# UART software build
# ============================================================    

$(UART_ELF): $(UART_START) $(UART_SRC) $(UART_LDS)
>mkdir -p $(UART_DIR)
>$(RISCV_GCC) \
>    $(UART_CFLAGS) \
>    $(UART_LDFLAGS) \
>    -o $(UART_ELF) \
>    $(UART_START) \
>    $(UART_SRC)

$(UART_BIN): $(UART_ELF)
>$(RISCV_OBJCOPY) \
>    -O binary \
>    $(UART_ELF) \
>    $(UART_BIN)

$(UART_HEX): $(UART_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py \
>    $(UART_BIN) \
>    $(UART_HEX)

$(UART_DUMP): $(UART_ELF)
>$(RISCV_OBJDUMP) \
>    -d \
>    -M no-aliases \
>    $(UART_ELF) \
>    > $(UART_DUMP)

# ============================================================
# UART SoC simulation
# ============================================================

$(UART_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_uart.sv
>mkdir -p build/obj_uart
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    -Wno-PINMISSING \
>    --Mdir build/obj_uart \
>    --top-module tb_soc_uart \
>    $(RTL) \
>    $(SOC_RTL) \
>    tb/tb_soc_uart.sv

uart-test: $(UART_HEX) $(UART_DUMP) $(UART_SIM)
>./$(UART_SIM)

uart-dump: $(UART_DUMP)
>cat $(UART_DUMP)

uart-wave: uart-test
>gtkwave build/uart/uart.vcd &

# ============================================================
# Zicsr assembly test
# ============================================================

ZICSR_DIR := build/zicsr

ZICSR_SRC := sw/asm/zicsr_test.S
ZICSR_LDS := sw/asm/link.ld

ZICSR_ELF  := $(ZICSR_DIR)/zicsr.elf
ZICSR_BIN  := $(ZICSR_DIR)/zicsr.bin
ZICSR_HEX  := $(ZICSR_DIR)/zicsr.hex
ZICSR_DUMP := $(ZICSR_DIR)/zicsr.dump
ZICSR_MAP  := $(ZICSR_DIR)/zicsr.map

ZICSR_SIM := build/obj_zicsr/Vtb_zicsr_asm

$(ZICSR_ELF): $(ZICSR_SRC) $(ZICSR_LDS)
>mkdir -p $(ZICSR_DIR)
>$(RISCV_GCC) \
>    -march=rv32i_zicsr \
>    -mabi=ilp32 \
>    -nostdlib \
>    -nostartfiles \
>    -ffreestanding \
>    -Wl,-T,$(ZICSR_LDS) \
>    -Wl,--no-relax \
>    -Wl,-Map,$(ZICSR_MAP) \
>    -o $(ZICSR_ELF) \
>    $(ZICSR_SRC)


$(ZICSR_BIN): $(ZICSR_ELF)
>$(RISCV_OBJCOPY) \
>    -O binary \
>    $(ZICSR_ELF) \
>    $(ZICSR_BIN)


$(ZICSR_HEX): $(ZICSR_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py \
>    $(ZICSR_BIN) \
>    $(ZICSR_HEX)


$(ZICSR_DUMP): $(ZICSR_ELF)
>$(RISCV_OBJDUMP) \
>    -d \
>    -M no-aliases \
>    $(ZICSR_ELF) \
>    > $(ZICSR_DUMP)


$(ZICSR_SIM): $(RTL) tb/tb_zicsr_asm.sv
>mkdir -p build/obj_zicsr
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    -Wno-PINMISSING \
>    --Mdir build/obj_zicsr \
>    --top-module tb_zicsr_asm \
>    $(RTL) \
>    tb/tb_zicsr_asm.sv


zicsr-test: $(ZICSR_HEX) $(ZICSR_DUMP) $(ZICSR_SIM)
>./$(ZICSR_SIM)


zicsr-dump: $(ZICSR_DUMP)
>cat $(ZICSR_DUMP)


# ============================================================
# ECALL / MRET assembly test
# ============================================================

ECALL_DIR := build/ecall

ECALL_SRC := sw/asm/ecall_test.S
ECALL_LDS := sw/asm/link.ld

ECALL_ELF  := $(ECALL_DIR)/ecall.elf
ECALL_BIN  := $(ECALL_DIR)/ecall.bin
ECALL_HEX  := $(ECALL_DIR)/ecall.hex
ECALL_DUMP := $(ECALL_DIR)/ecall.dump
ECALL_MAP  := $(ECALL_DIR)/ecall.map

ECALL_SIM := build/obj_ecall/Vtb_ecall_asm

$(ECALL_ELF): $(ECALL_SRC) $(ECALL_LDS)
>mkdir -p $(ECALL_DIR)
>$(RISCV_GCC) \
>    -march=rv32i_zicsr \
>    -mabi=ilp32 \
>    -nostdlib \
>    -nostartfiles \
>    -ffreestanding \
>    -Wl,-T,$(ECALL_LDS) \
>    -Wl,--no-relax \
>    -Wl,-Map,$(ECALL_MAP) \
>    -o $(ECALL_ELF) \
>    $(ECALL_SRC)

$(ECALL_BIN): $(ECALL_ELF)
>$(RISCV_OBJCOPY) -O binary $(ECALL_ELF) $(ECALL_BIN)

$(ECALL_HEX): $(ECALL_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py $(ECALL_BIN) $(ECALL_HEX)

$(ECALL_DUMP): $(ECALL_ELF)
>$(RISCV_OBJDUMP) -d -M no-aliases $(ECALL_ELF) > $(ECALL_DUMP)

$(ECALL_SIM): $(RTL) tb/tb_ecall_asm.sv
>mkdir -p build/obj_ecall
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    --Mdir build/obj_ecall \
>    --top-module tb_ecall_asm \
>    $(RTL) \
>    tb/tb_ecall_asm.sv

.PHONY: ecall-test ecall-dump ecall-wave

ecall-test: $(ECALL_HEX) $(ECALL_DUMP) $(ECALL_SIM)
>./$(ECALL_SIM)

ecall-dump: $(ECALL_DUMP)
>cat $(ECALL_DUMP)

ecall-wave: ecall-test
>gtkwave $(ECALL_DIR)/ecall.vcd &


# ============================================================
# Illegal instruction / CSR access assembly test
# ============================================================

ILLEGAL_DIR := build/illegal

ILLEGAL_SRC := sw/asm/illegal_test.S
ILLEGAL_LDS := sw/asm/link.ld

ILLEGAL_ELF  := $(ILLEGAL_DIR)/illegal.elf
ILLEGAL_BIN  := $(ILLEGAL_DIR)/illegal.bin
ILLEGAL_HEX  := $(ILLEGAL_DIR)/illegal.hex
ILLEGAL_DUMP := $(ILLEGAL_DIR)/illegal.dump
ILLEGAL_MAP  := $(ILLEGAL_DIR)/illegal.map

ILLEGAL_SIM := build/obj_illegal/Vtb_illegal_asm

$(ILLEGAL_ELF): $(ILLEGAL_SRC) $(ILLEGAL_LDS)
>mkdir -p $(ILLEGAL_DIR)
>$(RISCV_GCC) \
>    -march=rv32i_zicsr \
>    -mabi=ilp32 \
>    -nostdlib \
>    -nostartfiles \
>    -ffreestanding \
>    -Wl,-T,$(ILLEGAL_LDS) \
>    -Wl,--no-relax \
>    -Wl,-Map,$(ILLEGAL_MAP) \
>    -o $(ILLEGAL_ELF) \
>    $(ILLEGAL_SRC)

$(ILLEGAL_BIN): $(ILLEGAL_ELF)
>$(RISCV_OBJCOPY) -O binary $(ILLEGAL_ELF) $(ILLEGAL_BIN)

$(ILLEGAL_HEX): $(ILLEGAL_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py $(ILLEGAL_BIN) $(ILLEGAL_HEX)

$(ILLEGAL_DUMP): $(ILLEGAL_ELF)
>$(RISCV_OBJDUMP) -d -M no-aliases $(ILLEGAL_ELF) > $(ILLEGAL_DUMP)

$(ILLEGAL_SIM): $(RTL) tb/tb_illegal_asm.sv
>mkdir -p build/obj_illegal
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    --Mdir build/obj_illegal \
>    --top-module tb_illegal_asm \
>    $(RTL) \
>    tb/tb_illegal_asm.sv

.PHONY: illegal-test illegal-dump illegal-wave

illegal-test: $(ILLEGAL_HEX) $(ILLEGAL_DUMP) $(ILLEGAL_SIM)
>./$(ILLEGAL_SIM)

illegal-dump: $(ILLEGAL_DUMP)
>cat $(ILLEGAL_DUMP)

illegal-wave: illegal-test
>gtkwave $(ILLEGAL_DIR)/illegal.vcd &


# ============================================================
# Misaligned load/store assembly test
# ============================================================

MISALIGNED_DIR := build/misaligned

MISALIGNED_SRC := sw/asm/misaligned_test.S
MISALIGNED_LDS := sw/asm/link.ld

MISALIGNED_ELF  := $(MISALIGNED_DIR)/misaligned.elf
MISALIGNED_BIN  := $(MISALIGNED_DIR)/misaligned.bin
MISALIGNED_HEX  := $(MISALIGNED_DIR)/misaligned.hex
MISALIGNED_DUMP := $(MISALIGNED_DIR)/misaligned.dump
MISALIGNED_MAP  := $(MISALIGNED_DIR)/misaligned.map

MISALIGNED_SIM := build/obj_misaligned/Vtb_misaligned_asm

$(MISALIGNED_ELF): $(MISALIGNED_SRC) $(MISALIGNED_LDS)
>mkdir -p $(MISALIGNED_DIR)
>$(RISCV_GCC) \
>    -march=rv32i_zicsr \
>    -mabi=ilp32 \
>    -nostdlib \
>    -nostartfiles \
>    -ffreestanding \
>    -Wl,-T,$(MISALIGNED_LDS) \
>    -Wl,--no-relax \
>    -Wl,-Map,$(MISALIGNED_MAP) \
>    -o $(MISALIGNED_ELF) \
>    $(MISALIGNED_SRC)

$(MISALIGNED_BIN): $(MISALIGNED_ELF)
>$(RISCV_OBJCOPY) -O binary $(MISALIGNED_ELF) $(MISALIGNED_BIN)

$(MISALIGNED_HEX): $(MISALIGNED_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py $(MISALIGNED_BIN) $(MISALIGNED_HEX)

$(MISALIGNED_DUMP): $(MISALIGNED_ELF)
>$(RISCV_OBJDUMP) -d -M no-aliases $(MISALIGNED_ELF) > $(MISALIGNED_DUMP)

$(MISALIGNED_SIM): $(RTL) tb/tb_misaligned_asm.sv
>mkdir -p build/obj_misaligned
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    --Mdir build/obj_misaligned \
>    --top-module tb_misaligned_asm \
>    $(RTL) \
>    tb/tb_misaligned_asm.sv

.PHONY: misaligned-test misaligned-dump misaligned-wave

misaligned-test: $(MISALIGNED_HEX) $(MISALIGNED_DUMP) $(MISALIGNED_SIM)
>./$(MISALIGNED_SIM)

misaligned-dump: $(MISALIGNED_DUMP)
>cat $(MISALIGNED_DUMP)

misaligned-wave: misaligned-test
>gtkwave $(MISALIGNED_DIR)/misaligned.vcd &


# ============================================================
# CSR unit test and M8.3 mtval checks
# ============================================================

CSR_SIM := build/obj_csr/Vtb_csr_file

$(CSR_SIM): rtl/core/csr_file.sv tb/tb_csr_file.sv
>mkdir -p build/obj_csr
>$(VERILATOR) \
>    --binary \
>    --timing \
>    -Wall \
>    -Wno-fatal \
>    --Mdir build/obj_csr \
>    --top-module tb_csr_file \
>    rtl/core/csr_file.sv \
>    tb/tb_csr_file.sv

.PHONY: csr-test mtval-test

csr-test: $(CSR_SIM)
>./$(CSR_SIM)

mtval-test: csr-test ecall-test illegal-test
>@echo "M8.3 MTVAL TESTS PASS"


# ============================================================
# M9.1 standalone machine timer test
# ============================================================

TIMER_SIM := build/obj_timer/Vtb_timer_mmio

# addr[1:0] is intentionally ignored by the register word decoder.
# Byte write selection is carried by wstrb.
$(TIMER_SIM): rtl/soc/timer_mmio.sv tb/tb_timer_mmio.sv
>mkdir -p build/obj_timer
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-UNUSEDSIGNAL \
>    --Mdir build/obj_timer \
>    --top-module tb_timer_mmio \
>    rtl/soc/timer_mmio.sv \
>    tb/tb_timer_mmio.sv

.PHONY: timer-test timer-lint timer-wave

timer-test: $(TIMER_SIM)
>mkdir -p build/timer
>./$(TIMER_SIM)

timer-lint:
>$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL \
>    --top-module timer_mmio rtl/soc/timer_mmio.sv

timer-wave: timer-test
>gtkwave build/timer/timer.vcd &


# ============================================================
# M9.2 SoC timer polling program
# Reuse the UART image's startup code and ROM/RAM linker map.
# ============================================================

SOC_TIMER_DIR := build/soc_timer
SOC_TIMER_SRC := sw/timer/main.c
SOC_TIMER_START := sw/uart/start.S
SOC_TIMER_LDS := sw/uart/link.ld

SOC_TIMER_ELF  := $(SOC_TIMER_DIR)/soc_timer.elf
SOC_TIMER_BIN  := $(SOC_TIMER_DIR)/soc_timer.bin
SOC_TIMER_HEX  := $(SOC_TIMER_DIR)/soc_timer.hex
SOC_TIMER_DUMP := $(SOC_TIMER_DIR)/soc_timer.dump
SOC_TIMER_MAP  := $(SOC_TIMER_DIR)/soc_timer.map
SOC_TIMER_SIM  := build/obj_soc_timer/Vtb_soc_timer

$(SOC_TIMER_ELF): $(SOC_TIMER_SRC) $(SOC_TIMER_START) $(SOC_TIMER_LDS)
>mkdir -p $(SOC_TIMER_DIR)
>$(RISCV_GCC) \
>    $(UART_CFLAGS) \
>    -Wall -Wextra \
>    -Wl,-T,$(SOC_TIMER_LDS) \
>    -Wl,--no-relax \
>    -Wl,-Map,$(SOC_TIMER_MAP) \
>    -o $(SOC_TIMER_ELF) \
>    $(SOC_TIMER_START) $(SOC_TIMER_SRC)

$(SOC_TIMER_BIN): $(SOC_TIMER_ELF)
>$(RISCV_OBJCOPY) -O binary $(SOC_TIMER_ELF) $(SOC_TIMER_BIN)

$(SOC_TIMER_HEX): $(SOC_TIMER_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py $(SOC_TIMER_BIN) $(SOC_TIMER_HEX)

$(SOC_TIMER_DUMP): $(SOC_TIMER_ELF)
>$(RISCV_OBJDUMP) -d -M no-aliases $(SOC_TIMER_ELF) > $(SOC_TIMER_DUMP)

$(SOC_TIMER_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_timer.sv
>mkdir -p build/obj_soc_timer
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    --Mdir build/obj_soc_timer \
>    --top-module tb_soc_timer \
>    $(RTL) \
>    $(SOC_RTL) \
>    tb/tb_soc_timer.sv

.PHONY: soc-timer-test soc-timer-dump soc-timer-wave

soc-timer-test: $(SOC_TIMER_HEX) $(SOC_TIMER_DUMP) $(SOC_TIMER_SIM)
>./$(SOC_TIMER_SIM)

soc-timer-dump: $(SOC_TIMER_DUMP)
>cat $(SOC_TIMER_DUMP)

soc-timer-wave: soc-timer-test
>gtkwave $(SOC_TIMER_DIR)/soc_timer.vcd &


.PHONY: mtip-test

mtip-test: csr-test soc-timer-test
>@echo "M9.3.1 MTIP CHECKS PASS"


# ============================================================
# M9.3.2 CPU machine timer interrupt arbitration and precise traps
# ============================================================

CPU_TIMER_IRQ_SIM := build/obj_cpu_timer_irq/Vtb_cpu_timer_irq

$(CPU_TIMER_IRQ_SIM): $(RTL) tb/tb_cpu_timer_irq.sv
>mkdir -p build/obj_cpu_timer_irq
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    --Mdir build/obj_cpu_timer_irq \
>    -Werror-IMPLICIT \
>    -Werror-UNDRIVEN \
>    --top-module tb_cpu_timer_irq \
>    $(RTL) \
>    tb/tb_cpu_timer_irq.sv

.PHONY: timer-irq-test timer-irq-wave

timer-irq-test: $(CPU_TIMER_IRQ_SIM)
>mkdir -p build/cpu_timer_irq
>./$(CPU_TIMER_IRQ_SIM)

timer-irq-wave: timer-irq-test
>gtkwave build/cpu_timer_irq/cpu_timer_irq.vcd &


# ============================================================
# M9.3.3 Real SoC timer interrupts through an assembly/C handler
# ============================================================

SOC_TIMER_IRQ_DIR := build/soc_timer_irq
SOC_TIMER_IRQ_SRC := sw/timer_irq/main.c
SOC_TIMER_IRQ_TRAP := sw/timer_irq/trap.S
SOC_TIMER_IRQ_START := sw/uart/start.S
SOC_TIMER_IRQ_LDS := sw/timer_irq/link.ld
SOC_TIMER_IRQ_ELF := $(SOC_TIMER_IRQ_DIR)/soc_timer_irq.elf
SOC_TIMER_IRQ_BIN := $(SOC_TIMER_IRQ_DIR)/soc_timer_irq.bin
SOC_TIMER_IRQ_HEX := $(SOC_TIMER_IRQ_DIR)/soc_timer_irq.hex
SOC_TIMER_IRQ_DUMP := $(SOC_TIMER_IRQ_DIR)/soc_timer_irq.dump
SOC_TIMER_IRQ_MAP := $(SOC_TIMER_IRQ_DIR)/soc_timer_irq.map
SOC_TIMER_IRQ_SIM := build/obj_soc_timer_irq/Vtb_soc_timer_irq
SOC_TIMER_IRQ_CFLAGS := $(filter-out -march=%,$(UART_CFLAGS)) \
    -march=rv32i_zicsr -Wall -Wextra -fstack-usage

$(SOC_TIMER_IRQ_ELF): $(SOC_TIMER_IRQ_SRC) $(SOC_TIMER_IRQ_TRAP) $(SOC_TIMER_IRQ_START) $(SOC_TIMER_IRQ_LDS)
>mkdir -p $(SOC_TIMER_IRQ_DIR)
>$(RISCV_GCC) $(SOC_TIMER_IRQ_CFLAGS) \
>    -Wl,-T,$(SOC_TIMER_IRQ_LDS) -Wl,--no-relax \
>    -Wl,-Map,$(SOC_TIMER_IRQ_MAP) \
>    -o $(SOC_TIMER_IRQ_ELF) \
>    $(SOC_TIMER_IRQ_START) $(SOC_TIMER_IRQ_TRAP) $(SOC_TIMER_IRQ_SRC)

$(SOC_TIMER_IRQ_BIN): $(SOC_TIMER_IRQ_ELF)
>$(RISCV_OBJCOPY) -O binary $(SOC_TIMER_IRQ_ELF) $(SOC_TIMER_IRQ_BIN)

$(SOC_TIMER_IRQ_HEX): $(SOC_TIMER_IRQ_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py $(SOC_TIMER_IRQ_BIN) $(SOC_TIMER_IRQ_HEX)

$(SOC_TIMER_IRQ_DUMP): $(SOC_TIMER_IRQ_ELF)
>$(RISCV_OBJDUMP) -d -M no-aliases $(SOC_TIMER_IRQ_ELF) > $(SOC_TIMER_IRQ_DUMP)

$(SOC_TIMER_IRQ_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_timer_irq.sv
>mkdir -p build/obj_soc_timer_irq
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN \
>    --Mdir build/obj_soc_timer_irq --top-module tb_soc_timer_irq \
>    $(RTL) $(SOC_RTL) tb/tb_soc_timer_irq.sv

.PHONY: soc-timer-irq-test soc-timer-irq-dump soc-timer-irq-wave

soc-timer-irq-test: $(SOC_TIMER_IRQ_HEX) $(SOC_TIMER_IRQ_DUMP) $(SOC_TIMER_IRQ_SIM)
>./$(SOC_TIMER_IRQ_SIM)

soc-timer-irq-dump: $(SOC_TIMER_IRQ_DUMP)
>cat $(SOC_TIMER_IRQ_DUMP)

soc-timer-irq-wave: soc-timer-irq-test
>gtkwave $(SOC_TIMER_IRQ_DIR)/soc_timer_irq.vcd &


# ============================================================
# M10.1 Configurable memory and a 64 KiB ROM / 64 KiB RAM image
# ============================================================

SOC_MEMORY_DIR := build/soc_memory
SOC_MEMORY_SRC := sw/memory/main.c
SOC_MEMORY_LDS := sw/memory/link.ld
SOC_MEMORY_START := sw/uart/start.S
SOC_MEMORY_ELF := $(SOC_MEMORY_DIR)/soc_memory.elf
SOC_MEMORY_BIN := $(SOC_MEMORY_DIR)/soc_memory.bin
SOC_MEMORY_HEX := $(SOC_MEMORY_DIR)/soc_memory.hex
SOC_MEMORY_DUMP := $(SOC_MEMORY_DIR)/soc_memory.dump
SOC_MEMORY_SIM := build/obj_soc_memory/Vtb_soc_memory
SOC_MEMORY_SMALL_SIM := build/obj_memory_small/Vtb_soc_memory_params
SOC_MEMORY_BAD_ROM_SIM := build/obj_memory_bad_rom/Vtb_soc_memory_params
SOC_MEMORY_BAD_RAM_SIM := build/obj_memory_bad_ram/Vtb_soc_memory_params
SOC_MEMORY_PARAM_FLAGS := --binary --timing -Wall -Wno-fatal \
    -Werror-IMPLICIT -Werror-UNDRIVEN --top-module tb_soc_memory_params

$(SOC_MEMORY_ELF): $(SOC_MEMORY_SRC) $(SOC_MEMORY_LDS) $(SOC_MEMORY_START)
>mkdir -p $(SOC_MEMORY_DIR)
>$(RISCV_GCC) $(UART_CFLAGS) -Wall -Wextra \
>    -Wl,-T,$(SOC_MEMORY_LDS) -Wl,--no-relax \
>    -Wl,-Map,$(SOC_MEMORY_DIR)/soc_memory.map \
>    -o $(SOC_MEMORY_ELF) $(SOC_MEMORY_START) $(SOC_MEMORY_SRC)

$(SOC_MEMORY_BIN): $(SOC_MEMORY_ELF)
>$(RISCV_OBJCOPY) -O binary $(SOC_MEMORY_ELF) $(SOC_MEMORY_BIN)

$(SOC_MEMORY_HEX): $(SOC_MEMORY_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py $(SOC_MEMORY_BIN) $(SOC_MEMORY_HEX)

$(SOC_MEMORY_DUMP): $(SOC_MEMORY_ELF)
>$(RISCV_OBJDUMP) -d -M no-aliases $(SOC_MEMORY_ELF) > $(SOC_MEMORY_DUMP)

$(SOC_MEMORY_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_memory.sv
>mkdir -p build/obj_soc_memory
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN \
>    --Mdir build/obj_soc_memory --top-module tb_soc_memory \
>    $(RTL) $(SOC_RTL) tb/tb_soc_memory.sv

$(SOC_MEMORY_SMALL_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_memory_params.sv
>mkdir -p build/obj_memory_small
>$(VERILATOR) $(SOC_MEMORY_PARAM_FLAGS) --Mdir build/obj_memory_small \
>    $(RTL) $(SOC_RTL) tb/tb_soc_memory_params.sv

$(SOC_MEMORY_BAD_ROM_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_memory_params.sv
>mkdir -p build/obj_memory_bad_rom
>$(VERILATOR) $(SOC_MEMORY_PARAM_FLAGS) --Mdir build/obj_memory_bad_rom \
>    -GROM_BYTES=12 $(RTL) $(SOC_RTL) tb/tb_soc_memory_params.sv

$(SOC_MEMORY_BAD_RAM_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_memory_params.sv
>mkdir -p build/obj_memory_bad_ram
>$(VERILATOR) $(SOC_MEMORY_PARAM_FLAGS) --Mdir build/obj_memory_bad_ram \
>    -GRAM_BYTES=12 $(RTL) $(SOC_RTL) tb/tb_soc_memory_params.sv

.PHONY: soc-memory-test soc-memory-param-test soc-memory-dump soc-memory-wave

soc-memory-test: $(SOC_MEMORY_HEX) $(SOC_MEMORY_DUMP) $(SOC_MEMORY_SIM) soc-memory-param-test
>./$(SOC_MEMORY_SIM)

soc-memory-param-test: $(SOC_MEMORY_SMALL_SIM) $(SOC_MEMORY_BAD_ROM_SIM) $(SOC_MEMORY_BAD_RAM_SIM) scripts/check_soc_memory_params.py
>./$(SOC_MEMORY_SMALL_SIM)
>python3 scripts/check_soc_memory_params.py

soc-memory-dump: $(SOC_MEMORY_DUMP)
>cat $(SOC_MEMORY_DUMP)

soc-memory-wave: soc-memory-test
>gtkwave $(SOC_MEMORY_DIR)/soc_memory.vcd &


# ============================================================
# M10.2 Cooperative contexts, independently compiled at O0 and O2
# ============================================================

CONTEXT_DIR := build/context
CONTEXT_O2_DIR := build/context_o2
CONTEXT_SOURCES := sw/uart/start.S sw/context/switch.S sw/context/main.c
CONTEXT_DEPS := $(CONTEXT_SOURCES) sw/context/context.h sw/context/link.ld
CONTEXT_FLAGS := $(filter-out -O0,$(UART_CFLAGS)) -Wall -Wextra -fstack-usage
CONTEXT_SIM := build/obj_context/Vtb_soc_context

$(CONTEXT_DIR)/context.elf: $(CONTEXT_DEPS)
>mkdir -p $(CONTEXT_DIR)
>$(RISCV_GCC) $(CONTEXT_FLAGS) -O0 -Wl,-T,sw/context/link.ld -Wl,--no-relax \
>    -Wl,-Map,$(CONTEXT_DIR)/context.map -o $@ $(CONTEXT_SOURCES)

$(CONTEXT_O2_DIR)/context.elf: $(CONTEXT_DEPS)
>mkdir -p $(CONTEXT_O2_DIR)
>$(RISCV_GCC) $(CONTEXT_FLAGS) -O2 -Wl,-T,sw/context/link.ld -Wl,--no-relax \
>    -Wl,-Map,$(CONTEXT_O2_DIR)/context.map -o $@ $(CONTEXT_SOURCES)

$(CONTEXT_DIR)/context.bin: $(CONTEXT_DIR)/context.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(CONTEXT_O2_DIR)/context.bin: $(CONTEXT_O2_DIR)/context.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(CONTEXT_DIR)/context.hex: $(CONTEXT_DIR)/context.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(CONTEXT_O2_DIR)/context.hex: $(CONTEXT_O2_DIR)/context.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(CONTEXT_DIR)/context.symbols.hex: $(CONTEXT_DIR)/context.elf scripts/context_symbols.py
>python3 scripts/context_symbols.py $(RISCV_PREFIX)nm $< $@

$(CONTEXT_O2_DIR)/context.symbols.hex: $(CONTEXT_O2_DIR)/context.elf scripts/context_symbols.py
>python3 scripts/context_symbols.py $(RISCV_PREFIX)nm $< $@

$(CONTEXT_DIR)/context.dump: $(CONTEXT_DIR)/context.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(CONTEXT_O2_DIR)/context.dump: $(CONTEXT_O2_DIR)/context.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(CONTEXT_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_context.sv
>mkdir -p build/obj_context
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_context \
>    --top-module tb_soc_context $(RTL) $(SOC_RTL) tb/tb_soc_context.sv

.PHONY: context-test context-dump context-wave

context-test: $(CONTEXT_DIR)/context.hex $(CONTEXT_DIR)/context.symbols.hex $(CONTEXT_DIR)/context.dump \
              $(CONTEXT_O2_DIR)/context.hex $(CONTEXT_O2_DIR)/context.symbols.hex $(CONTEXT_O2_DIR)/context.dump $(CONTEXT_SIM)
>./$(CONTEXT_SIM) +image=$(CONTEXT_DIR)/context.hex +symbols=$(CONTEXT_DIR)/context.symbols.hex +wave=$(CONTEXT_DIR)/context.vcd
>./$(CONTEXT_SIM) +image=$(CONTEXT_O2_DIR)/context.hex +symbols=$(CONTEXT_O2_DIR)/context.symbols.hex +wave=$(CONTEXT_O2_DIR)/context.vcd
>@echo "M10.2 CONTEXT O0/O2 CHECKS PASS"

context-dump: $(CONTEXT_DIR)/context.dump
>cat $(CONTEXT_DIR)/context.dump

context-wave: context-test
>gtkwave $(CONTEXT_DIR)/context.vcd &


# ============================================================
# M10.3 Timer-preempted full contexts, compiled at O0 and O2
# ============================================================

PREEMPT_DIR := build/preempt
PREEMPT_O2_DIR := build/preempt_o2
PREEMPT_SOURCES := sw/uart/start.S sw/preempt/trap.S sw/preempt/main.c
PREEMPT_DEPS := $(PREEMPT_SOURCES) sw/preempt/trap_frame.h \
    sw/preempt/link.ld sw/common/irq.h
PREEMPT_FLAGS := $(filter-out -march=% -O0,$(UART_CFLAGS)) \
    -march=rv32i_zicsr -Wall -Wextra -Werror -fstack-usage
PREEMPT_SIM := build/obj_preempt/Vtb_soc_preempt

$(PREEMPT_DIR)/preempt.elf: $(PREEMPT_DEPS)
>mkdir -p $(PREEMPT_DIR)
>$(RISCV_GCC) $(PREEMPT_FLAGS) -O0 -Wl,-T,sw/preempt/link.ld -Wl,--no-relax \
>    -Wl,-Map,$(PREEMPT_DIR)/preempt.map -o $@ $(PREEMPT_SOURCES)

$(PREEMPT_O2_DIR)/preempt.elf: $(PREEMPT_DEPS)
>mkdir -p $(PREEMPT_O2_DIR)
>$(RISCV_GCC) $(PREEMPT_FLAGS) -O2 -Wl,-T,sw/preempt/link.ld -Wl,--no-relax \
>    -Wl,-Map,$(PREEMPT_O2_DIR)/preempt.map -o $@ $(PREEMPT_SOURCES)

$(PREEMPT_DIR)/preempt.bin: $(PREEMPT_DIR)/preempt.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(PREEMPT_O2_DIR)/preempt.bin: $(PREEMPT_O2_DIR)/preempt.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(PREEMPT_DIR)/preempt.hex: $(PREEMPT_DIR)/preempt.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(PREEMPT_O2_DIR)/preempt.hex: $(PREEMPT_O2_DIR)/preempt.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(PREEMPT_DIR)/preempt.symbols.hex: $(PREEMPT_DIR)/preempt.elf scripts/preempt_symbols.py
>python3 scripts/preempt_symbols.py $(RISCV_PREFIX)nm $< $@

$(PREEMPT_O2_DIR)/preempt.symbols.hex: $(PREEMPT_O2_DIR)/preempt.elf scripts/preempt_symbols.py
>python3 scripts/preempt_symbols.py $(RISCV_PREFIX)nm $< $@

$(PREEMPT_DIR)/preempt.dump: $(PREEMPT_DIR)/preempt.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(PREEMPT_O2_DIR)/preempt.dump: $(PREEMPT_O2_DIR)/preempt.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(PREEMPT_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_preempt.sv
>mkdir -p build/obj_preempt
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_preempt \
>    --top-module tb_soc_preempt $(RTL) $(SOC_RTL) tb/tb_soc_preempt.sv

.PHONY: preempt-test preempt-dump preempt-wave

preempt-test: $(PREEMPT_DIR)/preempt.hex $(PREEMPT_DIR)/preempt.symbols.hex $(PREEMPT_DIR)/preempt.dump \
              $(PREEMPT_O2_DIR)/preempt.hex $(PREEMPT_O2_DIR)/preempt.symbols.hex $(PREEMPT_O2_DIR)/preempt.dump $(PREEMPT_SIM)
>./$(PREEMPT_SIM) +image=$(PREEMPT_DIR)/preempt.hex +symbols=$(PREEMPT_DIR)/preempt.symbols.hex +wave=$(PREEMPT_DIR)/preempt.vcd
>./$(PREEMPT_SIM) +image=$(PREEMPT_O2_DIR)/preempt.hex +symbols=$(PREEMPT_O2_DIR)/preempt.symbols.hex +wave=$(PREEMPT_O2_DIR)/preempt.vcd
>@echo "M10.3 PREEMPT O0/O2 CHECKS PASS"

preempt-dump: $(PREEMPT_DIR)/preempt.dump
>cat $(PREEMPT_DIR)/preempt.dump

preempt-wave: preempt-test
>gtkwave $(PREEMPT_DIR)/preempt.vcd &


# ============================================================
# M10.4 Nested interrupt save/restore, compiled at O0 and O2
# ============================================================

IRQ_DIR := build/irq
IRQ_O2_DIR := build/irq_o2
IRQ_SOURCES := sw/uart/start.S sw/timer_irq/trap.S sw/irq/main.c
IRQ_DEPS := $(IRQ_SOURCES) sw/common/irq.h sw/irq/link.ld
IRQ_FLAGS := $(filter-out -march=% -O0,$(UART_CFLAGS)) \
    -march=rv32i_zicsr -Wall -Wextra -Werror -fstack-usage
IRQ_SIM := build/obj_irq/Vtb_soc_irq

$(IRQ_DIR)/irq.elf: $(IRQ_DEPS)
>mkdir -p $(IRQ_DIR)
>$(RISCV_GCC) $(IRQ_FLAGS) -O0 -Wl,-T,sw/irq/link.ld -Wl,--no-relax \
>    -Wl,-Map,$(IRQ_DIR)/irq.map -o $@ $(IRQ_SOURCES)

$(IRQ_O2_DIR)/irq.elf: $(IRQ_DEPS)
>mkdir -p $(IRQ_O2_DIR)
>$(RISCV_GCC) $(IRQ_FLAGS) -O2 -Wl,-T,sw/irq/link.ld -Wl,--no-relax \
>    -Wl,-Map,$(IRQ_O2_DIR)/irq.map -o $@ $(IRQ_SOURCES)

$(IRQ_DIR)/irq.bin: $(IRQ_DIR)/irq.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(IRQ_O2_DIR)/irq.bin: $(IRQ_O2_DIR)/irq.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(IRQ_DIR)/irq.hex: $(IRQ_DIR)/irq.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(IRQ_O2_DIR)/irq.hex: $(IRQ_O2_DIR)/irq.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(IRQ_DIR)/irq.symbols.hex: $(IRQ_DIR)/irq.elf scripts/irq_symbols.py
>python3 scripts/irq_symbols.py $(RISCV_PREFIX)nm $< $@

$(IRQ_O2_DIR)/irq.symbols.hex: $(IRQ_O2_DIR)/irq.elf scripts/irq_symbols.py
>python3 scripts/irq_symbols.py $(RISCV_PREFIX)nm $< $@

$(IRQ_DIR)/irq.dump: $(IRQ_DIR)/irq.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(IRQ_O2_DIR)/irq.dump: $(IRQ_O2_DIR)/irq.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(IRQ_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_irq.sv
>mkdir -p build/obj_irq
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_irq \
>    --top-module tb_soc_irq $(RTL) $(SOC_RTL) tb/tb_soc_irq.sv

.PHONY: irq-test irq-dump irq-wave

irq-test: $(IRQ_DIR)/irq.hex $(IRQ_DIR)/irq.symbols.hex $(IRQ_DIR)/irq.dump \
          $(IRQ_O2_DIR)/irq.hex $(IRQ_O2_DIR)/irq.symbols.hex $(IRQ_O2_DIR)/irq.dump $(IRQ_SIM)
>./$(IRQ_SIM) +image=$(IRQ_DIR)/irq.hex +symbols=$(IRQ_DIR)/irq.symbols.hex +wave=$(IRQ_DIR)/irq.vcd
>./$(IRQ_SIM) +image=$(IRQ_O2_DIR)/irq.hex +symbols=$(IRQ_O2_DIR)/irq.symbols.hex +wave=$(IRQ_O2_DIR)/irq.vcd
>@echo "M10.4 IRQ API O0/O2 CHECKS PASS"

irq-dump: $(IRQ_DIR)/irq.dump
>cat $(IRQ_DIR)/irq.dump

irq-wave: irq-test
>gtkwave $(IRQ_DIR)/irq.vcd &


# ============================================================
# M11.1 Pinned RT-Thread kernel services and board console
# ============================================================

RTTHREAD_ROOT := third_party/rt-thread
RTTHREAD_DIR := build/rtthread
RTTHREAD_O2_DIR := build/rtthread_o2
RTTHREAD_OBJECTS := start.o main.o cpuport.o board.o kservice.o
RTTHREAD_DEPS := sw/rtthread/rtconfig.h sw/rtthread/cpuport.h sw/common/irq.h \
    $(wildcard $(RTTHREAD_ROOT)/include/*.h)
RTTHREAD_FLAGS := $(filter-out -march=% -O0,$(UART_CFLAGS)) \
    -march=rv32i_zicsr -Wall -Wextra -Werror -fstack-usage \
    -ffunction-sections -fdata-sections \
    -Isw/rtthread -I$(RTTHREAD_ROOT)/include
# Upstream supplies optional weak hooks with intentionally unused parameters.
RTTHREAD_UPSTREAM_FLAGS := $(filter-out -Wextra,$(RTTHREAD_FLAGS))
RTTHREAD_SIM := build/obj_rtthread/Vtb_soc_rtthread

$(RTTHREAD_DIR)/%.o: sw/rtthread/%.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_O2_DIR)/%.o: sw/rtthread/%.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_DIR)/start.o: sw/uart/start.S
>mkdir -p $(RTTHREAD_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_O2_DIR)/start.o: sw/uart/start.S
>mkdir -p $(RTTHREAD_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_DIR)/kservice.o: $(RTTHREAD_ROOT)/src/kservice.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_DIR)
>$(RISCV_GCC) $(RTTHREAD_UPSTREAM_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_O2_DIR)/kservice.o: $(RTTHREAD_ROOT)/src/kservice.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_UPSTREAM_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_DIR)/rtthread.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_OBJECTS)) sw/rtthread/link.ld
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/link.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_DIR)/rtthread.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_O2_DIR)/rtthread.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_OBJECTS)) sw/rtthread/link.ld
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/link.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_O2_DIR)/rtthread.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_DIR)/rtthread.bin: $(RTTHREAD_DIR)/rtthread.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_O2_DIR)/rtthread.bin: $(RTTHREAD_O2_DIR)/rtthread.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_DIR)/rtthread.hex: $(RTTHREAD_DIR)/rtthread.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_O2_DIR)/rtthread.hex: $(RTTHREAD_O2_DIR)/rtthread.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_DIR)/rtthread.symbols.hex: $(RTTHREAD_DIR)/rtthread.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@

$(RTTHREAD_O2_DIR)/rtthread.symbols.hex: $(RTTHREAD_O2_DIR)/rtthread.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@

$(RTTHREAD_DIR)/rtthread.dump: $(RTTHREAD_DIR)/rtthread.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_O2_DIR)/rtthread.dump: $(RTTHREAD_O2_DIR)/rtthread.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread.sv
>mkdir -p build/obj_rtthread
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread \
>    --top-module tb_soc_rtthread $(RTL) $(SOC_RTL) tb/tb_soc_rtthread.sv

.PHONY: rtthread-test rtthread-dump rtthread-wave

rtthread-test: $(RTTHREAD_DIR)/rtthread.hex $(RTTHREAD_DIR)/rtthread.symbols.hex $(RTTHREAD_DIR)/rtthread.dump \
               $(RTTHREAD_O2_DIR)/rtthread.hex $(RTTHREAD_O2_DIR)/rtthread.symbols.hex $(RTTHREAD_O2_DIR)/rtthread.dump $(RTTHREAD_SIM)
>./$(RTTHREAD_SIM) +image=$(RTTHREAD_DIR)/rtthread.hex +symbols=$(RTTHREAD_DIR)/rtthread.symbols.hex +wave=$(RTTHREAD_DIR)/rtthread.vcd
>./$(RTTHREAD_SIM) +image=$(RTTHREAD_O2_DIR)/rtthread.hex +symbols=$(RTTHREAD_O2_DIR)/rtthread.symbols.hex +wave=$(RTTHREAD_O2_DIR)/rtthread.vcd
>@echo "M11.1 RT-THREAD CONSOLE O0/O2 CHECKS PASS"

rtthread-dump: $(RTTHREAD_DIR)/rtthread.dump
>cat $(RTTHREAD_DIR)/rtthread.dump

rtthread-wave: rtthread-test
>gtkwave $(RTTHREAD_DIR)/rtthread.vcd &


# ============================================================
# M11.2 RT-Thread initial stack and first context restore
# ============================================================

RTTHREAD_START_DIR := build/rtthread_start
RTTHREAD_START_O2_DIR := build/rtthread_start_o2
RTTHREAD_START_SHARED := start.o cpuport.o board.o kservice.o
RTTHREAD_START_SIM := build/obj_rtthread_start/Vtb_soc_rtthread_start

$(RTTHREAD_START_DIR)/start_test.o: sw/rtthread/start_test.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_START_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_START_O2_DIR)/start_test.o: sw/rtthread/start_test.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_START_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_START_DIR)/context.o: sw/rtthread/context.S
>mkdir -p $(RTTHREAD_START_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_START_O2_DIR)/context.o: sw/rtthread/context.S
>mkdir -p $(RTTHREAD_START_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_START_DIR)/rtthread_start.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_START_SHARED)) \
    $(RTTHREAD_START_DIR)/start_test.o $(RTTHREAD_START_DIR)/context.o sw/rtthread/start_test.ld
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/start_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_START_DIR)/rtthread_start.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_START_O2_DIR)/rtthread_start.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_START_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/start_test.o $(RTTHREAD_START_O2_DIR)/context.o sw/rtthread/start_test.ld
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/start_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_START_O2_DIR)/rtthread_start.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_START_DIR)/rtthread_start.bin: $(RTTHREAD_START_DIR)/rtthread_start.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_START_O2_DIR)/rtthread_start.bin: $(RTTHREAD_START_O2_DIR)/rtthread_start.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_START_DIR)/rtthread_start.hex: $(RTTHREAD_START_DIR)/rtthread_start.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_START_O2_DIR)/rtthread_start.hex: $(RTTHREAD_START_O2_DIR)/rtthread_start.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_START_DIR)/rtthread_start.symbols.hex: $(RTTHREAD_START_DIR)/rtthread_start.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ start

$(RTTHREAD_START_O2_DIR)/rtthread_start.symbols.hex: $(RTTHREAD_START_O2_DIR)/rtthread_start.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ start

$(RTTHREAD_START_DIR)/rtthread_start.dump: $(RTTHREAD_START_DIR)/rtthread_start.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_START_O2_DIR)/rtthread_start.dump: $(RTTHREAD_START_O2_DIR)/rtthread_start.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_START_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_start.sv
>mkdir -p build/obj_rtthread_start
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_start \
>    --top-module tb_soc_rtthread_start $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_start.sv

.PHONY: rtthread-start-test rtthread-start-dump rtthread-start-wave

rtthread-start-test: $(RTTHREAD_START_DIR)/rtthread_start.hex $(RTTHREAD_START_DIR)/rtthread_start.symbols.hex \
    $(RTTHREAD_START_DIR)/rtthread_start.dump $(RTTHREAD_START_O2_DIR)/rtthread_start.hex \
    $(RTTHREAD_START_O2_DIR)/rtthread_start.symbols.hex $(RTTHREAD_START_O2_DIR)/rtthread_start.dump $(RTTHREAD_START_SIM)
>./$(RTTHREAD_START_SIM) +image=$(RTTHREAD_START_DIR)/rtthread_start.hex +symbols=$(RTTHREAD_START_DIR)/rtthread_start.symbols.hex +wave=$(RTTHREAD_START_DIR)/rtthread_start.vcd
>./$(RTTHREAD_START_SIM) +image=$(RTTHREAD_START_O2_DIR)/rtthread_start.hex +symbols=$(RTTHREAD_START_O2_DIR)/rtthread_start.symbols.hex +wave=$(RTTHREAD_START_O2_DIR)/rtthread_start.vcd
>@echo "M11.2 RT-THREAD START O0/O2 CHECKS PASS"

rtthread-start-dump: $(RTTHREAD_START_DIR)/rtthread_start.dump
>cat $(RTTHREAD_START_DIR)/rtthread_start.dump

rtthread-start-wave: rtthread-start-test
>gtkwave $(RTTHREAD_START_DIR)/rtthread_start.vcd &


# ============================================================
# M11.3 RT-Thread scheduler and thread-mode context switching
# ============================================================

RTTHREAD_SCHED_DIR := build/rtthread_sched
RTTHREAD_SCHED_O2_DIR := build/rtthread_sched_o2
RTTHREAD_SCHED_KERNEL := object thread scheduler timer clock irq idle
RTTHREAD_SCHED_SHARED := $(RTTHREAD_START_SHARED) sched_test.o \
    $(addsuffix .o,$(RTTHREAD_SCHED_KERNEL))
RTTHREAD_SCHED_SIM := build/obj_rtthread_sched/Vtb_soc_rtthread_sched

$(RTTHREAD_DIR)/%.o: $(RTTHREAD_ROOT)/src/%.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_DIR)
>$(RISCV_GCC) $(RTTHREAD_UPSTREAM_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_O2_DIR)/%.o: $(RTTHREAD_ROOT)/src/%.c $(RTTHREAD_DEPS)
>mkdir -p $(RTTHREAD_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_UPSTREAM_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_SCHED_DIR)/rtthread_sched.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_SCHED_SHARED)) \
    $(RTTHREAD_START_DIR)/context.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_SCHED_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_SCHED_DIR)/rtthread_sched.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_SCHED_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/context.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_SCHED_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_SCHED_DIR)/rtthread_sched.bin: $(RTTHREAD_SCHED_DIR)/rtthread_sched.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.bin: $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_SCHED_DIR)/rtthread_sched.hex: $(RTTHREAD_SCHED_DIR)/rtthread_sched.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.hex: $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_SCHED_DIR)/rtthread_sched.symbols.hex: $(RTTHREAD_SCHED_DIR)/rtthread_sched.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ sched

$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.symbols.hex: $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ sched

$(RTTHREAD_SCHED_DIR)/rtthread_sched.dump: $(RTTHREAD_SCHED_DIR)/rtthread_sched.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.dump: $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_SCHED_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_sched.sv
>mkdir -p build/obj_rtthread_sched
>$(VERILATOR) --binary --timing --trace -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_sched \
>    --top-module tb_soc_rtthread_sched $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_sched.sv

.PHONY: rtthread-sched-test rtthread-sched-dump rtthread-sched-wave

rtthread-sched-test: $(RTTHREAD_SCHED_DIR)/rtthread_sched.hex $(RTTHREAD_SCHED_DIR)/rtthread_sched.symbols.hex \
    $(RTTHREAD_SCHED_DIR)/rtthread_sched.dump $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.hex \
    $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.symbols.hex $(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.dump $(RTTHREAD_SCHED_SIM)
>./$(RTTHREAD_SCHED_SIM) +image=$(RTTHREAD_SCHED_DIR)/rtthread_sched.hex +symbols=$(RTTHREAD_SCHED_DIR)/rtthread_sched.symbols.hex +wave=$(RTTHREAD_SCHED_DIR)/rtthread_sched.vcd
>./$(RTTHREAD_SCHED_SIM) +image=$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.hex +symbols=$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.symbols.hex +wave=$(RTTHREAD_SCHED_O2_DIR)/rtthread_sched.vcd
>@echo "M11.3 RT-THREAD SCHEDULER O0/O2 CHECKS PASS"

rtthread-sched-dump: $(RTTHREAD_SCHED_DIR)/rtthread_sched.dump
>cat $(RTTHREAD_SCHED_DIR)/rtthread_sched.dump

rtthread-sched-wave: rtthread-sched-test
>gtkwave $(RTTHREAD_SCHED_DIR)/rtthread_sched.vcd &


# ============================================================
# M11.4 RT-Thread hardware tick and interrupt-exit switching
# ============================================================

RTTHREAD_TICK_DIR := build/rtthread_tick
RTTHREAD_TICK_O2_DIR := build/rtthread_tick_o2
RTTHREAD_TICK_SHARED := $(RTTHREAD_START_SHARED) tick.o tick_test.o \
    $(addsuffix .o,$(RTTHREAD_SCHED_KERNEL))
RTTHREAD_TICK_SIM := build/obj_rtthread_tick/Vtb_soc_rtthread_tick

$(RTTHREAD_TICK_DIR)/trap.o: sw/rtthread/trap.S
>mkdir -p $(RTTHREAD_TICK_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -c $< -o $@

$(RTTHREAD_TICK_DIR)/rtthread_tick.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_TICK_SHARED)) \
    $(RTTHREAD_START_DIR)/context.o $(RTTHREAD_TICK_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_TICK_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_TICK_DIR)/rtthread_tick.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_TICK_DIR)/rtthread_tick.bin: $(RTTHREAD_TICK_DIR)/rtthread_tick.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_TICK_DIR)/rtthread_tick.hex: $(RTTHREAD_TICK_DIR)/rtthread_tick.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_TICK_DIR)/rtthread_tick.symbols.hex: $(RTTHREAD_TICK_DIR)/rtthread_tick.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ tick

$(RTTHREAD_TICK_DIR)/rtthread_tick.dump: $(RTTHREAD_TICK_DIR)/rtthread_tick.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_TICK_O2_DIR)/trap.o: sw/rtthread/trap.S
>mkdir -p $(RTTHREAD_TICK_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -c $< -o $@

$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_TICK_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/context.o $(RTTHREAD_TICK_O2_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_TICK_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.bin: $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.hex: $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.symbols.hex: $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ tick

$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.dump: $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_TICK_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_tick.sv
>mkdir -p build/obj_rtthread_tick
>$(VERILATOR) --binary --timing --trace --timescale 1ns/1ps -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_tick \
>    --top-module tb_soc_rtthread_tick $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_tick.sv

.PHONY: rtthread-tick-test rtthread-tick-dump rtthread-tick-wave

rtthread-tick-test: $(RTTHREAD_TICK_DIR)/rtthread_tick.hex $(RTTHREAD_TICK_DIR)/rtthread_tick.symbols.hex \
    $(RTTHREAD_TICK_DIR)/rtthread_tick.dump $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.hex \
    $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.symbols.hex $(RTTHREAD_TICK_O2_DIR)/rtthread_tick.dump $(RTTHREAD_TICK_SIM)
>./$(RTTHREAD_TICK_SIM) +image=$(RTTHREAD_TICK_DIR)/rtthread_tick.hex +symbols=$(RTTHREAD_TICK_DIR)/rtthread_tick.symbols.hex +wave=$(RTTHREAD_TICK_DIR)/rtthread_tick.vcd
>./$(RTTHREAD_TICK_SIM) +image=$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.hex +symbols=$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.symbols.hex +wave=$(RTTHREAD_TICK_O2_DIR)/rtthread_tick.vcd
>@echo "M11.4 RT-THREAD TICK O0/O2 CHECKS PASS"

rtthread-tick-dump: $(RTTHREAD_TICK_DIR)/rtthread_tick.dump
>cat $(RTTHREAD_TICK_DIR)/rtthread_tick.dump

rtthread-tick-wave: rtthread-tick-test
>gtkwave $(RTTHREAD_TICK_DIR)/rtthread_tick.vcd &


# ============================================================
# M11.5 RT-Thread blocking delays, timeout wakeups and idle cleanup
# ============================================================

RTTHREAD_DELAY_DIR := build/rtthread_delay
RTTHREAD_DELAY_O2_DIR := build/rtthread_delay_o2
RTTHREAD_DELAY_SHARED := $(RTTHREAD_START_SHARED) tick.o delay_test.o \
    $(addsuffix .o,$(RTTHREAD_SCHED_KERNEL))
RTTHREAD_DELAY_SIM := build/obj_rtthread_delay/Vtb_soc_rtthread_delay

$(RTTHREAD_DELAY_DIR)/rtthread_delay.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_DELAY_SHARED)) \
    $(RTTHREAD_START_DIR)/context.o $(RTTHREAD_TICK_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_DELAY_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_DELAY_DIR)/rtthread_delay.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_DELAY_DIR)/rtthread_delay.bin: $(RTTHREAD_DELAY_DIR)/rtthread_delay.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_DELAY_DIR)/rtthread_delay.hex: $(RTTHREAD_DELAY_DIR)/rtthread_delay.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_DELAY_DIR)/rtthread_delay.symbols.hex: $(RTTHREAD_DELAY_DIR)/rtthread_delay.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ delay

$(RTTHREAD_DELAY_DIR)/rtthread_delay.dump: $(RTTHREAD_DELAY_DIR)/rtthread_delay.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_DELAY_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/context.o $(RTTHREAD_TICK_O2_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_DELAY_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.bin: $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.hex: $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.symbols.hex: $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ delay

$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.dump: $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_DELAY_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_delay.sv
>mkdir -p build/obj_rtthread_delay
>$(VERILATOR) --binary --timing --trace --timescale 1ns/1ps -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_delay \
>    --top-module tb_soc_rtthread_delay $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_delay.sv

.PHONY: rtthread-delay-test rtthread-delay-dump rtthread-delay-wave

rtthread-delay-test: $(RTTHREAD_DELAY_DIR)/rtthread_delay.hex $(RTTHREAD_DELAY_DIR)/rtthread_delay.symbols.hex \
    $(RTTHREAD_DELAY_DIR)/rtthread_delay.dump $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.hex \
    $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.symbols.hex $(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.dump $(RTTHREAD_DELAY_SIM)
>./$(RTTHREAD_DELAY_SIM) +image=$(RTTHREAD_DELAY_DIR)/rtthread_delay.hex +symbols=$(RTTHREAD_DELAY_DIR)/rtthread_delay.symbols.hex +wave=$(RTTHREAD_DELAY_DIR)/rtthread_delay.vcd
>./$(RTTHREAD_DELAY_SIM) +image=$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.hex +symbols=$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.symbols.hex +wave=$(RTTHREAD_DELAY_O2_DIR)/rtthread_delay.vcd
>@echo "M11.5 RT-THREAD DELAY O0/O2 CHECKS PASS"

rtthread-delay-dump: $(RTTHREAD_DELAY_DIR)/rtthread_delay.dump
>cat $(RTTHREAD_DELAY_DIR)/rtthread_delay.dump

rtthread-delay-wave: rtthread-delay-test
>gtkwave $(RTTHREAD_DELAY_DIR)/rtthread_delay.vcd &


# ============================================================
# M11.6 RT-Thread static semaphore handoff, cancellation and timeout
# ============================================================

RTTHREAD_SEM_DIR := build/rtthread_sem
RTTHREAD_SEM_O2_DIR := build/rtthread_sem_o2
RTTHREAD_SEM_SHARED := $(RTTHREAD_START_SHARED) tick.o sem_test.o ipc.o \
    $(addsuffix .o,$(RTTHREAD_SCHED_KERNEL))
RTTHREAD_SEM_SIM := build/obj_rtthread_sem/Vtb_soc_rtthread_sem

$(RTTHREAD_SEM_DIR)/rtthread_sem.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_SEM_SHARED)) \
    $(RTTHREAD_START_DIR)/context.o $(RTTHREAD_TICK_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_SEM_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_SEM_DIR)/rtthread_sem.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_SEM_DIR)/rtthread_sem.bin: $(RTTHREAD_SEM_DIR)/rtthread_sem.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_SEM_DIR)/rtthread_sem.hex: $(RTTHREAD_SEM_DIR)/rtthread_sem.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_SEM_DIR)/rtthread_sem.symbols.hex: $(RTTHREAD_SEM_DIR)/rtthread_sem.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ sem

$(RTTHREAD_SEM_DIR)/rtthread_sem.dump: $(RTTHREAD_SEM_DIR)/rtthread_sem.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_SEM_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/context.o $(RTTHREAD_TICK_O2_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_SEM_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.bin: $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.hex: $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.symbols.hex: $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ sem

$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.dump: $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_SEM_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_sem.sv
>mkdir -p build/obj_rtthread_sem
>$(VERILATOR) --binary --timing --trace --timescale 1ns/1ps -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_sem \
>    --top-module tb_soc_rtthread_sem $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_sem.sv

.PHONY: rtthread-sem-test rtthread-sem-dump rtthread-sem-wave

rtthread-sem-test: $(RTTHREAD_SEM_DIR)/rtthread_sem.hex $(RTTHREAD_SEM_DIR)/rtthread_sem.symbols.hex \
    $(RTTHREAD_SEM_DIR)/rtthread_sem.dump $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.hex \
    $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.symbols.hex $(RTTHREAD_SEM_O2_DIR)/rtthread_sem.dump $(RTTHREAD_SEM_SIM)
>./$(RTTHREAD_SEM_SIM) +image=$(RTTHREAD_SEM_DIR)/rtthread_sem.hex +symbols=$(RTTHREAD_SEM_DIR)/rtthread_sem.symbols.hex +wave=$(RTTHREAD_SEM_DIR)/rtthread_sem.vcd
>./$(RTTHREAD_SEM_SIM) +image=$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.hex +symbols=$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.symbols.hex +wave=$(RTTHREAD_SEM_O2_DIR)/rtthread_sem.vcd
>@echo "M11.6 RT-THREAD SEMAPHORE O0/O2 CHECKS PASS"

rtthread-sem-dump: $(RTTHREAD_SEM_DIR)/rtthread_sem.dump
>cat $(RTTHREAD_SEM_DIR)/rtthread_sem.dump

rtthread-sem-wave: rtthread-sem-test
>gtkwave $(RTTHREAD_SEM_DIR)/rtthread_sem.vcd &


# ============================================================
# M11.7 RT-Thread recursive mutex and priority inheritance
# ============================================================

RTTHREAD_MUTEX_DIR := build/rtthread_mutex
RTTHREAD_MUTEX_O2_DIR := build/rtthread_mutex_o2
RTTHREAD_MUTEX_SHARED := $(RTTHREAD_START_SHARED) tick.o mutex_test.o ipc.o \
    $(addsuffix .o,$(RTTHREAD_SCHED_KERNEL))
RTTHREAD_MUTEX_SIM := build/obj_rtthread_mutex/Vtb_soc_rtthread_mutex

$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_MUTEX_SHARED)) \
    $(RTTHREAD_START_DIR)/context.o $(RTTHREAD_TICK_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_MUTEX_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.bin: $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.hex: $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.symbols.hex: $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ mutex

$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.dump: $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_MUTEX_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/context.o $(RTTHREAD_TICK_O2_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_MUTEX_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.bin: $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.hex: $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.symbols.hex: $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ mutex

$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.dump: $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_MUTEX_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_mutex.sv
>mkdir -p build/obj_rtthread_mutex
>$(VERILATOR) --binary --timing --trace --timescale 1ns/1ps -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_mutex \
>    --top-module tb_soc_rtthread_mutex $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_mutex.sv

.PHONY: rtthread-mutex-test rtthread-mutex-dump rtthread-mutex-wave

rtthread-mutex-test: $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.hex $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.symbols.hex \
    $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.dump $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.hex \
    $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.symbols.hex $(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.dump $(RTTHREAD_MUTEX_SIM)
>./$(RTTHREAD_MUTEX_SIM) +image=$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.hex +symbols=$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.symbols.hex +wave=$(RTTHREAD_MUTEX_DIR)/rtthread_mutex.vcd
>./$(RTTHREAD_MUTEX_SIM) +image=$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.hex +symbols=$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.symbols.hex +wave=$(RTTHREAD_MUTEX_O2_DIR)/rtthread_mutex.vcd
>@echo "M11.7 RT-THREAD MUTEX O0/O2 CHECKS PASS"

rtthread-mutex-dump: $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.dump
>cat $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.dump

rtthread-mutex-wave: rtthread-mutex-test
>gtkwave $(RTTHREAD_MUTEX_DIR)/rtthread_mutex.vcd &


# ============================================================
# M11.8 RT-Thread continuous producer/consumer and heartbeat demo
# ============================================================

RTTHREAD_DEMO_DIR := build/rtthread_demo
RTTHREAD_DEMO_O2_DIR := build/rtthread_demo_o2
RTTHREAD_DEMO_SHARED := $(RTTHREAD_START_SHARED) tick.o demo.o ipc.o \
    $(addsuffix .o,$(RTTHREAD_SCHED_KERNEL))
RTTHREAD_DEMO_SIM := build/obj_rtthread_demo/Vtb_soc_rtthread_demo

$(RTTHREAD_DEMO_DIR)/rtthread_demo.elf: $(addprefix $(RTTHREAD_DIR)/,$(RTTHREAD_DEMO_SHARED)) \
    $(RTTHREAD_START_DIR)/context.o $(RTTHREAD_TICK_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_DEMO_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O0 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_DEMO_DIR)/rtthread_demo.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_DEMO_DIR)/rtthread_demo.bin: $(RTTHREAD_DEMO_DIR)/rtthread_demo.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_DEMO_DIR)/rtthread_demo.hex: $(RTTHREAD_DEMO_DIR)/rtthread_demo.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_DEMO_DIR)/rtthread_demo.symbols.hex: $(RTTHREAD_DEMO_DIR)/rtthread_demo.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ demo

$(RTTHREAD_DEMO_DIR)/rtthread_demo.dump: $(RTTHREAD_DEMO_DIR)/rtthread_demo.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.elf: $(addprefix $(RTTHREAD_O2_DIR)/,$(RTTHREAD_DEMO_SHARED)) \
    $(RTTHREAD_START_O2_DIR)/context.o $(RTTHREAD_TICK_O2_DIR)/trap.o sw/rtthread/sched_test.ld
>mkdir -p $(RTTHREAD_DEMO_O2_DIR)
>$(RISCV_GCC) $(RTTHREAD_FLAGS) -O2 -Wl,-T,sw/rtthread/sched_test.ld -Wl,--no-relax \
>    -Wl,--gc-sections -Wl,-Map,$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.map -o $@ $(filter %.o,$^) -lgcc

$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.bin: $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.elf
>$(RISCV_OBJCOPY) -O binary $< $@

$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.hex: $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.bin scripts/bin2hex.py
>python3 scripts/bin2hex.py $< $@

$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.symbols.hex: $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.elf scripts/rtthread_symbols.py
>python3 scripts/rtthread_symbols.py $(RISCV_PREFIX) $< $@ demo

$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.dump: $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.elf
>$(RISCV_OBJDUMP) -d -M no-aliases $< > $@

$(RTTHREAD_DEMO_SIM): $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_demo.sv
>mkdir -p build/obj_rtthread_demo
>$(VERILATOR) --binary --timing --trace --timescale 1ns/1ps -Wall -Wno-fatal \
>    -Werror-IMPLICIT -Werror-UNDRIVEN --Mdir build/obj_rtthread_demo \
>    --top-module tb_soc_rtthread_demo $(RTL) $(SOC_RTL) tb/tb_soc_rtthread_demo.sv

.PHONY: rtthread-demo rtthread-demo-test rtthread-demo-dump rtthread-demo-wave

rtthread-demo: $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.hex \
    $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.symbols.hex $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.dump

rtthread-demo-test: $(RTTHREAD_DEMO_DIR)/rtthread_demo.hex $(RTTHREAD_DEMO_DIR)/rtthread_demo.symbols.hex \
    $(RTTHREAD_DEMO_DIR)/rtthread_demo.dump $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.hex \
    $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.symbols.hex $(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.dump $(RTTHREAD_DEMO_SIM)
>./$(RTTHREAD_DEMO_SIM) +image=$(RTTHREAD_DEMO_DIR)/rtthread_demo.hex +symbols=$(RTTHREAD_DEMO_DIR)/rtthread_demo.symbols.hex
>./$(RTTHREAD_DEMO_SIM) +image=$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.hex +symbols=$(RTTHREAD_DEMO_O2_DIR)/rtthread_demo.symbols.hex
>@echo "M11.8 RT-THREAD DEMO O0/O2 CHECKS PASS"

rtthread-demo-dump: $(RTTHREAD_DEMO_DIR)/rtthread_demo.dump
>cat $(RTTHREAD_DEMO_DIR)/rtthread_demo.dump

rtthread-demo-wave: rtthread-demo-test
>./$(RTTHREAD_DEMO_SIM) +image=$(RTTHREAD_DEMO_DIR)/rtthread_demo.hex +symbols=$(RTTHREAD_DEMO_DIR)/rtthread_demo.symbols.hex +ticks=55 +wave=$(RTTHREAD_DEMO_DIR)/rtthread_demo.vcd
>gtkwave $(RTTHREAD_DEMO_DIR)/rtthread_demo.vcd &


TB := tb/tb_rv32i.sv


VFLAGS := \
    --binary \
    --timing \
    --trace \
    -Wall \
    -Wno-fatal \
    -Wno-PINMISSING \
    --top-module $(TOP)


ASM_DIR := build/asm

ASM_SRC := sw/asm/rv32i_smoke.S
ASM_LDS := sw/asm/link.ld

ASM_ELF := $(ASM_DIR)/rv32i_smoke.elf
ASM_BIN := $(ASM_DIR)/rv32i_smoke.bin
ASM_HEX := $(ASM_DIR)/rv32i_smoke.hex
ASM_DUMP := $(ASM_DIR)/rv32i_smoke.dump

ASM_SIM := build/obj_asm/Vtb_asm

# ============================================================
# RISC-V toolchain
# ============================================================

RISCV_PREFIX := riscv64-unknown-elf-

RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP := $(RISCV_PREFIX)objdump


# ============================================================
# C smoke test
# ============================================================

C_DIR := build/c

C_START := sw/baremetal/start.S
C_SRC   := sw/baremetal/main.c
C_LDS   := sw/baremetal/link.ld

C_ELF  := $(C_DIR)/c_smoke.elf
C_BIN  := $(C_DIR)/c_smoke.bin
C_HEX  := $(C_DIR)/c_smoke.hex
C_DUMP := $(C_DIR)/c_smoke.dump
C_MAP  := $(C_DIR)/c_smoke.map

C_SIM := build/obj_c/Vtb_c

CFLAGS := \
    -march=rv32i \
    -mabi=ilp32 \
    -O0 \
    -g \
    -ffreestanding \
    -fno-builtin \
    -fno-pic \
    -msmall-data-limit=0 \
    -nostdlib \
    -nostartfiles

LDFLAGS_C := \
    -Wl,-T,$(C_LDS) \
    -Wl,--no-relax \
    -Wl,-Map,$(C_MAP)


.PHONY: all test build lint wave clean \
        asm-test asm-dump \
        c-test c-dump \
        uart-test uart-dump uart-wave

$(ASM_ELF): $(ASM_SRC) $(ASM_LDS)
>mkdir -p $(ASM_DIR)
>$(RISCV_GCC) \
>    -march=rv32i \
>    -mabi=ilp32 \
>    -nostdlib \
>    -nostartfiles \
>    -ffreestanding \
>    -Wl,-T,$(ASM_LDS) \
>    -Wl,--no-relax \
>    -Wl,-Map,$(ASM_DIR)/rv32i_smoke.map \
>    -o $(ASM_ELF) \
>    $(ASM_SRC)


$(ASM_BIN): $(ASM_ELF)
>$(RISCV_OBJCOPY) \
>    -O binary \
>    $(ASM_ELF) \
>    $(ASM_BIN)


$(ASM_HEX): $(ASM_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py \
>    $(ASM_BIN) \
>    $(ASM_HEX)


$(ASM_DUMP): $(ASM_ELF)
>$(RISCV_OBJDUMP) \
>    -d \
>    -M no-aliases \
>    $(ASM_ELF) \
>    > $(ASM_DUMP)


$(ASM_SIM): $(RTL) tb/tb_asm.sv
>mkdir -p build/obj_asm
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    -Wno-PINMISSING \
>    --Mdir build/obj_asm \
>    --top-module tb_asm \
>    $(RTL) \
>    tb/tb_asm.sv


$(C_ELF): $(C_START) $(C_SRC) $(C_LDS)
>mkdir -p $(C_DIR)
>$(RISCV_GCC) \
>    $(CFLAGS) \
>    $(LDFLAGS_C) \
>    -o $(C_ELF) \
>    $(C_START) \
>    $(C_SRC)


$(C_BIN): $(C_ELF)
>$(RISCV_OBJCOPY) \
>    -O binary \
>    $(C_ELF) \
>    $(C_BIN)


$(C_HEX): $(C_BIN) scripts/bin2hex.py
>python3 scripts/bin2hex.py \
>    $(C_BIN) \
>    $(C_HEX)


$(C_DUMP): $(C_ELF)
>$(RISCV_OBJDUMP) \
>    -d \
>    -M no-aliases \
>    $(C_ELF) \
>    > $(C_DUMP)


$(C_SIM): $(RTL) tb/tb_c.sv
>mkdir -p build/obj_c
>$(VERILATOR) \
>    --binary \
>    --timing \
>    --trace \
>    -Wall \
>    -Wno-fatal \
>    -Wno-PINMISSING \
>    --Mdir build/obj_c \
>    --top-module tb_c \
>    $(RTL) \
>    tb/tb_c.sv


c-test: $(C_HEX) $(C_DUMP) $(C_SIM)
>./$(C_SIM)


c-dump: $(C_DUMP)
>cat $(C_DUMP)


asm-test: $(ASM_HEX) $(ASM_DUMP) $(ASM_SIM)
>./$(ASM_SIM)


asm-dump: $(ASM_DUMP)
>cat $(ASM_DUMP)

all: test


build: $(SIM)


$(SIM): $(RTL) $(TB)
>mkdir -p build
>$(VERILATOR) $(VFLAGS) $(RTL) $(TB)


test: $(SIM)
>./$(SIM)


lint:
>$(VERILATOR) \
>    --lint-only \
>    --timing \
>    -Wall \
>    -Wno-fatal \
>    -Wno-PINMISSING \
>    $(RTL) \
>    $(TB)


wave: test
>gtkwave build/rv32i.vcd &


clean:
>rm -rf obj_dir
>rm -rf build/obj_asm
>rm -rf build/obj_c
>rm -rf build/obj_uart
>rm -rf build/obj_ecall
>rm -rf build/obj_illegal
>rm -rf build/obj_csr
>rm -rf build/obj_misaligned
>rm -rf build/obj_timer
>rm -rf build/obj_soc_timer
>rm -rf build/obj_cpu_timer_irq
>rm -rf build/obj_soc_timer_irq
>rm -rf build/obj_soc_memory
>rm -rf build/obj_memory_small
>rm -rf build/obj_memory_bad_rom
>rm -rf build/obj_memory_bad_ram
>rm -rf build/obj_context
>rm -rf build/asm
>rm -rf build/c
>rm -rf build/uart
>rm -rf build/ecall
>rm -rf build/illegal
>rm -rf build/misaligned
>rm -rf build/timer
>rm -rf build/soc_timer
>rm -rf build/cpu_timer_irq
>rm -rf build/soc_timer_irq
>rm -rf build/soc_memory
>rm -rf build/context
>rm -rf build/context_o2
