# PC-MOS/386 v5.01 — Protected Mode: Current State and Extension Options

Source reviewed: `SOURCES/src/latest` (the tree actually built by `MAKEMOS.BAT` → `kernel.mak` → `$$MOS.SYS`), plus `_386.ASM` (`$386.SYS`) and `_DPMI.ASM` (`$DPMI.SYS`).

## 1. The kernel already has more 386/protected-mode plumbing than expected

Three separable layers exist today:

### a) The kernel core (`MOSxxx.ASM`, linked into `$$MOS.SYS`)
No `.386` directive anywhere in the scheduler/DOS-API/filesystem modules
(`MOSNXTSK.ASM`, `MOSITASK.ASM`, `MOSCNTXT.ASM`, `MOSFRONT.ASM`, `MOSINIT.ASM`,
etc.). This is 16-bit, segment:offset code, unchanged in spirit since the
8086/286-era multiuser design. `MOSCNTXT.ASM` explicitly supports task
switching both "for non memory management multitasking" (plain physical
copy/bank-switch of task RAM — works on an 8086) and "the memory managed
case" (386, via paging). In other words: **the kernel's own execution model
never left real mode**; the 386 path only changes how task memory is
remapped underneath it.

### b) `$386.SYS` (`_386.ASM`, ~9,900 lines) — the V86/paging supervisor
This is the piece that actually flips `CR0.PE`. Around `build_page`/`vmstart`
it:
- builds a GDT/IDT (`wsgdtr`, `wsvmidtr`),
- sets `CR0.PE` (and later `CR0.PG`, message: *"386 Protected mode and
  paging are now active."*),
- immediately drops into **Virtual-8086 mode** and stays there for the
  kernel and every DOS task.

So on a 386, PC-MOS already runs as a true ring-0 protected-mode+paging
supervisor whose only job is to virtualize N real-mode DOS sessions (V86
tasks) — architecturally the same idea as DESQview-386 or Windows 3.x
386-Enhanced mode's virtual machine manager. Memory isolation between users
comes from page tables, not segment limits.

### c) `$DPMI.SYS` (`_DPMI.ASM`, ~4,300 lines) — a genuine DPMI 1.0 host
Written by Stewart Hyde, 1990–91, against the VCPI/DPMI spec. It is far more
complete than a stub — the vectored dispatch table covers:

- **0000–000F**: LDT descriptor management (Allocate/Free LDT, get/set base,
  limit, access rights, create alias, get/set descriptor, multiple-descriptor
  alloc)
- **0100–0102**: DOS conventional-memory block alloc/free/resize
- **0200–0213**: real-mode interrupt vector get/set, protected-mode
  exception get/set (including the "extended" 0x0210–0x0213 variants)
- **0300–0306**: simulate real interrupt, call real-mode proc, real-mode
  callbacks (alloc/free), get raw mode-switch address
- **0400/0401**: get DPMI version / capabilities
- **0500–050B**: extended memory alloc/free/resize, **linear** memory
  alloc/resize, page attributes, device-memory mapping, conventional-memory
  mapping, get memory base/info
- **0600–0604, 0702–0703**: page lock/unlock/mark-real/relock, virtual-memory
  functions
- **0800/0801**: physical address mapping / unmapping
- **0900–0902**: virtual interrupt state (disable/enable/get)
- **0A00**: PC-MOS-specific API passthrough
- **0B00–0B03**: hardware debug register support
- **0C00/0C01**: install resident / DPMI TSR support
- **0D00–0D03**: shared memory
- **0E00/0E01**: MPU status/emulation control

`AccessBits equ 1` and 32-bit `CX:DX` linear addresses/limits throughout
`SetSegBase`/`SetSegLimit`/`SetDescriptor` confirm this host already reports
**32-bit segment support** — i.e. a DOS/4GW-, PharLap-, or Watcom-extended
32-bit protected-mode client can in principle already run as a real ring-3
protected-mode process inside a MOS user session, alongside the V86 DOS
tasks. `code32`/`init32` segments (`use32`) exist inside the driver itself.

## 2. What this means for "extend it for protected mode"

You're not starting from zero — you're starting from a working three-layer
design (16-bit real-mode kernel core → 386 V86/paging monitor → DPMI 1.0
host for protected-mode guests). The open question is which layer you
actually want to extend, because the three have very different scope and
compatibility risk:

| Option | What it touches | Compatibility risk | Payoff |
|---|---|---|---|
| **A. Harden/complete the existing DPMI 1.0 host** | `_DPMI.ASM` only | Low — kernel core untouched | Lets more/newer DPMI clients (Watcom, DOS/4GW-linked binaries, later Windows 3.x standard-mode pieces) run reliably; a compliance audit against the DPMI 1.0 spec (function-by-function) would likely turn up gaps or bugs worth fixing first |
| **B. Give the kernel core a native 32-bit flat-mode path** | `MOSxxx.ASM` scheduler/API/FS, `MOSCNTXT.ASM` context switch, `MOSTCB.INC`/`MOSSCBDF.INC` structures | High — this is a real kernel rewrite of the segment-based internals | Removes the 16-bit segment/64KB-object ceiling from kernel data structures (buffers, task tables, filesystem cache); biggest engineering lift by far |
| **C. Add a thin protected-mode kernel service layer on top of (b/a) without touching the DOS-compat core** | New module(s) callable via the existing `$DPMI.SYS`/`_386.ASM` mechanisms | Medium — additive, existing V86/DOS path stays as-is | A middle ground: e.g. a native 32-bit API surface for new tools while old DOS apps and TSRs keep working exactly as today |

Given the existing shape of the code, **A is the natural "protected mode for
a start" step**: it's self-contained, it's the layer that already speaks
DPMI 1.0, and getting it solid is also a prerequisite for B or C (any native
protected-mode kernel service will want to reuse the same GDT/LDT/paging
primitives `_386.ASM`/`_DPMI.ASM` already implement).

## 3. Concrete first tasks if going the DPMI-audit route (Option A)

1. Diff the implemented vector table above against the DPMI 1.0
   specification's mandatory function list — flag anything missing
   (0x0D — shared memory — and 0x0E — MPU — are non-standard PC-MOS
   extensions and worth understanding on their own).
2. Trace `GetDPMICap` (0x0401) to see exactly what capability flags are
   currently advertised to clients — this tells you what real-world DPMI
   clients will assume is safe to use.
3. Exercise `AllocateLdt`/`SetDescriptor`/`CreateAlias` against a real
   32-bit DPMI client (Watcom's DOS4GW-alternative or a small hand-written
   test client) under `run.sh` (DOSBox) to confirm 32-bit selectors survive
   a context switch when another user's V86 task interrupts (this is where
   Option A work would intersect `MOSCNTXT.ASM`'s save/restore — worth
   checking whether DPMI client state is preserved correctly across a
   preemptive switch to a different user session).
