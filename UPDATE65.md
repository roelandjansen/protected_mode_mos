## UPDATE 65 (2026-09-27) — DPMI version 0.90; initial ss/ds G=0; makegdte keeps what it reuses

Two open items from UPDATE 64, fixed and regression-tested together.
Full regression clean (below). Item 3 of the plan (larger real
programs) is next.

### 1. DPMI version

1687h returned DX = `0100h` (DPMI 1.00) while 0400h (monitor) returns
0.90 (`005Ah`). We implement 0.90; an extender may take other paths for
1.0. `_DPMI.INC`: **`DPMIVersion equ 005Ah`** (was `0100h`). Used by the
1687h answer and the dormant `GetDPMIVer` in `_DPMI.ASM` only.

Measured (DPMI32 prints 1687h's DX now): `1687h flags: 0001 version:
005A`, `0400 fl/ax/bx: 3292005A0001`.

### 2. Initial ss/ds: G=0

`makegdte` builds every descriptor with g=1,d=1 (`00C0h`): the client's
initial ss/ds had a 256 MB limit on a 64 KB segment. HDPMI32 gives
`0040h`. With G=0 a bad stack/data pointer faults (#SS/#GP) instead of
silently using memory above the segment -- UPDATE 64's bug 4 would have
been a clean #SS.

`_386.ASM`:

- **`clrgran`** (new, res16, after `cleardti`): g=0 on the descriptor
  of selector ax; ax = 0 left alone; keeps d/b and limit 19:16;
  preserves all registers. `nmswitch` calls it after `makegdte` for ds,
  es, gs, fs and ss (not cs).
- **`makegdte` reuses a matching entry AS IT IS.** A match (same task,
  access, base) used to fall into `mgdgotav` and get limit `FFFFh` and
  `00C0h` again -- undoing `clrgran` as soon as the kernel translated the
  same segment again, and any limit a client set itself with 0008h
  (DOS/32A: ds to 4 GB; the UPDATE 64 open item). The match now jumps to
  `mgdret` (return the selector); only a fresh entry is written.

**Caught before hand-over:** `clrgran` first used the selector as
returned by `makegdte` (rpl 3, `or al,3`) as the gdt offset: it cleared
bit 7 of byte `+61h`, the next descriptor's limit (`60h` read `FF 7F`).
Fixed with `and di,0fff8h` (`83 E7 F8`, also right in the 32-bit
segment).

Measured: `cs/ss/ds ar-high: 0000 0040 0040` (was `0000 00C0 00C0`),
twice in one boot and after the mixed session. GDT read from the
emulator: `58h` `FF FF A0 DA 00 F2 40 00`, neighbour `60h` intact
(`FF FF`).

### DPMI32

Saves 1687h's DX (`rDX`) and prints it on the flags line.

### Full regression

| test | result |
| --- | --- |
| DPMI32 kit, 18 clients | identical to UPDATE 64 (layout values included: sB `8103`, sC/sD `1DFC`/`1E05`, sS `54F5`) |
| s32 (`DPMI32`), twice | all checks; version `005A`; ar-high `0000 0040 0040` |
| mixed boot | `DJHELLO`, `DJMEM`, `W4HELLO`, `W4MEM`, `DOS32A WAHELLO`, `DOS32A WAMEM`, then all six again in another order, then `DPMI32`, `SET`: every line and sum (`1FE00000`) correct, environment intact |

### Build

`$386.SYS` 42240 -> 42288, 0 warnings. `$DPMI.SYS` 5149 (same size),
the 4 pre-existing warnings.

| file | size | md5 |
| --- | --- | --- |
| `$386.SYS` | 42288 | `735935e8b1f27e494f0bdfededbc833f` |
| `$DPMI.SYS` | 5149 | `f84240795eaad457dc4a208ba147ae1d` |
| `DPMI32.COM` | 1558 | `d7dd6f0a54f7fd0e35d9b33c32aaca5e` |
| `_386.ASM` | | `d251538242e41a5f1868b0bdfdcd7795` |
| `_DPMI.INC` | | `22d2c481ce0fe3e423c0ac2c48d15df9` |
| `DPMI32.ASM` | | `6337eee5bfe072ad5a342fccbe89eba6` |

`_DPMI.ASM` unchanged since UPDATE 64 (`ee86eb51…`).

### Lessons

- **The GDT is not at a fixed address.** It moved when `dtitable` grew
  (UPDATE 64). Take `GDT` from the listing (`18A0` now) before reading
  descriptors with `mem.sh`: linear = `700h + GDT + selector`.
- `makegdte` returns the selector with rpl 3: mask before using it as a
  gdt offset.
- Regression runs longer than one tool call: run them as a background
  script writing to a file (`runkit.sh`, `runext.sh`), then poll. A
  background job does not survive the end of a turn -- check where it
  stopped and restart from there.

### Open

- A client that relied on the 256 MB limit of its initial ds/ss now
  faults. None of the four environments does.
- Per-client ownership of hooks, descriptors and memory (parked).
- 0001h at DOS/4GW's exit fails for 11 selectors (harmless so far).

### Next

Item 3: larger real programs per environment (file I/O, keyboard,
graphics).
