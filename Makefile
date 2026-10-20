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
>rm -rf build/asm
>rm -rf build/c
>rm -rf build/uart
>rm -rf build/ecall
>rm -rf build/illegal
>rm -rf build/misaligned
>rm -rf build/timer
