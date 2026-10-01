## UPDATE 68 (2026-10-01) — multiuser: DPMI clients in several tasks

DPMI clients run in two PC-MOS tasks at the same time, nested and under
heavy load. One fix to UPDATE 67's nesting code. `_386.ASM` only.

### Test method: a second task

`ADDTASK.COM` (built from the tree: `make -f MAKEUTIL.MAK ADDTASK.COM`,
2743 bytes). `ADDTASK 500,1,,T1.BAT` starts task 1 with 500 KB, running
`T1.BAT`; it writes its results to `T1.TXT`, read from the floppy image
while the emulator runs (`mtype -i IMG ::T1.TXT`, read only). Task 0
runs programs at the console as usual. Example `T1.BAT`:

	DJXTEST DJHELLO > T1.TXT
	W4XTEST W4HELLO >> T1.TXT
	DOS32A WAXTEST DJHELLO >> T1.TXT
	ECHO T1 DONE >> T1.TXT

### Found

Single clients in task 1 worked; nesting in task 1 hung on the SECOND
child start: the parent looped on a fault at `008B:00000007` (the
monitor in `e31xflp`, the exception-handler lookup, every sample) and
starved task 0.

The per-client tables in that state: `curcid[1]=1`, `cidtask[1]=2`,
`parcid[2]=1` -- all right -- but **`pendsw[1]=2`, stale**: the first
child's "switch pending" mark was never consumed. `cidtagsw` (UPDATE
67, in `nmswitch` after `cleardti`) read the task id through esi --
and `cleardti` changes esi. In task 0 the garbage read happened to give
0 and it worked by accident; in task 1 the child's initial selectors
kept the plain task tag, the child's `cleardti` freed the parent's too,
and the second child's switch reused them under the running parent.

**Fix:** `cidtagsw` takes the task id from dh (`mov al,dh`), which
`nmswitch` loads right before `cleardti` (cleardti uses it).

### Measured

| test | result |
| --- | --- |
| task 1 alone: DJHELLO x2, W4HELLO, DOS32A WAHELLO | all correct |
| task 1: DJGPP->DJGPP, DOS/4GW->DOS/4GW, DOS/32A->DJGPP | every child rc 0, twice |
| at once: task 0 DJGPP->DOS/4GW->DJGPP, task 1 the three pairs | every child rc 0; both finish |
| at once: task 0 `DOS32A WASTEST` + `DJSTEST`, task 1 `DJSTEST` + `W4STEST` | all four churn 0 bad, sort 0 bad |

Regression on this build: DPMI32 kit 19/19, values identical to UPDATE
67. FTEST (`1BE00000`), TTEST (275 @ 91/s; 3021 @ 1000/s), KTEST, MTEST
(11/11/12 MB) on DJGPP, DOS/4GW and DOS/32A; SET ok.

### Build

`$386.SYS` 52496 (unchanged), 0 warnings.

| file | md5 |
| --- | --- |
| `_386.ASM` | `d3aeb172e774b16f1836d729453a32f3` |
| `$386.SYS` (52496) | `767358ae9e6f96db1adf79d0c47f4add` |

### Lessons

- A value read through a register a called routine is free to change
  works only by accident: in task 0 the wrong id was the right one.
  Test in a task other than 0.
- Dump the state tables of a hung system before theorising (a stale
  `pendsw` named the bug; the "stuck TF / vector 1" idea did not survive
  one look at the stub selectors).
- Rig, after a container restart: a stale `/tmp/.X99-lock` blocks Xvfb
  -- remove it. `pkill -f PATTERN` kills your own shell when the pattern
  is in the command line: stop background runs by PID. Never run a
  second emulator while a background test runs: screen reads hit the
  wrong one (three false empty kit results here, all fine rerun alone).

### Next

- `e31xfind` scans all 1024 hook entries on every exception: fine, but
  a per-client index would make a fault-heavy client cheaper.
- Per-call cost of int 31h in the native dispatch (~25-30x HDPMI32).
- More tasks at once (3-4), and terminals other than the console.
