# PC-MOS/386 debug rig

A headless test rig around a debug build of DOSBox Staging 0.82.2, with an
emulator-side tracer. Private tooling — not part of the project tree.

## Restore in a fresh session

    tar xzf pmrig-toolkit.tar.gz
    cd pmrig-toolkit
    ./restore.sh

This installs the rig into `/home/claude/rig` and the emulator into
`/home/claude/dosbox-staging/build-dbg/dosbox`. It uses the prebuilt binary
if its libraries resolve, otherwise it clones upstream `v0.82.2`, applies
`dosbox-pmtrace.patch` and rebuilds (meson, `--buildtype=debug
-Denable_debugger=heavy`). No sudo.

Then unpack the PC-MOS tree to `/home/claude/pm` (the rig's default `TREE`).

## Contents

| file | what |
| --- | --- |
| `dosbox.gz` | prebuilt debug DOSBox Staging 0.82.2 with the pmtrace patch (x86-64 Linux, Ubuntu 24.04 libraries) |
| `dosbox-pmtrace.patch` | the patch against upstream `v0.82.2` |
| `restore.sh` | installs the rig, uses or rebuilds the emulator |
| `rig/` | the scripts below |

## Scripts

| script | use |
| --- | --- |
| `rig.sh start [--testconfig] [--bootdir DIR] [--configsys F] [--add F]` | build a boot floppy and start the emulator headless |
| `rig.sh screen` / `cpu` / `mem ADDR LEN` / `ivt N` | read the text screen, registers, guest memory, IVT entry |
| `rig.sh type TEXT` / `key KEY` | send keystrokes |
| `rig.sh gdb CMD...` / `log` / `stop` | raw gdb against the emulator, its log, stop |
| `dosbuild.sh _NAME` | build one driver (`_386`, `_DPMI`) with an error gate; `TREE=` selects the tree |
| `kbuild.sh [OBJ...]` | build the kernel via `make -f KERNEL.MAK $$MOS.SYS`; never uses `MAKEMOS.BAT` (its `del $*.*` wipes every built driver) |
| `txtscr.c` | text-screen decoder used by `rig.sh screen` |

Always set `TREE=` explicitly for scratch builds: the default is the real
tree.

## The pmtrace tracer

Emulator-side, so it cannot change guest code layout — which guest-side
instrumentation repeatedly did in this project. Enabled by environment:

| variable | effect |
| --- | --- |
| `PMTRACE=file` | log every interrupt, exception and IRET in a window after each v-86 int 6Fh |
| `PMTRACE_WIN=n` | size of that window (events) |
| `PMTRACE_STEPS=n` | log the next n v-86 instructions after an int 6Fh `ax=7705h`, or a native `int 0D4h ah=11h` |
| `PMTRACE_HOOK_LO` / `_HI` / `_N` | log `bp`, `esp`, all segment registers, the general registers, `[bp-16]`, `[bp-12]` and four words at `ss:esp` for every instruction executed in a code range |

Hook ranges are offsets into the `$386.SYS` image (cs base `0700h`). For
code elsewhere, subtract `0700h` from the linear address: the driver at
`C0DE:xxxx` is `0xC0DE0 + xxxx - 0x700`.

Stack and memory peeks use a read-only page-table walk over physical
memory — no guest side effects.

## Useful addresses (current tree)

| what | where |
| --- | --- |
| GDT | image offset `17C0h`, linear `0700h + 17C0h` |
| `dtitable` (descriptor ownership, 30 entries) | image offset `1789h` |
| `$DPMI.SYS` group | segment `C0DE` in the test boots |

`dtitable` values: `ff` free, a task id = task-owned (freed by `cleardti`
on every `nmswitch`), `fe` permanent, `80h|taskid` = DPMI client
descriptor (exempt from `cleardti`).

## Lessons encoded in the tooling

- **Measure from the emulator, not the guest.** Guest instrumentation
  shifted layout and, once, never compiled in at all and was read back as
  data.
- **A value equal to its initialiser is not evidence.**
- **Dump the frame before theorising about a selector.**
- **Check encodings in the linked binary**, not the listing.
- `awk` with `RS="\r\n"` counts records differently from line numbers
  taken from a CR-stripped copy. Match on text, not line numbers, when
  editing CRLF sources.

## Peeking a table (PMTRACE_PEEK_OFF / _LEN)

`PMTRACE_PEEK_OFF` plus `PMTRACE_PEEK_LEN` append that many bytes, read
from the given `$386.SYS` image offset, to every hook line (cs base
`0700h`, same convention as the hook range; max 256 bytes). Read-only
page-table walk like the other peeks, so the guest image is untouched
and code layout cannot shift.

Watching `dtitable` (offset `1789h`, 30 entries) across a DPMI client's
termination:

	export PMTRACE=/tmp/t.log
	export PMTRACE_HOOK_LO=0x31FA PMTRACE_HOOK_HI=0x3230
	export PMTRACE_PEEK_OFF=0x1789 PMTRACE_PEEK_LEN=30
	./boot.sh /tmp/boot.img

The hook range is `einfun4c`+`freeclsel`; the first and last `H` lines
are then the table on entry and on exit. A client's entries read
`80h|taskid`, free ones `0ffh`.
