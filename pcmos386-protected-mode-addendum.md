# PC-MOS/386 Protected-Mode Assessment — Addendum

Follow-up to `pcmos386-protected-mode-assessment.md`. That doc's static
read of `_DPMI.ASM` characterized the 0.9-heritage core (LDT management,
translation services, DOS memory, interrupt vectors) as "genuinely
implemented, far more complete than a stub." This session traced what
actually happens when that code runs for the first time — first by
reproducing a garbage/beep bug on boot, then by chasing it to ground —
and that characterization needs a real correction. Static reading
("there's code here, not a bare `ret`") isn't the same as "this works,"
and this session is the concrete evidence why.

## Starting symptom

`DEVICE=$DPMI.SYS` in `CONFIG.SYS`, alongside a working `MEMDEV=$386.SYS`
+ `FREEMEM=` setup (9 tasks, ~612K each, both confirmed working — see
`pcmos386-config-sys-tuning.md`), produced garbage text and continuous
PC-speaker beeping during boot, then continued on to a live, working
`[A:\]` prompt. Not a hang, not a crash — a repeating, self-terminating
glitch.

## Root cause #1: `CheckFor386SYS` checks a bit `$386.SYS` never sets

`_DPMI.ASM`'s `CheckFor386SYS` (part of `InstallDriver`'s init chain)
requires `scbmmfea` bit `40h` ("io protection enable" per its own
comment). That field is populated by the kernel copying 14 words
straight out of `_386.ASM`'s `parmfeat` value during `MEMDEV=`
registration (`MOSINIT2.ASM`, `mminit`, the `rep movsw` around line
5017). `_386.ASM`'s `parmfeat` is `0B600h` (or `0F600h` with `INT6`
defined) — and its own comment block documents every bit it uses, all
in the high byte (`0200h`–`8000h`). Bit `40h` (low byte) is never set,
by design — `_386.ASM` doesn't implement the capability this specific
bit represents. `CheckFor386SYS` was checking for something this
`$386.SYS` build never advertises, so it fails unconditionally, every
time, regardless of configuration.

**Considered fix:** add bit `40h` to `_386.ASM`'s `parmfeat`. Rejected —
that bit isn't DPMI-specific. The kernel itself gates two unrelated
subsystems behind it (`MOSINIT2.ASM` lines 3940 and 4858: timer/counter-
chip I/O trapping, and keyboard-rate-control setup). Setting it would
silently activate currently-dormant kernel behavior well beyond DPMI,
with no way to validate the consequences in the time available.

## Root cause #2: the kernel never checks a failed character-driver's actual status

Independent of the above, and worth fixing regardless: `MOSDDINT.ASM`'s
`ddinit0`, for character-mode devices, had:
```
ddi0a:
    call    moscdint    ; character device (look for standard devices)
    xor     al,al       ; no errors possible in moscdint
ddi0b:
    ret
```
The comment says it outright — this path unconditionally reports success
to the kernel's loader, regardless of what the driver itself reported in
its own request-block status word. So when `_DPMI.ASM` correctly detects
the `CheckFor386SYS` failure, prints its own error text, and reports
failure — the kernel ignores that and proceeds to link the driver in as
if it had installed successfully. It then calls `calc_size`/
`adj_smp_alloc` to compute the driver's resident size from request-block
fields (`+14`/`+16`, the break-address offset/segment) that were never
initialized, because `InstallIt` — the only code that sets them — never
ran. That uninitialized read is what cascades into the garbage/beep:
something ends up printing (or reflecting through) memory it has no
business touching, and by chance some of those bytes are `0x07` (BEL),
hence the beeping.

**Fix applied** (`MOSDDINT.ASM`, kept in the tree): check the driver's
actual status word, but conservatively — treat only the one confirmed
failure signature (status left at exactly `0`, which is what
`_DPMI.ASM`'s `ErrorHandler` produces, and also what an untouched
request block starts as) as failure. Deliberately *not* an exact-match
check against the "done" convention (`0100h`, confirmed via `_EMS.SYS`'s
own `or word ptr es:[bx+03],0100h`) — other character drivers may
legitimately set additional bits alongside it, and a stricter check
risked misclassifying drivers that currently work correctly. This is a
real, general kernel correctness fix, independent of DPMI.

