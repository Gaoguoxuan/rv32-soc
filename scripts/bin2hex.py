#!/usr/bin/env python3
# RISC-V 是 little-endian，因此需将 bin -> hex 再通过 $readmemh 读入

import sys
from pathlib import Path


def main():
    if len(sys.argv) != 3:
        print(
            "Usage: bin2hex.py <input.bin> <output.hex>"
        )
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    data = input_path.read_bytes()

    # Pad to complete 32-bit words
    while len(data) % 4 != 0:
        data += b"\x00"

    with output_path.open("w") as f:

        for i in range(0, len(data), 4):

            word_bytes = data[i:i + 4]

            word = int.from_bytes(
                word_bytes,
                byteorder="little"
            )

            f.write(f"{word:08x}\n")


if __name__ == "__main__":
    main()