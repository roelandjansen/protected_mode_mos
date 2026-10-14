# PC-MOS/386 debug rig

A headless test rig around DOSBox Staging 0.82.2, patched with an
emulator-side tracer and with int 13h extensions. Private tooling, not
part of the project tree.

## Restore in a fresh session

    tar xzf pmrig-toolkit.tar.gz
    cd pmrig-toolkit
    ./restore.sh

`restore.sh` installs the rig into `/home/claude/rig` and the emulator
into `/home/claude/dosbox-staging/build-dbg/dosbox`.

- It uses the prebuilt binary if its libraries resolve.
- Otherwise it clones upstream `v0.82.2`, applies
  `dosbox-pmtrace.patch` and `dosbox-int13ext.patch`, and rebuilds
  (meson, `--buildtype=debug -Denable_debugger=heavy`).
- No sudo.

Then unpack the PC-MOS tree to `/home/claude/pm`.

**Which tree the rig boots:** `rig.sh` takes the kernel, drivers and
utilities from `PM_ROOT` (default `/home/claude/pm`). The work tree is
`/home/claude/scr`, so set `PM_ROOT=/home/claude/scr` to boot current
builds. An older kernel does not see 0Fh extended partitions, for
example.

## Contents

| file | what |
| --- | --- |
| `dosbox.gz` | prebuilt debug DOSBox Staging 0.82.2 with all three patches (x86-64 Linux, Ubuntu 24.04 libraries) |
| `dosbox-pmtrace.patch` | tracer patch against upstream `v0.82.2` |
| `dosbox-int13ext.patch` | int 13h 41h/42h/43h/48h for hard disk images; 08h reports at most 1024 cylinders (UPDATE 93) |
| `dosbox-hdd4.patch` | four hard disk images (80h-83h) instead of two; `imgmount 2`-`5` (UPDATE 104) |
| `restore.sh` | installs the rig, uses or rebuilds the emulator |
| `rig/` | the scripts and tools below |

## Scripts

**Emulator control**

