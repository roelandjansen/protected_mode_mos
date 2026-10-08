# PC-MOS/386 v5.01 — DPMI host: current state (after UPDATE 82, 2026-10-08)

Put this at the top of `HANDOVER.md`. It is the state to start from; the
UPDATE sections below it are the history and the reasons. UPDATE 62-82
are summarised here.

## What works

- **Real DPMI 0.9 extenders**: DJGPP (GCC 12.2), DOS/4GW 1.97 and DOS/32A
  9.1.2 run real programs -- file I/O (FTEST), memory (MTEST), time
  (TTEST), keyboard (KTEST), a long mixed load (STEST) -- with the same
  results as under HDPMI32 in plain DOSBox.
- **Nested clients** (UPDATE 67): three levels deep, any mix of the
  three extenders.
- **Several tasks** (UPDATE 68/69): the original `GO.BAT` -- four tasks,
  all three extenders, nested -- passes (UPDATE 79 build, dynamic core).
- **Maximum task size 596 KB** (UPDATE 71/73; measured again on 80, 81, 82).
- **int 31h cost** (UPDATE 75-77): one 0300h call 479 -> 401 monitor
  instructions.
- **DOS/4GW's clock** (UPDATE 79): int 21h 2Ch / `time()` correct.
- **.COM clients after another client** (UPDATE 78): full 64 KB DS.

## Files and builds

| file | built | size | md5 (first 12) |
| --- | --- | --- | --- |
| `_386.ASM` | `$386.SYS` -- memory manager + the DPMI host | 37,584 | `22081d7ac5ca` |
| `_DPMI.ASM`, `_DPMI.INC` | `$DPMI.SYS` -- front end (int 2Fh 1687h, `GoProtect`) | 5,149 | `f84240795eaa` |
| `MOSFUN39.ASM` | in `$$MOS.SYS` -- commit on a character device (UPDATE 66) | | |
| `ADDTASK.ASM` | `ADDTASK.COM` | 2,854 | |
| `DPMI32.ASM` | `DPMI32.COM` -- the kit's 32-bit client | | |

Only `_386.ASM` changed in UPDATE 75-82. The build is reproducible: two
builds in two containers gave the same md5.

## How the host is built (orientation)

- **`$386.SYS` holds the host.** `res16` (assembled for the 286, runs in a
  32-bit segment!) and `res32` (use32), one group `mmgrp`, CS `0018`, SS
  `0020`, base `0x700`. Everything resident in `res16` costs every task
  conventional memory.
- **Entry**: `einative` (saves the client's es/ds/fs/gs into `ncap0stk`,
  loads gs = `gdthook`, and since UPDATE 75 stores the caller's client id
  in **`entcid`**) -> `einvhook` -> `eindisp` -> `einint31` -> the
  function handlers; back through `einback`. v-86 services through
  `dovmint` (resets the monitor stack -- `MEMDEV` only at a handler's top
  level).
- **`entcid`** (UPDATE 75): valid from `einative` until the first v-86
  run (`dovmint`) or task switch. Read it in `einvh1` and `e0300s`
  (`c32edc`); everything after a v-86 round trip must keep using
  `e31tid`/`c32edx`.
- **Fast paths**: `einvhook` sends vectors 08h-E5h straight to `einvh1`
  (UPDATE 77); `einint31` tests 0300h, 0301h/0302h, 0501h-0503h,
  0900h-0902h before the compare chain (UPDATE 76).
- **Client ids** (UPDATE 67): every DPMI session has an id 1..127;
  everything owned is tagged with it.
- **Hook table** (UPDATE 73/74): 1,024 x 12 bytes plus a per-client
  bitmap at `gs:[3000h + id*32 + vector/8]`, behind GDT entry `gdthook`.
  **gs inside the monitor belongs to the hook table.**
- **Initial selectors**: `makegdte` reuses an entry with the same tag,
  access byte `F2h` and base. Func 93's PSP/environment descriptors are
  written with access **`F3h`** (UPDATE 78) so they can never be handed
  out as a client's DS/SS.
- **Int 21h translation** (UPDATE 80): DOS conventions, as Windows/HDPMI.
  Per-client DTA at `gs:[4000h + id*8]` (dd offset, dw selector, db set),
  cleared by `cidstart`; default PSP:80h. 42h is plain reflection.
- **16-bit clients** (UPDATE 82): the int 21h dispatch clears the high
  words of the CX/DX/SI/DI slots before any translator. 5Ch is a plain
  reflection. 0B00h-0B03h refused (no watchpoints).
- **0800h** (UPDATE 81): identity mapping above `pt_pages`; page tables
  from `nalloc`, entered in the global page directory (`gdtpage` base -
  1000h); `phytab`/`phylin` (16) let later mappings reuse them.
- **Selector 0040h** (`gdtzero3`, dpl 3) has **base 400h** = BIOS data
  area (UPDATE 79); DOS/4GW reads the tick count through it.
  `einfun82` (int 38h/D4h 02h SCB, 04h TCB) returns `es:ebx` with ES = 0043h and EBX
  = linear - 400h.
- **Memory**: 0501h checks the reserve (`dpmirsv`, 2 MB) against the
  free page count and allocates exactly the request; 0500h from
  `nlargest`.

## Test procedure (before every hand-over)

