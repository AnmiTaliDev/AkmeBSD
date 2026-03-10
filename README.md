# AkmeBSD

![License](https://img.shields.io/github/license/AnmiTaliDev/AkmeBSD)
![Language](https://img.shields.io/badge/language-Zig%200.15-f7a41d)
![Status](https://img.shields.io/badge/status-experimental-orange)

An educational kernel written in Zig. Forked from
[MoskoviumBSD](https://github.com/z3nnix/MoskoviumBSD) by z3nnix and rewritten from scratch.

## Requirements

- [Zig](https://ziglang.org/) 0.15
- `xorriso`
- `limine` CLI
- QEMU (for `zig build run`)

## Building

```sh
zig build        # produces dist/akme-amd64.iso
zig build run    # boots in QEMU
```

Release ISO:

```sh
OS_STAGE=RELEASE chorus build build-release
```

## Philosophy

AkmeBSD follows the UNIX tradition in spirit: small, composable, and honest about what it does.
BSD taught that an OS can be a coherent whole built by people who understand it end to end.

## License

MIT — see [LICENSE](LICENSE).
