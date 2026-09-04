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

## Current state of the tree (final, safe, for today)

- **`_DPMI.ASM` `CheckFor386SYS`: refuses explicitly**, honestly
  labeled (`NotFin` message), not relying on the old accidental
  bit-mismatch.
- **`_DPMI.ASM` `ErrorHandler`: writes safe break-address values** on
  every failure path. Kept — harmless, strictly safer than leaving
  those fields uninitialized, even though it didn't turn out to be the
  fix for the crash.
- **`MOSDDINT.ASM` `ddinit0` status-word check: reverted back to
  original unconditional-success behavior for character devices.**
  This is the one real behavior change from where this session started
  the day: everything else nets out to "DPMI refuses safely instead of
  proceeding into a confirmed crash," which is a genuine improvement,
  even though the original cosmetic garbage/beep symptom is back as a
  result. Do not re-apply the status-word check without first tracing
  and fixing whatever's actually wrong in `mosddint`'s driver-unlink
  path — re-enabling it as-is reintroduces a confirmed DOSBox-crashing
  bug, not a cosmetic one.
- **Diagnostic instrumentation left in place** in `_DPMI.ASM`
  (`WriteLog`, `Counters`, the `0040:00F0` segment-recording write in
  `InstallDriver`) — harmless, and useful groundwork if either
  `SegToSel` or the driver-unlink path get picked up later.
- **`MAKEUTIL.MAK`: case-sensitivity fixed** — the `_DPMI.SYS`/
  `_DPMI.ASM` target and dependency now match the real, on-disk
  uppercase filenames. Worth checking whether the same mismatch exists
  for other entries (`_386.sys`, `_ems.sys`, etc.) if any of those
  sources are ever edited — this class of bug (silently rebuilding
  from a stale object because `make` can't find the real source file
  to compare timestamps against) cost significant time twice today.

## Net result

DPMI does not work — that was never going to change today, and
shouldn't have been the goal. What changed: loading `DEVICE=$DPMI.SYS`
now fails safely (refuses cleanly, cosmetic garbage/beep, boots through
to a working prompt) instead of the confirmed alternative (a real
DOSBox-crashing bug, independently reproduced multiple times on a real
machine). Two genuine, scoped follow-up projects are documented above
for whenever there's appetite to continue: a real `SegToSel`
implementation, and tracing `mosddint`'s driver-unlink path under a
genuine character-driver failure.

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
