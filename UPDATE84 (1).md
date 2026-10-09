# UPDATE 84 -- kernel: EXEC's EXEPACK pad block is freed with the program (2026-10-08)

Files: `MOSFUN00.ASM` only (kernel, int 21h 4Bh). On top of
UPDATE 83. `$$MOS.SYS` 130,033 bytes, md5 `fd17ceb5cbb7`; built with
`kbuild.sh MOSFUN00`, MASM 0 warnings / 0 severe errors. Boot with the
UPDATE 82 `$386.SYS`.

## Problem

After the first big program on a fresh boot, 355h paragraphs (13.6 KB)
at `0CA9h`, owned by the shell's PSP, stayed allocated, and every later
program loaded at `1000h:0` (DPMI32: `es base:00010000` instead of
`0000CAA0`).

The earlier explanation -- a shell "transient part" reloaded low -- was
wrong. `$$SHELL.SYS` has no transient part: `MOSINIT` loads it once
into freemem (`scbcpseg`), and the shell never rereads it. The block
merely held stale bytes of the boot-time read of `$$SHELL.SYS` into low
memory (`MOSINIT2`, "load into low memory initially").

The real cause is EXEC's EXEPACK workaround (SAH 04/16/92, "allocated an
additional piece of memory so that EXEPACK programs will not conflict
with 1st 4k of memory"). For an EXE with no relocations and a non-zero
entry point whose load point is below 1000h, EXEC frees the PSP block,
allocates a pad of `0FFFh - pgmseg` paragraphs (`0FFFh - 0CAAh = 355h`),
then a new PSP block at 1000h. The pad is allocated while the **parent**
is current, so its owner is the parent (the shell). `setmcbs` hands the
environment and PSP blocks to the new program, but not the pad. At
termination DOS frees what the program owns, so the pad stayed for the
whole session. DJGPP stubs match the EXEPACK test, so the first DJGPP
program set it off. Later programs already load at 1000h, so it
happened only once.

## Change (`MOSFUN00.ASM`, EXEC)

The pad's segment is kept on the stack across the PSP allocation; once
the PSP block exists, the pad's MCB owner is set to the new PSP. The pad
is now freed with the program. A program that stays resident (31h)
keeps its pad, as it keeps its other blocks.

```
	call	sim21			; force enviroment to be bigger
	jc	f4berr1
	push	ax			; UPDATE 84: the pad block's segment
	...
	call	sim21			; the psp block
	pop	bx			; UPDATE 84 (flags kept)
	jc	f4berr1
	or	[rsflags],rs_pgm
	mov	[pgmseg],ax
	push	es			; UPDATE 84: pad owner = new psp
	dec	bx
	mov	es,bx
	mov	[mbowner],ax
	pop	es
```

The error path is unchanged: `pop` comes before `jc`, so `f4berr1`'s
`add sp,4` still matches.

## Tests (rig, `--testconfig`, UPDATE 82 `$386.SYS`)

Sequence: `Q300`, `DPMI32`, `Q300`, `DPMI32`, on a fresh boot.

| kernel | Q300 | DPMI32 after the 1st Q300 | after the 2nd |
| --- | --- | --- | --- |
| UPDATE 83 | ok | `es base:00010000 psp:10000` | `00010000` |
| UPDATE 84 | ok | **`es base:0000CAA0 psp:0CAA0`** | **`0000CAA0`** |

Regression, original `GO.BAT` (four tasks, dynamic core), UPDATE 84,
**6 runs, 6 clean**: T0 three deep, 6x rc 0; T1/T2/T3 2x rc 0 each,
STEST churn 0 bad, sort 0 bad; all four DONE in every run. No task-2
hang.

## Open items

- The single UPDATE 83 `GO.BAT` hang (task 2, W4STEST) did not recur:
  UPDATE 83 + 84 together now have 11 clean runs out of 12. Still not
  attributed; treated as rare until it shows up again.
- INT 22h after a nested EXEC (DOS/32A warning 9003): standard DOS
  behaviour, see `INT22-9003.md`.

## Files

- `MOSFUN00.ASM` -- the kernel module, CRLF.
