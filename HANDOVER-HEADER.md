# PC-MOS/386 v5.01 — DPMI host: current state (after UPDATE 74, 2026-10-03)

Put this at the top of `HANDOVER.md`. It is the state to start from; the
UPDATE sections below it are the history and the reasons. UPDATE 62-74
are summarised here.

## What works

- **Real DPMI 0.9 extenders**: DJGPP (GCC 12.2), DOS/4GW 1.97 and DOS/32A
  9.1.2 run real programs -- file I/O (FTEST), memory (MTEST), time
  (TTEST), keyboard (KTEST), a long mixed load (STEST) -- with the same
  results as under HDPMI32 in plain DOSBox.
- **Nested clients** (UPDATE 67): a DPMI program starting another one
  via `system()`/exec, three levels deep, any mix of the three
  extenders. A client that dies without 4Ch is cleaned up at the next
  session start in its task.
- **Several tasks** (UPDATE 68/69): four PC-MOS tasks running DPMI
  clients at once, nested, under heavy allocation load.
- **Maximum task size 596 KB** (UPDATE 71/73; 580 before, 600 with the
  UPDATE 61 driver). `ADDTASK` reports the current maximum on its size
  errors (UPDATE 70).

## Files and builds

| file | built | size | md5 (first 12) |
| --- | --- | --- | --- |
| `_386.ASM` | `$386.SYS` -- memory manager + the DPMI host | 36,720 | `6383f1809dc3` |
| `_DPMI.ASM`, `_DPMI.INC` | `$DPMI.SYS` -- front end (int 2Fh 1687h, `GoProtect`) | 5,149 | `f84240795eaa` |
| `MOSFUN39.ASM` | in `$$MOS.SYS` -- commit on a character device (UPDATE 66) | 130,017 | `16fc9d34ac6c` |
| `ADDTASK.ASM` | `ADDTASK.COM` (`make -f MAKEUTIL.MAK ADDTASK.COM`) | 2,854 | |
| `DPMI32.ASM` | `DPMI32.COM` -- the kit's 32-bit client | | |
| `MAXTASK.ASM` (rig) | `MAXTASK.COM` (`combuild.sh MAXTASK`) | 70 | |

`_386.ASM` md5 `486be34726702632e9977f4eb425e079` (UPDATE 74).

## How the host is built (orientation)

- **`$386.SYS` holds the host.** `res16` (assembled for the 286, runs in a
  32-bit segment!) and `res32` (use32), one group `mmgrp`, CS `0018`, SS
  `0020`, base `0x700`. Everything resident in `res16` costs every task
  conventional memory. res32 starts at res16's length rounded to a
  paragraph (`9510h`-ish: check the listing).
- **Entry**: `einative` (saves the client's es/ds/fs/gs into `ncap0stk`,
  loads gs = `gdthook`) -> `eindisp` -> `einint31` -> the function
  handlers; back through `einback`. v-86 services through `dovmint`
  (which **resets the monitor stack** -- `MEMDEV` only at a handler's top
  level, never inside a called routine).
- **Client ids** (UPDATE 67): every DPMI session has an id 1..127;
  everything owned (descriptors `80h|id`, memory blocks, hooks,
  callbacks, `c32tab`, `envtab`) is tagged with it. `e31tid` returns
  it. `curcid` (task -> current), `cidtask`, `parcid`, `savnca`,
  `cidpsp`, `pendsw`. `cidstart` (nest under a live parent, found on
  the PSP chain, or clean up a dead one), `cidpop` (at the client's
  4Ch), `cidtagsw` (initial selectors per client, in `nmswitch`).
- **Hook table** (UPDATE 73/74): 1,024 x 12 bytes plus a 4 KB per-client
  "maybe hooked" bitmap at `gs:[3000h + id*32 + vector/8]`, in four
  pages of extended memory behind GDT entry `gdthook`, set up by
  `hookinit` at the first session start. `phooktab equ 0`. Lookups
  (`e31hfind`, `e31xfind`) stop at `hookhwm`, return "not hooked" while
  `hookok` = 0, and skip the scan when the client's bit is 0.
  **gs inside the monitor belongs to the hook table.**
- **Default stubs** (UPDATE 71): generated at first use into two pages
  of extended memory (`stbget`, `stublin`); layout in UPDATE 71.
- **Memory**: 0501h checks the reserve (`dpmirsv`, 2 MB) against the
  free page count and allocates exactly the request, first fit;
  `nalloc` starts at `nhint` (UPDATE 70). 0500h reports min(longest
  free run, free - reserve) from a read-only scan, `nlargest` (UPDATE
  72). Banks are mapped at linear `(bank + 110h) << 12`.
- **res16 -> res32 calls** go through dword pointers filled by `e6f8e`
  with `offset mmgrp:label` (`stbptr`, `nlgptr`).

## Test procedure (before every hand-over)

