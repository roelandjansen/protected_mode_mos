## UPDATE 64 (2026-09-27) — DOS/4GW runs

DOS/4GW 1.97 (Open Watcom v2) runs: `W4HELLO` three times and `W4MEM`
(4 MB, sum `1FE00000`) twice in one boot, environment intact. Found
with a differential trace against HDPMI32. DOS/32A: next (still only
its banner). Full regression over all environments (DPMI32 kit,
DJGPP, DOS/4GW, DOS/32A) comes when DOS/32A passes; not run yet for
this update.

### Test environments (host side, not in the PC-MOS tree)

- **Open Watcom v2**, `ow-snapshot.tar.xz` (GitHub
  `open-watcom/open-watcom-v2`, tag `Current-build`), in `~/ow`:
  `WATCOM=~/ow PATH=~/ow/binl64:$PATH INCLUDE=~/ow/h wcl386 -q -bt=dos
  -l=dos4g -fe=w4hello.exe w4hello.c` (`-l=dos32a` for DOS/32A; its
  bind stub is not found, run those as `DOS32A WAHELLO`). Extenders:
  `~/ow/binw/dos4gw.exe`, `dos32a.exe`, copied onto the floppy.
- Programs: `djhello.c` / `djmem.c` renamed: `W4HELLO`, `W4MEM`,
  `WAHELLO`, `WAMEM`.
- **Reference host HDPMI32**: HX runtime `HXRT224.zip` (GitHub
  `Baron-von-Riedesel/HX`, `v2.24pre1`, `BIN/HDPMI32.EXE`), plain
  DOSBox: `HDPMI32 -r`, then the program. All four Watcom programs work
  there, so every difference under PC-MOS is ours.

### Method: differential trace

Same program, same tracer, two hosts. `rig/pair.sh LOG REGEX` pairs
each client `int 31h` with ITS return: the IRET whose frame starts with
the caller's eip and cs (the host's internal IRETs in between made a
next-line pairing wrong). Compare, per call: function and bx, call
site (eip), cs/ss/ds/es, and the returned registers and flags. The
first difference is the bug. Also compare CF in against CF out: it
exposed (3). In plain DOSBox arm the tracer with `PMTRACE_ALL=1`.

### Found and fixed

1. **Hook table full** (`_386.ASM`). `phooktab` had `DPHKN = 32`
   entries for 0203h AND 0205h, all tasks together. DOS/4GW hooks all
   256 vectors and 32 exceptions (288). Its 33rd hook (0205h vector
   25h) returned cf=1; its error path then #GP'd in its own formatter
   and exited 4CFFh. **`DPHKN equ 320`.** The five scans compare
   against `DPHKN*12` as immediates; nothing else changes.
2. **Descriptor pool** (`_386.ASM`). `dtitable` held **30** client
   descriptors for the whole system, the host's own per-client ones
   (cs/ds/ss, PSP, environment, stubs) included. DOS/4GW asks for 47;
   0000h failed (call 568) and it reported "DOS/16M error: [6] not
   enough memory to load program". **`db 250 dup(-1)`.** GDT limit,
   `gdtlen` and all checks follow from `dtilen`; the GDT is relocated
   by base only. +220 x 9 bytes.
3. **Default handler lost the flags** (`_386.ASM`). 0204h returned the
   stub `int 0E6h / N / iret`. DOS/4GW hooks int 31h itself and chains
   to the default; the monitor serviced N and resumed at the stub's
   iret -- which restored the flags the CALLER pushed. Every call that
   came in with cf=1 went out with cf=1: 0200h 144/144, 0201h 37/37,
   0205h 49 times, with valid results. New tables, appended after
   `+488h` (fixed offsets unchanged):
   - `+48Ch`: 16-bit, `int 0E6h / N / retf 2` (`CD E6 N CA 02 00`)
   - `+A8Ch`: 32-bit, `int 0E6h / N / retf 4` (`CD E6 N CA 04 00`)
   Stub descriptor limit `48Bh` -> `108Bh`. 0204h default offset:
   `48Ch + N*6`, + `600h` for a 32-bit client. `einvhook` reads N after
   `int 0E6h` as before: no other change. The old iret table stays,
   unused. The new 0204h code runs in the 32-bit segment: immediates
   by `db 0bah / dw 6,0` and `EAXI` (a plain `mov dx,6` would take a
   32-bit immediate at run time).