## What fixing #1 uncovered: `SegToSel` has no working implementation

With `CheckFor386SYS`'s bit-`40h` check removed (requiring only
`scbmmfg='Y'`), `_DPMI.ASM` proceeds past the point it had always failed
at before, into `AllocateExtend` → `InstallIt` → `Init32Code` — the
actual protected-mode flip (`goprot`/`InitProtect`/`goreal`). This is
something the driver had never successfully attempted in any testing
this session. Attempting it **crashed DOSBox itself** — not a guest-level
fault, an unhandled C++ exception terminating the emulator process.
Confirmed reproducible.

Traced to `InitProtect`'s first real instruction: `call SegtoSel`
(name is `SegToSel`, MASM is case-insensitive — an early false alarm in
this session's own tracing). `SegToSel`:
```
SegToSel proc near
    push ebx
    mov  bx,ax
    mov  ax,SEGMENT_SELECTOR    ; equ 7786h, in _DPMI.INC
    int  6fh
    jc   short SegSel1
    mov  ax,bx
SegSel1:
    pop  ebx
    ret
SegToSel endp
```

Called while genuinely in native protected mode (post-`goprot`).
`_386.ASM`'s native-mode `int 6Fh` handler (`entint6f` → `einative`,
since `iveccode=6Fh` matches none of the special-cased `38h`/`0D4h`/`21h`
vectors) has no recognized handler for `AX=7786h` — the only in-range
native-mode VCPI/DPMI codes are `7700h`–`770Fh` (16 entries,
`i6f_tbl_entries`). It falls through to the generic fallback,
`einstand` → `dovmint`, which reflects the interrupt into a freshly
constructed V86 context, built by reading the **real-mode** interrupt
vector table entry for whatever vector was called (`6Fh*4`). Confirmed
via exhaustive search: nothing in this codebase (`_DPMI.ASM`, `_386.ASM`,
`_EMS.ASM`, kernel) ever hooks real-mode `int 6Fh`. So `dovmint` builds a
V86 re-entry pointing at whatever DOSBox's BIOS leaves that
never-initialized vector as — the exact byte value wasn't confirmed
(would need a BIOS-level probe outside this tree), but the practical
result is definitive: this crashes the emulator, confirmed by direct
reproduction, and would fail even if it *didn't* crash — nothing at that
target address is legitimate code.

**This is not a narrow bug.** `SegToSel` is called from four places:
- `SegToDisc` (DPMI function `0002h`, "Map Real-Mode Segment to
  Descriptor") — line 587
- `AllocDOSBlock` (DPMI function `0100h`, allocate DOS memory) — line
  1115
- `GetDataSelector` — twice, lines 3326 and 3335

`GetDataSelector` is almost certainly called near the start of most
meaningful `int 31h` operations, to establish the driver's own data
selector before doing real work. If it's broken, most of the driver's
runtime functionality is broken with it — not just the four call sites
directly, but everything downstream of them. This corrects the earlier
assessment: the 0.9-heritage core has real code, not stubs, but that
code shares one foundational, unguarded, broken primitive. It was
clearly trusted to work (called with no error handling in three of the
four sites) and doesn't.

**What a real fix needs:** `SegToSel` needs an actual implementation —
something that builds a genuine GDT descriptor for the given real-mode
segment (base = segment×16, limit = `0FFFFh`, standard data-segment
access rights) and returns its selector, likely modeled on whatever
`CreateAlias`/`AllocateLdt` already do correctly for LDT descriptors,
adapted for the GDT. Not attempted this session — deliberately, since
`InitProtect` doesn't check `SegToSel`'s result at all, so a quick
patch that stops the crash without a genuinely correct implementation
would produce a worse failure mode than today's: DPMI reporting
"Installed" successfully while actually broken, failing later, less
predictably, whenever a real client tried to use it. A loud, correct
failure beats a silent wrong success.

## Current state of the tree (mid-investigation — NOT the safe end state)

**Important:** the tree right now has a NARROW `msdd5a` bypass applied
(skips only the `origroot2`/`scbnul` sub-block, keeps the simple
`[scbdrvr]=origroot` restore) — and per the correction above, **this
combination still crashes.** It is not safe. Before stopping, revert
`MOSDDINT.ASM`'s `msdd5a` back to its fully original form (remove both
bypass lines) and re-decide between: (a) also revert `ddinit0`'s
status check, back to yesterday's known-safe state (garbage-but-no-
crash), or (b) keep pushing on the `scbdrvr`-offset theory now that
it's precisely bounded.

