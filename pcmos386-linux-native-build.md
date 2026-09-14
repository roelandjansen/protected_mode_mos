# PC-MOS/386: Building Natively on Linux (openSUSE Tumbleweed)

Goal: be able to build (now or later) without needing a DOS emulator and a
set of 1990s DOS binaries as the toolchain, using tooling actively maintained
in 2026, running directly on Tumbleweed.

This is a build-time goal, separate from running/testing the OS — see
section 4.

## 1. What the build actually does today

`build.sh` requires **DOSBox** (`check_dosbox_installed`) and drives the
original DOS-era toolchain inside it: it writes a throwaway DOSBox config
that mounts the repo as `C:`, then `CALL`s `MAKEMOS.BAT` and quits.

```
dosbox -conf "$CONF_FILE"      # autoexec: mount c <repo> / call MAKEMOS.BAT
```

This replaced an earlier `dosemu2`-based invocation
(`dosemu -td -ks -K .:SOURCES\src -E MAKEMOS.BAT ...`); the switch was made
because dosemu2's current command-line handling no longer supports what this
build needs on a current install, and DOSBox does. Note DOSBox exits 0
regardless of whether the build succeeded, so `build.sh` checks for
`$$MOS.SYS` afterwards rather than trusting the exit status.

Practical note from the protected-mode work: individual components can be
rebuilt without a full `MAKEMOS.BAT` run by driving the `.ASM.SYS` inference
rule from `MAKEUTIL.MAK` directly under DOSBox — `public` / `masm` / `link` /
`exe2bin`. Much faster to iterate on a single driver.

