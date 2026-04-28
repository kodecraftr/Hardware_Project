import pathlib
import struct
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: elf_to_imem_hex.py <input.bin> <output.hex>")
        return 1

    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])
    data = src.read_bytes()

    pad = (-len(data)) % 4
    if pad:
        data += b"\x00" * pad

    with dst.open("w", encoding="ascii") as fh:
        for offset in range(0, len(data), 4):
            word = struct.unpack_from("<I", data, offset)[0]
            fh.write(f"{word:08x}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