All with `CORE=dynamic ./boot.sh IMG.img` (the interpreter core is ~400x
slower; pmtrace's hook/step modes need it). Type only at an idle prompt
(`rig/waitp.sh`).

1. **DPMI32 kit**, 19 images (`/tmp/runkit.sh`; background, ~25 min).
   Reference values (UPDATE 74):

| client | value |
| --- | --- |
| qR | `[A:\]` |
| s2 | `0503h grow lin:0020E000 ... 1234ABCD` |
| s3 | `L:00CB2000 kept h:001000EE ... fl:32133247` |
| s5 | `CB20CA20CB20` |
| sB | `5A5AA5A5 ... 324700088203` |
| sC | `1CFC 1D05 1D05 grow fl:3246` |
| sD | `324732461CFC` |
| sE | `324612345678` |
| sF | `count now:0001` |
| sH | `000500053246` |
| sI | `fl/ax:32461234 ... fl/bx:32465234` |
| sJ | `00010100` |
| sK | `32460000 rm:0070051C pm:007B0400` |
| sL | `count ... 0005xxxx` (loop count varies) |
| sN | Div=2, `007B04040002` |
| sQ | `32463247` |
| sR | `324612340005` |
| sS | `324600704A10007B0488` |
| s32 | `#GP count:0000 bytes 1/2/3:A1A200A3` |

   Layout-dependent values (linear addresses, segments, sS's offset,
   the stub selector `007B`) move whenever the driver's size or its
   extended-memory use changes; check that the shift matches.
2. **Extender tests**, all three extenders in one boot each:
   FTEST sum `1BE00000`; TTEST 275 @ 91/s (DJGPP), 3021 @ 1000/s
   (Watcom); KTEST echoes the line; MTEST 11 / 11 / 12 MB.
3. **Four-task run**: `GO.BAT` (`ADDTASK 500,n,,Tn.BAT` for tasks 1-3,
   task 0's chain into `T0.TXT`); read `T0..T3.TXT` with `mtype`. Every
   return rc 0, three STESTs churn/sort 0 bad, all "DONE".
4. Change-specific checks: `W4XTEST W4HELLO` (nested DOS/4GW, hooks),
   `MAXTASK`, `DJMI500` (0500h), `DJBENCH n` (per-call cost).

## Rig

- `boot.sh` (`CORE=` override, needs an `.img` name), `key.sh`,
  `screen.sh`, `regs.sh`, `mem.sh` (reads **physical** memory),
  `waitp.sh`, `mcbwalk.sh`, `pair.sh`, `kbuild.sh` (900 s), `dosbuild.sh`
  (600 s), `combuild.sh`.
- **Tracer** (`~/dosbox-trace`, heavy debugger build; patches 64/66/70/71):

| variable | effect |
| --- | --- |
| `PMTRACE=file`, `PMTRACE_WIN=n` | log INT/IRET events (armed by v-86 int 6Fh) |
| `PMTRACE_ALL=1` | log without arming (plain DOSBox, HDPMI32) |
| `PMTRACE_HOOK_LO/HI/N` | log monitor instructions (`H`), offsets from `0x700` |
| `PMTRACE_STEPS=n`, `PMTRACE_STEP_AX=hex` | log v-86 instructions (`S`) from an IRET into v-86 / a v-86 int 21h with that ax |
| `PMTRACE_GATE_AX=hex`, `PMTRACE_GATE_N=n` | hook/step logging only from the n-th int 31h with that ax |

- Methods that found every bug: **differential trace** (the same program
  on a known-good build or HDPMI32, int 31h sequences compared until
  they split), then a **gated monitor trace** of exactly that call,
  addresses mapped to routines from the listing.
- Test programs (`tests/`): ftest, mtest, ttest, ktest, fdiag2, stest,
  xtest, dbench, mi500.c; built for DJGPP and Watcom (dos4g, dos32a).

## Lessons (consolidated)

- **res16 is a 286-assembled segment executing 32-bit code**: no 16-bit
  immediates (`EAXI`), no fs/gs overrides (prefix bytes `64h`/`65h`), a
  register op without `66h` is 32-bit -- clear eax before a 16-bit load
  (`NLDW`) unless the high word is built on purpose; memory operands
  need `67h` for `[si+disp]`.
- MASM 5.1: a macro or `equ` used before its definition -> phase error;
  use16 data cannot hold a use32 label's offset; a res32 label's group
  offset is `offset mmgrp:label`; `jcc` reaches only +-127.
- Moving data to high linear addresses exposes code that relied on a
  low value (UPDATE 71). Size tables per client, and bound every scan.
- Measure before designing (page map, per-call instruction counts).
- Rig: dash `printf` has no `\x` (octal escapes, check with `od`); mawk
  has no `strtonum` (gawk); `pkill -f PATTERN` can kill your own shell,
  stop by PID; one emulator at a time; after a container restart remove
  `/tmp/.X99-lock`; restore clean floppies; check free floppy space.

## Open ideas

- A DOS/4GW child runs as its own nested client; under HDPMI32 it
  attaches to the parent's DOS/4G. Works either way.
- The per-call cost is now the v-86 round trip (0300h, 0501h/0502h each
  ~ one round trip); a faster reflection path would help all of them.
- Terminals other than the console (`ADDTASK ... termid,port`).
- Exception lookups (`e31xfind`) could use a bitmap like interrupts.

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
