# Code changes made this session

Two files touched: `SOURCES/src/latest/_386.ASM` and
`SOURCES/src/latest/_DPMI.ASM`. Nothing else. `MOSDDINT.ASM` and
`MOSINIT2.ASM` were **not** modified — their existing markers came from
earlier sessions.

`pcmos386-changes.diff` is a unified diff against the tree exactly as
uploaded, so `patch -p0` from the repo root reproduces this state.

Both drivers are prebuilt here (`386.SYS.built`, `DPMI.SYS.built`) if you
want to drop them straight onto a floppy image rather than rebuild — rename
to `$386.SYS` and `$DPMI.SYS`.

**Read the fix/diagnostic split below before keeping any of this.** Roughly
half these edits are throwaway instrumentation.

---

## REAL FIXES — keep these

### 1. `_386.ASM` — `nmswitch` guard removed (the boot fix)

`contirq` reverted to unconditional fall-through to `cirqhndl`, i.e. the
original real-mode-IVT reflection. This is what takes the system from
"no prompt" to a live prompt. The guard was an earlier session's change and
was itself the cause of the stall.

Verified: boots to a live prompt, `VER` answers, `V`+`W` markers both fire.

### 2. `_DPMI.ASM` — `OFFSET ddt:` on every message pointer in INIT16

The screen garbage. `OFFSET var` in MASM yields the offset within var's
**segment**, not its **group**, and `assume cs:ddt` does not change that.
Messages live in INIT16 (link base `0E30h`) while `ds` = `cs` = the group
base, so `ds:dx` landed `0E30h` low and ah=9 dumped memory until it hit a
`'$'`.

Proven in the emitted bytes, not just the listing — the `R` relocatable flag
is a red herring, LINK does not fix these up:

| | before | after |
| --- | --- | --- |
| `NoMem` | `BA A7 01` | `BA D7 0F` |
| `MsgNotIns` | `BA 80 00` | `BA B0 0E` |

Sites changed: `MsgIns`, `MsgMem`, `MsgNotIns`, `NoMOS400`, `Already`,
`No386`, `NotFin`, `No386Sys`, `NoMem`.

`lea`-based arithmetic (e.g. `AllocateExtend`'s `EndProtect - BeginProtect`
size computation) is deliberately untouched — the segment/group bias cancels
in a difference.

### 3. `_DPMI.ASM` — `stc` restored on `CheckMOS`'s `NotMos` path

Was `;stc` + `clc`, i.e. reporting **success on failure**. The caller's
`jc ErrorHandler` never fired, but `scboff`/`scbseg` are only written on the
success path, so they stayed 0 and `CheckFor386SYS` then read `scbmmfg` out
of `0000:0000` (the IVT). This is what made `scbmmfg` look unset when it
never was.

### 4. `_DPMI.ASM` — MOS 5.x version detection

Dropped the `cmp ax,bx / jne NotMos` two-call equality test. Measured:

```
MOS 5.01 (original shipped kernel):  first 0005, second 0105
MOS 5.02 (our rebuilt kernel):       first 0005, second 0205
```

The `BX=-1` call reports minor `00`; the second reports the true minor. Same
divergence on the **original shipped kernel**, so this is genuine MOS
behaviour, not a rebuild regression. The driver dates from 1990–91 and was
written against MOS 4.10, where the two calls presumably agreed. Version
floor is now checked against the second call's AX, which carries the true
version.

**Caution, and please weigh in on this one.** The *original* intent of the
double-call idiom is not established. It may have been a MOS-vs-plain-DOS
identification trick rather than a sanity check, in which case dropping it
removes a guard against loading on non-MOS DOS. If that matters, replace it
with an explicit MOS check (e.g. treating the `int 0D4h` ah=2 call as the
test) — **not** by restoring the equality test, which demonstrably rejects
real MOS.

---

## DIAGNOSTICS — remove before committing

### `_386.ASM`

- `vmstart` markers `V` (pre-`sti`) and `W` (post-`sti`), written direct to
  `b800:0e60` / `0e64`. No push/pop by design, so they do not depend on
  `SS:SP` at v-86 entry.

### `_DPMI.ASM`

- `WriteLog` extended to emit a visible step marker to `b800:0e60 + step*2`.
  Steps print `'1'`..`'9'` and `':'` for 10.
  **Marker semantics:** `WriteLog` is called *after* a check returns but
  *before* its `jc`, so the last marker present names the step that FAILED,
  not the last one that passed. I got this wrong once already.
- `PutHex` helper + the two `int 21h` ah=30h version dumps in `CheckMOS`
  (row 23, columns 20 and 24).
- `DevLoadMsg` and `Copyright` sign-on prints in `InstallDriver` commented
  out. These were investigated and found **innocent** of the garbage. When
  restoring them, give them `offset ddt:` like the rest.
- The SCB-segment record moved from `0040:00F0` to `0040:00F2`, because
  `MOSINIT2`/`MOSDDINT` also write `00F0` and were contaminating it.

