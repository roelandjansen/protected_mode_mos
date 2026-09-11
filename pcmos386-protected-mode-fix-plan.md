# PC-MOS/386 `$386.SYS` Protected-Mode Crash — Fix Plan

Drawn from a full re-read of `pcmos386-protected-mode-addendum.md`.
This is the plan to actually *fix* the crash, not just localize it
further. It separates what is solid from what is still assumed, then
gives an ordered path that is designed to converge on a fix rather
than produce more localization for its own sake.

## What is solid (independently confirmed, not to be re-litigated)

- The crash is a real, deterministic segfault of the emulator when
  `MEMDEV=$386.SYS` is loaded, reproducible on **both** classic
  DOSBox 0.74 and DOSBox Staging 0.83.0. Not an emulator-version
  artifact.
- Under Staging (symbols present) the backtrace is an unbounded
  recursion: `CPU_Interrupt → CPU_Push32 → InitPageHandler::writed →
  CPU_Interrupt → …`, ~26,146 deep, until the host stack overflows.
- Mechanism of the recursion: an exception is raised; delivering it
  pushes an interrupt frame; the push targets a linear address that
  isn't backed by a real page (still on DOSBox's placeholder
  `InitPageHandler`); that push itself faults; delivering *that* fault
  pushes again to the same unbacked address; forever.
- Vector `0Eh` (page fault) is wired as a 32-bit **interrupt gate**
  (IDT access byte `0EEh`), not a task gate — so fault delivery uses
  the *current* `SS:ESP`, no TSS stack switch. The unbacked address
  being pushed to is therefore the current stack.
- The `build_page` identity map (`bpg6`, `256+16` PTEs) covers linear
  `0x000000`–`0x10FFFF` exactly: all conventional memory + UMB +
  64 KB past 1 MB.
- Neither `FREEMEM=C0000,F0000` nor `smpsize` (16 vs 64) changes
  whether the crash happens. Ruled out as triggers.
- **Hardware watchpoints on the in-driver bisection markers A–G show
  none of them ever fire** — not even marker A, placed a handful of
  instructions after the `build_page:` label. Verified not a
  stale-pointer artifact (`MemBase` identical at early breakpoint and
  at crash).

## The central tension the plan must resolve

Two facts point in different directions:

1. The watchpoint says **marker A never executes** ⇒ the failure is at
   or before `build_page`'s first instructions.
2. The logged `CS:IP` (`18:5272h`) decodes cleanly to `test_extmem`'s
   `??0031` label — which is *inside* `build_page`, well past marker A.

These can't both be the true fault location. The addendum's current
best reading — which this plan adopts as its working hypothesis — is
that **(1) is trustworthy and (2) is not**: the logged `CS:IP` is a
snapshot from deep inside the already-cascading recursion (where
`CS`/`EIP` are being rewritten by failing frame pushes), not the
original fault site. Its clean decode is likely coincidental, the same
class of false-positive that the ascending-heap-byte pattern produced
earlier in the investigation.

**Crucial structural fact that reframes everything** (`_386.ASM`
~9367–9385): `build_page` is entered by a far jump through `gdtcode`
issued *immediately after* `mov cr0,eax` sets the PE bit. So the
real→protected-mode transition and the entry into `build_page` are the
same few instructions. "Marker A never fires" is therefore fully
consistent with **the protected-mode transition itself faulting** —
before the first `build_page` instruction retires — which would be
invisible to every marker because all markers live after it.

## Working hypothesis to drive the fix

The first page fault happens at or immediately after the
`PE`-enabling far jump into `build_page`, while `SS:ESP` (or `CS`, or
the jump target) refers to a linear address the just-loaded GDT /
soon-to-be-active identity map doesn't cover. Because the fault is
delivered through an interrupt gate onto that same unmapped stack, it
recurses immediately. Everything downstream (`test_extmem`,
page-table build, `cr3`/`cr0` paging enable) is a red herring — the
machine never gets there.

This is a *refinement* of the addendum's "stack outside the identity
map" candidate, moved earlier: not "stack unmapped when paging is
enabled at the end of `build_page`," but "stack (or code) unmapped/
mis-descriptor'd at the moment protected mode is entered at the
*start*." Note one important nuance: at PE-enable but before paging is
enabled, a fault would be `#GP`/`#SS`, not `#PF` — so if the recursion
truly involves `InitPageHandler` (a paging construct), paging may
already be on at the fault, which points back toward the end-of-
`build_page` window after all. **Resolving which of these two it is
(pre-paging entry vs. post-paging enable) is step 1 of the plan** —
the watchpoint and the backtrace currently disagree and that
disagreement is the crux.

## The plan, ordered to converge on a fix

### Step 1 — Settle the contradiction directly, with a breakpoint on the transition (not a marker)

Markers can only report points *after* they execute; they can't see a
fault in the transition itself. Use the debugger on the emulator
instead:

- Under Staging + `gdb`, set `handle SIGSEGV stop nopass`, then a
  **breakpoint on `CPU_Interrupt`** conditioned on the vector being an
  exception (`0x0E`, and also check `0x0D`/`0x0C` — `#GP`/`#SS` — since
  pre-paging the fault would be one of those). Use `ignore` or a
  counting condition to skip DOSBox's own startup faults (the earlier
  entries already catalogued that vector 14 fires benignly during
  `DOS_Shell::ExecuteProgram` and EMS init — condition on the fault
  address or on guest `CS`/`EIP` being in `$386.SYS`'s range to skip
  those).
- At the **first** guest-originated exception, capture: the vector,
  guest `CS:EIP` (via `Segs`/`cpu_regs`, using the real struct layout
  already recovered from `registers.h`), guest `SS:ESP`, and `CR0`
  (is PG set yet?) and `CR2` (the faulting linear address, if `#PF`).