| script | use |
| --- | --- |
| `rig.sh start [--testconfig] [--bootdir DIR] [--configsys F] [--add F]` | build a boot floppy and start the emulator headless; `HDIMG=` attaches a hard disk image, `HDGEOM=512,63,255,CYLS` gives its geometry; `DOSBOX=` and `CYCLES=` select the emulator; `BOOTIMG=img` boots that floppy image instead of building one, `HDBOOT=1` boots from the hard disk (`boot -l c`); `HDIMG2`-`HDIMG4` (geometry `HDGEOM2`-`4`) attach disks 81h-83h |
| `rig.sh screen` / `cpu` / `mem ADDR LEN` / `ivt N` | read the text screen, registers, guest memory, IVT entry |
| `rig.sh type TEXT` / `key KEY...` | send keystrokes (see the keyboard notes) |
| `rig.sh gdb CMD...` / `log` / `stop` | raw gdb against the emulator, its log, stop |
| `kt.sh CMD [WAIT]` | type a command one key at a time, check the echo, press Return, print the screen |
| `waitp.sh [TRIES]` | wait for an idle `A:\` prompt before typing |
| `boot.sh`, `xstart.sh`, `stop.sh`, `screen.sh`, `regs.sh`, `mem.sh`, `key.sh` | lower-level pieces used by the above |
| `mkfloppy.sh OUT.img [CFGDIR] [OVERLAYDIR]` | build a boot floppy without starting the emulator |
| `common.sh`, `env.sh` | shared settings; source `env.sh` first (library and tool paths, mtools) |

**Builds**

| script | use |
| --- | --- |
| `dosbuild.sh _NAME` | build one driver (`_386`, `_DPMI`) with an error gate; `TREE=` selects the tree |
| `kbuild.sh [OBJ...]` | build the kernel via `make -f KERNEL.MAK $$MOS.SYS`; never uses `MAKEMOS.BAT` (its `del $*.*` wipes every built driver) |
| `ubuild.sh TARGET` | build one utility via `MAKEUTIL.MAK` (timeout 900 s) |
| `combuild.sh NAME` | build one `.COM` from `NAME.ASM` inside the emulator |

HDSETUP is built outside the emulator, with Open Watcom, by the tree's
own `SOURCES/src/cutils/HDBUILD.SH` (UPDATE 99/100).

**Analysis**

| script | use |
| --- | --- |
| `mcbwalk.sh DUMP` | print the DOS MCB chain from a memory dump |
| `pair.sh LOG REGEX` | pair int 31h calls with their returns in a pmtrace log |
| `txtscr.c` | text-screen decoder used by `rig.sh screen` |

**Disk images** (Linux side; `restore.sh` builds `mkpt` and `mkmbr`)

| tool | use |
| --- | --- |
| `mkmbr IMG [type start size]...` | write an MBR with up to four primary partitions (UPDATE 93) |
| `mkpt IMG SEC BASE [type start size]...` | write a partition table sector (MBR or EBR) at sector `SEC`; starts as stored (relative for EBRs), CHS computed from `BASE + start`, 1023/254/63 when too big |
| `ptdump.sh IMG` | print the MBR and follow the EBR chain: type, start, absolute start, size, CHS |

Example, a 1 MiB aligned layout with a logical drive beyond 8.4 GB:

    truncate -s 21467980800 t.img
    mkpt t.img 0 0 06 2048 204800 0f 20000768 1050624
    mkpt t.img 20000768 20000768 0e 2048 1048576
    mformat -i t.img@@$((2048*512)) -T 204800 -h 255 -s 63 -H 2048 ::
    ptdump.sh t.img
    HDIMG=$PWD/t.img HDGEOM=512,63,255,2610 PM_ROOT=/home/claude/scr rig.sh start --testconfig

Always set `TREE=` explicitly for scratch builds: the default is the real
tree.

## Keyboard and timing notes

- **Missing xdotool:** on a host without it, run
  `apt-get download xdotool libxdo3`, unpack with `dpkg-deb -x` and put a
  wrapper on `PATH` that sets `LD_LIBRARY_PATH`. No sudo.
- **Shifted characters:** `xdotool type` drops them (`:` `*`). Use
  `kt.sh`, or `rig.sh key ... shift+semicolon`.
- **Arrow keys:** the grey arrow keys do nothing in HDSETUP. Use
  `KP_Up`/`KP_Down`, and do not send keypad digits.
- **Typing too early:** keys typed right after boot are lost. Wait for
  the prompt (`waitp.sh`), about 65-70 s with `--testconfig`.
- **FORMAT:** it needs an extra Return after `Y`.
- **Image writes:** DOSBox buffers them. Wait a few seconds before
  `rig.sh stop`, or the last sector written may be missing from the
  image. PC-MOS has its own write-back cache on top of that.
- **Stale emulators:** after a timeout, kill leftover dosbox processes
  (`pgrep -a dosbox`, then `kill PID`). Never use `pkill -f`: it kills
  the shell.
- **Speed:** the debug build is slow; `FORMAT` of a 2 GB partition takes
  about 15 minutes. Use `DOSBOX=.../build-rel/dosbox` for long runs. It
  has to be built separately, with the same patches.

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

## QEMU: a second test machine with a real BIOS

DOSBox handles int 10h, int 13h and int 15h inside the emulator. A real
PC or VM has a video BIOS at C000 and a system BIOS at E000-FFFF, and
its disk BIOS may use DMA. Two VMware-only bugs came from that
(UPDATE 103: DMA under paging; UPDATE 106: FREEMEM over the video
BIOS). QEMU with SeaBIOS reproduced the second one here.

Setup, no sudo (Ubuntu 24.04 packages):

    mkdir -p /tmp/claude-0/qemu && cd /tmp/claude-0/qemu
    apt-get download qemu-system-x86 qemu-system-common qemu-system-data seabios ipxe-qemu \
        libfdt1 libpmem1 librdmacm1t64 libibverbs1 libslirp0 libbpf1 liburing2 libaio1t64 \
        libndctl6 libdaxctl1 libnl-3-200 libnl-route-3-200
    for F in *.deb; do dpkg-deb -x $F root; done

`rig/qemu.sh` (QEMU 8.2, TCG, `-machine pc`, no network):

| command | use |
| --- | --- |
| `qemu.sh start FLOPPY [HDIMG] [MEM_MB]` | boot a floppy image (hard disk image as IDE 0), default 32 MB |
| `qemu.sh screen` | the 80x25 text screen (read from b8000 via the monitor) |
| `qemu.sh key KEY...` | QEMU key names (`ret`, `y`, `shift-semicolon`) |
| `qemu.sh mon CMD` | any monitor command (`info registers`, `xp`) |
| `qemu.sh stop` | stop |

Upper memory in QEMU: video BIOS C000-CCFF, SeaBIOS from about E700
on. In DOSBox: video BIOS and fonts at C000-C3FF and C700-C9FF; the EMS
page frame (RAM) at E000.

## Bochs: a strict CPU

QEMU's TCG and DOSBox do not enforce every protection check. A write
through a code segment, for example, passes there; a real CPU (VMware,
real hardware) answers it with #GP. That class of bug hid in `$DPMI.SYS`
from 1991 to UPDATE 108. Bochs checks segment types, limits and
descriptor rules like a real CPU, so it reproduces VMware-only faults
here, and its debugger stops at an exact instruction count.

Setup, no sudo (Ubuntu 24.04 packages):

    mkdir -p /tmp/claude-0/bochs && cd /tmp/claude-0/bochs
    apt-get download bochs bochsbios vgabios bochs-x
    for F in *.deb; do dpkg-deb -x $F root; done

`rig/bochs.sh FLOPPY [INSNS] [MEM_MB]` boots the floppy for INSNS
instructions (default 2,000,000,000), prints the text screen and lists
every CPU error from the Bochs log with its count and the instruction
count of its first occurrence.

- To stop just before an error: `BOCHS_CMDS='r\nsreg\nu /4'
  bochs.sh FLOPPY COUNT-1` (one less than "first at"); the registers,
  segment descriptors and the next instructions are printed.
- It uses the legacy BIOS (`BIOS-bochs-legacy`): the 32-bit part of
  `BIOS-bochs-latest` crashes during POST in this build.
- The X frontend runs on Xvfb (`:99`); `term` would take over a
  terminal and `nogui` is not built in.
- About 25 s per 10^9 instructions; a boot to the prompt with DPMI is
  under 2 * 10^9.

A clean run lists no CPU errors. With the `$DPMI.SYS` of UPDATE 107:

    1 x  first at 366115097  write_virtual_checks(): no write access to seg
    9293219 x  first at 366117378  read_virtual_checks(): read beyond limit

A hard disk image: `BOCHS_HD=disk.img` (ata0-master), geometry
`BOCHS_HDGEOM=cyls,heads,spt` (default 4161,16,63, the 2 GB disk
VMware reports). Bochs' BIOS, like QEMU's, transfers without DMA, so
DMA staging bugs (UPDATE 103, 109) do not show here; segment and
descriptor faults do.

## Kernel size and md5

`kbuild.sh` leaves 768 bytes of the linked EXE at the end of
`$$MOS.SYS` (DEBUG writes the stripped image without truncating the
file). The real image is the link map's end minus the origin: up to
`FCSEG`, 100h less (130,753 bytes in UPDATE 107-109). Compare kernels by
`head -c 130753 '$$MOS.SYS' | md5sum`; MAKEMOS.BAT on Linux DOSBox
produces exactly that length.