`DevLoadMsg` should be deleted rather than restored: it is project-added,
and it contains a literal `'$'` inside `'$DPMI.SYS'` while being printed
with ah=9, so it could only ever have printed `>>> DEVICE=`.

---

## Current state when you boot this

```
Not Installed.
DPMI protected-mode init not yet implemented (SegToSel
has no working GDT-descriptor implementation -- ...)
```

That is the **expected and correct** result. `CheckMOS`, `CheckDPMI`,
`CheckMicroProcessor` and `CheckFor386SYS` all now pass — `scbmmfg` reads
`'Y'` from the real SCB — and init stops at the deliberate refusal in
`CheckFor386SYS`.

**Do not remove that refusal to "make DPMI install".** `InitProtect` depends
on `SegToSel`, which calls `int 6Fh` with function `7786h` that nothing
implements; it falls through to generic native-mode reflection and executes
whatever sits at the never-hooked real-mode `int 6Fh` vector. That crashes
DOSBox outright, not just the guest. Implementing `SegToSel` properly —
building a real GDT descriptor — is the next piece of work.

## Reproducing the test setup

Boot floppy: template image + `$$MOS.SYS`, `$$SHELL.SYS`, `COMMAND.COM`,
`$386.SYS`, `$DPMI.SYS`, and a CONFIG.SYS of:

```
smpsize=64
cache=16
MEMDEV=$386.SYS
DEVICE=$DPMI.SYS
FREEMEM=C0000,F0000
```

Single-driver rebuild without a full `MAKEMOS.BAT` run, via the `.ASM.SYS`
rule from `MAKEUTIL.MAK`, inside DOSBox:

```
public _DPMI.ASM
masm _DPMI;
link _DPMI;
exe2bin _DPMI _DPMI.sys
```

then rename `_DPMI.SYS` to `$DPMI.SYS`. Same shape for `_386`.

---

# UPDATE — `SegToSel` implemented

## `_386.ASM`: int 6Fh DPMI function block (new, REAL FIX)

`_DPMI.INC` declares a 14-function memory-manager API at `7780h`–`778Dh`
("All DPMI related Memory manager functions start from 80h"). `i6f_tbl`
only covered `7700h`–`770Fh`, so **all of them** fell through to `contirq`,
were reflected to the never-hooked real-mode int 6Fh vector, and executed
whatever was there. That is why `$DPMI.SYS` could never install.

Added:

- `i6f_dpmi_tbl` — second dispatch table, its own range check in `entint6f`,
  rather than padding `i6f_tbl` to 142 mostly-empty entries
- `e6f86` — **SEGMENT_SELECTOR (7786h)**, i.e. `SegToSel`
- `e6f87` — **SELECTOR_SEGMENT (7787h)**, the inverse
- `e6funimp` — everything else in the block returns CF set, so an
  unimplemented function now **fails cleanly** instead of taking DOSBox down

`e6f86` is mostly plumbing: `makegdte` already did the real work (base =
seg*16, limit `0FFFFh`, reuse-on-identical-base — which *is* DPMI 0002h
semantics — from the `gdtspace`/`dtitable` pool of 30 user selectors,
returning RPL=3 or null when full).

ABI used: caller's BX is at `[bp-16]` (saved by `eicommon`; same idiom as
`nmswitch`'s `[bp-12]` for CX); CF is returned by editing `ss:[s0flags]`,
which `cgrm7`'s `iretd` restores; `makegdte`/`addrnca` are 16-bit near calls
(`db 66h` before `call`).

Assembles clean: **0 warnings, 0 severe errors**.

## `_DPMI.ASM`: refusal lifted + `memman` restored (REAL FIX)

The `CheckFor386SYS` refusal is removed, since `SegToSel` now exists.

Also restored: **`memman`**. It is declared `dd 0` and was never written
anywhere in the file — only read, as `call cs:[memman]` by `AllocateExtend`
and `InitProtect`. Left at 0 that far-calls offset 0 of the driver's own
segment, i.e. its device-driver header (`FF FF FF FF ...`). It now loads
from `scbmmsub` ("pointer to memman entry point") and refuses if null. This
was almost certainly dropped when `CheckFor386SYS` was rewritten.

## Current state

No crash. Emulator survives. Markers read `V123456` — steps 1–6 pass and
**ErrorHandler is never reached** (no `:`).

New wall: marker 7 never fires, so init hangs inside `AllocateExtend`, at
`call cs:[memman]` with `ah=1`. `scbmmsub` is non-zero (we did not take
`NoMemdev`), so the far call reaches a real entry point and does not return.

Next question: the memman calling convention. `MOSINIT.ASM:890` initialises
`scbmmsub` to a `retf` stub, and the kernel calls it from `MOSCNTXT`,
`MOSDDTMC`, `MOSFUTL3/4`, `MOSINIT2` and others — so the live entry point
and its `AH` function numbering can be read off those call sites. `_386.ASM`
contains no `scbmmsub` reference at all, so how `$386.SYS` publishes itself
needs establishing too.

---

# UPDATE 2 — `memman` far pointer, and a MASM truncation trap

## REAL FIX: MASM silently truncates E-registers in USE16 segments

