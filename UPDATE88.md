# UPDATE 88 -- DOS API sweep: TRUENAME, 65h/66h, 5802h (2026-10-09)

Files: `MOSFUN39.ASM`, `MOSTEMP.ASM`, `MOSINT21.ASM` (kernel), CRLF;
`sweep.c` (test). `$$MOS.SYS` 130,657 bytes, md5 `4be8fcbff98e`
(UPDATE 84-87 + this), `kbuild.sh MOSFUN39 MOSTEMP MOSINT21`, MASM 0
warnings / 0 severe errors.

## Method

`sweep.c` (Open Watcom, 16-bit real mode, `wcl -bt=dos -ms`) calls
about 70 int 21h/2Fh functions and prints the raw results. The same
binary runs on DOSBox's built-in DOS (reference) and on PC-MOS, and
the outputs are diffed. DOSBox's DOS is not a perfect reference (it
opens a read-only file for writing, for instance), so every difference
was judged against DOS 5 behaviour. Output: `sweep-ref.txt` (DOSBox,
drive C:) and `sweep-pcmos.txt` (PC-MOS, floppy A:).

## Fixed

| function | before | now |
| --- | --- | --- |
| **60h** TRUENAME | returned the *last opened file name* and ignored ds:si (PC-MOS's 1987 reading of an "undocumented" call) | canonical path as DOS 3.0+: `\A\.\B\..\C.TXT` -> `A:\A\C.TXT`, `sub\..\x.y` -> `A:\X.Y`, current directory put in front of relative paths, upper case; bad drive: CF, AX=0Fh |
| **6501h** extended country info | invalid function | header (id 1, size 38, country, code page 437) + the 34 bytes of 38h |
| **6520h/6521h/6522h** upper case char/string/ASCIIZ | invalid function | code page 437 (as `caps`, without its E5h->05h directory trick) |
| **6523h** yes/no | invalid function | 0 no / 1 yes / 2 neither |
| **6601h/6602h** code page | invalid function | get: 437/437; set: 437 accepted, others error 2 |
| **5802h** get UMB link | CF set | AL=0, no error (DOS 5 without UMBs) |
| **5803h** set UMB link | always error | unlink (BX=0) ok; link: error 1 (no UMBs) |

60h moved from `MOSTEMP.ASM` (segment `mos`) to `MOSFUN39.ASM` (segment
`mo2`, the far function table in `MOSINT21.ASM`): **`mos` is full**,
and the link failed with "MOSSEG: segment size exceeds 64K" (it is at
FFC6h of 10000h).

## Kernel space: the low area moves in 8 KB steps

The first complete version (with 6502h/6504h/6505h/6506h/6507h, i.e.
the upper case, file name, collating and DBCS **table pointers**) cost
**8 KB per task**: MAXTASK 564K -> 556K. `grp`+`mo2` sit in low memory
below the tasks (`MEM /FULL`: "IO system data" 74K -> 82K) and that
area grows in 8 KB steps. About 900 bytes of code and tables crossed
one.

The table pointer subfunctions (about 450 bytes with their tables)
were therefore left out: they return "invalid function", as before.
Programs that need case conversion use 6520h-6522h, which are there.
With that, `mo2` ends at 0CC7Bh (MOS at 0CD00h; the step was crossed at
0CE00h): **about 130 bytes of room left** before the next 8 KB step.
That is a constraint for anything added to `mo2` from now on.

## Differences that are fine

| call | PC-MOS | note |
| --- | --- | --- |
| 3800h date separator | `-` | correct for USA in MS-DOS; DOSBox has `/` |
| 3D01h on a read-only file | refused (05h) | correct; DOSBox allowed it |
| 59h after file not found | class 8, action 3, locus 2 | as MS-DOS; DOSBox differs |
| 3306h flags | 00h | DOS not in HMA: correct |
| 0Eh | 2 drives | PC-MOS returns the drives that exist, not LASTDRIVE |
| 4400h stdin | 80C3h | bit 4 (int 29h fast console) clear: cosmetic |
| 7147h (LFN probe) | CF=0, AX=7100h | as MS-DOS 5/6 (AL=0, CF unchanged); LFN-aware programs check AX=7100h |
| 4Eh volume label | not found | the test floppy has no label |
| 49h on a freed block | no error | as MS-DOS |
| 440Eh | AL=1 | A: and B: on one drive, A: active: correct |

## Regression (final kernel)

- sweep: all new functions as listed;
- MAXTASK **564K** (unchanged);
- `xmst` 45 ok;
- four-task `GO.BAT` all rc 0, STEST 0 bad, all DONE.
