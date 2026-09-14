# PC-MOS/386: Third-Party Copyrighted Material in the Tree

Not legal advice — I'm not a lawyer, and this is a factual inventory, not a
clearance opinion. But the evidence below is unambiguous: this tree bundles
a substantial amount of other companies' proprietary DOS-era software, none
of which is covered by the GPLv3 relicensing (the README is explicit that
the GPL only applies to "the PC-MOS/386/The Software Link inc/CDROM code,"
not helper files).

## Status: PKWARE batch removed

Update to what's below: the PKWARE set has actually been removed, and one
part of the original assessment in this doc was wrong — `PKZIP.EXE` and
`ZIP2EXE.EXE` were *not* dependency-free like the rest of that batch.
`SOURCES/src/MAKEALL.BAT` and `SOURCES/src/cdlink/PACKMOS.BAT` (plus the
duplicate `CDLINK/cdlink_src/` copies) call `pkzip`/`zip2exe` directly.
Neither is part of `build.sh`'s actual path, though — `MAKEMOS.BAT` doesn't
call either of them — so removal was done anyway, accepting that those two
packaging scripts (not the build itself) are now broken until someone
rewrites them for a native host `zip`, or they're retired.

Removed: `PKZIP.EXE`, `ZIP2EXE.EXE`, `PKZIPFIX.EXE`, `PKZ110.EXE`,
`PUTAV.EXE`, `BIN/LICENSE.DOC`, and — found during the same sweep, all
turned out to be PKWARE's own bundled documentation rather than PC-MOS's —
`ADDENDUM.DOC`, `README.DOC`, `MANUAL.DOC`, `ORDER.DOC`, `WHATSNEW.110`.

**Held back, different category:** `APPNOTE.TXT` is PKWARE's ZIP *file
format* specification, not tool documentation — a spec doc for an open,
widely-used format rather than proprietary software docs. Worth a separate
call rather than bundling it into the same removal.

**New, not yet audited:** the sweep for lingering references turned up
embedded strings inside three *other* binaries that reference pkzip/zip2exe
by name — `LIST.COM` ("Y/C PKZIP /C ARCA", likely archive-format
recognition in a file viewer), `AS.EXE` (its own PKZIP-availability check
text), `MAKESFX.COM` (embedded help text mentioning `ZIP2EXE`). These are
separate proprietary tools with their own undetermined ownership, not
something the PKWARE removal touches — add to the "check before deciding"
list below.

## What I checked

`BORLANDC/` and `BRIEF/` turned out to be non-issues on inspection — both
are just a `README.md` pointing at where to get the real package plus a
`FILESTRUCT.md` that's literally an `unzip -l` listing for reference. No
actual Borland C++ 3.1 or Brief 3.1 binaries are present. Nothing to remove
there — the concern was already handled by whoever set the tree up this way
originally.

`BIN/` and `LIB/` are a different story. Extracting embedded copyright
strings from the binaries (`strings <file> | grep -i copyright`) turns up
identifiable, non-PC-MOS ownership on a large fraction of them:

| File(s) | Confirmed owner (embedded string) |
|---|---|
| `MASM.EXE`, `LINK.EXE`, `CV.EXE`, `CVPACK.EXE`, `CL.EXE`, `C1.EXE`/`C2.EXE`/`C3.EXE`, `ILINK.EXE`, `LIB.EXE`, `EXEHDR.EXE`, `EXEMOD.EXE`, `EXEPACK.EXE`, `MAKE.EXE`, `EXE2BIN.EXE`, `DEBUG.COM`, `SMARTDRV.EXE`, `MOUSE.COM`, `UNDEL.EXE`, `MAIL.EXE`, `MSD.EXE` | **Microsoft Corp.** ("MS Run-Time Library — Copyright (c) 19xx, Microsoft Corp" / explicit Microsoft Corp copyright notices) |
| `NU.EXE`, `NCD.EXE` | **Peter Norton** (pre-Symantec-acquisition Norton Utilities) |
| `SPEEDISK.EXE` | **Symantec Corporation** (1991) |
| `NDD.EXE` | Norton Disk Doctor — no embedded copyright string found directly, but same Norton Utilities suite as `NU.EXE`/`NCD.EXE`; same category |
| `PKZIP.EXE`, `PKZIPFIX.EXE`, `PKZ110.EXE`, `PUTAV.EXE`, `ZIP2EXE.EXE` | **PKWARE, Inc.** — and `BIN/LICENSE.DOC` is literally PKWARE's own license document, which states plainly "It is the policy of PKWARE, Inc. not to release source code of its products" and restricts redistribution/repackaging to third parties without a paid distribution license |
| `ASM86.86`, `LINK86.86`, `LIB86.86` | **Intel Corp.** (1980) |
| `RCD.SYS` | **Iomega Corporation** (1985–1990) |
| `LIB/LLIBCE.LIB`, `SLIBCE.LIB`, `MLIBCE.LIB`, `CLIBCE.LIB`, and the associated `.OBJ` startup files | Microsoft C runtime libraries (companion to the MS compiler above) |
| `TS.COM` | **The Periscope Company, Inc.** ("TABLESIZE (TS) Version 5.31, Copyright 1986-1991... All rights reserved" — found while inventorying the live build; it's called from `KERNEL.MAK` itself, post-link, to trim the `.MAP` file's symbol table. Only touches the debug map, not the actual kernel binary, so skippable without affecting build correctness) |

