## UPDATE 70 (2026-10-02) — 0501h without "valloc everything"; task size; profiling — IN PROGRESS

**Status: not regression-tested. The test-phase verifier `nverify` is
still active (it repeats every allocation scan from page 0). Do not
ship this `$386.SYS`; see "To finish" below.**

### Task size (measured, no change yet)

`MAXTASK.COM` (new rig tool, `MAXTASK.ASM`; build with `combuild.sh`)
prints the kernel's maximum task size -- services int D4h, ah=2Dh, dx =
paragraphs, the call `ADDTASK MAX` uses.

| configuration | max task |
| --- | --- |
| `$386.SYS` UPDATE 69 (52.5 KB) + `$DPMI.SYS` | 580 KB |
| `$386.SYS` UPDATE 61 (32.5 KB) + `$DPMI.SYS` | 600 KB |
| `$386.SYS` UPDATE 69, no `$DPMI.SYS` | 580 KB |

`$DPMI.SYS` costs nothing. The 20 KB is exactly the growth of
`$386.SYS`, whose resident part sits in conventional memory. Biggest
items: the hook table (1,024 x 12 = 12 KB, mostly empty) and the retf
stub tables (3 KB) -- candidates to move to extended memory (to-do 2).

### Profiling int 31h calls

Hook mode (monitor instructions, `H` lines) plus step mode (v-86
instructions, `S` lines); the lines between two consecutive calls of
one kind are one round trip.

New: **`PMTRACE_GATE_AX=hex`** -- hook and step logging stay off until
the first int 31h with that ax (`rig/pmtrace-update70.patch`). The boot
runs at normal tracing speed (6.5 MB of log instead of 436 MB).

	PMTRACE=/tmp/t.log PMTRACE_WIN=50000000 PMTRACE_HOOK_LO=0x100
	PMTRACE_HOOK_HI=0xD000 PMTRACE_HOOK_N=20000000 PMTRACE_STEPS=200000
	PMTRACE_GATE_AX=0501 DOSBOX_BIN=~/dosbox-trace ./boot.sh IMG.img

(Boot and test in separate tool calls; `boot.sh` needs an `.img`
name.) Monitor offsets above `A4E0` (res16's length, para-aligned) are
res32: subtract `A4E0` for the res32 listing offset.

| call | monitor | real mode | note |
| --- | --- | --- | --- |
| 0400h | ~210 (UPDATE 69) | 0 | fine |
| 0300h | 630 | 744 | ~180 of the 630 are the hook lookup (to-do 3) |
| 0501h+0502h (UPDATE 69) | **69,379** | 248 | 65,000 in one loop: 3,606 x ~18 in `nalloc` |

### Found: 0501h allocated all free memory

The page map (`nparspace`, physical `0x111440`, `parsize` = 3E80h =
4,000 entries, free = bit 11) after boot and DJBENCH: **two runs** --
0..233 in use, 234..3999 free. Not fragmented.

The cost was our 0501h (`e31alc`): to enforce the reserve (`dpmirsv`
= 200h pages, 2 MB) it asked the memory device for everything (`cx =
FFFFh`, "valloc everything"): `nalloc` walked all ~3,766 free pages
and marked them in use; then the tail beyond the request was released,
walking them again. Two passes over all free memory per allocation.

### Change (working tree)

1. **0501h (and the 0503h grow path, which shares `e31alc`)**: the
   reserve is checked against the free page count (`parsize/4 -
   parmused`, both kept by the memory manager); then exactly the
   request is allocated (first fit). No contiguous block that large:
   given back, fail, as before. **Meaning changes**: the reserve now
   stays free IN TOTAL, not "request + reserve in one block". Blocks
   are the first that fits, not the largest.
2. **`nalloc` start hint `nhint`**: every page-map entry below it is in
   use. `nalloc` starts there (was 0) and advances it after allocating
   (to the end of its run if the run started at the first free entry
   it saw, `nfirst`, else to `nfirst`); `nrelease` lowers it to a freed
   start. The only writers of the free bit are `nalloc` and `nrelease`.
3. **`nverify` (test phase)**: repeats the original scan from page 0
   without marking, compares start and count; differences count in
   `nhintbad`. To be removed before release.

`$386.SYS` 52,528 -> 52,800, 0 warnings.

### Measured (dynamic core, DJBENCH 20000, relative to its cpu loop)

| | UPDATE 69 | working tree |
| --- | --- | --- |
| 0501h+0502h pair | 8.1 | **2.5** |
| `nhintbad` | -- | 0 |
| page map afterwards | -- | unchanged: 0..233 used, 234..3999 free |

What is left of a pair is mostly its two v-86 round trips (valloc,
vrelease), each about as costly as a 0300h.

### To finish UPDATE 70

1. Full regression with the verifier still in: DPMI32 kit, the
   four-task run (`GO.BAT`), FTEST/TTEST/KTEST/MTEST/STEST on DJGPP,
   DOS/4GW and DOS/32A. MTEST matters most (reserve semantics): it
   should still get 11/11/12 MB. Then `nhintbad` must read 0.
2. Remove `nverify` (the `call nverify` at `nal2` and the routine),
   rebuild, rerun the benchmark and a short regression.
3. ADDTASK reports the current maximum task size (see to-do 4).

### Files

| file | md5 |
| --- | --- |
| `_386.ASM` (working tree, verifier in) | `b6ff6a3fcc59f2d1f957e729e959791a` |
| `$386.SYS` (52800, NOT for release) | `d85977538550c22f622a5ac36032848b` |
| `MAXTASK.ASM` (rig tool) | `c59eb7c159bc94785e0294d4a8b05434` |
| `rig/pmtrace-update70.patch` | on top of UPDATE 66's |

### Lessons

- Measure the data before designing the structure: "the map must be
  fragmented" was wrong; two runs, and the probe was ours.
- `mem.sh` reads PHYSICAL memory: a selector's linear base above 1 MB
  is not the address to read (`gdtpage` linear `1C1000h` = physical
  `111000h`, the page table).
- mawk has no `strtonum` or hex literals: use `gawk`.
- A traced emulator can survive `pkill -x` after a timed-out call: stop
  by PID (`for P in $(pgrep dosbox); do kill -9 $P; done`).

### To-do (ordered)

1. Finish UPDATE 70 (above).
2. Win back ~15 KB per task: hook table and stub tables out of
   conventional memory (580 KB now; 600 KB with UPDATE 61's driver).
3. Per-client hook bitmap: ~30% less monitor work per int 31h (the
   remaining hook lookup); fits with 2.
4. **ADDTASK: report the current maximum task size** -- wherever it
   reports size limits (minimum 32K, "Insufficient memory available",
   usage), add a line such as `Maximum task size now: 580K`, from int
   D4h ah=2Dh (as MAXTASK). `ADDTASK.ASM` only. (Agreed.)
5. Fresh handover header summarising UPDATE 62-70.