4. Only after that: decide whether kernel-core changes (Option B) are
   actually needed, or whether Option C's thin layer gets you what you want
   without touching the DOS-compatible core at all.

---

## 4. STATUS UPDATE — what has since been established empirically

This note was written from **source reading only**. Subsequent work booted
and instrumented the system, and two of its conclusions need qualifying.
The architectural analysis in §1 and §2 stands; the readiness assessment in
§2 and §3 does not.

### `$386.SYS` (§1b) — confirmed working

The V86/paging supervisor does what this note describes. PC-MOS boots to a
live, responsive prompt in protected mode with paging active, verified by
typing at the prompt and getting real answers back. `build_page` completes,
`CR0.PE`+`CR0.PG` are set, `vmstart` is entered and survives its `sti`, and
the "486 Protected mode and paging are now active." message prints.

One caveat: the binary confirmed clean is the **shipped 5.01.01 (940421)**
9-user build. Our source tree builds **5.01 (921119)**. These are different
revisions, so "the original works" is proven for a later shipped build, not
for the source we hold.

### `$DPMI.SYS` (§1c) — **does NOT install**

This is the correction that matters. §1c called it "a genuine DPMI 1.0 host"
and "far more complete than a stub", and §2's option table rated hardening it
as **low risk / kernel untouched**. The dispatch-table inventory in §1c is
accurate — but the driver never gets far enough to use any of it:

```
[A:\]DUMPLOG
No DPMI host found (int 2Fh 1687h failed)
```

`CheckFor386SYS` refuses on both of its paths. One path reports "386 Memory
Manager required" (`scbmmfg` is not `'Y'`, reproduced against the original
`$386.SYS` too). The other is an explicit refusal, deliberately added,
because `InitProtect` depends on `SegToSel`, which has **no working
implementation** — it calls int 6Fh with `SEGMENT_SELECTOR=7786h`, nothing
implements it, and it ends up executing whatever sits at the never-hooked
real-mode int 6Fh vector. Confirmed to crash DOSBox outright, not just the
guest.

**Consequence for §2's Option A.** "Harden/complete the existing DPMI host"
is not a low-risk audit-and-patch exercise. Before any of §3's tasks 1–3 can
be attempted, `SegToSel` has to be genuinely implemented — building a real
GDT descriptor rather than routing through an unimplemented int 6Fh. That is
foundational work, not hardening. §3's tasks remain the right follow-on
sequence *after* that, not before.

Also note the refusal in `CheckFor386SYS` must stay until `SegToSel` is real.
It looks like a bug and is not one; removing it to "make DPMI install" walks
straight into the int 6Fh crash.

See `pcmos386-protected-mode-fix-plan.md` for the ordered plan and
`pcmos386-protected-mode-addendum.md` for the measurements behind all of the
above.
