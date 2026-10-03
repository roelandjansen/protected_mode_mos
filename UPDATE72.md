## UPDATE 72 (2026-10-03) — 16-bit loads used as 32 bits; 0500h without probing

Two to-do items. `_386.ASM`; rig test `mi500.c`. Full regression clean.

### 1. Audit: NLDW followed by 32-bit use

UPDATE 71's DOS/4GW failure was `NLDW` (loads the low 16 bits) followed
by code that uses all of eax -- in res16 a plain `or ax,ax`, `mov si,ax`
or `mov cx,ax` IS the 32-bit operation. Correct only while eax's high
word happens to be 0. All 42 `NLDW` sites checked; five depended on it:

| place | with a stale high word |
| --- | --- |
| `e31desc` (0000h-000Ch) | function unknown: UPDATE 71's DOS/4GW failure |
| `e310300`, `e310301` (0300h-0302h) | "CX (stack words) != 0": every real-mode call refused, i.e. all DJGPP I/O |
| `e3100` (0000h) | cleared cx, not ax: a huge descriptor count |
| `e310304` | a wrong dx for the callback lookup |

Each now clears eax (`xor ax,ax`) right before its `NLDW`. Intentional
cases left alone: `e31pages` (`bx<<16 | cx`, eax cleared first) and
0503h's `start<<16 | pages`. UPDATE 71's clearing in `einvst` stays as a
second line.

### 2. 0500h: no "valloc everything"

0500h found the largest block by asking the memory device for all of
it and releasing it again: two v-86 round trips, `nalloc` marking all
free pages and `nrelease` unmarking them (the pattern UPDATE 70 removed
from 0501h). New res32 **`nlargest`**: one read-only pass over the page
map from `nhint`, out eax = the longest free run, ecx = free pages in
total (`parsize/4 - parmused`). 0500h reports **min(longest run, free
- reserve)**, never below 0 -- 0501h's own conditions (UPDATE 70).
Reached from res16 through `nlgptr` (filled in `e6f8e`, like `stbptr`).
The client's registers are no longer touched (no dovmint); the old
save/restore stays, harmless.

`mi500.c` (DJGPP, `__dpmi_get_free_memory_information`), same floppy:

| | largest | unlocked | locked | free |
| --- | --- | --- | --- | --- |
| UPDATE 71 | 12,664,832 bytes | 3,092 | 3,092 | 3,092 pages |
| UPDATE 72 | 12,664,832 bytes | 3,092 | 3,092 | 3,092 pages |

### Regression

- DPMI32 kit 19/19 (only sS's rm->pm offset `7A00` -> `7A04`).
- Four-task run (`GO.BAT`): every return rc 0; three STESTs 0 bad.
- FTEST `1BE00000`, TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
  (11/11/12 MB) on DJGPP, DOS/4GW and DOS/32A.

### Build

| file | md5 |
| --- | --- |
| `_386.ASM` | `4ec5db43c11ac6d49047587040b88383` |
| `$386.SYS` (48720) | `2fdbaabd0974a54a1820eaa4569b29b4` |

### Lessons

- In res16 every register operation without `66h` is 32-bit. After a
  16-bit load, clear eax first unless the high word is built on
  purpose -- and say so in a comment.
- Container restarts kill background test runs: rerun the remainder
  (the kit script takes an explicit client list).

### To-do

1. Hook table (12 KB) out of conventional memory: ~41 accesses in 18
   routines move to a dedicated selector; +12 KB per task.
2. Per-client hook bitmap (fits with 1).
3. Fresh handover header summarising UPDATE 62-72.
