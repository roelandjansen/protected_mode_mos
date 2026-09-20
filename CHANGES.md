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

---

# UPDATE 12 — kernel diagnostics stripped; screen is clean

## Applied: `MOSDDINT.ASM` + `MOSINIT2.ASM`

Removed 13 BIOS-teletype marker blocks (the `[`, `<`, `>`, `{`, `}`, `(`,
`)` bracket noise that prefixed every driver-load line) and 3 BIOS-data-area
recorder blocks (`0040:00F5` etc., read back via DUMPLOG), plus their
comment blocks. `kernel-strip.diff`.

Both are single regular shapes, and the strippers only remove a block when
**every** line in it is a marker instruction:

```
push ax / push bx / mov al,'X' / mov ah,0eh / xor bx,bx / int 10h / pop bx / pop ax
push ax / push es / mov ax,40h / mov es,ax / ... / mov es:[0f5h],ax / pop es / pop ax
```

## Kernel build path (new)

`MAKEMOS.BAT` cannot be used as-is: it starts with `del $*.*`, which would
wipe `$386.SYS`, `$DPMI.SYS` and every other built driver in `latest/`.
The rig now drives `make -f KERNEL.MAK $$MOS.SYS` directly, deleting only
the named `.OBJ`s and `$$MOS.SYS`. The kernel target links `mosfront` +
the common list + `mosinit2` + `mosback`, then converts with
`debug <exe2bin.dat`.

**The tree's `$$MOS.SYS` was stale**, as the drivers were: 129457 bytes
shipped vs 130225 rebuilt from unmodified sources. The rebuilt unmodified
kernel was boot-verified identical **before** any edit, so the strip is
measured against a real reference and not against a stale binary.

## Measured result

Screen is clean end to end — no bracket prefixes, no marker characters
from the kernel:

```
Loading $386.SYS  version 5.01  (921119)
486 Protected mode and paging are now active.
  640K RAM found in first megabyte;
16000K total RAM found;
  640K allocated to first megabyte.
PC-MOS DPMI Driver Version 1.00 (910430)
(C) Copyright 1991, The Software Link, Incorporated.
Dos Protected Mode Insterface Not Installed.
Protected Code Initialization failed.
5K SMP #1 allocated;     3K of SMP #1 allocated to device drivers.
```

No-DPMI boot: date/time prompts, `$$SHELL.SYS version 5.04`, live prompt,
`VER` answers.

Tree kernel is byte-identical to the verified scratch build.

## Still present

`_386.ASM`'s markers only (`V`/`W`, `R`/`A`/`I`/`E`/`N`/`P`, the `ZQ`
bisection set). They write absolute video cells, so they land in scrolled
output at rows 22-23. Blocked by UPDATE 11: removing the `R` marker alone
stops the boot.

---

# UPDATE 13 — `_386.ASM` diagnostics stripped; UPDATE 11's conclusion RETRACTED

## Retraction

UPDATE 11 reported that the `R` marker in `rhentry` was **load-bearing**:
removing it stopped the boot, and that survived a NOP-padding test and a
`B000`-vs-`B800` test. That conclusion was **wrong**. The fault was in my
stripper, not in the code.

The `R`/`A`/`I`/`E`/`N`/`P` blocks contain an **inner** `push ax`/`pop ax`
around `lahf`/`sahf`:

```
push ax / push es / lahf / push ax / mov ax,0b800h / mov es,ax
mov byte ptr es:[0eb2h],'R' / mov byte ptr es:[0eb3h],07h
pop ax / sahf / pop es / pop ax
```

The filter matched from the first `push ax` to the **first** `pop ax` —
the inner one — and deleted that span, leaving `sahf / pop es / pop ax`
behind. Three stray pops on the trap path, hence the hang. The
NOP-padding and `B000` tests were consistent with that too: both left the
block's pops balanced.

Removing the block properly (all 12 lines, balanced) boots fine. So there
is **no** unexplained sensitivity here, and the "third inert change that
broke the code" framing in UPDATE 11 and the addendum does not stand. The
UPDATE 9 nesting-counter result is unaffected: that was a source-level
change, measured 2/2, not a stripper artefact.

## Applied

`_386.ASM` stripped: 15 marker blocks (`S`, `G`, `R`, `A`, `I`, `E`, `N`,
`P`, and the 7 `ZQx` bisection markers), the `V`/`W` vmstart markers, the
`eidbgsp`/`eidbgbp`/`eidbgsp2` latches, the `e6dbg*` caller latch with its
`e6fnolatch` label, the `e5dbgip` latch, all the declarations including
`nestcur`/`nestmax`, and 13 orphan comment blocks. 10574 -> 10260 lines.