- **`_DPMI.ASM` `CheckFor386SYS`: refuses explicitly**, honestly
  labeled (`NotFin` message).
- **`_DPMI.ASM` `ErrorHandler`: writes safe break-address values** on
  every failure path. Keep regardless of what happens with the items
  below — harmless, strictly safer than leaving those fields
  uninitialized.
- **`MOSDDINT.ASM` `ddinit0` status-word check: currently RE-APPLIED**
  (honest failure reporting restored) for this bisection. Combined with
  the `msdd5a` bypass below, confirmed safe. Combined with the
  *original* `msdd5a` (unbypassed), confirmed to crash — do not ship
  that combination.
- **`MOSDDINT.ASM` `msdd5a`: currently BYPASSED** (`jmp short msdd7`
  right at entry) — diagnostic only, confirms the isolation but is not
  a correct fix (skips unlinking a failed driver entirely).
- **Diagnostic instrumentation left in place** in `_DPMI.ASM`
  (`WriteLog`, `Counters`, the `0040:00F0` segment-recording write in
  `InstallDriver`) — harmless, useful groundwork for either follow-up
  project below.
- **`MAKEUTIL.MAK`: case-sensitivity fixed** — worth checking whether
  the same mismatch exists for other entries (`_386.sys`, `_ems.sys`,
  etc.) if any of those sources are ever edited.

## Net result

Two genuine, distinct, well-scoped follow-up projects are now
documented, both precisely bounded rather than vague:

1. **`SegToSel` has no working implementation** (root cause behind the
   original `AllocateExtend`/`InitProtect` crash path, before
   `CheckFor386SYS` was made to refuse explicitly). Needs a real GDT
   descriptor builder.
2. **`mosddint`'s `origroot2` capture/restore is inconsistent** between
   `CONFIG.SYS`-time and `ADDDEV`-time driver loading, corrupting the
   `scbnul` sentinel on the one path (a character driver genuinely
   failing during boot) that had apparently never been exercised
   before `ddinit0`'s status-word check made real failures visible for
   the first time. Needs `if_scbnul`'s two call sites traced against
   `[scbdrvr]`'s actual boot-time value to confirm, then a correct
   fix (not a bypass).

Both are self-contained enough to pick up independently, whenever.

## Resolved: the `$386.SYS`-alone crash was sandbox-specific

The apparent `MEMDEV=$386.SYS`-alone crash noted during this session's
own verification pass did not reproduce on a real run: default config
(no DPMI) built and booted cleanly. Confirms that was sandbox
environment noise from a long session with many repeated DOSBox
launches, not a real finding. Not investigated further.

## Independent confirmation: `SegToSel` crash reproduces, with more detail

