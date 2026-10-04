## UPDATE 74 (2026-10-03) — hook lookup guard; per-client hook bitmap

`_386.ASM` only; full regression clean.

### 1. Guard: no lookups before the table exists

Since UPDATE 73 the hook table is behind `gdthook` (gs), set up at the
first session start; `einative` loads gs on every native-mode entry,
with base 0 until then. `dpmiclr` already skipped its scan while
`hookok` = 0. Now **`e31hfind` and `e31xfind` return "not hooked"
(cf = 1) while `hookok` = 0** too: no path can read linear 0 (the IVT)
as hook entry 0, whatever reaches the lookups first.

### 2. Per-client "maybe hooked" bitmap

One bit per (client id, vector): 128 x 256 bits = 4 KB, a fourth page
behind the table in the same segment, at **`gs:[3000h + id*32 +
vector/8]`**, mask `1 << (vector & 7)`. `hookinit` now takes four pages
(16 KB of extended memory), zeroes them, sets `gdthook`'s limit to
`3FFFh` and keeps the linear in `hooklin`.

- **Set only**: `e0205s` sets the bit when 0205h makes an entry. An
  unhook leaves it -- a stale bit only means the usual scan, which is
  still correct. A cleared bit for a hooked vector cannot happen.
- **Cleared per id**: `cidstart` clears an id's 32 bytes when it hands
  the id out (through `hooklin`, flat; gs is not loaded on that res32
  path). Covers reuse of an id.
- **`e31hfind`**: bit 0 -> "not hooked" at once; bit 1 -> the scan as
  before. Exceptions (`e31xfind`, kind 1) keep their scan (32 vectors,
  rare).

In res16 the bitmap accesses need both `67h` (16-bit addressing --
without it `[si+disp]` would decode as a 32-bit address with a SIB
byte) and `65h` (gs). Two `je e0205u` went out of short range (the
286 `jcc` reaches +-127): inverted around `db 66h / jmp e0205u`.

### Measured

DJBENCH 20000, relative to its cpu loop: 0300h 1.30 (UPDATE 73) vs 1.34
-- within the noise. The lookup was ~180 of the 630 monitor
instructions per 0300h (~13% of the instructions), but the emulator's
time goes into the two mode switches of the v-86 round trip. The guard
is the part that matters.

### Regression

- DPMI32 kit 19/19 -- sF (int 21h through a hook), sL (IRQ0 through a
  hooked 08h), sN (exception handlers) all through the new lookup.
  Changed: s2 lin `0020D000` -> `0020E000` (the bitmap page; s3, s5,
  sB likewise); s3's forged 0502h flags `3217` -> `3213` (PF only, cf=1
  both: a side effect of the host's last arithmetic, undefined by DPMI).
- Four-task run (`GO.BAT`): every return rc 0; three STESTs 0 bad --
  nested DOS/4GW (all 256 bits of a client set) and many id reuses.
- FTEST `1BE00000`, TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
  (11/11/12 MB) on DJGPP, DOS/4GW and DOS/32A.

### Build

| file | md5 |
| --- | --- |
| `_386.ASM` | `486be34726702632e9977f4eb425e079` |
| `$386.SYS` (36720) | `6383f1809dc3f7ef37083ba6ed83c3ad` |

### To-do

1. Fresh handover header summarising UPDATE 62-74 (done: `HANDOVER-HEADER.md`).