**This is the important one, and it is not confined to my code.**

MASM accepts `mov eax,...` / `or eax,eax` / `mov cs:[x],eax` inside a
**USE16** segment and assembles them 16-bit — no `66h` prefix, no
warning, no error. From `_DPMI.LST`:

```
0547  8B 84 005F      mov eax,[si+scbmmsub]   ->  mov ax,[si+5Fh]
055E  0B C0           or  eax,eax             ->  or  ax,ax
0562  2E: A3 0059     mov cs:[memman],eax     ->  mov cs:[memman],ax
```

Not a listing artifact: the listing renders `66|` prefixes elsewhere
(246 occurrences), and CODE32 shows the same mnemonics prefix-free as
expected for USE32.

Effect here: only the **offset** half of the memman far pointer was
read and stored, leaving its **segment** word at the initialised 0.
`call cs:[memman]` then far-called into segment 0, and the V86 task was
measured sitting at `0000:0000` with VM=1.

Rewritten as two explicit word moves, with the null guard testing both
halves:

```
        mov     ax,[si+scbmmsub]        ; entry point offset
        mov     bx,[si+scbmmsub+2]      ; entry point segment
        mov     cx,ax
        or      cx,bx
        jz      NoMemdev
        mov     cs:[memman],ax
        mov     cs:[memman+2],bx
```

**Rule for this file: do not use E-register forms in CODE16 or INIT16.**
Use word pairs, or hand-encode with an explicit `db 66h` the way
`_386.ASM` does throughout.

### Open: this needs a proper audit

Any 32-bit operation anywhere in the USE16 segments of this driver has
been silently half-executing since it was written, and the build will
never tell you. I could not scope the audit honestly — the listing
shows per-segment offsets, so USE16 hits cannot be separated from the
many legitimate prefix-free USE32 ones in CODE32/INIT32 by offset
alone. A naive grep returned 182 hits, mostly false positives; do not
trust that number.

Given the driver's age, some of these may be **original** defects
rather than ours. Worth a scoped pass over CODE16 and INIT16.

## Verified: `memman` now points at the right handler

Diagnostic prints `0070 04B6`; `_386.LST` puts `rhentry:` at offset
`04B6`, segment `0070`. Confirmed from both sides.

Also established this round:

- `valloc` **is** AH=1 in `rhtable` — the function number was never
  wrong
- memman ABI: AH=function, BX=handle, CX=count, ES=target
  (AH=3 map, AH=0Dh list-base mapping)
- `$386.SYS` publishes `rhentry` via `parmrhad` (line 9609); MOS copies
  it to `scbmmsub`. `_386.ASM` never references `scbmmsub` by name —
  it reaches the SCB through its own `parmscb` block with hand-rolled
  offsets
- `AllocateExtend`'s page arithmetic is correct: `BeginProtect` and
  `EndProtect` are both in CODE32 at `0000`/`0CD4`, so the group bias
  cancels and CX=1

## Current state

Still no `>` — init has not returned — but the failure has **moved**.
Previously: V86 parked at `0000:0000`, interrupts off, null far call.
Now: V86, **interrupts enabled**, `CS=5803`, EIP wandering across a
wide range. Executing rather than stuck. Different problem, further in.

Diagnostics currently on screen, row 23:
`V123456` = step markers, `00050205` = the two int 21h ah=30h version
words, `0070 04B6` = the memman far pointer.

---

# UPDATE 3 — ROOT CAUSE: the V86 monitor emulates only I/O instructions

## The IOPL experiment

`uioplb` (`db 00110000b` = IOPL 3) is OR'd into `t2eflags+1` at init
(`or byte ptr [t2eflags+1],al`) — that is what fills in the `iopl=??`
the TSS2 comment was unsure about. Set it to 0 and rebuilt.

Result, immediately:

```
row 23:  V              <- vmstart entered, NO 'W'
CS=0018 EIP=299D VM=0 vec=06 v86frame=76CD:0000A1E1
CS=76CD EIP=A1E1 VM=1 vec=06
```

`vec=06`. That is the `mov cl,6` "unsupported opcode -> reflect int 6"
path. **The monitor treats `STI` as an invalid opcode.**

`V` without `W` is precisely the session-2 failure: vmstart entered,
killed by its `sti`.

## What this means

The V86 monitor in this `$386.SYS` emulates **only I/O instructions** —
exactly what the opcode dispatch table at `2776h`/`27E2h` contains
(IN/OUT, DMA port translation). It has no emulation for the
IOPL-sensitive instructions: `CLI`, `STI`, `PUSHF`, `POPF`, `INT n`,
`IRET`.

That makes IOPL=3 a deliberate, self-consistent choice: at IOPL=3 none
of those trap, so the missing emulation never matters. I/O still traps
via the TSS permission bitmap (`t2iopbm`), which is all the monitor can
actually handle.

But it is unresolvably at odds with the memory manager:

- `valloc` runs **in virtual mode by design** (`dovmrh`/`rhentry`
  dispatch, commented "call allocation routine in virtual mode") and
  re-enters native mode via `int 6fh` -> needs `INT n` to trap ->
  **IOPL < 3**