- `CR2` is the single most valuable number not yet captured: it is
  *the* unmapped linear address the whole recursion is about. It
  converts "the stack is probably unmapped" into "linear address X is
  unmapped," which is directly checkable against the identity map.

Deliverable: the true first-fault vector, faulting address, and
whether paging was on. This ends the watchpoint/backtrace
disagreement definitively.

### Step 2 — Pin the fault to a specific guest instruction and cause

With the true guest `CS:EIP` from step 1 (not the recursion-corrupted
`5272h`), decode it against the `.LST` already generated
(`build/latest/_386.LST`, INIT32 base `04740h`). Combined with `CR2`
and PG state, this identifies the exact instruction and which of these
it is:

- **(a) stack not mapped**: `SS:ESP`'s linear address > `0x10FFFF`
  (the HMA-load candidate). Confirm by comparing `CR2` / the pushed
  address to the driver's actual load segment (`CS*16 + pt_stack`).
- **(b) code not mapped**: the `build_page` target itself (`CS:EIP`
  linear) is outside the identity map — same root cause (high load),
  different symptom.
- **(c) a descriptor problem**: `gdtcode`/`gdtdata` base got relocated
  wrong, so the selector resolves to a bad linear base regardless of
  the identity map. (Relocation code at ~9336–9355 relocates
  `gdtcode`/`gdtdata`/`gdttss1/2` but the values it adds are derived
  from `CS`; a high `CS` is exactly what would push these bases out of
  the mapped range.)

All three converge on the same underlying variable: **where DOS loaded
`$386.SYS` (its `CS`).** So:

### Step 3 — Capture the driver's actual load segment

Independently of the fault, get `$386.SYS`'s load `CS`. Two routes,
either works:
- Breakpoint in the emulator at the driver's real-mode entry
  (`init` command dispatch, before any PM transition) and read guest
  `CS`. This is *before* the fault, so no recursion corruption.
- Or the marker pipeline: add one marker at the very first real-mode
  instruction of the driver's `init` handler that writes `CS` itself
  (not a constant) to video memory — this is the "record CS at driver
  entry" idea from the addendum, now the clearly-indicated next
  instrumentation and known to work end-to-end.

If `CS*16` puts the driver at/above `0x100000`, the HMA-load
hypothesis is confirmed and the fix target is clear.

### Step 4 — Fix, choosing the correct layer

Depending on steps 1–3, the fix is one of:

- **If the driver loads into HMA/high memory and the identity map
  simply doesn't reach it**: extend the identity map in `build_page`
  to cover the driver's own load region before enabling paging. The
  map is built by a counted `stosd` loop (`bpg6`); the fix is to
  ensure the PTE range includes the linear region containing
  `SS:ESP`/`CS`. This is the most likely fix and the most in-spirit
  one (the driver must map its own code+stack before it can survive
  paging).
- **If a GDT descriptor base is mis-relocated**: correct the
  relocation math at ~9336–9355 so `gdtcode`/`gdtdata` bases land in
  the mapped range. Less likely but must be excluded by step 2.
- **If the stack specifically is the only unmapped piece**: point
  `SS:ESP` at a stack that *is* inside the identity-mapped region for
  the duration of the PM setup (e.g. a low-memory scratch stack),
  rather than the relocated `pt_stack`. `pt_stack` lives in INIT32,
  which is part of the driver image — so this is the same root cause
  as (a), and mapping the driver region fixes it too.

Whichever it is, the change is small, local to `build_page`'s setup or
the relocation block, and testable immediately with the pipeline
already built.

### Step 5 — Verify the fix the same way the crash was found

- Rebuild `$386.SYS` with the fix (MASM-under-DOSBox recipe,
  `dobuild.bat`, already working — do **not** rely on UASM for
  `_386.ASM`; it can't assemble this file, established earlier).
- Boot under DOSBox Staging with `MEMDEV=$386.SYS`, no DPMI. Success
  = no segfault, boot proceeds past the point it currently dies.
- Then re-enable the bisection markers' logic as a positive check:
  with the fix in, markers A–G *should* now fire in order (via the
  same hardware-watchpoint harness), directly confirming
  `build_page` now runs to completion.
- Finally, retest with DPMI re-enabled — expect the separate,
  already-documented `SegToSel` issue to resurface next; that's a
  known, distinct problem, not a regression of this fix.

## Guardrails carried from the addendum

- **Trust mechanical facts over decoded snapshots.** The watchpoint
  (mechanical) outranks the logged `CS:IP` (a snapshot mid-recursion).
  `CR2` at the *first* fault is mechanical and is the number to get.
- **One clean debugger reading beats a timeout-truncated one.** Always
  `handle SIGSEGV stop nopass` and avoid `timeout -s KILL` racing
  DOSBox's own crash handler (it produced a spurious `SoundBlaster`
  backtrace once).
- **`gdb` `find` halts at the first unmapped gap** — don't use it for
  broad memory sweeps; use watchpoints / targeted reads.
- **Conditional breakpoints on hot paths (`mem_writeb`) are too slow**
  to reach the driver in reasonable time — condition on vectors/
  addresses at `CPU_Interrupt`, or use hardware watchpoints, instead.
- `_386.ASM` must be built with the original MASM/LINK (UASM chokes on
  its `nca segment at 386h` hand-encoded-opcode trick).

## Why this converges (vs. more localization)

Every prior step localized by elimination and kept discovering the
fault was "earlier than thought." Step 1 breaks that regress by
capturing the *first* fault directly with `CR2`, which is a single
authoritative address rather than an inference. Steps 2–3 turn that
address into "the driver loaded here, the map covers there, the gap is
X." Step 4 closes gap X. That is a fix, and step 5 proves it with the
harness that already exists.