The gateway (`i6fstub`/`doi6fgate`/`dooutali9`) is **kept** — it is
load-bearing, as UPDATE 11 correctly noted; only its `S`/`G` markers went.

Verification, beyond the build gate:

- global `push`/`pop` balance of the stripped file is `-8`, **identical to
  the original**, which is what the first stripper would have failed
- `eicommon` reads exactly as it should: `pop ss:[trash1]` / `push bp` /
  `mov bp,sp` / `push ds` / `push es` / `push cx` / `push bx`
- 0 warnings, 0 severe errors; tree `$386.SYS` byte-identical to the
  verified scratch build

## Measured result — the screen is completely clean

```
Loading $386.SYS  version 5.01  (921119)
486 Protected mode and paging are now active.
  640K RAM found in first megabyte;
16000K total RAM found;
  640K allocated to first megabyte.
PC-MOS DPMI Driver Version 1.00 (910430)
(C) Copyright 1991, The Software Link, Incorporated.
Dos Protected Mode Insterface Not Installed.
Protected Code Initialization failed.
5K SMP #1 allocated;     3K of SMP #1 allocated to device drivers.
[A:\]
```

No-DPMI boot: date/time, `$$SHELL.SYS version 5.04`, live prompt, `VER`
answers. No diagnostics remain in `_386.ASM`, `_DPMI.ASM`,
`MOSDDINT.ASM` or `MOSINIT2.ASM`.

---

# UPDATE 14 — `$DPMI.SYS` installs; the use32/use16 call defect

First time the driver initializes. `Dos Protected Mode Insterface
Installed.`, boot continues through SMP allocation to `[A:\]`, no-DPMI
boot unaffected. Kernel files unchanged.

## Applied

`_DPMI.INC`

| change | why |
| --- | --- |
| `goprot` = `mov ax,1001h` / `int 0d4h` | `$386.SYS`'s `entintd4` routes `ah=10h` from a v-86 task to `nmswitch`: 32-bit, ring 3, segments aliased as `g=1,d=1` descriptors |
| `goreal` = same call, with `db 66h` | dispatched by mode to `einfun90`. Runs under `d=1`, where `B8 01 10` takes a 32-bit immediate and swallows the following `CD D4` — measured as `eax=d4cd1001` |

`_DPMI.ASM`

| change | why |
| --- | --- |
| SCB segment -> selector moved into v-86, before `goprot` | `einative` dispatches only vectors `38h`/`D4h`/`21h`, so int 6Fh from native mode never reaches the `77xx` tables |
| size computation moved into `InitProtect` (INIT32) | it was in INIT16 but executed after `goprot` with `d=1`, so every operand size was inverted: ECX came out 0 and the native ESP was garbage |
| `InitProtect` completed | ES from the monitor's `ah=11h` service (allocate extended memory, returns a permanent `0FEh` selector), ESI = `offset ddt:BeginProtect`, EDI = 0. The original `rep movsd` ran with ESI, EDI and ES never set by anyone |
| `mov dx,offset ddt:Dpmi2f` in `SetVectors` | segment-relative `offset` installed the int 2Fh vector `0E30h` low |

`_386.ASM`

| change | why |
| --- | --- |
| `nca32`, `mgd32` wrappers in `res16`; `nca_ptr`, `mgd_ptr` dword pointers; `e6f86` calls through them | see below |

## The defect class: use32 -> use16 calls

MASM cannot encode a call from a `use32` segment to a label in a `use16`
one. It emits a `66h` operand-size override **together with a `rel32`
displacement**. The cpu takes `rel16` and executes the trailing two bytes.
In `e6f86` that was `66 e8 63 f9 ff ff`, and the stray `ff ff` was the
`#UD` at `0018:3AB2` that killed every `7786h` call.

Removing the `66h` prefix fixes the decode but breaks the contract:
**both `addrnca` and `makegdte` end with a `66h`-prefixed `ret` and pop 2
bytes.** A 4-byte push against a 2-byte pop leaks 2 bytes per call. Two
calls, 4 bytes, and `cgrm7`'s `pop ebx/ecx/es/ds/ebp` then read straddled
values — which is exactly the "caller's registers come back shifted by a
word" symptom, BP included.

Measured, same call, before and after:

```
in:   eax=7786 ebx=d000 ecx=0001 edx=3005  bp=0e67  esp=0fc8
bad:  ax=3005  bx=7786  cx=005b  dx=0240   bp=0000  esp=0fc6
good: eax=7786 ...                          bp=0e67  esp=0fc8, [bp-16]=005b
```

The fix is a wrapper in `res16` per callee, reached by a normal 32-bit
indirect call through a dword pointer, doing the 16-bit call itself. An
indirect call with a `66h` override does **not** work: measured, it still
pushed 4.

This class has now produced five bugs across `_386.ASM`, `_DPMI.ASM` and
`_DPMI.INC`. Treat any transfer between `res16` and `res32`, and anything
executing after `goprot`, as suspect until its encoding is checked **in
the linked binary** — the listing shows pre-link values and can look right
when the bytes are wrong.

## Retractions

- **`e6f86`'s BP frame is fine.** An earlier note here claimed `bp=0` in
  the handler, from instrumentation that never compiled in; the reported
  values were the initialisers. Measured from the emulator side:
  `bp=0fd8`, `[bp-16]=0000d000` (caller's BX), `[bp-12]=00000001`.
  Anything inferred from the `bp=0` reading, including the idea that these
  handlers exchange registers through `ntrash*`, is withdrawn.
- **`makegdte` does not return 32-bit.** It ends `db 66h` / `ret`, same as
  `addrnca`.
- **`nxtdrvr` is untouched and still unvalidated.** The null-segment
  dispatch (`les bx,[bp-28]` reading `0000:0000`, `#GP` loop at
  `0000:0008`) was BP corruption upstream, not a chain-walk bug. Two
  `MOSDDINT.ASM` edits made while chasing it are reverted, and the install
  was re-verified against the tree's own kernel binary.
- The int 2Fh vector fix is real but was not the hang either.

## Not bugs

- `0000000K of Extended Memory Available.` — original TSL behaviour.
  `MsgMem` is defined and printed; nothing ever writes the digits.
- `install not done` — a hardcoded `ECHO` in the test `AUTOEXEC.BAT`.

## Next

C4, the client path. `GoProtect` is reachable through int 2Fh `1687h` but
never tests carry after `int 0D4h ah=10h`, so a client whose switch fails
believes it succeeded. Testing needs a DPMI client binary running under
MOS — the first item here that cannot be checked by watching a boot.

---

# UPDATE 15 — C4: clients reach protected mode; no code selector exists for them

The mode switch works for a real client. The remaining blocker is
architectural, not a coding defect, and `GoProtect` now refuses cleanly
instead of dropping the client into a context it cannot execute in.

## New: `DPMITST.ASM` / `DPMITST.COM`

A minimal DPMI 0.9 client, built by `MAKEUTIL.MAK` (rule added, and
`DPMITST.COM` added to `ALL`). It queries the host with int 2Fh `1687h`,
prints everything the host reports, shrinks its own memory block,
allocates the host data block, calls the mode-switch entry, and reports
which side of the switch it ended up on. First test in this project that
needs a binary rather than a boot observation.

Current output with the driver loaded:

```
DPMITST - DPMI 0.9 client test
  1687h ax   : 0000
  entry      : C0DE:00A6
  flags (bx) : 0001
  version(dx): 0100
  paras  (si): 0005
  calling the mode-switch entry...
  returned with carry SET: switch refused, still real mode
```

## Applied to `_DPMI.ASM`

| change | why |
| --- | --- |
| `mov di,offset ddt:GoProtect` in the `1687h` response | plain `offset` is segment-relative: clients were handed an entry point low by the group base |
| carry test after `int 0D4h ah=10h` | the switch can be refused (`$386.SYS` declines, kernel returns `ax=1` carry set). The old code fell through and told the client it had switched |
| `GoProtect` refuses up front, carry set | interim; see below |

## Measured: the switch works

`DPMITST` calling the entry produces a real transition — `int 0D4h
ax=1001h` from v-86 at `cs=C0DE`, returning `vm=0`, `cpl=3`, `cs=006B`,
`ds=es=ss=005B`. The client is genuinely in 32-bit protected mode at
ring 3.

## Measured: there is nothing for it to return to

GDT, read live (`gdt` at image offset `17C0h`, cs base `0700h`):

| selector | base | access | meaning |
| --- | --- | --- | --- |
| `005B` | `0008AA0` | `F2` | data, dpl 3 — the client's own segment |
| `0063` | `0007060` | `F2` | data, dpl 3 |
| `006B` | `000C0DE0` | `FA` | **code**, dpl 3 — the *driver's* segment |

DPMI requires the client to resume at a code selector for its own code.
`nmswitch` builds its code descriptor from whatever was executing at
switch time — the host, since the client got there by far-calling
`GoProtect` — and `makegdte` (behind `7786h`) builds data descriptors
only (`dl=11110010b`). Returning to either `005B` or `0063` aborts:
measured, `IRET: CS selector beyond limits`.

Two further `GoProtect` defects found on the way, both unreachable until
now: its post-switch tail did `mov cs:[OrgCS],ax`, a write through CS,
impossible in protected mode (`#PF` at offset `00E4`, task torn down);
and it read the new selector from `gs` when the pre-switch code had
loaded `fs`.

## What unblocks C4

The host must be able to create an **executable** descriptor for a
client's code segment. Either:

- a code-descriptor variant of `makegdte`, reachable through a new
  `7780h`-block function, or
- have `nmswitch` build the client's CS from the caller's return frame
  rather than from the current CS.

Both interact with descriptor lifetime: `cleardti` frees task-owned
descriptors on every `nmswitch`, and `7786h` hands out task-owned ones,
so anything given to a client has to be permanent (`0FEh`). That
decision is still open — see `pcmos386-protected-mode-entry-design.md`,
section 7.

## Interim behaviour

`GoProtect` returns carry set immediately. The client stays in real mode,
survives, and the shell continues. The code below the refusal is intact
and commented, ready for when a code selector can be supplied.

---

# UPDATE 16 — a DPMI client runs in protected mode on its own code selector

`DPMITST` now switches and resumes executing its own code with
`cs=008B`, `cpl=3`, `vm=0`. The client survives, the shell returns.

## New: int 6Fh `778Eh` CODE_SELECTOR (`_386.ASM`, `_DPMI.INC`)

Sibling of `7786h`, but the descriptor is executable+readable
(`dl=11111010b`) instead of data. `makegdte` compares the access byte as
well as the base, so it does not collide with the data alias of the same
segment.

`makegdte` hardcodes `00c0h` (`g=1,d=1`). The caller passes the wanted
bitness in `cl` — 0 for 16-bit, which clears G and D and keeps the byte
limit; nonzero leaves the 32-bit descriptor alone. `GoProtect` passes the
client's own declaration, which DPMI hands it in `ax` at the entry point.

`778h`-block numbering: `88h`-`8Dh` are already named by TSL
(GET/SET_PROT_EXCEPTION, GET/SET_REAL_EXCEPTION, CREATE_ALIAS,
ALLOC_SPEC_SELECTOR), so the table gains unimplemented entries for those
and the new function sits at `8Eh`.

## `GoProtect` rebuilt (`_DPMI.ASM`)

| change | why |
| --- | --- |
| bp frame, not `cs:[OrgIP]`/`cs:[OrgCS]` | after the switch this code runs in protected mode, where cs is not writable. The old `mov cs:[OrgCS],ax` faulted at offset `00E4` |
| request a code selector before switching, patch it into `[bp+4]` | `nmswitch` builds its code descriptor from whatever ran at switch time — the host. The client needs one for its own segment |
| keep the real-mode cs in `fs` for the failure path | so the frame can be put back if the switch is refused |
| discard the saved fs after the switch, `add sp,2` | restoring a real-mode segment value into fs faults in protected mode |
| `66h` on every pop and on the far ret | `nmswitch` gives the host a 32-bit cs, so the tail decodes with 32-bit operand size while the values were pushed 2 bytes wide before the switch |

## Measured

```
00001628 INT 21 t=1 eip=000001de vm=0 cpl=3 cs=008b ss=005b:0000fffc eax=00000900
```

That is `DPMITST` itself, in protected mode, on the 16-bit code selector
`008B` built by `778Eh`, issuing its own `int 21h`.

## Known and expected: DOS calls do not work yet

The client's `int 21h ah=09h` prints garbage. `dx` is now an offset into
a selector, and the call is serviced as a real-mode DOS call. A DPMI host
has to catch client DOS and BIOS calls, translate pointer arguments from
selectors to real-mode segments, run them in v-86 and pass results back.
Nothing implements that. It is the next milestone and the bulk of what a
host actually does.

## Bug of my own, recorded

The last failure before this worked was mine: `push fs` in 16-bit mode
pushes 2 bytes and the tail discarded 4, leaving the frame two bytes off
so the far return loaded `cs=0000`. Found by dumping the stack at the
`retf` rather than reasoning about it — `[esp]: 008b 0000 aa4d 0508`
showed it immediately.