- the monitor cannot survive IOPL < 3, because vmstart's first `sti`
  traps and is reflected as `#UD`

Both cannot hold. **`$DPMI.SYS` cannot install in this build, and no
amount of work inside `_DPMI.ASM` changes that.**

## This also explains the original stall

The session-2 result (`V` but no `W`, vmstart killed by its `sti`) is
the same defect, reproduced on demand. The `nmswitch` guard and its
removal were both downstream symptoms. Removing the guard "fixed" the
boot only because at IOPL=3 the `sti` never traps at all.

So the corrected history is: there was never an `ivtable[6]==0`
reflection bug, and the guard never fixed anything. There is one
defect — an incomplete V86 monitor — and IOPL=3 hides it.

## Two ways forward

**(a) Implement the missing emulation.** Add `CLI`/`STI`/`PUSHF`/
`POPF`/`INT`/`IRET` to the monitor's opcode dispatcher with a virtual
interrupt flag. Correct, and what a real V86 monitor does. Substantial,
and every one of those instructions becomes a trap.

**(b) Keep IOPL=3 and give int 6Fh a path that still traps.** Hook
`IVT[6Fh]` with a small real-mode stub in `$386.SYS` that reaches
native mode by a mechanism which does trap at IOPL=3 — the I/O bitmap
being the obvious lever — then dispatch into the existing `i6f_tbl`.
Much smaller, and it leaves the working boot intact. Start here.

## Tree state

`uioplb` reverted to `00110000b` and rebuilt; the tree boots again
(`V123456`, `0070 04B6`, protected mode active, DPMI init reaching
`AllocateExtend`). The IOPL=0 rationale is kept as a comment above
`uioplb` for whoever revisits it.

---

# UPDATE 4 — eicommon frame measured; int 6Fh gateway built (untested)

## Measured: the frame, and why res16 is not what it looks like

Instrumented `eicommon` with three plain `mov`s (no flags touched, `ax`
not clobbered — `entint6f` reads `ax` immediately after):

```
sp_before = 0F8C   (= s0ip = p0stack-36, top of the 9-dword v86 frame)
bp        = 0F88   (= sp_before - 4)
sp_after  = 0F78   (= bp - 16)
```

`push bp` consumed **4 bytes**; the four following pushes consumed 16.
All five are 32-bit. The `[bp-4]`/`[bp-8]`/`[bp-12]`/`[bp-16]` comments
and the `bp = p0stack-40` landmark are correct.

**Why:** `gdtcode` has **d=1**, so `res16` *executes* 32-bit even
though MASM assembles it USE16. That is what the pervasive
`db 66h ; 16-bit data` comments mean — hand-forcing 16-bit operations
inside code that runs 32-bit.

Consequence: `dohexit`'s `pop bx` executes as `pop ebx`. `dohexit` and
`cgrm7` do the identical thing. **There was never a frame mismatch**
between the I/O trap path and the int 6Fh dispatch path.

### Do not conflate this with the `_DPMI.ASM` truncation fix

- `_386.ASM` / `res16` — declared USE16, **runs 32-bit** (d=1).
  Prefix-free `mov eax,...` executes as a genuine 32-bit move.
  Correct as written. **Do not "fix" it.**
- `_DPMI.ASM` / `INIT16` — genuinely runs 16-bit (real/v-86 driver
  init). Prefix-free `mov eax,...` really does truncate. That fix
  stands.

Same mnemonics, opposite meanings, depending on the descriptor the
code runs under.

## Built: the int 6Fh gateway (option b)

- port `0E0h` force-protected in `t2iopbm` at all three sites that
  already force `04h`/`81h` (byte `1Ch`, bit 0), including inside
  `vsetiop` so a task-supplied bitmap cannot clear it
- `doi6fgate` added to `dooutali`: advances `s0ip` past both bytes of
  `out imm8,al`, sets `debugint`/`iveccode` to 6Fh, and `jmps32 e6fa`
- `i6fstub` — real-mode/v-86 entry: `out 0e0h,al` to trigger the trap,
  then propagates CF into the caller's saved flags image at `[bp+6]`
  before `iret` (a plain `iret` would discard the handler's CF; a
  `retf 2` would preserve CF but leave IF as `int 6fh` cleared it)
- `IVT[6Fh]` hooked at init next to the existing int 13h hook, with
  `oldint6f` storage for the previous vector

Assembles clean: **0 warnings, 0 severe errors**. Hook verified live:
`IVT[6Fh] = 0070:01B8`, which is `i6fstub`.

## Status: gateway is UNTESTED — the guest never reaches it

Still hung at `[<`, markers `V123456`, no step 7. Sampling shows
`CS=5803`, VM=1, EIP scattered across the full 64K — never `CS=0070`
(the stub) and never `CS=0018` (the monitor).

So execution runs away **before** the `int 6fh` is ever reached,
somewhere between the far call into `rhentry` and `valloc`'s
`int 6fh`. The gateway may be correct or may not; it has not been
exercised.

