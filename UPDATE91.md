# UPDATE 91 -- DOS API sweep 2: int 2Fh, IOCTL, disk info; int 21h 69h (20261010)

Files: `MOSFUN44.ASM`, `MOSINT21.ASM` (kernel), CRLF; `sweep2.c` (test),
`sweep2-ref.txt`, `sweep2-pcmos.txt`.

- `$$MOS.SYS` 130,657 bytes, md5 `5dbab76c6434` (UPDATE 84-90 + this),
  `TREE=/home/claude/scr kbuild.sh MOSFUN44 MOSINT21`.
- MASM 0 warnings / 0 severe errors.
- `mo2` (DDT) now ends at 0CCAFh: about 80 bytes left before the next
  8 KB step.

## Method

The method is the same as UPDATE 88. `sweep2.c` (Open Watcom, 16-bit)
makes the following calls:

- int 2Fh installation checks;
- IOCTL 4400h-4411h on handles and drives, plus 440Dh 0860h/0866h/0867h;
- the disk information calls 1Bh/1Ch/1Fh/32h/36h;
- 69h (disk serial number), 68h (commit), 57h (file date and time),
  5Ch (record locking), 5Ah/5Bh (temp and new files), 6Ch (extended
  open), 5F02h (redirection list).

The reference is DOSBox's own DOS with a 1.44 MB floppy image mounted
(`imgmount`). Every difference was judged against DOS 5 behaviour.

## Fixed

| call | before | now |
| --- | --- | --- |
| **6900h** get disk serial number, label and file system type | CF clear, buffer **untouched** (function not in the table) | as `440Dh` CX=0866h: serial, label, `FAT12   ` |
| **6901h** set serial number | same | as `440Dh` CX=0846h |
| 69h with AL > 1 | CF clear, nothing done | error 1 (invalid function) |
| 69h on a drive that does not exist | CF clear | error 0Fh |

`mosfun69` (in `MOSFUN44.ASM`, segment `mo2`) changes the task's AL/CX
to the 440Dh form, calls `mosfun44`, and puts AL/CX back unless an
error code was returned. It costs 52 bytes in `mo2`.

## Differences that are fine

| call | PC-MOS | note |
| --- | --- | --- |
| 440Ah on a local file | CF=0, DX bit 15 = 0 | correct (local). DOSBox does not support 440Ah |
| 4411h 0860h/0866h | supported | correct: the block driver handles them. DOSBox says unsupported |
| 440Dh 0860h | the real BPB (224 root entries, media F0h) | correct; DOSBox returns zeros |
| 440Dh 0867h | error 16h | unknown command, as MS-DOS. DOSBox: 01h |
| 1Fh | the real DPB, max cluster 2848, matching 36h | correct; DOSBox fakes it |
| 4408h/4409h/36h/1Ch/32h on Z: | invalid drive | correct. DOSBox has its own Z: drive |
| 5Ch lock/unlock, 57h, 6Ch (create/open/exclusive/truncate), 5Ah, 5Bh, 68h | identical | |

## Not changed

- **2F1A00h (ANSI.SYS installed?)** returns 00h, but PC-MOS has ANSI
  built into its console (`MOS ANSI ON/OFF`, `tcbansi`). Programs that
  test for ANSI.SYS therefore won't use escape sequences. A check in
  `mosint2f` (24 bytes in `MOSTEMP.ASM`, segment `mos`) worked, but
  **any growth of `mos` past about 0FFC6h makes the system hang**
  (below). Left out.
- **The mos segment is full in practice, not just at 64 KB.** With only
  24 bytes of `nop` padding added to `mos` (MOSSEG 0FFC6h -> 0FFDEh), a
  test program run with redirected output (`swa >out.txt`) never
  returned. The same program on the UPDATE 90 layout runs fine. The
  link still succeeds, and `MOS INFO` shows segment #2 ending at
  10F700h (below the end of the HMA), so the real limit is somewhere
  else. Not found yet. Added to `SHRINK-PLAN.md`.
- **Open bug: a hidden wait after 440Dh (or 69h) on a drive that does
  not exist, with redirected output.**
  - The call returns error 0Fh correctly.
  - With output redirected to a file, the program then stops before it
    exits, until a key is pressed.
  - Nothing shows on the screen. The CPU is in the kernel idle loop.
  - It also happens with plain 440Dh, so it was there before 69h was
    added.
  - It does not happen with output on the console, and not in a
    four-call test program (`z.c`). So something else from the sweep
    is also involved.
  - Reproducer: `sweep2 >out.txt` with the "6900 Z:" call (`swc`
    variant). Looks like a critical error (int 24h) prompt that goes
    nowhere. Needs its own session; `sweep2-pcmos.txt` is therefore
    the run without that one call.

## Regression (final kernel)

- sweep2: as listed;
- four-task `GO.BAT`: all rc 0, STEST churn/sort 0 bad, all DONE.

## Rig note

Old DOSBox processes from runs that had timed out kept running and
held the same `boot.img`. Several of the "random" failures this session
were caused by them. Check `pgrep -a dosbox` after a timeout. Do not
use `pkill -f`: that kills the shell.
