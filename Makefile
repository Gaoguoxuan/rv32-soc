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
>rm -rf build/asm
>rm -rf build/c
>rm -rf build/uart