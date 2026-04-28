import pathlib
import struct
import sys


def main() -> int:
    if len(sys.argv) not in (3, 4):
        print("usage: bin_to_word_hex.py <input.bin> <output.hex> [depth_words]")
        return 1

    src = pathlib.Path(sys.argv[1])
    dst = pathlib.Path(sys.argv[2])
    depth_words = int(sys.argv[3]) if len(sys.argv) == 4 else None

    if src.exists():
        data = src.read_bytes()
    else:
        data = b""

    pad = (-len(data)) % 4
    if pad:
        data += b"\x00" * pad

    with dst.open("w", encoding="ascii") as fh:
        words = []
        if not data:
            words = [0]
        else:
            for offset in range(0, len(data), 4):
                words.append(struct.unpack_from("<I", data, offset)[0])

        if depth_words is not None and len(words) < depth_words:
            words.extend([0] * (depth_words - len(words)))

        for word in words:
            fh.write(f"{word:08x}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
