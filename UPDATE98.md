# UPDATE 98 -- diskette driver init moved to the init segment (20261011)

Files: `MOSDDBLK.ASM` (kernel), CRLF.

- `$$MOS.SYS` 131,153 bytes, md5 `ade1989decbe` (UPDATE 84-97 + this),
  `TREE=/home/claude/scr kbuild.sh MOSDDBLK`.
- MASM 0 warnings / 0 severe errors.

## Change

`finitblk`, `isdrive` and `maxparm` (diskette driver init: drive
count and types, A:/B: on one drive, the diskette parameter tables)
only run at boot. They now live in `initseg`, the same way as the hard
disk init in UPDATE 93:

- `ffuntbl` entry 0 -> `finitstub` in `mos`: a far call through
  `initcall`, with `sinit:imosaddr` set to `finitblk`;
- `mosheman` through `cfmos`/`camos`;
- the driver end address is taken from `initmos`;
- all data stays in `gdata` (the tables were already there).

| | UPDATE 97 | UPDATE 98 |
| --- | --- | --- |
| MOSSEG | 0FBDEh | **0FA6Eh** (368 bytes more room: 1,426 bytes free) |
| resident `mos` (`CLOBBER`) | 0F372h | **0F202h** (368 bytes less HMA) |
| `mo2` (DDT end) | 0CC89h | 0CC89h |

## Other candidates checked, not moved

The remaining `*init*` routines in `mos` are small or also used at run
time:

- `vinit`/`initvect` (video and vectors, per task);
- `initlpt`/`initcom`/`initspl` (per-task device setup, 30-160 bytes
  each);
- `initmcb`/`initstation`.

Moving them gains little for the risk. Init code after `CLOBBER`
(`mosinit` ...) already costs nothing in the HMA, but it counts
against the 64 KB of MOSSEG.

## Tests

| test | result |
| --- | --- |
| boot from the diskette, A: reads and writes | ok |
| four-task `GO.BAT` (diskette heavy) | all rc 0, STEST churn/sort 0 bad, all DONE |
| 20 GB disk, logical drives at 8.2/8.7 GB: `TYPE D:`, `TYPE E:` | correct |
| `ADDTASK 900` (test config) | "Maximum task size now: 596K", as before |
