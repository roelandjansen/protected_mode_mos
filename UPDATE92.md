# UPDATE 92 -- the "mos is full" hang was a media-change bug; 2F1A00h (20261010)

Files: `MOSDDBLK.ASM`, `MOSTEMP.ASM` (kernel), CRLF.

- `$$MOS.SYS` 130,673 bytes, md5 `a51127e1f176` (UPDATE 84-91 + this),
  `TREE=/home/claude/scr kbuild.sh MOSDDBLK MOSTEMP`.
- MASM 0 warnings / 0 severe errors.
- `mo2` unchanged, so the per-task memory is unchanged.

## What the hang really was

UPDATE 91 had two open problems:

1. growing `mos` by 18+ bytes hung `swa >outa.txt`;
2. `sweep2 >out.txt` with a 440Dh/69h call hung, with a silent wait
   for a key.

Both are the same kernel bug. The size of `mos` has nothing to do with
it.

**The chain of events:**

1. The kernel is loaded at 0080:0000 and copied twice during init.
   The low copies stay in memory that later becomes program memory.
2. The Watcom C runtime reads uninitialised heap memory (in the
   `stdout` buffer area) when it decides whether to call int 21h
   6801h (commit) after a write. So moving or changing **any** byte at
   physical 18C6Eh (here: `shfttbl` entry 71h of the stale kernel
   copy) decides whether the test program commits its redirected
   output or not. Proved by zeroing that word at run time on an
   unchanged kernel: the hang appears.
3. Without the commit, `OUTA.TXT` has dirty, unwritten buffers when
   the program calls **440Dh 0860h (get device parameters)**.
4. `fgenioctl` (`MOSDDBLK.ASM`) set `dirtybpb` for **every** generic
   IOCTL, including the reading ones. So the next access to A:
   decided "media changed", re-read the boot sector, and failed with
   int 24h, error 0Ch (general failure) on drive A:. The test program
   inherited the shell's int 24h handler, whose prompt was not
   visible. The task waited for A/R/I/F; pressing `I` released it.

How it was found:

- int 13h logging: identical up to a missing FAT write, then a boot
  sector read;
- gdb read watchpoints on the stale copy;
- a `CPU_Interrupt` breakpoint showing INT 24h with AH=18h, DI=000Ch,
  BP:SI = the A: driver header;
- an int 21h trace: the good run has `6801h` after each write, the bad
  run does not.

## Fix

`fgenioctl`: the reading subfunctions no longer mark the BPB dirty:

- get device parameters (60h);
- read track (61h);
- verify track (62h);
- get media id (66h).

The setting and formatting ones still do: set device parameters (40h),
write track (41h), format/verify track (42h), set media id (46h). Same
instructions, in a different order: no size change. This is what
MS-DOS does: a get-parameters call does not count as a disk change.

With it, any program that asks for drive parameters (disk tools,
FreeDOS utilities, `sweep2`) while it has unwritten files open no
longer gets a "general failure".

## 2F1A00h (ANSI.SYS installed?)

`mosint2f` now returns AL=FFh when the current task's console has ANSI
on (`tcbansi` = FFh), and 00h after `MOS ANSI OFF` (24 bytes in
`mos`). Programs that check for ANSI.SYS before using escape
sequences now use them.

## Space in mos (corrects UPDATE 91 and SHRINK-PLAN)

`mos` is **not** full. Only 1080h-`CLOBBER` (0F75Ah, 0F772h with this
update) is resident; the rest up to `MOSEND` is init code. The
resident part ends at 10F700h (linear), so about **2.3 KB** are left
below the end of the HMA (10FFF0h). With this update about 2.2 KB
remain.

## Tests (final kernel)

| test | result |
| --- | --- |
| `swa`, `swc`, `sweep2` redirected to A:, one after the other | all complete (57/58/59 lines) |
| good kernel with the stale word zeroed at run time (the old trigger) | completes, no int 24h, ends with 4Ch |
| `sweep2` 2F1A00h | FFh; 00h after `MOS ANSI OFF` |
| 6902h, 6900h on Z: | error 1, error 0Fh |
| four-task `GO.BAT` | all rc 0, STEST churn/sort 0 bad, all DONE |

## Note for test programs

Watcom's runtime decides from uninitialised memory whether to commit
after a write. Test results that depend on that (disk timing, media
checks) can change from one kernel layout to the next. The kernel now
behaves the same either way.