Consistent with the history: `CS=0000` while `memman` was null, then
`CS=5803` from the moment `memman` began pointing at `rhentry`.
Calling `rhentry` is what triggers the runaway.

`rhentry` is at `04C9` and `memman` reads `0070:04C9`, so the pointer
is correct and the far call does land on it.

### Hypothesis worth testing first

`res16` contains code intended for **both** execution modes.
Prefix-free sequences are correct under 16-bit (v-86) execution;
`db 66h`/`db 67h` sequences are correct under 32-bit (native)
execution. The two are mutually exclusive for the same bytes.

`rhentry`/`valloc` are reached both ways — natively via `entint6f`,
and from v-86 via the `dovmrh` dispatch ("call allocation routine in
virtual mode") and now via `$DPMI.SYS`'s far call. If any prefixed
instruction lies on the v-86 path, those bytes invert meaning and the
code runs away. That would explain `CS=5803` exactly.

### Next step

Bracket with the video-marker technique, which has worked all session:
a marker at `rhentry` entry, one at `valloc` entry, one immediately
before its `int 6fh`, one in `i6fstub`, one in `doi6fgate`. That
localises the runaway to a single instruction range and simultaneously
tells us whether the gateway works once reached.

---

# UPDATE 5 — gateway built but unexercised; BUILD TRAP

## READ THIS FIRST: stale-EXE build trap

`exe2bin` rebuilds `$386.SYS` from a **stale `_386.EXE`** whenever
MASM fails: byte-identical output, fresh timestamp, no visible error.
Three builds were silently stale before the unchanged file size gave
it away.

**Always: `del _386.obj` + `del _386.exe`, assemble with a listing
(`masm _386,_386,_386;`), check the error count.** The `.ASM.SYS`
recipe has no error gate.

The error was `A2053: Jump out of range`. `dooutali`'s short jumps
have **zero headroom** — anything inserted between them and
`doout04i`/`doout81i`/`dooutald` breaks the build. The gateway body
therefore lives next to `i6fstub`, reached by a near jump, with only
the existing `jmp` retargeted (`jmp dooutali9`, same encoding size).

## Added to _386.ASM

- `0E0h` force-protected in `t2iopbm` at the three sites that force
  `04h`/`81h` (byte `1Ch`, bit 0), `vsetiop` included
- `i6fstub` + `IVT[6Fh]` hook at init, `oldint6f` for the old vector
- `dooutali9` / `doi6fgate`
- diagnostic markers: `R` rhentry, `A` valloc, `I` before its int 6fh,
  `S` i6fstub, `G` doi6fgate, `E` entint6f, `N` e6f05, `P` after
  nalloc; `eidbgsp`/`eidbgbp`/`eidbgsp2` frame capture; `e5dbgip`
  latch

## Two hypotheses disproved

1. **Per-task IVT remapping** — wrong. `CR3=00110000`,
   `PDE[0]=00111027`, `PTE[0]=00000067`: linear page 0 maps to
   physical page 0, identity mapped.
2. **rhentry/valloc are dual-mode code** — wrong. That range contains
   **zero** `66h`/`67h` prefixes; it is prefix-free 16-bit code, and
   `rhentry`'s stack discipline checks out by inspection.

## Marker results — NOT conclusive

Observed `R A I E N P`; `S` and `G` absent.

Naively that says int 6fh reaches the IDT dispatcher directly and the
gateway is unnecessary. **Do not bank it.** The markers do not
identify the caller — `E`/`N`/`P` fire on any `int 6fh` AX=7705h,
including the kernel's own memory-manager traffic.

Decisive against it: `s0ip` latched at `e6f05` entry reads **0000**,
not `05F2` (valloc's int 6fh) nor `05F4`. That trap had no v-86 frame,
so it was not our caller.

`R`/`A`/`I` are prefix-free 16-bit code, so those three ARE the v-86
DPMI path, and it still dies at or around its `int 6fh`.

`s0ip` is too volatile to sample live (a read at 24s returned a BIOS
timer context, `FFF8:D048`) — latch it at the handler.

## Status

Boot parks at `[<`; `AllocateExtend` never returns; marker 7 never
fires. Gateway installed and **unexercised**.

## Next

Gate `E`/`N`/`P` on the latched `s0cs` matching the DPMI driver's
segment, or latch `s0cs:s0ip` per entry. Until the caller is
identified the int 6fh question is open.

---

# UPDATE 6 — gateway proven UNNECESSARY; failure narrowed to one `ret`

## int 6fh from v-86 works. The gateway is not needed.

Caller-aware latch at `entint6f` (gated on `bp < p0stack-28`, the
existing native-vs-v86 discriminator, so kernel traffic cannot
overwrite it):

```
count=16  caller=0070:05F4  ax=7705
```

`05F4` is exactly the instruction AFTER `valloc`'s `int 6fh` at
`05F2`. So:

- **int 6fh from a v-86 task DOES reach the IDT dispatcher.** The
  "IOPL=3 severs int 6fh" conclusion is dead.
- **the return ip is correctly advanced.** The "monitor does not
  advance the v-86 ip" hypothesis is dead too.
- `i6fstub` / `doi6fgate` / the `0E0h` bitmap bit / the `IVT[6Fh]`
  hook are all **unnecessary** and should be reverted. `S` and `G`
  never fire because nothing needs them.

## Full marker chain

`M → R → A → I → E → N → P → Z → K → Q`

- `M` reaches the far call into memman
- `R` `A` `I` rhentry and valloc run, up to the int 6fh
- `E` `N` `P` dispatcher, native valloc handler, nalloc returned
- `Z` the far call RETURNS
- `K` AllocateExtend takes the **success** path (ax=0, cx non-zero and
  >= requested) — **the allocation genuinely succeeds**
- `Q` execution reaches the instruction immediately before the `ret`

**But marker 7 in InstallDriver never fires, and neither does marker
10 (ErrorHandler).** The `ret` executes and lands somewhere other than
`pushf / mov al,7`.

## Stack discipline verified by inspection (and it balances)

- `AllocateExtend`: `push cx` ... `pop ax` on every path; `ErrMem`
  pops `cx`, `ErrMem1` is reached after `pop ax`
- far `call cs:[memman]`: `rhentry` pushes bx, bp, rhe2, handler;
  restores bx/bp from `[bp+2]`/`[bp]`; `ret` consumes the handler;
  valloc's near `ret` consumes rhe2; `rhe2` pops the two saved
  registers into `pop_junk`; `rhe1` `retf`s
- `ExtendMem`/`ExtendHand` are CODE16 `005E`/`0060`, base 0 — correct
  offsets, no repeat of the OFFSET bug
- the marker blocks are push/pop balanced and disturb no flags

Inspection says the return address should be intact. It evidently is
not. **Read the value; do not reason about it.**

## Next

Latch `[sp]` inside the `Q` block (before its `push ax`, so the stack
is undisturbed) and read it against `InstallDriver`'s expected return
offset from the listing. That converts "the ret goes somewhere wrong"
into an address.

## Process notes (mine)

- A first attempt at the `Q` marker used an awk pattern that matched
  **every** `clc` in the file — 25 bogus insertions. Stripped; file
  verified clean. **Use `str_replace` with a unique anchor, not
  pattern-matching awk, for edits like this.**
- An apparent 300s hang was a `grep -c` written without a filename,
  reading stdin. The edit itself had already succeeded.

---

# UPDATE 7 — failure is a corrupted return address; SP is ODD on entry

## Marker chain (all fire)

`M R A I E N P Z K Q` — plus four PutHex readouts on row 23.

The allocation **succeeds** (`K` = success path: ax=0, cx non-zero and
>= requested). Execution reaches the instruction before
`AllocateExtend`'s `ret` (`Q`). But marker 7 in `InstallDriver` never
fires, and neither does marker 10 (ErrorHandler).

## The return address is wrong, and wrong EARLY

Expected return: INIT16 `03D0h` + INIT16 base `0E30h` = **`1200h`**
(`call AllocateExtend` is `E8 057D`, 3 bytes, at INIT16 `03CD`).

Measured, at BOTH sample points:

```
at Q (just before the ret)            : 6FEB
at Z (right after memman far call)    : 6FEB
```

Identical, so the return slot is **already wrong the instant
`call cs:[memman]` returns**. Corruption is in the memman call path,
not in `AllocateExtend`'s tail.

## SP is ODD on entry — this is upstream of everything

```
SP on entry to AllocateExtend : 0E07     <-- ODD
SP at Z                       : 2428
```

**`0E07` is odd.** The stack is already misaligned BEFORE
`AllocateExtend` is entered, i.e. upstream of the memman call
entirely. With an odd SP every subsequent push/pop/ret straddles word
boundaries, which is exactly how you get a plausible-looking but wrong
return address.

This reframes the failure: look earlier, in `InstallDriver`, not in
the memman path.

## What this data does NOT establish

The `0E07` -> `2428` delta is a wholesale change, not the small shift
predicted by an `rhentry` `pop_junk` imbalance. That hypothesis is
**neither supported nor refuted** by this measurement, because the two
samples may come from **different invocations** — `count=16` for
v-86-originated int 6fh, and the screen only shows the last value
written at each position. Nothing currently pairs them.

Do not read a stack-switch conclusion into that delta yet.

## Next

Two additions to the same run:

1. capture `SS` alongside `SP` at both points — distinguishes a stack
   switch from a shift
2. write a per-call sequence counter next to each sample — proves the
   two samples belong to the same invocation

Then chase the odd SP upstream in `InstallDriver`.

## Correction to UPDATE 6 notes

A worry that the `R`/`A`/`I` markers contaminated results via
`pushf`/`popf` (unimplemented in the monitor, opcode-table 0) was
**unfounded** — they already use `lahf`/`sahf`. Checked the file
rather than trusting recollection of an earlier edit.

---

# UPDATE 8 — nesting test inconclusive; session wrapped

Counters (`inc` at `eicommon`, `dec` at `cgrm7` and `dohexit`) read
`nestcur=124 nestmax=255`. **Inconclusive, not confirmation.**
`nestmax` is a `db` and saturated. `nestcur` drifting up shows only
that `eicommon` has exits bypassing both decrement sites (`contirq`,
`nmswitch`, `dovmint`/`dovmrh`) — the counter was unbalanced by
construction.

Redo with a word counter and a `dec` at every enumerated exit, or
instrument narrowly: flag on entry to the int 6fh handler, report if a
second trap arrives while set.

See `HANDOVER.md` for the consolidated state.

---

# UPDATE 9 — baseline set: nesting counter removed

## Change

`_386.ASM` only. Removed the UPDATE 8 trap-nesting counter:

- `inc`/`mov ch`/`cmp`/`jbe`/`mov` block at `eicommon`, its comment and
  the `eicnomax:` label
- the `dec` at `dohexit`
- the `dec` at `cgrm7`

`nestcur`/`nestmax` declarations left in place (removal shifts layout);
they are on the strip list.

`pcmos386-baseline.diff`, `patch -p1` from the repo root, on top of
`pcmos386-changes.diff`.

## Why — measured

| build | boot (testconfig: `MEMDEV=$386.SYS`, `DEVICE=$DPMI.SYS`) | runs |
| --- | --- | --- |
| UPDATE 8 (counter in) | `V W`, `>{}()]`, parks after `$386.SYS` returns; no pass-2 device markers; v-86 at `76CD:FC8x` | 2/2 |
| counter kept, CH use removed | same as UPDATE 8 | 1 |
| counter removed | `V123456 … RAIENPZK Q 6FEB 6FEB 0E07 2428 D120`, parks at `[<` on `$DPMI.SYS` — the UPDATE 7 screen | 2/2 |
| older binaries from the 09-17 tarball | same as counter removed | 3/3 |

No DPMI config, counter removed: live prompt, `VER` answers.

`$DPMI.SYS` was `DPMI.SYS.built` in every row; only `$386.SYS` varied.

## Consequences

- UPDATE 8's `nestcur=124 nestmax=255` is **void**: that build never
  loaded `$DPMI.SYS`.
- CH clobber is **ruled out** as the counter's failure mechanism.
- Open lead: an `inc`/`dec` at `eicommon` (flags, or layout shift)
  breaks the kernel's post-`$386.SYS` path. Contradicts the counter's
  comment that nothing downstream is flag-sensitive. Unmeasured.

## Verification

- 0 warnings, 0 severe errors, obj/exe deleted first, listing checked
- comment/label removal byte-identical to the tested code-only removal
- `DPMI.SYS.built` byte-identical to a fresh build of `_DPMI.ASM`

## Packaging note

The 09-17 tarball's `latest/$386.SYS` and `$DPMI.SYS` predated the
UPDATE 8 source it shipped with. Rebuild and `cmp` before trusting a
tree.

---

# UPDATE 10 — `$DPMI.SYS`: three 16-bit/32-bit encoding fixes; native-mode entry located

## Applied to the tree (`_DPMI.ASM`)

| change | why |
| --- | --- |
| `AllocateExtend`: `mov cx,EndProtect-BeginProtect+4095` / `mov ax,0` replacing the two `lea`s | the `lea`s referenced USE32 labels from a 16-bit segment; MASM emitted a 32-bit displacement with **no** `67h` prefix |
| `Init32Err`: `mov dx,offset ddt:No32` | group-relative, so the error message prints instead of memory |
| `Init32Code`: `db 67h` before `mov [DriverRealCS],ax` | same missing prefix; without it the last 2 bytes ran as `add [bx+si],al` |

All three are original TSL code, confirmed identical in upstream
`roelandjansen/pcmos386v501` master.

## The `6FEB` corruption — root cause

Executed as 16-bit code, `AllocateExtend`'s two `lea`s desynchronise the
instruction stream:

```
13E0  lea cx,[di] / and bx,[0000] / lea ax,[di] / push ax
13E9  add [bx+si],ax / add [bp+di],ch
13ED  enter 0E9C1h,12          <- the "sub cx,ax / shr cx,12" bytes
13F1  push cx
```

`ENTER 0E9C1h,12` accounts for three independently measured values: SP
`0E07` -> `242A` (push + bp + 11 nesting words + frame pointer, minus
`0E9C1h`), saved bp `0E03`, and the return slot at `[242A]` reading `6FEB`.

**Measured after the fix:** return slot `1200` (expected), SP at Z `0E05`
(entry minus the `push cx`, balanced), install markers `V123456789:;`, boot
reaches the `[A:\]` prompt, driver reports `Not Installed.` /
`Protected Code Initialization failed.`

## Monitor findings (no `_386.ASM` change)

- The v-86 trap path is clean: across 2054 v-86 traps the monitor returns
  SS:SP exactly (reflected interrupts -6, int 6Fh unchanged). The `s0`
  single-frame hypothesis is **refuted for the failing call**.
- `int 0D4h AH=10h` from a v-86 task is handled by **`$386.SYS`**
  (`entintd4` -> `nmswitch`), not the kernel: it is the v-86 -> native
  switch. The same function from native mode reaches `einfun90`, the
  switch back. `_DPMI.INC`'s empty `goprot`/`goreal` are these two calls.
- `eixtable` also offers `11h` allocate-extended-memory-with-selector,
  `12h` deallocate, `13h` gdt alias. `dtitable` already supports permanent
  (`0FEh`) descriptors.
- `einative` dispatches only vectors `38h`/`D4h`/`21h`, so int 6Fh from
  native mode is reflected to the never-hooked real-mode vector. This is
  why `InitProtect`'s `SegToSel` fails **once `goprot` works**.
- The kernel's `mosint38` has `dw 0` for functions `10h`-`15h`: it returns
  `AX=1` with carry set. `GoProtect` never tests carry.

## Not applied: `goprot`/`goreal` (`_DPMI.INC`)

Implemented and measured (`goprot-goreal.diff`): the switch works — the
task becomes `vm=0`, ring 3, 32-bit (`cs=007b`, `ss=0073`) and
`InitProtect` executes as 32-bit code for the first time. It then calls
int 6Fh `7786h` from native mode, gets reflected, and the task dies. Boot
parks at marker 8.

Held back because on its own it turns a clean failure into a hang. It
should go in together with the driver-side `scbsel` change (C2a in
`pcmos386-protected-mode-entry-design.md`).

## Corrections to earlier records

- The addendum's "`SegToSel` -> int 6Fh `7786h` -> emulator crash" was
  **unreachable** in the UPDATE 9 tree: `InitProtect` never ran as 32-bit
  code. With `goprot` implemented the reflection is real again, now
  measured directly.
- `InitProtect` is incomplete beyond `SegToSel`: its `rep movsd` runs with
  ESI, EDI and ES never set by anyone.

---

# UPDATE 11 — `_DPMI.ASM` diagnostics stripped; `_386.ASM` strip blocked by a load-bearing marker

## Applied: `_DPMI.ASM` stripped clean

Removed: `WriteLog` and its 11 call sites, `Counters`, the `Mk*` marker
strings, `LogHandle`/`LogInited`/`LogName`, `PutHex` and every readout
(SP/SS on entry and at Z, return-address slots, the two `int 21h` ah=30h
version dumps, the memman far-pointer dump), the `M`/`Z`/`K`/`F`/`Q`
markers, `callseq`, `retdbg`, the row-22 sequence counters, the
`0040:00F2` segment record, and the project-added `DevLoadMsg`.

**Also restored:** the driver's own sign-on print, which had been
commented out while the screen-garbage cause was unknown, now with
`offset ddt:Copyright`. Measured output:

```
PC-MOS DPMI Driver Version 1.00 (910430)
(C) Copyright 1991, The Software Link, Incorporated.
...
Dos Protected Mode Insterface Not Installed.      (typo original)
Protected Code Initialization failed.
```

This independently confirms the UPDATE 10 diagnosis: the garbage was the
segment-relative `OFFSET` defect, not the print.

Verified: 0 severe errors; `DEVICE=$DPMI.SYS` boot reaches `[A:\]` with
the text above; no-DPMI boot answers `VER`.

## Not applied: `_386.ASM` strip — removing the `R` marker breaks the boot

Stripping `_386.ASM` stops the boot right after `$386.SYS` loads (no
pass-2 drivers, no prompt). Bisected to **one block**: the `R` marker in
`rhentry` (11 lines, row 23 col 41).

| variant | result |
| --- | --- |
| all markers removed | parks after `$386.SYS` |
| `eicommon` latches restored, rest stripped | same |
| `S`+`G` (gateway markers) removed only | boots fine |
| `R` block removed only | parks after `$386.SYS` |
| `R` removed, replaced by 16 NOP bytes (image byte-size identical) | parks |
| `R` block kept, writing to `B000` instead of `B800` | **boots fine**, no marker on screen |

So the dependency is on **those instructions executing**, not on the
write target and not on code layout or image size. NOPs of the same byte
count are not a substitute. The block is `push ax/push es/lahf/push ax/
mov ax,<seg>/mov es,ax/<two byte writes>/pop ax/sahf/pop es/pop ax` — no
net register or flag effect.

Untested next discriminators: a block with the segment load but no write;
a block with a write to ordinary RAM; an equivalent-length delay that
touches no memory. This is the third time this code has proved sensitive
to a change that should be inert (see UPDATE 9's nesting counter), and it
may be the same underlying fragility.

**Interim:** `_386.ASM` keeps its markers. They are visible but harmless;
because they write absolute video cells, they appear in scrolled shell
output.

## Correction to the strip list

The handover said to strip "the whole gateway". **Wrong — it is
load-bearing.** `i6fstub` is hooked into IVT[6Fh] and its `out 0e0h` is
the only path from a v-86 int 6Fh into the dispatcher (`doi6fgate` ->
`e6fa`); every DPMI memman call was traced through it. Only its `S` and
`G` markers are diagnostic, and removing just those is verified safe.
