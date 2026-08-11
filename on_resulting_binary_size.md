# On the resulting binary size

Notes from investigating why `scratchpad4k.exe` is ~500 KB and whether it can
be made smaller (spoiler: not below ~430 KB with the current toolchain).

## Sizes at a glance

| Build | Size |
|---|---|
| Debug (`zig build`) | 1.93 MiB (2,025,984 B) + 2.8 MiB `.pdb` |
| ReleaseSmall, gnu target (`zig build -Doptimize=ReleaseSmall`) | 557 KiB, before changes → 487 KiB (499,200 B) after |
| ReleaseSmall, msvc target (`-Dtarget=x86_64-windows-msvc`) | 429 KiB (439,296 B) |

## Where the bytes go

Section analysis of the final ReleaseSmall binary (gnu target):

| Section | Raw size | Real content | Notes |
|---|---|---|---|
| `.text` | 140 KiB | ~124 KiB (88% non-zero) | code |
| `.rdata` | 288 KiB | ~21 KiB (7% non-zero) | UTF-16 string atoms, jump tables; the rest is zeros |
| `.data` | 52 KiB | 292 B (1% non-zero) | mutable globals; the rest is zeros |
| **total** | **487 KiB** | **~145 KiB** | **~320 KiB is zero padding** |

The app's own logic is only a few KiB of `.text`. Almost everything else is
Zig std code pulled in transitively: `std.fmt` formatting, `std.unicode`
converters, a crypto/RNG component, `std.ArrayListUnmanaged`, allocators, and
the panic handler (which re-imports `std.fmt`).

## The padding

The bulk of the file is zero padding in `.rdata`/`.data`. The cause is the
Zig 0.16 compiler's COFF object layout: every `wchar` of every UTF-16 string
is emitted as its own tiny 2-byte atom, and atoms are placed across
over-sized sections with gaps up to 64 KB (five stray atoms ~64 KB apart
account for most of the `.rdata` waste). The layout is baked into the object
file, so no linker flag helps:

- the builtin linker and `lld-link` (`-flld`) produce byte-identical output
- `--gc-sections`, `-fno-data-sections`, `-ffunction-sections`, `-fstrip`
  have no effect
- only the target ABI changes the result: `-gnu` (Zig default) → 487 KiB,
  `-msvc` → 429 KiB

## What was changed to shrink the binary

- `std.heap.DebugAllocator` → `std.heap.page_allocator` (`main.zig`)
- stopped formatting `std.os.windows.Win32Error` with `{}` in message boxes
  and debug prints; formatting the enum emits the full ~1500-entry error-name
  table (~60 KiB) via `@tagName`
- replaced `std.fmt.allocPrint` with a tiny fixed-buffer formatter and manual
  decimal appends (`helpers/error_message.zig`, `main_window.zig`)
- replaced `std.unicode` conversions with the Win32 `MultiByteToWideChar` /
  `WideCharToMultiByte` APIs (`helpers/string_conversions.zig`)
- replaced `std.debug.panic` / `std.debug.print` with plain `@panic` / nothing

Build and tests pass; the app runs (verified: caption `Scratchpad4k`).

## Can it go below 100 KB?

No, not with Zig 0.16:

1. the zero padding is ~270-330 KiB regardless of app code (compiler layout)
2. even with zero padding, the remaining ~145 KiB (code + data) exceeds 100 KiB

The realistic floor with this toolchain is ~430 KiB (ReleaseSmall + msvc
target). Going lower would require a Zig version with a denser COFF layout or
a different toolchain. If the padding were fixed and the std code trimmed to a
minimum (custom panic handler, no `std.fmt`/`std.unicode`/crypto), the
content-only size would be on the order of ~100 KiB.

## Building the smallest variant

```
zig build -Doptimize=ReleaseSmall -Dtarget=x86_64-windows-msvc
```