4. **Dirty ESP/EBP high words at the switch** (`_DPMI.ASM`
   `GoProtect`). A second DOS/4GW run in a boot failed ("Divide by zero
   error", later a hang). Session 2 was identical to session 1 up to
   call 354 (0303h), then ss:esp became `0073:003113E8`: EBP had
   `0031xxxx` from the very first event of session 2 -- the previous
   client's high words survive its 4Ch, COMMAND.COM and the next
   program's real-mode code. Our client ss has B=1, so DOS/4GW's 16-bit
   `LEAVE` copies all of EBP to ESP. DPMI 0.9: high word of ESP is 0
   after the switch. **`movzx esp,sp` / `movzx ebp,bp`** right before
   `int 0d4h` 1001h.

### Ruled out (measured, keep)

- *Segment reload after 0009h* (DPMI 1.0 requires it, 0.9 allows
  either). `DPMI32` line `32d`: DS = a data selector, 0009h makes it
  code, then writes through DS straight after, after 0205h (61h, 25h)
  and after timer ticks. HDPMI32 and PC-MOS both:
  `#GP count:0000 bytes 1/2/3:A1A200A3`. The #GP in DOS/4GW was its
  error path after (1).
- 000Ch reading a wrong buffer (EDI `0000146C`, clean).
- 0A00h: cf=1 (`3217`), correct for an unknown vendor.

### Open (not blocking)

- **0006h refuses the client's initial cs/ds/ss** (kernel-made, not
  tagged `80h|taskid`; `e31sel` checks the tag for every 000xh). Right
  for writes, wrong for reads. DOS/4GW copes; others may not.
- **Initial ss/ds are `00C0`** (G=1, B=1); HDPMI32 gives `0040`. With
  G=0, bug (4) would have been a clean #SS instead of silent stack
  corruption. Change only with the full regression behind it.
- The hook table and descriptor pool are still shared by all tasks and
  scanned linearly (per-client ownership, parked).
- 0001h at DOS/4GW's exit fails for 11 selectors (not ours to free, or
  freed already); harmless so far, look at it with the ownership work.

### Change summary

| file | change |
| --- | --- |
| `_386.ASM` | `DPHKN` 320; `dtitable` 250; retf-n stub tables; stub limit `108Bh`; 0204h default |
| `_DPMI.ASM` | `GoProtect`: `movzx esp,sp` / `movzx ebp,bp` before the switch |
| `DPMI32.ASM` | `32d` test: 0000h/0007h/0008h/0009h, 32-bit #GP handler `hgp` (counts, skips 2 bytes), three writes through DS after 0009h (straight, after 0205h 25h, after timer ticks); base from PSP*16 |

Build: `$386.SYS` 33664 -> 42208, 0 warnings. `$DPMI.SYS` 5133 -> 5149,
the 4 pre-existing warnings (A4057, `scbmmsub` / `memman`). Binary
checked against the listing at the new 0204h code (`6F2B`).

| file | size | md5 |
| --- | --- | --- |
| `$386.SYS` | 42208 | `a1ab24dffd13674c7cb7233198a789d5` |
| `$DPMI.SYS` | 5149 | `52ebe63ec6ad7d23abe0222320c44841` |
| `DPMI32.COM` | 1529 | `07e3d2cc7fec615fa913cd90d7428b70` |
| `_386.ASM` | | `10d49fa10f072e7dc47adc8341c2ebd4` |
| `_DPMI.ASM` | | `ee86eb514c8898fca87c5dbc7d06c29a` |
| `DPMI32.ASM` | | `3a525f6443472bb7409a6bb953ecfea3` |

### Rig

- `rig/pmtrace-update64.patch` (on top of `dosbox-pmtrace.patch`):
  every line gets ` esi= edi= ebp=` appended after `efl=` (existing
  greps keep working); `PMTRACE_ALL=1` arms the window at start.
- `rig/pair.sh`: call/return pairing (needs gawk).
- `common.sh`: `DOSBOX_BIN="${DOSBOX_BIN:-...}"`, so
  `DOSBOX_BIN=~/dosbox-trace ./boot.sh ...` runs the tracing build.
  Build with the normal binary.
- DOSBox from source, no wrapdb (blocked): dev packages
  `libsdl2-dev libsdl2-net-dev libopusfile-dev libspeexdsp-dev
  libslirp-dev libpng-dev zlib1g-dev libasound2-dev`, iir1 **1.9.3**
  via cmake, `meson setup build-trace --buildtype=debug
  -Dwrap_mode=nofallback -Duse_fluidsynth=false -Duse_mt32emu=false
  -Duse_opengl=false -Denable_debugger=normal`, `ninja` (~10 min on one
  CPU; one-file changes relink in seconds).
- `mem.sh` needs gawk (`strtonum`).

### Lessons

- **Leftover emulators block builds**: empty listing, old `.SYS`.
  `pkill -x dosbox; pkill -x dosbox-trace` first -- `-x dosbox` misses
  the tracing build, and `pkill -f dosbox` kills the calling shell.
- A #GP deep inside an extender is often its error path. Read the
  flags of the last `int 31h` return before it.
- A hypothesis test proves nothing until it runs on the reference host
  too (`32d` answered the same on both, and killed the theory).
- Code in res16 runs in a 32-bit segment: no plain 16-bit immediates.
- Keystrokes typed while a program is still exiting are lost: wait
  before the next command (it looked like a hang twice).

### Next

1. DOS/32A (`DOS32A WAHELLO`, `WAMEM`): banner only under PC-MOS, no
   banner under HDPMI32 -- different path from the start. Differential
   trace.
2. All environments together: DPMI32 kit (19 clients), DJGPP,
   DOS/4GW, DOS/32A.
3. The open items above.
