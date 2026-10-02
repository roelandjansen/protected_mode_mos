## UPDATE 69 (2026-10-01) — int 31h 10x cheaper; four DPMI tasks at once

### Four tasks with DPMI clients (no code change)

`GO.BAT` starts tasks 1..3 (`ADDTASK 500,n,,Tn.BAT`) and runs task 0's
chain into `T0.TXT`. One boot, all at once:

| task | workload | result |
| --- | --- | --- |
| 0 | DJGPP -> DOS/4GW -> DJGPP | every return rc 0 |
| 1 | DJGPP -> DJGPP, DJSTEST | rc 0; churn/sort 0 bad |
| 2 | DOS/4GW -> DOS/4GW, W4STEST | rc 0; churn/sort 0 bad |
| 3 | DOS/32A -> DJGPP, DJSTEST | rc 0; churn/sort 0 bad |

Rig: with other tasks busy the console drops keystrokes even at an idle
prompt (two `addtask` lines arrived cut or merged). Put the commands in
one batch file and type a single short command; `rig/waitp.sh` waits
for an idle prompt before typing.

### The cost of an int 31h call

`DBENCH` (UPDATE 67) put our cost per call at ~25-30x HDPMI32's.
Counted, not guessed: the tracing emulator's hook mode logs every
monitor instruction (`PMTRACE_HOOK_LO=0x100 PMTRACE_HOOK_HI=0xD000
PMTRACE_HOOK_N=3000000`); the lines between two consecutive
`INT 31 ... eax=00000400` events are one round trip.

One 0400h (get version -- the host only returns constants): **5,413**
instructions, five of them executed exactly **1,024** times: `e31hfind`
("has this client hooked this vector?", asked for every interrupt the
host dispatches for a client, int 31h included) walked the whole hook
table -- 1,024 entries since UPDATE 67 (320 before, 32 before UPDATE
64). Everything else: ~210 instructions.

**Fix: `hookhwm`**, the offset just past the highest `phooktab` entry
ever used. `e31hnew` raises it at `e31hnok`; the lookups `e31hfind`,
`e31xfind` and the clearing loop `e31hclr` stop there instead of at
`DPHKN*12`. Never lowered, so no entry is ever missed; entries are
allocated lowest-free-first, so it stays at the real working set (a
few entries with DJGPP, ~288 per DOS/4GW). The allocation loop
(`e31hnlp`) and `e6f8fhn` keep scanning the whole table.

`DBENCH 20000`, dynamic core, same floppy:

| call | UPDATE 68 | UPDATE 69 |
| --- | --- | --- |
| 0400h | 0.49 s | **0.05 s** |
| 0300h | 1.48 s | 1.48 s |
| 0501h+0502h | 8.24 s | 9.34 s (noise) |

Left: 0300h ~74 us and a 0501h/0502h pair ~450 us (HDPMI32: ~1 us).
Neither touches the hook table: both go through `dovmint` (v-86, the
real-mode code, int 6Fh 7702h, `nmswitch`). Next: count them the same
way and split our transitions from PC-MOS's own code.

### Regression

- DPMI32 kit 19/19; only sS's offset `79F6` -> `79F8` (+32 bytes).
- The four-task run above.
- FTEST (`1BE00000`), TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
  (11/11/12 MB) on DJGPP, DOS/4GW and DOS/32A; SET ok.

### Build

`$386.SYS` 52496 -> 52528, 0 warnings.

| file | md5 |
| --- | --- |
| `_386.ASM` | `c5eb681ed8719c2fccbb0de039cc5143` |
| `$386.SYS` (52528) | `c38702fe53a9e6c1bbf3fcc2d84dfab5` |

### Files

`_386.ASM`; `GO.BAT`, `T1.BAT`..`T3.BAT` (the four-task test);
`rig/waitp.sh`.

### Lessons

- Every enlargement of a table that is scanned per call is a slowdown
  for every call: size the table, then bound the scan.
- Profile by counting instructions, per call, in the monitor: one
  number told where the time went.
