# UPDATE 78 -- a .COM client could get its PSP descriptor as DS (2026-10-07)

Files: `_386.ASM` only, on top of UPDATE 77. `u78/_386.ASM` is 77 + 78,
CRLF. `$386.SYS` 36,816 bytes, md5 `602a7598ad6f` (rebuilt twice, in
two containers, byte-identical). MASM 5.10, 0 severe errors. RES16
ends at 065A0h, RES32 at 07BBEh.

## Symptom

DPMI32 run after another DPMI client on the same boot: every text line
missing, all hex values right. Text goes out through protected-mode
int 21h ah=09h (host-translated, `einfun09`); hex digits through ah=02h.
**Present on UPDATE 74** -- not caused by 75-77.

## Cause (traced)

In `einfun09`, `lsl` on the client's DS (`006Bh`) gave limit `0FFh`;
the string was at `05E5h`. The copy loop is capped at the segment
limit, so it copied nothing and DOS printed an empty string. On a clean
run the same `lsl` gives `0FFFFh`.

DPMI32 is a .COM: its DS segment equals its PSP segment. Func 93
(`e6f93`, called by GoProtect before the switch) builds the PSP selector
with `e93sel`: access `F2h`, limit `0FFh`, tag `80h|id`. At the switch,
`makegdte` builds DS by scanning `dtitable` for an entry with the same
tag, access byte `F2h` and base, and returns a match unchanged (UPDATE
65). If the PSP entry's slot comes before the first free slot, DS **is**
the PSP descriptor. On a fresh boot the slot order avoids it; once a
client has exited and freed slots, it does not.

Any .COM DPMI client started after another client could get a 256-byte
DS this way.

## Fix

`e93sel`, after the limit is written:

```
	mov	byte ptr ss:[ebx+gdt+5],11110011b	; F3h: accessed bit set
```

The PSP and environment descriptors now carry access `F3h` (the CPU
sets the accessed bit on the first load anyway). `makegdte` matches
only `F2h`, so these entries are never handed out again as a client's
DS or SS.

Checked: no other code needs `F2h` on these entries. 0002h
(`e3102`) also requires a 64 KB limit, so it never matched them.

Encoding in the linked binary: `36 C6 83 A5 18 00 00 F3` at 74B8h,
right after the `gdt+6` write (gdt at 18A0h).

Not covered: `e93sel` itself still goes through `makegdte`, so if a
plain `F2h` entry with the same tag and base existed before func 93, it
would be reused and re-limited. Tags are freed at 4Ch, so that should
not occur, but this change does not rule it out.

## Tests (rig, `--testconfig`, normal core)

| test | result |
| --- | --- |
| DPMI32, fresh boot | all lines as UPDATE 74 |
| DPMI32, twice in a row | all lines, `#GP count:0000 bytes 1/2/3:A1A200A3` |
| Q300, then DPMI32 (the reproducer) | all lines, `32: done` |
| Q300 | `ax=0005` |
| Q900 | `0902:1 0900:1 0902:0 0901:0 0902:1`, `0300 ax=0005 0501:0 0502:0 ok` |
| DJMTEST | `11 MB in 1 MB blocks, 0 bad, one 10 MB block ok` |
| DJFTEST | `sum 1BE00000` |
| DJXTEST DJXTEST DJHELLO | three deep, all six returns rc 0 |
| four tasks, `u76/gdsep` | task 0 three deep rc 0; tasks 1-3 rc 0, MTEST 6-8 MB 0 bad; all DONE |

After Q300, DPMI32 reports `32e es base:00010000 psp:10000` instead of
`0000CAA0`. Explained below; not a host issue.

## Side finding: 13.6 KB less program space after the first big program

After the first DJGPP client exits, a block of 355h paragraphs at
`0CA9h`, owned by the shell's PSP (`0B06h`), stays allocated, and later
programs load at `1000h:0`.

A gdb watchpoint on that MCB's owner word logged five writes: EXEC's
split, EXEC's 48h (owner = shell), the hand-over to Q300's PSP
(`0CAAh`), the free at Q300's exit (owner 0), then a **new** 48h for
355h paragraphs while the shell is current. The block contains
`$$SHELL.SYS` from file offset 23D0h onward (checked at three points).

So nothing leaks: the shell's transient part sat in free memory at the
top, the DJGPP program overwrote it, and the shell reloads it into a
block it allocates at the lowest free address -- and keeps it. That is
shell behaviour, independent of DPMI. Worth a look later (a reload high,
as COMMAND.COM does, would keep the program space).

## DOS/4GW and DOS/32A (added later the same day)

Open Watcom (current snapshot) in the container; clients built as in
`tests/build.sh`; `DOS4GW.EXE` 1.97 and `DOS32A.EXE` 9.1.2 from its
`binw`. Same boot, in this order:

| test | DOS/4GW 1.97 | DOS/32A 9.1.2 |
| --- | --- | --- |
| hello | ok | ok |
| FTEST | `sum 1BE00000` | `sum 1BE00000` |
| MTEST | 11 MB, 0 bad | 12 MB, 0 bad |
| TTEST | 3021 ticks @ 1000/s | 3020 ticks @ 1000/s |
| nested (`w4xtest w4hello`, `dos32a waxtest dos32a wahello`) | rc 0, rc 0 | rc 0, rc 0 |

Then DPMI32 on the same boot: all lines, `32: done`.

All values match the UPDATE 74 references (TTEST 3020 vs 3021 is one
clock tick).

Two DOS/32A warnings, **identical on UPDATE 74** (same floppy, same
command):

- `9004: mouse initialization failed` -- no mouse driver in the
  testconfig.
- `9003: real mode interrupt vector has been modified: INT 22h` --
  after a nested EXEC. DOS/32A compares the real-mode vectors at exit
  with those at start; under PC-MOS a child's EXEC/terminate leaves
  INT 22h different. Harmless here (rc 0, clean exit); worth comparing
  with plain DOS + HDPMI32.

A DOS/32A child must be started as `dos32a wahello`: started bare, only
its stub runs (`This is a DOS/32 Advanced DOS Extender (LE-style)
executable`, rc 0).

## Not run here

The original `GO.BAT` (needs `W4STEST`, a four-task floppy with all
three extenders), the 19 kit images.