A real run with `DEVICE=$DPMI.SYS` added produced a full DOSBox abort
log (dosbox-staging build, more detailed than the vanilla 0.74-3 used
for this session's own testing):

```
Illegal write to 1000000, CS:IP  18:4dd4
Illegal write to 1000001, CS:IP  18:4dd4
Illegal write to 1000002, CS:IP  18:4dd4
Illegal write to 1000003, CS:IP  18:4dd4
Illegal write to 1000000, CS:IP  18:5057
Illegal write to 1000001, CS:IP  18:505c
Illegal read  from 1000000, CS:IP 18:5062
ABORT: Illegal descriptor type 0x0 for int D
```

This corroborates the `SegToSel` diagnosis rather than pointing at a
separate problem:

- Selector `0x18` is one of `$386.SYS`'s own fixed GDT code selectors
  (matches the `gdtcode-gdt` references throughout its IDT setup) —
  this is legitimate `$386.SYS` code executing, not a jump into
  garbage.
- Four single-byte violations at `1000000`–`1000003`, all at the same
  `CS:IP` — one 4-byte write logged byte-by-byte, not a `rep movsd`
  loop (which would show ascending 4-byte-aligned addresses across many
  iterations).
- `0x1000000` is exactly 16MB — the configured `memsize=16` extended-
  memory ceiling.
- A second burst (`5057`/`505c`/`5062`, a short nearby instruction
  sequence) writes, then *reads back*, the same address.
- Fatal abort: the IDT entry for interrupt `0x0D` — the GPF handler
  (`entint0d`) everything in this codebase's V86 fault handling depends
  on — has itself become an invalid/null descriptor. That's why this
  is unrecoverable rather than a clean guest-level fault: the CPU can't
  dispatch to the handler that would normally catch this class of
  error, because that handler's own dispatch entry is what's corrupted.

Consistent with the predicted mechanism: `SegToSel`'s unrecognized
`int 6Fh` function code falls through to `einstand`/`dovmint`, which
builds a simulated V86 stack frame from `s0ss`/`s0sp` — fields with no
legitimate value at this point, since no real V86 task backs this call.
`dovmint` computes a stack address from that garbage segment (`shl
bx,4`) and writes flags/CS/IP directly to it. A garbage segment value
landing at or near the configured memory ceiling, and corrupting
`$386.SYS`'s own IDT on the way, is an entirely plausible concrete
outcome of that — not a coincidence, and not a second, independent bug.

## Correction: that crash log was from a stale build, and the real cause is different

The crash log above turned out to be from a build predating the
`CheckFor386SYS` revert — a case-sensitivity bug in `MAKEUTIL.MAK`
(lowercase `_dpmi.asm`/`_dpmi.sys` referencing files that are actually
uppercase on disk, `_DPMI.ASM`/`_DPMI.SYS`) meant `make`'s dependency
check couldn't find the source file to compare timestamps against, so
it kept silently reusing an old `$DPMI.SYS` rather than rebuilding.
Fixed in `MAKEUTIL.MAK` (both the target and dependency line now use
the real, on-disk case).

After rebuilding clean with the case fix, the **same crash signature
reproduced again** — confirmed via a genuinely fresh build (`_DPMI.ASM`
grep-confirmed to contain the revert, `$DPMI.SYS` size and timestamp
consistent with a real rebuild). That ruled out staleness as the
explanation and forced a re-examination of the actual control flow,
which turned up a second, distinct bug — see below. The `SegToSel`
finding itself remains real and independently confirmed (it has no
working target, full stop), but it is **not** what causes this
particular crash, since `CheckFor386SYS`'s revert makes `InitProtect`/
`SegToSel` unreachable. Something else was producing an identical-
looking crash signature by an entirely different path.

## Root cause #3: `calc_size`/`adj_smp_alloc` run unconditionally too

`MOSDDINT.ASM`'s `mosddint`, in the code right after `ddinit0` returns:
```
cmp   al,0
jne   msdd1          ; driver failed -- lands here anyway
...
msdd1:
    cmp   [linktype],0
    jne   msdd5
    mov   cl,al
    les   bx,[origesbx]
    call  adj_smp_alloc     ; runs regardless of al (success or failure)
msdd5:
    ...
    lea   di,[ddrequest]
    call  calc_size         ; also runs regardless of al
```
Both `adj_smp_alloc` and `calc_size` are gated only on an unrelated
variable (`linktype`), never on the driver's actual reported status.
Root cause #2's fix made `ddinit0` correctly *report* failure — but
the code consuming that report never actually skips anything based on
it. So even with `CheckFor386SYS` correctly refusing before `InstallIt`
ever runs, `calc_size` still reads the same never-initialized
break-address fields (request-block offset `+14`/`+16` — only
`InstallIt` sets them, and it never runs on any path that reaches
`ErrorHandler`) and computes a resident size from garbage stack
content. That garbage size appears to be what reaches `$386.SYS`'s own
memory-management code via `adj_smp_alloc` — consistent with the crash
happening inside `$386.SYS`'s own resident code (selector `0x18`), with
`SegToSel` never in the picture at all.

**Fix applied** (`_DPMI.ASM`, `ErrorHandler`): write the same safe
break-address values `InstallIt`'s success path would — `es:[bx+14] =
offset EndOfDPMI`, `es:[bx+16] = cs` (declaring "no growth beyond
what's already loaded") — on the failure path too, before returning to
the kernel. Deliberately scoped to `_DPMI.ASM` rather than touching
`mosddint` a second time: changing kernel-wide unconditional behavior a
second time, on the same day, without a way to test every other
character driver against it, carries more risk than making the one
driver we're actually working on defensive against a kernel quirk that
apparently affects every character-mode driver equally. Not yet
verified live — this is the next thing to test.

## Root cause #4 (real) vs. a wrong turn: fix 2 itself triggers a separate, deeper kernel bug

The break-address fix above did not resolve the crash — same
signature, same `$386.SYS` selector, reproduced again on a genuinely
fresh build (confirmed: file sizes and a `grep` for the new code both
matched). That ruled out root cause #3 as *complete*, though the
break-address fix is harmless and worth keeping regardless (it makes
those fields valid in a case where they previously never were,
independent of anything else going on).

Isolated properly rather than guessing a fourth time: rebuilt with
`ddinit0`'s status-word check (root cause #2's fix) **temporarily
reverted** back to unconditional success for character devices, while
keeping `CheckFor386SYS`'s refusal (fix 1, reverted/relabeled) and the
break-address fix. Result: **the original garbage/beep symptom
reproduced, faithfully, with no crash.**

That's a clean, decisive isolation. It means:

- With `ddinit0` lying about success (original kernel behavior, every
  character driver, always): the kernel never finds out `_DPMI.ASM`
  refused internally, so its "driver failed, unlink it" cleanup path
  never runs. The uninitialized-break-address cascade into
  `calc_size`/`adj_smp_alloc` still happens (this is the *original*
  bug this whole session started with) — cosmetic, non-fatal, already
  well-characterized above.
- With `ddinit0` honestly reporting failure (root cause #2's fix): the
  kernel's "driver failed, unlink it" path becomes reachable for the
  first time. **That path is where the actual crash lives** — not in
  `_DPMI.ASM` at all. Given every character-mode driver in this
  codebase's history has always unconditionally claimed success before
  today, this is very plausibly a pre-existing kernel bug that has
  simply never been exercised until `ddinit0`'s status check made a
  genuine character-driver failure visible to it for the first time.

Not traced further this session — `mosddint`'s actual unlink logic
(referenced by its own comment, "if the driver returns cs:0000 or
there is an error, unlink," immediately after the `calc_size` call)
was never fully read. That's the concrete starting point for whoever
picks this up: find and trace that unlink path specifically, under a
genuine character-driver-failure condition, the same careful,
instrumented, verify-before-trusting approach used for everything
above.

## Narrowed further: `[scbdrvr]` gets reset to a stale value on the failure branch

Traced one level deeper before stopping. The branch structure around
`calc_size`/`adj_smp_alloc`:

```
msdd1:
    call  adj_smp_alloc      ; runs regardless of AL -- doesn't branch on it at all
msdd5:
    call  calc_size           ; first call, also runs regardless of AL
    cmp   dx,[origesbx+2]
    je    msdd5a
    cmp   al,0
    je    msdd7               ; SUCCESS: skip straight to msdd7, msdd5a never runs
msdd5a:                        ; FAILURE falls in here first
    mov   word ptr [scbdrvr],cx     ; overwrites the GLOBAL driver-list head
    mov   word ptr [scbdrvr+2],dx   ; with whatever it was BEFORE this load
    call  if_scbnul
    ...
msdd7:
    call  calc_size           ; second call, reached either way
```

`adj_smp_alloc` itself never branches on `AL` — it runs identically
whether `ddinit0` reports success or failure, which is why reverting
just the status-word check (and not touching `adj_smp_alloc` at all)
was enough to make the crash disappear. The actual difference between
the two observed behaviors (crash vs. no crash) is entirely contained
in `msdd5a`: reached only on the failure path, and reached *before*
`msdd7`'s second `calc_size` call.

`msdd5a` overwrites `[scbdrvr]` — a **global**, system-wide kernel
pointer (head of the loaded-driver list) — resetting it to `[origroot]`
(whatever it was immediately before this load attempt), rather than
properly walking forward and unlinking just the one new entry. If
`$386.SYS` or any other kernel code has already read, cached, or
derived anything from the driver list while DPMI was briefly present
in it, resetting the head pointer this way — instead of surgically
removing one entry — could leave two different pieces of code (the
kernel's driver-list view, and whatever `$386.SYS` derived from it
earlier) looking at inconsistent state. That's a plausible, concrete
route to `$386.SYS`'s own later memory-management code computing a
boundary from a now-wrong picture of what's actually allocated —
matching the observed crash exactly (its own code, its own selector,
writing past a computed limit).

**Not confirmed** — this needs finding every place `[scbdrvr]` gets
read, especially inside `_386.ASM`, and confirming the actual
inconsistency, which wasn't done this session. But it's a precise,
well-reasoned starting point: the bug is somewhere in `msdd5a`'s
handling of the global driver-list pointers, not in `adj_smp_alloc`,
and not in `_DPMI.ASM` at all.

## Confirmed via bisection: it's `origroot2`, not `[scbdrvr]` visibility to `$386.SYS`

Checked directly: `[scbdrvr]`/`scbnul` are never referenced anywhere in
`_386.ASM` (grep, zero hits) — the previous section's theory (a
`$386.SYS`-visible inconsistency from the driver-list head being reset)
doesn't hold. Isolated properly instead of guessing further: rebuilt
with root cause #2's `ddinit0` check restored (so `AL` can genuinely
indicate failure again) **and** `msdd5a`'s `[scbdrvr]`/`[tcbddpf]`
pointer-mutation block bypassed entirely (`jmp short msdd7` right at
`msdd5a`'s entry, skipping straight past it).

**Result: no crash.** Reached a clean `[A:\]` prompt. A new, legible
kernel message appeared that the crash had always been cutting off
before: `"File error #FF processing DEVICE = $DPMI.SYS"` — the kernel's
own normal error-reporting path (`loaddrv`'s `deverr`), working
correctly now that nothing crashes before reaching it. (The original
garbage/beep cosmetic symptom is still present regardless — confirming
it has some other, still-unidentified source, entirely separate from
the crash mechanism. Honest loose end, not resolved by any of today's
work.)

This precisely and empirically isolates the crash to `msdd5a`'s
pointer-list handling specifically — not `adj_smp_alloc`, not the
break-address fields, not `_DPMI.ASM` at all, not a `$386.SYS`-visible
inconsistency.

**Likely specific cause, found by reading the setup code the bypassed
block depends on:** `mosddint`'s setup (run once, before the driver
even loads) captures `origroot2` — described in its own comment as
"storage for scbdrvr next in list pointer" — but only conditionally:

```
call    if_scbnul
jne     skdd1                    ; NOT scbnul -> skip capturing origroot2
push    ds / push si
lds     si,[scbdrvr]
mov     ax,ds:[si]
mov     word ptr [origroot2],ax  ; only reached if scbdrvr WAS scbnul
...
skdd1:
```

The comment immediately above this in the source states the capture is
specifically for when `mosddint` is invoked by the runtime `ADDDEV`
command ("when mosddint is called by adddev, scbdrvr will point to
scbnul"). For ordinary `CONFIG.SYS`-time `DEVICE=` loading, it's
plausible `[scbdrvr]` doesn't satisfy `if_scbnul` at this setup point
the same way — meaning `origroot2` is left uninitialized, holding
whatever was already on the stack from unrelated prior use. Then in
the (bypassed) failure-unlink path, if the *restored* `[scbdrvr]`
later does satisfy `if_scbnul`'s check, that same uninitialized
`origroot2` gets written directly into `scbnul`'s own next-pointer
field — corrupting a shared kernel sentinel structure with garbage
stack content, on the one path (a character driver genuinely failing
during `CONFIG.SYS` processing) that appears to have never been
exercised before today.

**Not fully confirmed** — `[scbdrvr]`'s exact runtime value at the
`mosddint` setup point, for `CONFIG.SYS`-time loading specifically,
wasn't traced far enough to prove `if_scbnul` genuinely takes the
`skdd1` branch in this exact scenario. That's the one remaining step
to close this out completely. But the bisection itself (bypass →
no crash, confirmed) is solid, and this is now a precise, well-bounded
place to pick the thread back up: read `if_scbnul`'s two call sites
(setup and `msdd5a`) side by side against `[scbdrvr]`'s actual value
at each point, for a genuine `CONFIG.SYS` `DEVICE=` load specifically.

**The bypass itself is not a real fix** — it skips unlinking a failed
driver entirely, leaving a ghost entry linked into the driver list.
Left in the tree only as the diagnostic state that confirmed this
isolation; a real fix needs `origroot2` to be captured correctly (or
the restore path to not depend on it when it wasn't captured) so the
unlink actually happens, correctly, without corrupting `scbnul`.

## Correction: narrowed further, and the previous theory was backwards

Checked `[scbdrvr]`'s actual boot-time value before trusting the
`origroot2` theory further: `MOSINIT2.ASM` (~line 4199) calls `initp8`
(loads every `DEVICE=`/`MEMDEV=` driver, `mosddint` included) *first*;
only *after* `initp8` returns does the kernel retroactively insert
`scbnul` at the head of whatever list resulted (lines 4209–4217). So
during `mosddint`'s actual processing of `DEVICE=$DPMI.SYS`,
`[scbdrvr]` is still at its raw declared value (`-1`, `MOSSCBDF.INC`),
not `scbnul` — meaning `if_scbnul` should say "no" at both the setup
and restore points for this exact scenario, and the `origroot2`/`scbnul`
sub-block should be skipped either way, not corrupting anything.

Bisected precisely rather than trusting that reasoning on its own:
split the previous full-block bypass into two narrower tests, on the
same honest-failure-reporting build.

- **Bypass only the `if_scbnul`-gated `origroot2` write, keep the
  simple `[scbdrvr]=origroot` restore** → **crashes.** Same signature
  as before (`$386.SYS` selector `0x18`, write to `0x1000000`, `int 0D`
  descriptor corruption).
- **Bypass the entire block, including the simple restore** → **no
  crash** (this was the previous round's result).

That flips the earlier conclusion: **the trigger is the plain
`mov word ptr [scbdrvr],cx` / `mov word ptr [scbdrvr+2],dx` restore
itself** — not the `origroot2`/`scbnul` logic, which turned out not to
matter either way (consistent with the boot-order finding above: it's
skipped in both tests).

This is surprising on its own terms — restoring a list-head pointer to
its pre-load value looks like it should be safe. That suggests
`scbdrvr`'s exact byte offset within the shared SCB structure may not
be as isolated as it looks: `_386.ASM` reads/writes other SCB fields
at fixed offsets via the same `scbadr`-relative addressing
(`CheckFor386SYS`'s `[si+scbmmfg]`, etc.). A struct-layout mismatch —
this specific write landing on or near a byte range `_386.ASM` assumes
holds something else — would explain a "safe-looking" pointer restore
corrupting `$386.SYS`'s own state. **Not confirmed** — would need
`scbdrvr`'s exact offset in `MOSSCBDF.INC` checked against every field
`_386.ASM` reads at a nearby offset via `scbadr`, which wasn't done
this session.

Stopping here for now rather than guessing a third time. Two clean,
precise bisections done; the next one (checking `scbdrvr`'s offset
against `_386.ASM`'s own SCB field assumptions) is well-defined and
ready to pick up.
