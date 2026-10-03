## UPDATE 73 (2026-10-03) — the hook table out of conventional memory: 596 KB per task

The pm hook table (`phooktab`, 1,024 x 12 = 12 KB) left res16, the part
of `$386.SYS` every task pays for in conventional memory. Maximum task
size 584 -> **596 KB** (580 before UPDATE 71; 600 with UPDATE 61's
driver, before protected-mode support). `_386.ASM` only; full
regression clean.

### Change

- **`gdthook`**: a new fixed GDT entry after `gdtpage` (data, dpl 0,
  limit `DPHKN*12-1`). `gdtspace` moves from 58h to 60h: every client
  selector is 8 higher (the kit's stub selector `0073` -> `007B`).
- **`phooktab equ 0`** (defined before the GDT): the table is offset 0
  of `gdthook`, so the 37 accesses keep their offsets and index
  arithmetic, loops and `hookhwm` unchanged; only the segment changes,
  `ss:` -> gs (`db 65h` + the instruction without an override).
- **`hookinit`** (res32), called by `e6f8e` before every session start,
  once: three pages from `nalloc` (as `stbget`), **zeroed** (a free
  entry is 0), the linear base into `gdthook`, `hookok = 1`.
- **gs = gdthook in the monitor**: `einative` loads it right after it
  saved the client's es/ds/fs/gs into `ncap0stk` (`einback` puts them
  back), so every client path (int 31h, IRQ reflection, exceptions,
  stubs) has it. `dpmiclr` -- res32, reached through int 6Fh, not
  einative -- saves gs, loads gdthook around its scan, restores it; and
  **skips the scan while `hookok` is 0** (a task that never had a client
  must not touch linear 0, where gs's base would point).

**From now on gs inside the monitor belongs to the hook table.** Monitor
code must not load gs for anything else between `einative` and
`einback`, or the hook lookups break.

### Measured

| | UPDATE 72 | UPDATE 73 |
| --- | --- | --- |
| `$386.SYS` | 48,720 | **36544** |
| max task (`MAXTASK`) | 584 KB | **596 KB** |

### Regression

- DPMI32 kit 19/19. Layout values move by the 12 KB (DOS memory lower:
  sC/sD `1FFC` -> `1CFC`; sS rm->pm `7A04` -> `4A0C`) and by the three
  pages `hookinit` takes first in extended memory (s2 lin `0020A000` ->
  `0020D000`; s5, sB, s3 likewise); stub selector `0073` -> `007B`.
- Four-task run (`GO.BAT`): every return rc 0; three STESTs 0 bad.
- `W4XTEST W4HELLO` (nested DOS/4GW, 2 x 288 hooks): rc 0, rc 0.
- FTEST `1BE00000`, TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
  (11/11/12 MB) on DJGPP, DOS/4GW and DOS/32A.

### Build

| file | md5 |
| --- | --- |
| `_386.ASM` | `9e3315afa3d497c909f0e78b4dfe78dd` |
| `$386.SYS` (36544) | `88f9f0c2dc73fb2b592fcbedce91911d` |

### Lessons (MASM 5.1, res16)

- res16 is assembled for the 286: no fs/gs overrides -- emit the prefix
  byte (`db 65h` for gs, `db 64h` for fs) before an override-free
  instruction.
- A macro used before its definition gives a **phase error** at the
  next label (`EAXI` is defined around line 7950; in `einative` the
  bytes are written out instead).
- An `equ` used before its definition can change an instruction's
  size between passes: define such constants early.

### To-do

1. Per-client hook bitmap: the remaining hook lookup per int 31h
   (~30% of the monitor's work per call).
2. Fresh handover header summarising UPDATE 62-73.