`MAKEMOS.BAT` (in `SOURCES/src`) orchestrates the whole build, `cd`-ing into
each subdirectory and invoking an `.MAK` file with DOS `MAKE.EXE`
(Microsoft's, from `BIN/MAKE.EXE`). Two separate DOS-era toolchains are in
play, split by directory:

- **Microsoft toolchain** (`BIN/MASM.EXE`, `LINK.EXE`, `CL.EXE`/`C1.EXE`/
  `C2.EXE`, `ILINK.EXE`, `LIB.EXE`) — used by the kernel (`latest/KERNEL.MAK`,
  `mos5src/KERNEL.MAK`, `kernel/KERNEL.MAK`) and most `.MAK` files
  (`MAKEUTIL.MAK`, `MAKETERM.MAK`, `EXPORT.MAK`, `ASMCDMOS.BAT`, etc.) — 22 of
  the 29 `.MAK`/`.BAT` files in the tree.
- **Borland toolchain** (`bcc`/`tcc`/`tlink`, from the — not fully included —
  Borland C++ 3.1 package referenced in `BORLANDC/README.md`) — used only by
  a handful of C utility builds: `ulib/ULIB.MAK`, `cutils/EXPORT.MAK`,
  `CUTILS.MAK`, `INSTALL.MAK`, `HDSETUP.MAK`.

Assembly invocation is plain and MASM-syntax: `masm $*;` (implicit-prompt
form), with one conditional-assembly variant, `masm mosinit2,$*/DRELCODE=YES;`
(MASM's inline `/D` symbol-definition switch). C invocation uses classic
memory-model switches, e.g. `loadfix cl -c -AL ed.c` (`-AL` = large model;
`loadfix` is a DOS TSR-loading workaround, irrelevant once off real DOS).

The kernel's final link step is unusual and worth calling out on its own,
since it's the hardest single piece to replicate outside DOS:

```
link mosfront +$(COMMON) +mosinit2 +mosback/m/se:512, $$$$mos.sys;
debug $$$$mos.sys <exe2bin.dat
ts $$$$mos.map/s
```

`LINK.EXE` produces a normal MZ-format `.EXE`. It is then **not** converted
with `EXE2BIN.EXE` (which is present in `BIN/` but unused here) — instead
`DEBUG.COM` is driven interactively via a scripted stdin file, `EXE2BIN.DAT`:

```
r sp
200
a 100
sub cx,300
sbb bx,0
int 3

g
w 400
q
```

Read literally: DEBUG loads the linked EXE (relocating it, setting CS:IP
and BX:CX from the MZ header), sets SP=0x200, assembles a 3-instruction
patch at offset 0x100 (`sub cx,300h` / `sbb bx,0` — a 32-bit subtraction of
0x300 from BX:CX — followed by `int 3`), then `g` runs the loaded image
until that breakpoint is hit, then `w 400` writes memory starting at offset
0x400 back to the same file, using the just-corrected BX:CX as the byte
count. Net effect: it's a hand-rolled, register-corrected equivalent of
`EXE2BIN` — strip the MZ header/relocation table, adjust the reported size
by a fixed 0x300-byte correction, and emit a raw binary image in place of
the EXE. The 0x300 constant and the 0x400 write offset are specific to how
this particular header/prologue is laid out; they are not generic EXE2BIN
behaviour.

## 2. Toolchain replacement candidates (Linux-native, actively maintained)

| DOS tool | Role | Linux-native, 2026-current replacement |
|---|---|---|
| `MASM.EXE` | assembler (bulk of codebase) | **UASM** (github.com/Terraspace/UASM) — MASM-compatible fork of JWasm, native OMF output, native Linux binaries, still receiving releases (v2.58 mid-2026). Packaged for Gentoo/Arch/Slackware; not in Tumbleweed's default repos as far as I found, but it's a single GCC makefile (`gccLinux64.mak`) — straightforward to build or wrap in an OBS package. |
| `LINK.EXE`/`ILINK.EXE` | OMF linker | **Open Watcom v2's `wlink`** — OMF-aware, targets DOS output, builds and runs natively on Linux x86-64 (uses GCC as host compiler for OW itself). No official openSUSE package found; build from the `open-watcom-v2` GitHub source tree. |
| `LIB.EXE`/`TLIB.EXE` | librarian | Open Watcom's `wlib`, same source tree as `wlink`. |
| `CL.EXE`/`C1.EXE`/`C2.EXE` (MS C) and `bcc`/`tcc` (Borland) | C compiler for the handful of `.C` files (`COMPFILE.C`, `ED.C`, kernel utils, `ulib`/`cutils`) | **Open Watcom's `wcc`** — real-mode DOS target, OMF objects link-compatible with `wlink`, one toolchain instead of two. Lower risk than the ASM port simply because there are far fewer `.C` files than `.ASM` files in the tree. |
| `DEBUG.COM` scripted EXE→raw conversion | final kernel image step | No off-the-shelf equivalent — this needs a small purpose-built tool (see §3.4). |

This converges on a **two-project toolchain** (UASM + Open Watcom) instead
of today's three (MS tools + Borland tools + DEBUG.COM scripting), which is
also a simplification worth having independent of the Linux-native goal.

## 3. Pitfalls, in descending order of how much they worry me

### 3.1 Fixed absolute segment addresses baked into the source
`_DPMI.ASM` declares `dseg segment at 0aceh` and `scbs segment at 0beach` —
i.e. parts of the kernel assume specific segments land at specific
addresses, presumably because other already-built pieces (or the loader)
reference them directly. Any assembler swap has to reproduce not just
"correct" code but the **same segment/group ordering and combine behaviour**
MASM used, or these `at`-addressed segments (and anything that reads them
from outside, e.g. `MOSDUMP.EXE`/`PMAP.EXE`) will silently break. This is the
main reason a byte-for-byte diff against a real-MASM build (§3.5)
has to be the acceptance test, not "it assembles without errors."

### 3.2 Assembler dialect coverage
The source uses `.286`, `.286c`, `.386`, `.386p`, `.287` mode directives,
raw hand-encoded opcode bytes for privileged instructions in at least one
place (`_386.ASM` encodes `lgdt`/`lidt` as `db 0fh,01h,...` rather than using
mnemonics — likely a limitation of the MASM version originally used, since
modern assemblers, UASM included, support `lgdt`/`lidt` as real mnemonics).
UASM's directive support needs to be spot-checked against this specific set
before trusting it on the real tree — `.286c` in particular is a less common
directive worth confirming explicitly rather than assuming.

### 3.3 Two toolchains, one migration
`ulib`/`cutils` use Borland's `bcc`/`tcc`/`tlink`, everything else uses MS
tools. A full native-Linux port has to decide whether to move both to Open
Watcom in one pass, or migrate the larger MS-toolchain portion first and
leave `ulib`/`cutils` on the DOSBox/MASM path for a while as a staged
approach. The
latter is lower-risk and still gets most of the benefit (the kernel itself
being the part actually being extended per the protected-mode work).

### 3.4 The `DEBUG.COM` script has no native equivalent
As detailed in §1, this step is a bespoke register-corrected EXE-to-raw
conversion, not a generic `EXE2BIN` call. It cannot be replaced by "run
`exe2bin` on Linux" — the 0x300 size correction and 0x400 write offset need
to be understood precisely (most likely: MZ header size in this particular
link configuration, plus whatever `mosfront`'s own prologue expects) and
then reimplemented as a small standalone tool. This is a natural fit for a
small C utility (per your usual toolchain — no perl/python) that parses the
MZ header emitted by `wlink`, applies the equivalent correction, and writes
the raw `.SYS` image — but it needs the exact semantics nailed down first,
ideally by tracing what `mosfront`'s startup code actually expects at
offset 0x400, before writing it.

### 3.5 Validation strategy — this is the part I'd insist on
Because of §3.1 and §3.4, "it builds" is not sufficient evidence of
correctness. The only trustworthy check is: build the same module both ways
(existing DOSBox + MASM/LINK, and the new UASM/Open Watcom path) and diff
the resulting `.OBJ`/binary output. Do this on one small, self-contained
module first — not the whole kernel — to shake out assembler-dialect and
object-format mismatches cheaply, before attempting a full kernel build on
the new toolchain.

## 4. Building vs. running — keep these separate

Porting the *build* off the DOS toolchain does not remove the need for an
emulator (
DOSBox, or another period-appropriate emulator) to actually **boot and test** the
resulting OS — `run.sh` and the DOS-386 runtime environment are a separate
concern from what compiles the sources. `ci_prereq.sh` installing the emulator
via `apt`/`sudo` is about the CI *test* environment and doesn't need to
change just because the build toolchain does.

## 5. Suggested staged plan

1. **Inventory** — walk all 29 `.MAK`/`.BAT` files and note exact
   tool+switches per module (this note only sampled `KERNEL.MAK` and
   `MAKEUTIL.MAK`); confirm which directives/macros are actually used
   across the full `.ASM`/`.INC` set so UASM's dialect coverage can be
   checked against the real requirement list, not assumptions.
2. **Stand up UASM + Open Watcom on Tumbleweed** — build both from source
   (neither has an official openSUSE package as far as I found); a local
   OBS package would make this repeatable.
3. **Single-module byte-diff harness** — pick one small, dependency-light
   `.ASM` file, assemble it both ways, diff the `.OBJ`. Automate this as a
   standing regression check before going further.
4. **Port module by module** — working through `KERNEL.MAK`'s object list,
   watching specifically for the `at`-addressed segments (§3.1).
5. **Replace the link + raw-image step** — `wlink` for linking, then the
   purpose-built C tool from §3.4 once its exact semantics are confirmed
   against what `mosfront` expects.
6. **Full clean build with no DOS-emulator involvement**, verified against a
   DOSBox+MASM-built reference `$$MOS.SYS` for the final acceptance check.
