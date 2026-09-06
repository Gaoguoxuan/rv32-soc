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
    rtl/core/cpu_core.sv


TB := tb/tb_rv32i.sv


VFLAGS := \
    --binary \
    --timing \
    --trace \
    -Wall \
    -Wno-fatal \
    -Wno-PINMISSING \
    --top-module $(TOP)

RISCV_GCC     := riscv64-unknown-elf-gcc
RISCV_OBJCOPY := riscv64-unknown-elf-objcopy
RISCV_OBJDUMP := riscv64-unknown-elf-objdump

ASM_DIR := build/asm

ASM_SRC := sw/asm/rv32i_smoke.S
ASM_LDS := sw/asm/link.ld

ASM_ELF := $(ASM_DIR)/rv32i_smoke.elf
ASM_BIN := $(ASM_DIR)/rv32i_smoke.bin
ASM_HEX := $(ASM_DIR)/rv32i_smoke.hex
ASM_DUMP := $(ASM_DIR)/rv32i_smoke.dump

ASM_SIM := build/obj_asm/Vtb_asm


.PHONY: all test build lint wave clean asm-test asm-dump

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
>rm -f build/*.vcd
>rm -f build/*.fst