`PUBLIC.COM` (also called from the live build, before every `masm`
invocation) turned out to be a non-issue on inspection — its own strings
say "Public domain utility - from the Periscope Company," explicitly, no
rights-reserved notice. No concern there, unlike its sibling `TS.COM`.

`TURBO.TPL` (Borland Turbo Pascal library) and the `MAILER`, `OMBUDSMN.ASP`
files I couldn't attribute from embedded strings — worth a closer look
rather than assuming either way.

`INCLUDE/` (standard C headers — `STDIO.H`, `STRING.H`, etc.) is likely
also Microsoft's own header set shipped with the compiler above, though I
didn't verify each file individually.

`IMAGES/`, `SHIPMOS/`, and `CDLINK/` are a different, cleaner category —
these are PC-MOS's own shipping disk/boot images and the CD-ROM driver
source explicitly credited to Rod Roark in the README, i.e. exactly the
material the GPLv3 relicensing agreement with Gary Robertson and Rod Roark
covers. No concern there.

## The complication: some of this is still load-bearing

`MASM.EXE`, `LINK.EXE`, `CL.EXE`/`C1.EXE`/`C2.EXE`, `ILINK.EXE`, `LIB.EXE`
are the toolchain the *current* DOSBox-driven build actually uses (`build.sh`
switched from dosemu2 to DOSBox; see
the Linux-native-build note). Pulling them now would break `build.sh` until
the UASM/Open Watcom migration is far enough along to not need them. The
Norton/PKWARE/Intel/Iomega tools, by contrast, aren't part of any build
path I found — they look like bundled DOS-session conveniences (disk
utilities, a zip tool, mail) rather than anything MOS's own build or
runtime depends on, so those can go without a sequencing concern.

## Recommendation

- **Remove now, no dependency concern:** the Norton/Symantec set
  (`NU.EXE`, `NCD.EXE`, `SPEEDISK.EXE`, `NDD.EXE`), Intel's
  `ASM86.86`/`LINK86.86`/`LIB86.86`, Iomega's `RCD.SYS`, and Microsoft's
  `UNDEL.EXE`/`MAIL.EXE`/`MSD.EXE`/`SMARTDRV.EXE`/`MOUSE.COM`. (The PKWARE
  set is done — see Status above.)
- **Remove once the toolchain migration lands, not before:** `MASM.EXE`,
  `LINK.EXE`, `CL.EXE`/`C1.EXE`/`C2.EXE`/`C3.EXE`, `ILINK.EXE`, `LIB.EXE`,
  `EXEHDR.EXE`, `EXEMOD.EXE`, `EXEPACK.EXE`, `MAKE.EXE`, `EXE2BIN.EXE`,
  `DEBUG.COM`, `CV.EXE`/`CVPACK.EXE`, the `LIB/` Microsoft runtime
  libraries/`.OBJ` files, and — new from the stage 1 inventory —
  `TS.COM`, which `KERNEL.MAK` genuinely calls post-link (removing it now
  would break `build.sh`, even though it only touches the debug `.MAP`
  file, not the kernel binary itself). These are exactly what the
  Linux-native-build note's UASM/Open Watcom plan is meant to replace.
- **Check before deciding:** `TURBO.TPL`, `MAILER`, `OMBUDSMN.ASP`,
  `INCLUDE/*.H`, and — new from the PKWARE-removal sweep — `LIST.COM`,
  `AS.EXE`, `MAKESFX.COM` (each references pkzip/zip2exe internally,
  ownership not yet checked) and `APPNOTE.TXT` (PKWARE's ZIP format spec,
  arguably a different category from tool docs/binaries).

I'd treat the "remove now" list as a genuinely small, self-contained
change (one clear category, no build dependency) and the "remove once
migrated" list as something to track and do as part of the toolchain work
itself, rather than as a separate change that temporarily breaks the
existing build.
