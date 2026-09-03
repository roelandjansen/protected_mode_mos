# PC-MOS/386: Stage 1 Inventory — What `build.sh` Actually Builds

Stage 1 from the Linux-native-build note's staged plan, done properly.
Correction up front: that note estimated "29 `.MAK`/`.BAT` files" to
inventory. The real count is **51**, but that's the wrong number to worry
about — walking `MAKEMOS.BAT` line by line shows `build.sh` only ever
exercises **three** of them. Everything else (`kernel/`, `jim/`,
`mos501src/`, `mos5src/`, `acu/`, `vna/`, `vgna/`, `unterm/`, `cutils/`,
`ulib/`, `export/`, the packaging scripts) is historical source snapshots
or dead/commented-out paths.

## The three live files

`MAKEMOS.BAT` does, in order: `cd latest`, build the kernel via
`kernel.mak $$mos.sys`, then — critically — the next line is
`rem cd mos5src`, **commented out**, so control never actually leaves
`latest/`. The following `make -f makeutil.mak all` therefore runs
`latest/MAKEUTIL.MAK`, not `mos5src/MAKEUTIL.MAK`. Then `cd import`,
`import.mak import.exe`. The `export/` step after that is also fully
commented out — dead.

So the live set is exactly: **`latest/KERNEL.MAK`**,
**`latest/MAKEUTIL.MAK`**, **`import/IMPORT.MAK`**.

## `import/IMPORT.MAK` (34 lines, simplest)

Plain implicit rules, no surprises: `.c.obj: loadfix cl -c $<` and
`.asm.obj: masm -Mx $*;` (`-Mx`: MASM's case-sensitivity switch, worth
confirming UASM's `-Mx`/equivalent). Builds `import.exe` from 7 objects,
linked with `link $(OBJLIST)/e,,,rsasmall` against the `rsasmall` runtime
library.

## `latest/KERNEL.MAK` (238 lines) — the kernel itself

Implicit rule for every module: `public $<` / `masm $*;` / `del $*.pub` —
`public` runs before every assemble, not just at the end. 43 objects in
`OBJECTS`, 38 of them (`$(COMMON)`) plus `mosfront`, `mosinit2`, `mosback`
get linked into the real target:

```
link mosfront +$(COMMON) +mosinit2 +mosback/m/se:512, $$$$mos.sys;
debug $$$$mos.sys <exe2bin.dat
ts $$$$mos.map/s
```

That's the DEBUG-script raw-image conversion covered in the
Linux-native-build note, followed by a tool we hadn't catalogued yet:
**`TS.COM`** (`ts $$$$mos.map/s`). Traced it — "TABLESIZE (TS) Version
5.31," Copyright 1986–1991 **The Periscope Company, Inc., all rights
reserved** (added to the copyright audit). It only trims/filters the
`.MAP` file's symbol table *after* the real kernel image already exists —
not required for a working `$$mos.sys`, only for a smaller/filtered debug
map. Safe to skip entirely in a native build if nobody needs that map.

The other new tool, **`PUBLIC.COM`**, is explicitly self-labeled "Public
domain utility - from the Periscope Company" in its own strings — no
licensing concern there at all.

One more thing worth knowing: the `$$$$eval.sys` (evaluation build)
target in this same file uses `masm mosinit2,$*/DRELCODE=YES;` — the one
`/D`-switch variant we noted early on — but `MAKEMOS.BAT` builds that
target only in a commented-out block ("this was for internal R&D use
only"). Not live. The real `$$$$mos.sys` target's `mosinit2.obj` uses the
plain generic rule, no `DRELCODE`.

## `latest/MAKEUTIL.MAK` (484 lines) — the utility programs

Four implicit rules (`.asm.com`, `.asm.sys`, `.asm.obj`, `.asm.exe`), all
the same shape: `public` → `masm` → `link` → **`exe2bin`** → cleanup.
Unlike `KERNEL.MAK`'s main target, this file uses the standard
`EXE2BIN.EXE` utility throughout, not the bespoke `DEBUG`-script
conversion — so `EXE2BIN.EXE` is genuinely load-bearing here (already
flagged as "remove once migration lands" in the copyright audit; this
confirms exactly where it's used).

~70 targets in `ALL`, mostly plain with no special-case recipe — the
implicit rules cover them. A few have their own explicit recipe instead
(`alias.com`, `debug.com`, `print.com`, `remtask.com`, the 16 `_kbXX.sys`
keyboard-layout drivers, `_serial.sys`, `_arnet.sys`, `__shell.sys` and
its 4 `moxcpXX.obj` pieces) — none use unusual switches beyond the same
`masm`/`link`/`exe2bin` pattern, though a few do a `copy foo.def
_foo.def` rename trick first (MASM/filename-convention workarounds, not
exotic tooling).

The C utilities: `compfile.exe` and `helpgen.exe` both build small-model
(`link .../e,,,rsasmall`, matching `import.mak`'s pattern); `ed.exe`
builds large-model (`cl -c -AL`, `link ed,,,rsalarge`) — matches the
file's own revision comment ("ED.EXE now builds in LARGE model").

Two things checked and confirmed **not** part of this live path, despite
initially looking like they might be:

- `help.exe`'s recipe uses `tpc` (Turbo Pascal Compiler) — but `help.exe`
  isn't actually listed in the `ALL` target (only `helpgen.exe`, the C
  version, is). Dead code, consistent with `BORLANDC/` being a doc stub
  with no real binaries.
- `hdsetup.com`'s rule is present but semicolon-commented-out here — the
  file examined earlier for the 32MB partition-size finding is actually
  built by the separate, non-live `cutils/HDSETUP.MAK`.

## Dialect/directive scan, scoped to exactly what's live

Pulled the precise list of `.asm` files these three makefiles actually
reference — 113 files — and scanned only those (not the other ~130 files
sitting unused in `latest/`).

**CPU-mode directives (`.286`/`.286c`/`.386`/`.386p`/`.387`):** used in
only **4 of the 113 files** — `_386.ASM` (all four: `.286`, `.286c`,
`.386`, `.386p` — matches it being the V86/paging supervisor, the most
demanding file by far), `_286N.ASM`, `_ARNET.ASM`, `_EMS.ASM`,
`DEBUG.ASM`. The other 109 files use no explicit CPU-mode directive at
all — plain default-8086 code. That's the great majority of the live
kernel.

**Macros:** light and localized — `IRP`/`IRPC`/`REPT`/`REPEAT` appears in
exactly one file (`_SERIAL.ASM`); `MACRO` definitions appear in four
(`SEARCH.ASM`, `DIRMAP.ASM`, `MORE.ASM`, `PRINT.ASM`). `MACROS.INC`,
despite its name and being `#include`d almost everywhere, contains zero
`MACRO` definitions and no dialect directives — it's just shared
EQU/structure definitions.

## What this means for stage 3 (the byte-diff harness)

The dialect-coverage worry from the original note turns out to be
concentrated in a small, already-known cluster (`_386.ASM` and its four
siblings) rather than spread across the kernel. That suggests the byte-
diff harness should deliberately start with something *outside* that
cluster — a small, plain, no-directive, no-macro file from the 109-file
majority — to validate UASM's baseline OMF/segment-layout fidelity
first, cheaply, before spending effort on the genuinely harder `_386.ASM`
case. Good small-first candidates from `KERNEL.MAK`'s object list:
`MOSBACK.ASM`, `MOSHEMAN.ASM`, or `MOSDEBUG.ASM` — all small, no special
recipe, no CPU-mode directive, no macros.
