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

## Resolved: it's not an offset overlap, and not the write itself — it's the value

Checked `scbdrvr`'s exact SCB offset by hand (summing every preceding
field's declared size in `MOSSCBDF.INC`): **239 (`0xEF`)**. Checked it
against every offset `_386.ASM` actually touches — `scbmmfea`=101,
`scbmmfg`=129, and the only hardcoded numeric SCB constant `_386.ASM`
uses anywhere (`scbtcbpc equ 19`, confirmed correctly in sync with the
current struct layout). None are anywhere near 239. The offset-overlap
theory doesn't hold — real negative result, not a dead end papered
over.

Also checked whether `_386.ASM`'s own write-protection mechanism
(`nprotect`, "clear the pl3 write enable bit in the pte" — a real,
implemented feature, matching the `parmfeat` bit `0x2000` "write
protection supported" decoded earlier) could apply here. It's
dispatched only via `int 6Fh AX=7707h`; `_DPMI.ASM`'s broken call
(`7786h`) never lands anywhere near that function. Nothing in this
scenario calls `nprotect` at all. Also doesn't hold.

**Then re-examined `mosddint`'s own linking code** (the success-path
counterpart to `msdd5a`'s unlink, never previously read) —
`MOSDDINT.ASM` around line 360, with a comment stating outright:
*"if scbdrvr is pointing to scbnul then adddev must be calling
mosddint... otherwise, must be loading a driver from CONFIG.SYS...
use scbdrvr as the root."* This **confirms** `[scbdrvr]` genuinely sits
at its raw declared value (`-1:-1`, `MOSSCBDF.INC`) throughout
`CONFIG.SYS`-time loading — DPMI gets optimistically linked in
(`[scbdrvr]` briefly becomes DPMI's own resident address), and
`origroot` (captured *before* that link, at `mosddint`'s very start)
holds `-1:-1`.

That meant the earlier "hardcoded -1:-1" bisection test was **not
actually different from the original code** — both write the same
final value. Corrected with a proper test: write a value clearly
different from `-1:-1` (`0x1234:0x1234`) instead.

**Result: no crash — but a genuine hang**, stuck right after
`$386.SYS` loads, before `DEVICE=$DPMI.SYS` even begins. Confirmed
reproducible (retried clean, waited 35+ seconds at `cycles=max`,
identical stuck state both times — every other successful boot this
entire session progresses within 1-2 seconds at that setting).

**This is the most informative result of the whole investigation.**
Neither `-1:-1` (crash) nor `0x1234:0x1234` (hang) produces a clean
boot. Both are wrong, in different ways, which is exactly the
signature of a downstream consumer that **follows/dereferences
`scbnul`'s "next" pointer field without first checking for the `-1`
terminator convention**:

- `MOSINIT2.ASM`'s post-`initp8` cleanup unconditionally copies
  whatever `[scbdrvr]` ends up as into `scbnul`'s own next-pointer
  field, once every `CONFIG.SYS` `DEVICE=`/`MEMDEV=` line has been
  processed.
- With `-1:-1` (the real value after a genuinely failed install):
  something — almost certainly inside `$386.SYS`, given the crash
  executes in its own code selector — treats this as input to a
  32-bit address computation, landing exactly on the configured
  16MB ceiling.
- With `0x1234:0x1234` (an arbitrary non-terminator value): treated as
  a real address to jump to or read from, landing on nonsense that
  hangs the CPU instead of tripping the specific boundary check that
  caused the crash.

Both outcomes are consistent with "this code never checks for `-1`
before following it," not with anything specific to `_DPMI.ASM` or
even to `mosddint`'s unlink logic specifically. **This reframes where
the actual fix belongs**: not in `_DPMI.ASM` (already refuses safely
via `NotFin`), and arguably not even in `mosddint`'s unlink code
itself (which correctly restores the empty-list sentinel value) — but
in whatever code, likely inside `_386.ASM`, walks this list and needs
to check for the `-1` sentinel *before* dereferencing it. That code
path has apparently never been exercised before today, because no
character-mode driver had ever genuinely failed `CONFIG.SYS`-time
installation until `ddinit0`'s status-word check (root cause #2) made
a real failure visible for the first time.

**Not yet found**: the exact `_386.ASM` routine that walks/dereferences
this list. Given the crash's `CS:IP` values (`4dd4`/`5057`/`505c`/
`5062`, all within `$386.SYS`'s own code selector), that's the next,
well-defined place to look — starting from those specific offsets in
a disassembly or listing of `_386.ASM`'s compiled output, working
backward to find what computation they're part of.

## Major correction: live debugger session overturns the list-walking theory

Built a genuine debug-enabled DOSBox from source specifically to settle
this (vanilla 0.74-3 from `github.com/jwilk-mirrors/dosbox`,
`./configure --enable-debug=heavy`, one real compile fix needed —
`debug_gui.cpp` accessed `WINDOW`'s private `_begy` field directly,
incompatible with modern `ncurses`'s opaque `WINDOW` type; fixed by
using the public `getbegy()` macro instead, four call sites). Used
`tmux` for the curses debugger console and `xdotool`/`Xvfb` for the
SDL window's keyboard input — the two are genuinely separate input
paths in DOSBox's architecture and both are needed simultaneously.

Set breakpoints at the crash's own `CS:IP` values and stepped through
live, with full register/disassembly visibility. This directly
contradicts the list-walking theory above:

**At `18:4DD4`** (`EAX=22C8 ESI=00100000 ECX=00000400 EDI=00000000
CS=0018 EIP=4DD4`, `CPL0`):
```
repe lodsd                              ; read ECX=0x400 dwords from ESI=0x100000 (1MB)
pop  ds
mov  eax,es:[00000000]                  ; save es:[0]
mov  dword es:[00000000],0              ; clear es:[0]
mov  dword es:[01000000],FFFFFFFF  [illegal]   ; write marker at exactly 16MB
cmp  dword es:[00000000],0              ; did es:[0] change? (wraparound test)
jz   00004E08                           ; no change -> no wraparound
mov  es:[00000000],eax                  ; restore es:[0]
```
This is a textbook memory-wraparound/sizing probe — not a driver-list
walk, not anything touching `scbdrvr`/`scbnul` at all.

**At `18:5057`** (`EBX=00100000 EDI=00100000 ES` selector decoded as
base=`00000000` limit=`FFFFFFFF` — a full 4GB flat segment):
```
mov  es:[edi],dl        ; write test byte
jmp  short $+0
mov  es:[edi+1],dh      ; write second test byte
jmp  short $+0
cmp  es:[edi],dl        ; read back, compare
jnz  00005095           ; mismatch -> exit loop (no memory here)
cmp  es:[edi+1],dh
jnz  00005095
```
A write/read-back memory-test loop, walking `EDI` upward from 1MB.
Continuing to the breakpoint at `18:5095` (the loop's exit) confirmed
`EDI` had grown to exactly `01000000` (16MB) at the point of the
logged illegal access — the loop naturally reaches the configured
`memsize=16` ceiling as part of normal operation.

**Critically: the loop exits cleanly.**
```
0018:5095  sub  edi,ebx      ; 0x1000000 - 0x100000 = 0xF00000 (15MB range tested)
0018:5097  shr  edi,0Ch      ; -> 0xF00 (3840) 4K pages = 15MB
0018:509A  mov  ebx,edi      ; result: 15MB of extended memory detected
0018:509C  pop  edi
0018:509D  pop  edx
0018:509E  pop  eax
0018:509F  ret               ; <- clean return, no fault
```
Stepped past the `ret` and several further instructions (`CS:IP`
reaching `0018:4E4D` with `EBX=00000F00`, the correctly-propagated
15MB page count) with **no exception, no abort, execution proceeding
completely normally** — in this build.

**This overturns the previous theory entirely.** The code executing
at these addresses is `$386.SYS`'s own memory-size detection routine,
unrelated to `_DPMI.ASM`, `mosddint`, `scbdrvr`, or `scbnul` in any way. It runs this same probe on every boot with
`MEMDEV=$386.SYS`, `DPMI` involved or not. The "illegal write/read"
DOSBox warnings are a side effect of the probe naturally reaching the
exact configured memory ceiling (`memsize=16` gives exactly 16MB, so
testing "is there memory at 16MB" necessarily touches the boundary) —
and in this freshly-built debug binary, that's genuinely harmless:
logged, then execution continues.

**Working hypothesis, immediately testable, not yet confirmed against
the user's actual crashing build:** different DOSBox variants/builds
likely differ in how strictly they enforce out-of-bounds access —
this vanilla 0.74-3 debug build logs and continues; the user's build
(dosbox-staging, per its distinctive timestamped log format) may
escalate the same condition to a fatal exception. If so, **the fix
isn't a code change at all** — raising `memsize` in `dosbox.conf`
(e.g. `memsize=32` or higher) would give `$386.SYS`'s normal,
always-present memory-sizing probe room to complete without ever
touching unmapped memory, regardless of how strict the specific
DOSBox build's enforcement is.

**Next step, cheap and concrete:** try `memsize=32` (or higher) in the
crashing config and see if the crash disappears. If it does, this was
never a `_DPMI.ASM`/`mosddint`/`scbdrvr` bug at all — root causes #1
and #2 (the `CheckFor386SYS` bit mismatch and the `ddinit0` status
check) remain real, correct, worthwhile fixes on their own merits, but
the crash they *exposed* may simply have been a memory-configuration
edge case, coincidentally triggered for the first time by DPMI
loading being the first scenario that ran a genuine post-`CONFIG.SYS`
memory-sizing pass under `memsize=16` in a way that got far enough to
provoke it.

## Root cause found: page-table construction physically overwrites the IDT

Continued the live debugger session. Set a breakpoint at `18:4E4D`
(confirmed clean return point from the memory-sizing routine, EBX=0xF00
correctly propagated). Checked the DOSBox-staging source directly
(`src/cpu/cpu.cpp`) for the `E_Exit("Illegal descriptor type...")`
call — confirmed it's unconditional and core-independent, called from
the shared interrupt-gate dispatch path regardless of `core=normal` vs
`core=dynamic`. This is also a known class of issue in dosbox-staging
generally (see their own issue #2346, unrelated software, same abort
message) — dosbox-staging is simply less forgiving of an invalid
descriptor than older DOSBox, which is why `core=normal` didn't help
on the user's real system even though it produced a graceful message
in this session's own vanilla-DOSBox testing. No DOSBox-side
configuration avoids this once it happens — the fix has to be at the
MOS source level.

Used the debugger's `CPU` command to get `IDT base=00001FD0
limit=000007FF` (standard 256-entry IDT, 8 bytes/entry). Computed
entry `0Dh`'s address: `0x1FD0 + 13×8 = 0x2038`. Dumped it directly
via `MEMDUMP ES:2038 8` (`ES` confirmed flat, base=0, from the earlier
session): `55 27 18 00 00 EE 00 00` — decodes to offset=`0x2755`,
selector=`0x0018`, Present=1, DPL=3, **Type=0xE (standard 32-bit
Interrupt Gate)**. Completely valid at this point — not type 0 at all.
So whatever invalidates it happens later, in code not yet traced.

Set a protected-mode memory breakpoint directly on that address
(`BPPM 0050:2038` — note: plain `BPM` uses different, apparently
real-mode-style addressing and gave a false-positive hit at what
turned out to be the same reported transition but on the wrong
underlying watch; `BPPM` is the correct command for a protected-mode
selector:offset memory watch) and resumed. **It fired** — inside the
`stosd` loop at `18:4EA2`, the same page-table-construction loop
identified while stepping through `4E4D`'s onward code:
```
0018:4EA2  stosd                    ; write EAX to [EDI], EDI += 4
0018:4EA3  add  eax,00001000        ; next page-aligned value
0018:4EA8  loop 00004EA2
```
`EAX` at the point of the hit: `00001007` — decodes as a standard
page-table entry (physical page `0x1000`, flags `007` =
Present+Writable+User). This loop is `$386.SYS` constructing its own
page tables, writing consecutive 4-byte entries starting from some
`EDI` base and walking forward. It is not walking anywhere near a
driver list, `scbdrvr`, or anything DPMI-related — this is core
`$386.SYS` paging setup that runs on every boot.

**The mechanism**: this loop's page-table destination region
overlaps, or extends into, the IDT's own memory location (`0x1FD0`–
`0x27D0`). As the loop walks forward writing page-table entries, it
reaches `0x2038` — exactly where IDT entry `0Dh` lives — and
overwrites it with page-table data instead of a valid interrupt gate.
The "invalid descriptor type 0x0 for int D" isn't corruption from a
logic bug elsewhere; it's the IDT being **physically clobbered** by
unrelated, legitimate page-table construction that was placed at (or
sized into) the same physical memory.

**Not yet confirmed**: the exact starting `EDI` value for this loop
(would need to look a few instructions earlier than `4EA2`, not done
this session) and the exact loop iteration count/total byte range, to
quantify precisely how much of an overlap this is and whether it's
specific to `memsize=16`/`32`'s particular memory layout (recall the
crash address itself scales exactly with `memsize` — `0x1000000` at
16, `0x2000000` at 32 — confirmed independently by the user on their
real system) or would happen regardless of configured memory size.
Given the crash address scaling with `memsize`, and this newly-found
IDT-overwrite mechanism being about a **fixed low address** (`0x2038`,
independent of `memsize`), these may be two separate observations
about the same boot sequence rather than the same event — worth
clarifying next: is the page-table loop's destination address itself
computed from `memsize` (in which case a larger `memsize` might move
it further from the IDT and avoid the overlap), or fixed (in which
case the overlap is unconditional and `memsize` is a red herring for
this specific mechanism, coincidentally correlating because a larger
`memsize` also means more loop iterations before things go wrong
elsewhere).

**This is real, load-bearing, `$386.SYS`-internal behavior**,
completely independent of `_DPMI.ASM`/`MOSDDINT.ASM`/`scbdrvr`. If
confirmed as unconditional, this would mean `DEVICE=$DPMI.SYS` was
never really the trigger at all — it's whatever first triggers this
particular boot-time codepath in `_386.ASM` reaching far enough to
build page tables that overlap the IDT, which DPMI's presence (or its
own memory allocation via `AllocateExtend`, if reached) may simply
be the first realistic scenario to exercise on a `CONFIG.SYS` with
`FREEMEM=`/`SMPSIZE=` tuned the way this session's testconfig has
them. Next session should pick up here: find the loop's starting
`EDI`, and check whether it's a fixed address or `memsize`-derived.

## RETRACTED: the IDT-overwrite finding above is wrong

Checked the static source directly (`_386.ASM` line 9720 onward,
`; init the pte`): page table construction starts at physical
`0x100000` (1MB) — nowhere near the IDT's `0x2038`. The live-debugger
`BPPM 0050:2038` "hit" inside that loop was almost certainly the same
class of addressing false-positive already caught once with plain
`BPM` on this same address earlier in the session. **Root cause of
the DOSBox abort is still unknown.** Do not trust the "page-table
overwrites IDT" section above without re-verifying independently.

## CONFIRMED WORKING: the actual goal, achieved

User-confirmed on real hardware, `./build.sh --clean`, current
`_DPMI.ASM` (`NotFin` refusal) + `MOSDDINT.ASM` (`ddinit0` reverted to
unconditional success) combination:

- `DEVICE=$DPMI.SYS` loads, refuses safely, **no crash, no hang**
- Same "Illegal write/read to <memsize boundary>" log lines still
  appear (harmless warnings, `$386.SYS`'s own memory-sizing probe,
  unrelated to DPMI) and the cosmetic garbage/beep is still present
  (known, harmless, already documented above) — neither is fatal
- `ADDTASK` confirmed working: 12 tasks successfully created (~600K
  each, correctly capped by configured SMP size)
- OS fully functional afterward

**This is the actual goal from this whole investigation, achieved.**
The deeper `$386.SYS`/IDT crash mechanism (dosbox-staging specifically,
`memsize`-scaled address, `E_Exit` on illegal descriptor type 0) is
still not root-caused — both live-debugger theories from this session
(scbdrvr/list-walking, page-table/IDT-overlap) were investigated and
retracted. That remains open for whenever there's appetite to chase it
further, but it is no longer blocking anything: DPMI loads safely,
the kernel and every other driver/task function normally.

## New observation: garbage and "Illegal write/read" lines are concurrent, not sequential

User-provided screen capture (frozen mid-scroll via Ctrl-S on a real
terminal, not a tool artifact) shows the sequence precisely: after
"640K allocated to first megabyte.", an incomplete/garbled
announcement appears, then several complete-looking repeats of
"PC-MOS DPMI 1.0...HOST (910430)...(c) Copyright 1991...Inc", with
more garbage interspersed — and critically, the host terminal's own
log pane shows `Illegal write to 2...` / `Illegal read from...` lines
**already appearing in this same window**, not clearly before or after
the on-screen garbage. Previously assumed these were two unrelated,
merely-coincidentally-timed events (the harmless `$386.SYS`
memory-sizing probe vs. the unidentified garbage-printing bug). This
observation means that assumption should not be trusted without
checking — they may be more directly connected.

Confirmed end state (user, waited it out): boots through cleanly to a
working `AUTOEXEC.BAT` completion and prompt. Matches everything
established above — not a hang, not fatal.

**For next session's static-marker instrumentation plan**: bracket
the kernel's driver-load sequence specifically around `$386.SYS`'s
known probe addresses (`18:4dd4`, `18:5057`/`505c`/`5062` from the
DOSBox abort logs) as well as `_DPMI.ASM`'s own init entry, rather
than only instrumenting the `_DPMI.ASM` side — the concurrency
observation above suggests the marker plan should establish ordering
between the memory probe and the garbage specifically, not just
ordering relative to `_DPMI.ASM`'s `Copyright` banner.

## Significant lead: load marker never appeared

Added a simple, guaranteed-safe marker print
(`>>> DEVICE=$DPMI.SYS NOW LOADING <<<`) as the literal first
instruction of `InstallDriver`, before even the `Copyright` print.
User rebuilt clean (`./build.sh --clean`) and tested: **marker never
appeared anywhere in the visible output.** Garbage pattern changed
(more garbage) from the few added bytes shifting the binary layout —
consistent with an uninitialized-length read hitting different
underlying bytes before a terminator, not with `_DPMI.ASM`'s own logic
running differently.

Two readings, not yet distinguished: (1) `InstallDriver` never
actually gets called in this failure path at all — meaning the entire
`_DPMI.ASM` init chain investigated this session is a red herring, and
the garbage is the kernel reading `$DPMI.SYS`'s raw loaded image as
data before ever handing control to it; or (2) the marker printed but
scrolled off-screen before capture, same as the `Copyright` banner did
earlier in the session.

**Sharp next question for next session**: does `InstallDriver` ever
actually execute in this failure path? Cheapest reliable check: don't
rely on screen visibility at all — use the same `0040:00F0`
segment-recording trick already in `InstallDriver` (writes
unconditionally, first thing, regardless of what prints) combined
with `DUMPLOG`-style readback at the `[A:\]` prompt once boot
completes. If `0040:00F0` holds a nonzero segment after boot, entry
happened regardless of what was visible on screen; if it's still
zero, `InstallDriver` genuinely never ran — a much more direct test
than trying to catch fast-scrolling text.

## Resolved: InstallDriver runs exactly once, correctly — theory ruled out with real data

Ran the `0040:00F0`/`DUMPLOG` test (queued up last entry) rather than
relying on screen visibility. Result: `00 01 01 01 01 01 00 00 00 01`.

Decoded against the marker map: `InstallDriver` entry (1) fired once;
`CheckMOS`/`CheckDPMI`/`CheckMicroProcessor`/`CheckFor386SYS` (2-6)
all fired once each, in order; `AllocateExtend`/`InstallIt`/
`Init32Code` (7-9) never fired (correct — `CheckFor386SYS` refuses via
`NotFin` before reaching them); `ErrorHandler` (10) fired once.

**This proves `InstallDriver` runs exactly once, correctly, refusing
exactly where it's designed to.** The "load marker never appeared"
observation from the previous entry is resolved: it almost certainly
did print and scrolled off-screen, same as the `Copyright` banner
always has — not evidence `InstallDriver` never ran. That theory is
retracted with real data behind the retraction this time, not just a
correction.

**Consequence for the on-screen garbage specifically**: since
`_DPMI.ASM`'s own init chain runs exactly once and exits cleanly, the
**3x repeat of the garbage/banner text is not `_DPMI.ASM` executing
multiple times** — that's now disproven. It must be the kernel doing
something with `$DPMI.SYS`'s already-loaded memory image three
separate times *after* `InstallDriver` returns. Given `ddinit0` is
currently reverted to unconditionally report success (the known-safe
configuration), the kernel believes the driver installed successfully
and proceeds through `mosddint`'s post-return handling — `calc_size`/
`adj_smp_alloc` and whatever surrounding logic in `MOSDDINT.ASM`/
`MOSINIT2.ASM` runs per apparently-successful driver load. That
kernel-side code, run three times against one driver, is now the
concrete, well-scoped place to instrument next — not `_DPMI.ASM`,
which is confirmed clean.

## DEFINITIVE: mosddint's post-processing runs 7-12 times for one driver load

Added two more safe counters (0040:00F2 = msdd1 entry, 0040:00F3 =
msdd7, extending DUMPLOG to read them). Result for one single
`DEVICE=$DPMI.SYS` line: **msdd1 = 7, msdd7 = 12.**

This is the concrete root of the repeated-garbage pattern: `mosddint`'s
post-`ddinit0` processing (`calc_size`/`adj_smp_alloc` and everything
around them) is not running once per driver as expected — it's running
7-12 times for a single `CONFIG.SYS` `DEVICE=` line. That directly
explains multiple partial/complete repeats of the driver's own
banner/name text appearing on screen: something in the kernel's own
driver-loading loop (`initp8`/`loaddrv`, not yet identified precisely)
is calling back into this processing repeatedly.

**Confirmed NOT `_DPMI.ASM`** (proven single, clean entry earlier this
session) and **NOT a simple "3x" pattern** — the real counts (7 and 12,
different from each other) suggest a loop with an early-exit branch
taken sometimes but not always, not a fixed retry count.

**Next, concrete step**: find what calls `mosddint` (or jumps back into
`msdd1`/`msdd7` specifically) repeatedly — likely in `initp8`
(`MOSINIT2.ASM`) or `loaddrv`. A loop-iteration counter at `initp8`'s
own top, read the same way, would confirm whether the *outer* driver-
processing loop itself is what's iterating 7-12 times for one line
(a genuine kernel bug in loop-termination logic), or whether something
*inside* `mosddint` branches back to `msdd1`/`msdd7` without ever
returning to the caller.

## Precise visual count from real hardware: 4 banner instances (1 incomplete, 3 complete)

User's direct, careful count on real screen: exactly 4 DPMI banner
appearances — 1 incomplete + 3 complete. Does not need to map 1:1 to
the `msdd1`=7/`msdd7`=12 iteration counts above (kernel-internal loop
iterations vs. visible complete-banner prints are different
granularities — not every iteration necessarily reads far enough to
produce a recognizable, complete banner). Useful as a cross-check once
the loop itself is found and instrumented per-iteration, to see which
iterations produce a visible print and which don't.

## DEFINITIVE ROOT CAUSE: mosddint conflates the driver's static "next" field with its own dynamic linking write

Traced `msdd1`/`msdd7`'s repeated hits to their actual source. Found
the real loop mechanism at `msdd1s`/`msdd6` in `MOSDDINT.ASM`:
```
msdd1s:
    les  bx,[nxtdrvr]
    cmp  bx,-1
    je   msdd1        ; offset == -1 -> single-header file, done
    jmp  msdd6         ; else -> "another header in this file", loop back
```
`nxtdrvr` is populated at `msdd6`'s own top by reading straight from
the driver's own header (`es:[bx]`/`es:[bx+2]` — the standard DOS
device-driver "pointer to next device" field). Confirmed via
`_DPMI.ASM`'s actual source (`code16` segment header): `dd -1 ; filled
in with pointer to next driver` — correctly declared as the proper
single-header terminator from the start.

Added a diagnostic recording the actual `nxtdrvr` value at each read
(safe bytes `0040:00F5`/`00F6`). Result after boot: **`FF FF`** — the
final value is the correct terminator. Combined with `msdd1`=7,
`msdd7`=12 from the previous entry, this means the loop *does*
eventually terminate correctly, but takes 7 passes to get there for
what is genuinely a single-header file.

**The actual mechanism**: `msdd6` reads the header's "next" field into
`nxtdrvr` at the start of each pass. Later in the *same* pass,
`msdd3`/`msdd4` (the driver-linking code) **writes** `[scbdrvr]`'s
current value into that *exact same header field*, as part of
legitimately linking the driver into the kernel's driver list. On the
next iteration, `msdd6` reads back its own previous linking-write,
mistakes it for evidence of a genuine additional device header chained
in the file, and loops back — repeating the entire process (including
the driver-name/banner read that produces the visible garbage) for a
file that only has one header. This continues until the accumulating
sequence of overwrites happens to produce `-1` again, at which point
it finally, correctly, stops.

**This is a genuine kernel bug, independent of `_DPMI.ASM` and DPMI
specifically** — `mosddint` conflates a field meant to be a static,
one-time-read property of the loaded file with a field it also uses
as dynamic, per-pass linking-bookkeeping scratch space. Any
character-mode driver loaded via this exact path is potentially
subject to the same false multi-header loop; `$DPMI.SYS` is simply
the scenario that happened to expose it (likely because
`AllocateExtend`/`InstallIt` never running left `scbdrvr`/the driver's
resident-size fields in a state that iterates a visible, non-trivial
number of times before self-correcting, rather than terminating on
the first or second pass unnoticed).

**Not yet attempted**: an actual fix. The most direct, narrowly-scoped
fix would be to read `nxtdrvr` from the header *before* any linking
write touches that field in the same pass — but the current code
already does that ordering (`msdd6` reads first, `msdd3`/`msdd4`
writes after). The real problem is that the write itself corrupts the
field for the *next* pass's read, meaning the fix needs to either
(a) save the driver's original, file-declared "next" value once,
before any pass ever writes to it, and use that saved copy for the
loop-continuation check instead of re-reading the (by-then-mutated)
header field on every pass, or (b) determine why a single-header file
takes multiple passes to resolve at all -- possibly the loop is
*by design* meant to run until linking stabilizes, and the real bug
is elsewhere (e.g. in why `scbdrvr`'s sequence of values takes 7
iterations to settle rather than 1). Needs careful, static tracing of
what `[scbdrvr]` actually holds across the 7 passes before proposing
a fix -- this session's tool budget did not extend to that.

## Connecting discovery: the scbdrvr value sequence looks like raw memory, not meaningful state

Added an 8-slot recorder capturing `[scbdrvr]`'s low word at each
`msdd1` pass (safe table at `0040:0100`, `DUMPLOG` extended to print
it). Result for the same one-driver-load scenario (`msdd1`=7 passes):

**`4334 92BA 9C8A 1934 24D2 0000 0000 0000`**

Five distinct, essentially random-looking 16-bit values across the
real passes, followed by zero-fill for the unused table slots. This
is not a clean, predictable progression (not counting up, not cycling
through a small known set of legitimate list-head addresses) — it
looks like whatever's at the driver header's "next" field location is
picking up **raw, unrelated memory content** each pass, being
reinterpreted as a pointer.

**This may unify the two mysteries this whole investigation has
chased separately**: the on-screen garbage (established: real driver
banner text, running past its intended bounds into actual code bytes)
and the 7/12-pass linking loop (established: caused by the kernel
reading back its own previous linking-write as a false "next device"
pointer) may share the same underlying root defect — something not
correctly bounding a read/pointer against `$DPMI.SYS`'s actual
single-header size, letting real memory content leak through as
"structure fields" in both places.

**Checked directly**: searched `_DPMI.SYS`'s actual binary file for
all five values as byte patterns (little-endian). **None found
anywhere in the file.** This rules out the simplest version of the
connecting hypothesis — these values are not raw bytes copied
directly from `$DPMI.SYS`'s own on-disk image being misread as a
header field.

**Second check, also negative**: compared against the driver's actual
runtime load segment (recorded independently at `0040:00F0` — this
same run: `CD8E`). None of the five values match it either. So this
isn't simply "scbdrvr correctly points at the driver, then something
walks forward through the driver's own resident bytes reinterpreting
them as pointers" — the first value in the sequence doesn't even match
the real starting point that theory would require.

That doesn't rule out a connection entirely — the *loaded, resident*
image in memory could differ from the raw file (relocation, or the
values could originate from a completely different already-resident
structure, e.g. `$386.SYS`'s own memory, or stale content left over
from something else previously occupying that memory) — but the
direct, easy-to-check version of "these are leaked driver bytes" is
now disproven, not just untested. Whoever picks this up next should
not assume the connection without further checking a different
source for these values (e.g. dump the driver's actual *loaded*
memory image at runtime, not the on-disk file, and compare against
that instead).

**Status**: two concrete, checkable hypotheses for the `scbdrvr`
sequence's origin tested and disproven this session. The real source
remains genuinely unknown. Given the practical goal (DPMI refuses
safely, OS fully functional) was already achieved separately, this
specific sub-question is now a pure curiosity/correctness item rather
than something blocking anything — worth a fresh, carefully-planned
live-debugging session (with a live breakpoint on the actual `mov
word ptr [scbdrvr],bx` write inside `msdd6a`/msdd3, to catch the
exact moment and see what `bx`/`es` actually are at write time,
rather than reading the already-written value after the fact) rather
than more static guessing.

## CORRECTION: the "msdd6 loop-back" theory is wrong — pass 1 terminates cleanly

Attempted the live-breakpoint approach queued up above. The tmux/dosbox
debug session got stuck (same class of interaction fragility seen
earlier this session — resumed execution stopped progressing and
repeated F5 didn't help, unrelated to anything in `MOSDDINT.ASM`
itself). Abandoned it and went back to the static-instrumentation
technique that's actually delivered every real finding this session,
rather than keep fighting an unreliable debugger session.

Added a direct recorder at the critical check itself (`cmp word ptr
es:[bx],-1` at source line 459) — an 8-slot table at `0040:0110`
capturing the actual value being compared, one slot per pass. Two
short-jump-out-of-range errors surfaced from code growth (same class
seen earlier — `je msdd5` and the diagnostic's own bounds check both
exceeded short-jump range once enough code was inserted before their
targets); fixed both with the same proven pattern (short jump to a
nearby label + unconditional `jmp` for the far target).

Result: **`FFFF 4362 92E8 9AC0 9AD2 9AE4 9AF6 9B08`**

**Pass 1's checked value is `FFFF` (`-1`) — correct, from the very
first pass.** This directly contradicts the earlier theory. If the
check genuinely sees `-1` on pass 1, the code takes the clean-
termination branch (source lines 465-471: restore `es:[bx]` from
`[savedrvr]`, `jmp short msdd1`) — it never reaches `msdd1s`'s
`nxtdrvr` comparison on pass 1 at all. The "kernel reads back its own
linking-write as a false next-header pointer, causing `msdd6` to loop"
mechanism described in the previous entries does not explain why
`msdd1` is reached 7 times, since pass 1 alone should terminate
processing for this single-header file immediately.

**This is a real correction, not a refinement** — the loop-back
mechanism at `msdd1s`/`msdd6` was static-source-plausible and fit the
comment ("extra passes... multi header case"), but the actual recorded
runtime data doesn't support it as *the* explanation for the 7-pass
count. Something else causes `msdd1` (and by extension `mosddint`'s
surrounding processing) to be reached repeatedly — possibilities not
yet checked: `mosddint` being invoked multiple times through a
different caller entirely (confirmed earlier: `MOSINT38.ASM` also
calls `mosddint`, separately from `loaddrv`/`ldloop` — not yet ruled
out as a contributor), or `msdd1` not actually being the point that
should be used to count "passes" the way this session assumed.

**Do not build a fix on the loop-back theory as previously described.**
The `if_scbnul`/`nxtdrvr`-corruption mechanism may still be *a* real
issue worth understanding, but it is not established as *the* cause
of the specific 7/12-pass counts measured. Next session should start
by checking whether `mosddint` itself gets entered more than once
(a counter at the very top of the `lproc mosddint` procedure itself,
before any of the `msdd1`/`msdd6`/`msdd7` internal labels, would
settle this directly) before revisiting the `msdd6`/`msdd1s` internal
loop logic at all.

## Real progress: visible markers rule out calc_size/adj_smp_alloc directly

Following the plan to use visible on-screen markers rather than silent
counters: added BIOS-teletype single-character markers (`int 10h
ah=0Eh` — chosen specifically because it needs no `DS`/segment setup
at all, unlike a string print, and `assume ds:nothing` is in effect
throughout this procedure) at five points: `[` (mosddint's true
entry), `<`/`>` (immediately before/after `ddinit0`), `{`/`}`
(immediately before/after `adj_smp_alloc`), `(` and `)` (before each
of the two `calc_size` calls), `]` (mosddint's final return). Two
short-jump-out-of-range errors surfaced from the added code size (same
class as before — `je msdd5` and one of the diagnostic's own branches
exceeded short range once enough code was inserted); fixed both with
the same proven short-jump-plus-unconditional-jmp pattern.

**First real finding**: `mosddint` is called multiple times *before
`$386.SYS` even loads* — full, clean `[<>{}()]` sequences appear two
or three times in the earliest part of boot, well before "Loading
$386.SYS" prints. This means `mosddint` processes other, unrelated
built-in devices through this exact same code path first (this
session's markers are generic — they fire for *any* driver mosddint
handles, not just DPMI). Each of these early passes completes cleanly,
no garbage, no interruption. This is expected, normal kernel behavior,
not part of the DPMI-specific symptom.

**Second, more directly useful finding**: captured a later frame
showing `♦{}()]` immediately preceding the correct "5K SMP #1
allocated" line — i.e., `adj_smp_alloc` and *both* `calc_size` calls
run **once, cleanly, together, immediately after all the visible
garbage has already happened**, not during it. This rules out
`adj_smp_alloc`/`calc_size` as the source of the repeated garbage
directly, by observation, not inference — they're confirmed innocent.

**Not yet captured**: where exactly DPMI's own `[`/`<`/`>` markers
land relative to the garbage itself. The transition from "$386.SYS
loaded" to "all garbage has already happened, 5K SMP allocated"
continues to happen in well under the ~1-second granularity screenshot
polling can reliably catch (consistent with every earlier finding this
session about this specific transition's speed, regardless of
`cycles=` throttling) — the markers may be buried within the dense
garbage itself, visually indistinguishable from the noise, rather than
genuinely absent.

**Narrowed conclusion**: the repeated garbage/banner-printing happens
specifically **during or immediately around `ddinit0`'s own call** —
i.e., during the DOS strategy/interrupt driver-init protocol dispatch
itself, or in the narrow window between `mosddint`'s entry and
`ddinit0` returning. Not in `adj_smp_alloc`/`calc_size` (ruled out
above), and not in `_DPMI.ASM`'s own code (`InstallDriver` proven
single-entry, clean, in an earlier session). That's a real narrowing
of the search space — from "somewhere in mosddint's ~370-line
procedure" to "somewhere in ddinit0's own ~60-line procedure, or the
protocol dispatch it performs" — even without having caught the exact
visual moment.

**Best next step**: rather than keep fighting screenshot timing, add
one more marker *inside* `ddinit0` itself, between its `ddstrat`/
`ddinter` calls specifically (the actual DOS strategy/interrupt
protocol dispatch to the driver) — narrowing further within this now
much smaller, confirmed-relevant procedure.

## CONFIRMED by direct visual evidence: garbage happens during ddinit0's own execution

User captured a real screenshot from actual hardware showing the full
marker sequence clearly. Decoded precisely:

The repeating `[<>)][<>)][<>)][<>)][<>)]` pattern (five times, missing
`{`/`}` and the first `(` entirely) is **not related to DPMI at all**.
Traced to `initp2` (`MOSINIT2.ASM`), which explicitly initializes five
standard built-in devices back-to-back — `scbstdcon` (console),
`mosstdclk` (clock), `scbcom24` (serial ports, `MOSDEVS.ASM`),
`scbstdblk` (standard disk), `scbstdhd` (standard hard disk) — each
through `dodrvr`, itself calling `mosddint` twice per device (`mov
al,[first] ; 0 for first pass, 2 for second`, `[first]` set to `2`
immediately after this block for the documented second pass). The
`linktype==2` code path (skips `adj_smp_alloc` and the first
`calc_size`, landing directly on the second) is this second pass,
running for five completely ordinary, unrelated kernel devices. Fully
explained, confirmed normal, no bug here.

**Right after these five clean passes, the actual DPMI-relevant one
begins**: a sixth `[<` appears (from `loaddrv`, which processes our
one `DEVICE=$DPMI.SYS` line — confirmed separately, earlier this
session, to invoke `mosddint` exactly once), and **garbage starts
immediately after `<` fires, before `>` (immediately after `ddinit0`
returns) ever appears cleanly**.

**This is now confirmed by direct observation, not narrowed by
elimination: the garbage happens specifically during `ddinit0`'s own
execution for `$DPMI.SYS`'s driver** — after `mosddint`'s entry and
the immediate-pre-`ddinit0` marker fire correctly, but before
`ddinit0` returns. Combined with the earlier finding that `_DPMI.ASM`'s
own `InstallDriver` runs once, cleanly (proven via its own internal
counters) — the garbage is not `_DPMI.ASM`'s own code executing
incorrectly, and not `mosddint`'s surrounding logic (`adj_smp_alloc`/
`calc_size`, proven to run once, cleanly, afterward) — it is
specifically in `ddinit0`'s own body, most likely in or around its
`ddstrat`/`ddinter` DOS device-driver protocol dispatch calls (the
actual mechanism by which `ddinit0` hands control to `_DPMI.ASM`'s
`inter`/`InstallDriver` and gets a result back).

**Next step, now precisely scoped**: add markers *inside* `ddinit0`
itself — before/after `ddstrat`, before/after `ddinter` specifically
— to narrow within this single, now-confirmed-relevant ~60-line
procedure. This is the smallest, best-defined search space reached
so far in the whole investigation.

## Correction: the repeated-marker pattern was misattributed to DPMI

The `[<>{}()]`/`[<>)]` sequences analyzed in the previous entry are
**not related to `$DPMI.SYS` at all**. Confirmed directly: user tested
the exact same marker build with `DEVICE=$DPMI.SYS` removed entirely,
and the same pattern still appeared. Traced to `initp2`
(`MOSINIT2.ASM`), which explicitly initializes five standard built-in
devices — `scbstdcon` (console), `mosstdclk` (clock), `scbcom24`
(serial ports, `MOSDEVS.ASM`), `scbstdblk` (standard disk),
`scbstdhd` (standard hard disk) — each through `dodrvr`, itself calling
`mosddint` twice per device (`mov al,[first] ; 0 for first pass, 2 for
second`). The repeating pattern is this normal, documented two-pass
mechanism running for five ordinary devices, confirmed by five
consecutive `call dodrvr` sites in `initp2`'s source. Not a bug, not
DPMI-specific. The earlier conclusion ("garbage happens during DPMI's
own `ddinit0`, confirmed by direct observation") was wrong — it was
very likely this same serial-port-related pattern, misread as DPMI's
own pass. Correcting the record rather than letting it stand.

## Two failed attempts to instrument inside ddstrat/ddinter — both reverted

Given `ddinit0`'s own call is still the confirmed-relevant region
(shared code, used by every driver including DPMI, not yet fully
cleared), attempted to narrow further with markers between its
`ddstrat`/`ddinter` calls specifically.

**Attempt 1 — `int 10h` teletype markers**: caused a genuine hang.
Confirmed via sustained ~90% CPU use with zero visible screen progress
for 15+ seconds, where every other test this session completed in
under one second. Reverted immediately.

**Attempt 2 — silent memory-counter markers** (same safe technique
used successfully everywhere else this session, no BIOS calls):
compiled individually without error, but **broke the full kernel
link** — `$$MOS.SYS` was not produced. Checked and ruled out two
hypotheses with real evidence: `/se:512`→`/se:1024` (linker symbol
table size) made no difference; the `DDT`/`CODE2` segment in a
successful build's own `.MAP` file measures `0A750H` (42,832 bytes),
well under the 64KB hard segment limit, ruling out segment overflow
too. The actual cause of the link failure was not found. Reverted.

**Both attempts reverted; the kernel builds successfully again** as of
this session's end. `MOSDDINT.ASM`'s `ddinit0` is back to its original,
unmodified form.

## Why this specific region is uniquely fragile — understood, not just observed

Read `ddstrat`/`ddinter` (`MOSDDINT.ASM`) and their targets `strat`/
`inter` (`_DPMI.ASM`) directly, without further live instrumentation,
given the risk just demonstrated twice.

`ddstrat`/`ddinter` do not use a normal call/return. `ddinit0` does
`push cs / call ddstrat` (building a return address on the stack
manually), then `ddstrat` itself pushes the *driver's own* handler
address (read from the driver's header, `es:[bx+6]` for strategy,
`es:[bx+8]` for interrupt) and executes `retf` — jumping directly into
`_DPMI.ASM`'s code with a manually-constructed far-return address
still sitting on the stack underneath. The driver's own `strat`/
`inter` routines are expected to eventually `retf` themselves, popping
that same address to return control to `ddinit0`. Any code inserted
inside this window has to keep that stack arrangement exactly intact.
This plausibly explains the `int 10h` hang (a real BIOS interrupt call
from within this unusual, manually-managed control-transfer context
is a reasonable thing to disrupt it) — though not conclusively the
link failure, which remains unexplained.

**Checked both targets directly, and both are confirmed sound:**
- `_DPMI.ASM`'s `strat:` — three instructions, trivially correct: save
  the request-block pointer, `retf`. Standard DOS strategy-routine
  convention.
- `_DPMI.ASM`'s `inter:` — pushes `ds,es,bx,ax` (4 registers) at entry,
  pops `ax,bx,es,ds` (correct reverse order) immediately before its own
  `retf`. Balanced, correct. This is also where `InstallDriver` gets
  called — already proven, via its own internal counters, to run
  exactly once, cleanly.

**This rules out `_DPMI.ASM`'s own dispatch entry points as the
source of the garbage, by direct code review, not just absence of
evidence.** Combined with everything else ruled out this session
(`_DPMI.ASM`'s init chain overall, `adj_smp_alloc`/`calc_size`), the
search space is now: `ddstrat`/`ddinter`'s own kernel-side code
(read, appears simple/correct, but not live-verified given the
instrumentation risk), or `ddinit0`'s own setup code immediately
before calling `ddstrat` (request-block field initialization,
`MOSDDINT.ASM` lines ~762-773 — not yet specifically examined).

## Honest status at session end

Real, substantial progress: several wrong theories identified and
corrected with evidence (not left standing), the search space
genuinely narrowed and most of it now ruled out by direct code
review rather than instrumentation. The exact mechanism remains
unfound. Given how fragile this specific code region has proven
(two failed live-instrumentation attempts), the next session should
be cautious about further markers here specifically — consider
static analysis of `ddinit0`'s request-block setup first, or a
carefully isolated single-instruction-at-a-time approach if live
debugging is attempted again, rather than multi-instruction marker
blocks.

## DEFINITIVE: the garbling is in scbcom24 (serial ports, MOSDEVS.ASM) specifically

Added distinct numbered markers ('1'-'5') directly before each of
`initp2`'s five `call dodrvr` sites, replacing position-counting with
direct identification. Result, no-DPMI config:

```
1[<>{}()]2[<>{}()]3[<>♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦♦()]4[<>{}()]5[<>{}()][<Loading $386.SYS...
```

**Device 3 is definitively, unambiguously the garbled one.** Devices 1
(`scbstdcon`, console), 2 (`mosstdclk`, clock), 4 (`scbstdblk`, standard
disk), and 5 (`scbstdhd`, standard hard disk) are all completely clean.
Device 3 is `scbcom24` — "init devices in MOSDEVS.ASM" — the serial
port devices.

This is a well-scoped, concrete, real lead: `scbcom24` most likely
represents multiple COM ports (COM1-4) as a genuine multi-header
device structure — unlike `$DPMI.SYS` (a real single-header file, where
the `nxtdrvr`/`msdd6` loop-back mechanism traced earlier in this
document should never legitimately trigger), this is exactly the kind
of driver where that same chaining logic is supposed to matter for
real. If there's a genuine bug in how multi-header chaining works,
this is precisely where it would surface.

**Next concrete step**: read `MOSDEVS.ASM` directly — specifically
`scbcom24`'s own device header structure(s) and whatever declares the
chain between individual COM port entries — before attempting any
further live instrumentation, given how fragile the `ddstrat`/
`ddinter` region has proven. This is now unambiguously about
`MOSDEVS.ASM`'s serial port devices, not `_DPMI.ASM`, not the other
four standard devices, and not the `mosddint` linking mechanism in the
abstract — a specific, real multi-header structure to go examine.

## Strong structural lead found in MOSDEVS.ASM — confidence, not certainty

Read `MOSDEVS.ASM` directly. Its own revision history (1988) states
explicitly: *"reordered the headers in here to accomodate the
corrections done in mosddint for device drivers with more than one
header per file"* — direct historical confirmation this file is a
genuine multi-header structure, exactly the kind of driver the
`nxtdrvr`/`msdd6` chaining logic traced earlier in this document is
meant to handle for real (unlike `$DPMI.SYS`, a genuine single-header
file where that logic should never legitimately trigger at all).

`scbcom24`'s `header` macro declares a **25-entry chain**: COM24 down
through COM1, AUX, LPT3, LPT2, PRN, terminating at LPT1 (`dd -1`).
Each entry's own "next" pointer:
```asm
header macro p1,p2,p3,p4
scb&p1  label dword
    dw  mos:scb&p2      ; offset of next header
    dw  0               ; segment of next header -- literal zero
    ...
```
The offset half is a valid, compile-time-resolvable group-relative
reference. The segment half is a **hardcoded literal zero** for every
one of the 25 entries. Checked `dodrvr` (the caller) directly — it
does no fix-up of any kind, just calls `mosddint` with `es:bx` as
given. No patch site was found anywhere searched this session
(`MOSDEVS.ASM`, `MOSINIT.ASM`, `MOSINIT2.ASM`).

**If this segment genuinely needs to be patched to the kernel's own
runtime segment (matching the same "filled in with pointer to next
driver" convention `_DPMI.ASM`'s own header comment describes for
standalone drivers) and that patch is missing**, then `mosddint`
reading this field (confirmed via `msdd6`'s own code: a direct,
unconditional copy of `es:[bx]`/`es:[bx+2]` into `nxtdrvr`, no special-
casing) would produce a "next" pointer of `offset:0000` — dereferencing
deep into low memory near the interrupt vector table, reading and
potentially printing/using unrelated data as if it were a real device
header. That's a precise, mechanical explanation matching the observed
symptom exactly.

**Genuine uncertainty, stated plainly**: whether `dw 0` truly needs a
runtime patch that's missing, or whether this reflects some other
`MASM`/kernel convention not fully understood this session (e.g.
`mosddint` or something else implicitly treating a `0` segment as
"same as current" — checked `msdd6`'s code and found no such special-
casing, but the *full* read/dereference path wasn't traced end to end).
This is a strong, well-evidenced lead, not a confirmed root cause.

**Next step**: trace precisely how `nxtdrvr`'s segment value actually
gets *used* after being read at `msdd6` — specifically, confirm
whether `es` (used for the next iteration's `es:[bx]` header read) is
set from `nxtdrvr`'s segment half directly, and if so, whether a
genuine `0` there is ever caught/rejected before being dereferenced.
Static reading only — this session's two live-instrumentation attempts
inside the related `ddstrat`/`ddinter` region both failed for reasons
not fully understood, so further live debugging here should be
approached cautiously, one minimal change at a time.

## Sharper data: device 3 garbles on first pass only, clean on second

User's numbered-marker test shows two complete passes through all 5
devices (matching `initp2` apparently being invoked twice overall —
once before `[first]` is set to 2, once after):

**Pass 1**: `1[<>{}()]2[<>{}()]3[<>♦♦♦♦♦...{}]4[<>{}()]5[<>{}()]` — device
3 garbled, all others clean.

**Pass 2**: `1[<>]2[<>]3[<>]4[<>]5[<>]` — **device 3 is completely clean
this time.** (Also note: pass 2's markers show only `[<>]` for every
device, no `{}`/`()` at all — different from the earlier
non-numbered-marker session's `[<>)]` finding for "linktype 2." Not
yet reconciled; possibly `initp2`'s second invocation here goes through
a different call context than previously assumed. Flagging the
discrepancy rather than ignoring it.)

**This narrows the question further than "device 3 has a problem"**:
specifically, device 3's *first* invocation of `mosddint` garbles;
its second does not. Since the chain-walking logic (`msdd6`/`nxtdrvr`,
which is where the previous entry's `MOSDEVS.ASM` hardcoded-zero-
segment hypothesis lives) runs *before* the first/second-pass branch
point in `mosddint` — both passes should walk the same 25-entry chain
— this doesn't cleanly fit that hypothesis as-is. Possible
reconciliation, not yet checked: by pass 2, device 3 may already be
linked into the driver list from pass 1 (even though pass 1's own
output was garbled, the *linking* may have still completed), changing
what pass 2's chain-walk actually encounters compared to pass 1's
genuinely-first walk. This would mean the corruption is specifically
tied to walking the chain from its *original, unlinked* state — which
would still be consistent with a bad segment value on the *first*
uncorrected read, if something about the state at that first read
differs from all subsequent ones.

**Not yet resolved** — recorded precisely so the discrepancy isn't
lost, rather than forcing a fit to the existing hypothesis.

## Targeted test result: scbdrvr does NOT change during device 3's processing — reconciliation theory disproven

Added two precise recordings bracketing device 3's `dodrvr` call
specifically: `[scbdrvr]`'s value immediately before (`0040:0130`) and
immediately after (`0040:0132`), staying entirely within `initp2`
(not the fragile `ddstrat`/`ddinter` region).

Result: **`0000` before, `0000` after — unchanged.**

This directly disproves the reconciliation theory from the previous
entry (that device 3 gets successfully linked during pass 1 despite
the garbled output, explaining why pass 2 is clean). `scbdrvr` doesn't
move at all — no linking occurs, successful or otherwise, as a
detectable side effect of device 3's first-pass processing.

Also notable: the value is `0000`, not `-1` (`FFFF`) as this session's
earlier `$DPMI.SYS` testing established as `scbdrvr`'s starting value.
This is a different point in boot (built-in device init, well before
any `CONFIG.SYS` `DEVICE=` processing) — plausible explanations not
yet checked: `scbdrvr` may simply not have been initialized to its
declared `-1` default yet at this point, or devices 1-2 (processed
immediately before device 3, also apparently without visibly changing
`scbdrvr` either, though not directly measured) don't actually link
themselves into this list in the way assumed.

**Status**: the "why does pass 2 come out clean" question remains
open. Ruled out: successful-linking-despite-garbled-output. Still
unknown: what actually differs about device 3's state between its
first and second invocation, given `scbdrvr` itself isn't the answer.
Next step, if continued: check whether `scbdrvr` is even the right
variable to track here at all — the built-in-device linking path
(`linktype` values used by `dodrvr`'s callers) may use `tcbddpf` or a
different list entirely rather than `scbdrvr`, given `msdd8`'s
existence in `mosddint` for exactly this "task-specific"/alternate-
linktype case.

## RESOLVED: why pass 2 is clean — it skips the chain-walk entirely, by design

Found the exact branch, `msdd6` (`MOSDDINT.ASM` line ~365):
```asm
msdd6:
    mov  es,word ptr [origesbx+2]
    cmp  [linktype],2      ; linktype 2, special case from mosinit
    jne  msdd6_not3
    jmp  msdd3              ; <- pass 2 goes straight here
msdd6_not3:
    mov  ax,es:[bx]         ; <- pass 1 only: reads nxtdrvr, walks the chain
    ...
```

On pass 2 (`linktype==2`), execution jumps directly to `msdd3`,
**completely bypassing** the `nxtdrvr` read, the `msdd6`/`msdd1s`
chain-walk loop, and the entire `scbdrvr`-linking logic underneath it.
This is by design, matching the "second pass does less work" pattern
already established (also skips `adj_smp_alloc` and the first
`calc_size`).

This means the earlier "`scbdrvr` unchanged, `0000`/`0000`" measurement
was captured on **pass 1** specifically — and pass 1 is exactly where
`scbcom24`'s real 25-entry chain (COM24 down to LPT1, documented in
`MOSDEVS.ASM`'s own 1988 revision history as a genuine multi-header
structure) actually gets walked. Devices 1, 2, 4, 5 are single-header,
so pass 1's chain-walk for them completes trivially (one iteration,
matching everything else this session established about single-header
files). Device 3 is the only one of the five that's genuinely
multi-header, so it's the only one where this chain-walk does real,
repeated work — 25 potential iterations instead of 1.

**This resolves the "why pass 2 is clean" question completely**: pass
2 doesn't re-walk the chain at all, by design, so whatever goes wrong
during pass 1's genuine 25-entry walk simply never gets a chance to
recur on pass 2.

**Does not yet explain**: what specifically goes wrong *during* that
25-entry walk to produce garbage, or why `scbdrvr` itself never changes
even during pass 1 (if linking is supposed to happen for at least the
head of a legitimately-processed chain, its absence here is itself
worth understanding, not just attributed to "the chain-walk". Given
`scbcom24`'s own 25 headers are declared with a **hardcoded-zero
segment** for each "next" pointer (documented in the "Strong structural
lead" entry above), the natural next check is whether that's the
actual point of failure during this now-confirmed real chain-walk —
that lead was found before this pass-1/pass-2 mechanism was understood,
and now has a confirmed, correct context to be tested in.

**Next step**: with the exact iteration point now confirmed (`msdd6`'s
`nxtdrvr` read/chain-walk, pass 1 only, for `scbcom24` specifically),
recording `nxtdrvr`'s value across each of the (up to 25) iterations
during device 3's pass 1 — the same per-pass recording technique used
successfully for `$DPMI.SYS` earlier this session — would directly
show whether the hardcoded-zero segment is really what's being
dereferenced, and at which specific link in the 25-entry chain it goes
wrong.