Dynamic core unless a tracer mode needs the normal one
(`CORE=dynamic ./rig.sh start ...`; `rig.sh` honours `CORE=` since
UPDATE 79's session). Type only at an idle prompt, one key at a time
with an echo check (`kt.sh`: xdotool `type` drops characters).

1. **DPMI32 kit**, 19 images -- reference values as in UPDATE 74 (not
   rerun for 75-79; DPMI32 itself is unchanged).
2. **Extender tests**, all three extenders: FTEST sum `1BE00000`; MTEST
   11 / 11 / 12 MB (DJGPP / DOS/4GW / DOS/32A); TTEST 3021 @ 1000/s
   (Watcom); KTEST.
3. **Four-task run**: original `GO.BAT`; every return rc 0, three STESTs
   0 bad, all DONE, task 2's STEST with a real start time.
4. **Change-specific**: `W4XTEST W4HELLO`, `DOS32A WAXTEST DOS32A
   WAHELLO`, DPMI32 **after** another client (UPDATE 78), `W4TIME`
   (UPDATE 79), `Q300` / `Q900` (0300h, 0900h-0902h), `PM21` / `PMFN` /
   `PMDEF` (UPDATE 80; on a floppy with room), `PMPHYS` (UPDATE 81),
   `HI16` / `PM38` / `PMWATCH` (UPDATE 82), `MAXTASK` (596 KB),
   `DJBENCH n`.

A DOS/32A child started through `system()` must be `dos32a NAME`: bare,
only its stub runs (prints the LE banner, rc 0).

## Measurement

`hookprof.sh MAP LOG FROM TO`: label-run profile of a pmtrace hook log.
Needs a LINK map with every label public (`public p386.asm`, then
`include _386.pub` after `include xifmacs.inc`, `link _386,_386,_386/map`).
Gate the hook from gdb at an idle prompt: `set var pmt_hook_lo/hi/left`.
The INT/IRET log can be opened the same way: `set var pmt_win_size=N`,
`set var pmt_window=N` (works on the dynamic core).

| 0300h call | 74 | 75 | 76 | 77 |
| --- | --- | --- | --- | --- |
| monitor instructions | 479 | 440 | 423 | 401 |

## Known, not fixed

| what | where | notes |
| --- | --- | --- |
| Tasks starting the **same EXE** at once: `can't open`, rc 255 | kernel: `openfile` / `chkacc` | EXEC opens 3D20h (deny-write) and is switched to compat only if the *first* open in `gfbtfb` is compat; the DJGPP stub opens 3D00h (compat). Ideas: (A) `openfile` walks the whole chain while `tcbexec3d` is set; (B) `chkacc` `ch13` lets a compat read-only open coexist with deny-write/deny-none |
| Shell keeps its **reloaded transient** low: 13.6 KB less program space after the first big program | `$$SHELL.SYS` | not a leak (watchpoint-proven); reload high like COMMAND.COM would keep it |
| DOS/32A warning 9003, INT 22h modified after a nested EXEC | kernel EXEC/terminate | same on UPDATE 74; compare with plain DOS + HDPMI32 |

## Open ideas

- The per-call cost is now mostly the v-86 round trip itself.
- Exception lookups (`e31xfind`) could use a bitmap like interrupts.
- Terminals other than the console (`ADDTASK ... termid,port`).

## Rig (container notes)

- `rebuild.sh` restores everything after a container reset (no sudo):
  tree, toolkit, user-local packages (`apt-get download` + `dpkg -x` into
  `~/deps/root`), `libiir` built from berndporr/iir1 **tag 1.9.3**,
  gawk, x11-utils, DJGPP 12.2 (andrewwutw/build-djgpp v3.4), test
  clients. Re-extract `dosbox.gz` afterwards if the toolkit's
  `restore.sh` deleted it. Open Watcom: `ow-snapshot.tar.xz` from the
  open-watcom-v2 `Current-build` release (`binw` has `dos4gw.exe`,
  `dos32a.exe`).
- `~/rig/env.sh` sets `LD_LIBRARY_PATH`/`PATH`; run rig scripts under
  bash. `rig.sh` keeps its pid in `/tmp/pmrig`, `common.sh` in
  `rig/state`: link the pid file.
- Guest memory under paging: read through `MEM_BlockRead` from gdb, not
  `MemBase + linear`. GDT at linear `1FA0h`.
- Background processes (the emulator) do not survive the end of a
  working turn: boot and measure in one go.

## UPDATE index

| | |
| --- | --- |
| 62-65 | real extenders: retf stubs, PSP/environment selectors, 0009h/0008h on initial selectors, DOS/32A |
| 66 | interrupts on for clients (IF), IRQ flags via iret stubs; PC-MOS commit on a character device |
| 67 | per-client ownership: client ids, nesting; hook table 320 -> 1024 |
| 68 | multiuser: `cidtagsw` took the task id from a clobbered esi |
| 69 | `hookhwm`: int 31h 10x cheaper; four tasks at once |
| 70 | 0501h without "valloc everything"; `nhint`; ADDTASK shows the maximum |
| 71 | default stubs into extended memory (+4 KB/task); `NLDW` + eax bug |
| 72 | five `NLDW` sites fixed; 0500h via `nlargest` |
| 73 | hook table into extended memory (+12 KB/task) |
| 74 | lookup guard; per-client hook bitmap |
| 75 | client id computed once per int 31h call (`entcid`) |
| 76 | int 31h fast path for 0300h-0302h, 0501h-0503h, 0900h-0902h |
| 77 | `einvhook`: vectors 08h-E5h straight to the hook lookup |
| 78 | PSP/environment descriptors access `F3h`: a .COM client no longer gets its PSP as DS |
| 79 | selector 0040h = BIOS data area (base 400h): DOS/4GW's int 21h 2Ch |
| 80 | host int 21h translation: DTA (1Ah/2Fh/4Eh/4Fh) and 42h by DOS conventions; per-client DTA in hook page 5 |
| 81 | int 31h 0800h physical address mapping (identity, above RAM's linear space) |
| 82 | 16-bit clients: int 21h high words cleared (was a host crash); 5Ch DOS conventions; int 38h 02h/04h ES; tidy-up |
