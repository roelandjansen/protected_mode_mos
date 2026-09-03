# PC-MOS/386: Stage 3 — First Byte-Diff Result (`MOSBACK.ASM`)

Stage 3 from the Linux-native-build note's staged plan, actually run — not
simulated. First candidate: `MOSBACK.ASM`, chosen per the stage 1
inventory's finding that it has no CPU-mode directives and no macros.

## Building a real reference, not a guess

Rather than assume what real MASM 5.10 would produce, I installed
`dosbox` (available via this sandbox's `apt`; not a statement about the
project's own SUSE-only policy, which governs the project's own scripts,
not incidental verification tooling here) and ran the tree's actual
`BIN/MASM.EXE` against `MOSBACK.ASM` under real DOS emulation, using
exactly `KERNEL.MAK`'s implicit rule (`public $<` / `masm $*;`).

Two real bugs surfaced and got fixed along the way, both worth knowing
for anyone repeating this:

- **DOSBox batch-chaining**: calling one `.bat` from another (or from the
  auto-generated autoexec) without `CALL` permanently transfers control
  and never returns — classic real MS-DOS behavior, faithfully emulated.
  Looked like a hang; was actually "the rest of autoexec never runs."
  Fix: use `CALL`.
- **Case sensitivity**: `KERNEL.MAK` lists `mosback.obj`'s dependencies
  as `options.inc`/`group.inc`, but `MOSBACK.ASM` actually only
  `include`s `page.inc`/`group.inc` (lowercase) — and DOS's case-
  insensitive filesystem meant this always silently worked against the
  uppercase `PAGE.INC`/`GROUP.INC` files on disk. This is a real,
  general porting hazard: **every lowercase `include` statement in this
  codebase is implicitly relying on case-insensitive file lookup**, and
  will need matching-case files (or a case-insensitive mount/overlay) once
  building natively on Linux for real.

With the right files in place, real MASM 5.10 assembled clean:

```
Microsoft (R) Macro Assembler Version 5.10
Copyright (C) Microsoft Corp 1981, 1988.  All rights reserved.

0 Warning Errors
0 Severe Errors
```

Producing a genuine reference `MOSBACK.OBJ` (392 bytes).

## UASM side

Same source, same two includes (renamed to the lowercase the source
actually asks for), assembled with the toolchain `ci_prereq.sh` sets up:
0 warnings, 0 errors, 397-byte `.OBJ`.

## Comparing them properly

Not byte-identical (392 vs. 397 bytes) — expected, translator-identity
metadata differs between assemblers regardless of correctness. What
matters is whether the actual segment/data content agrees. Wrote a small
C tool for this rather than reach for a scripting language: `tools/
omfdump.c` (builds with plain `gcc`, no dependencies) walks OMF records
and can dump `LEDATA` payloads specifically.

**Structurally identical:** `THEADR`, `LNAMES`, and all 8 `SEGDEF`
records match exactly — type, offset, and length, in both files.
`EXTDEF` and `COMENT` match too.

**Reordered, not different:** `GRPDEF` (4 records) and `PUBDEF` (6
records) contain the same sets of entries in both files, just in a
different declaration order. Checked whether this could matter: it only
would if something references a group or symbol by declaration index
rather than by name (an OMF `FIXUPP` record can do this) — and this
particular file has **no `FIXUPP` record at all**, so there's nothing
here for the reordering to affect. Worth re-checking on a file that
actually has fixups.

**The real question — `LEDATA` (actual code/data bytes):** MASM emitted
3 records (29 bytes); UASM emitted 4 (31 bytes). Dumped the raw payloads
of both to settle it:

```
MASM  seg=2 off=0x0000: ff ff 00 00 00 00 00 00 00 00   (10 bytes, one record)
UASM  seg=2 off=0x0000: ff ff                             (2 bytes)
UASM  seg=2 off=0x0004: 00 00 00 00 00 00                 (6 bytes)
```

UASM left a 2-byte gap (offset 2–3) instead of writing it explicitly.
That gap lines up exactly with the source's `dw ?` — an *uninitialized*
word, the second field declared in the `irq` segment (`dw 0ffffh` / `dw
?` / `dw 0` / `dw 0` / `dw 0`). MASM writes explicit zero bytes for
uninitialized data sitting between defined data; UASM instead splits the
`LEDATA` record around it and relies on the standard OMF/loader
convention that gaps default to zero. **Filled in, both reconstruct to
the identical 10 bytes.** Segments 3 and 7's data are byte-for-byte
identical outright, no gaps involved.

## Verdict

**UASM produces semantically correct output for `MOSBACK.ASM`.** Not
byte-identical, but every actual difference traces to a legitimate,
equally-valid encoding choice (`?` data handling, declaration ordering
with no fixups depending on it) rather than a real discrepancy.

## What to check on the next file

This file happened to have zero `FIXUPP` records, so the `GRPDEF`/
`PUBDEF` reordering never got exercised for real. The next candidate from
the stage 1 shortlist — `MOSHEMAN.ASM` or `MOSDEBUG.ASM` — should be
picked with an eye toward finding one that *does* have fixups, so the
harness actually tests whether index-based group/symbol references
survive UASM's different declaration ordering. That's the one open
question this first pass couldn't answer.

`tools/omfdump.c` is reusable as-is for every subsequent module in this
harness — `omfdump -d file.obj` for the full picture, plain `omfdump
file.obj` for just the record-type/length skeleton when that's enough.
