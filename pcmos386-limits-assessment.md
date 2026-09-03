# PC-MOS/386: Hard Disk and Memory Limits — What I Actually Found

Two separate questions here — disk volume sizing, and how much memory each
user "virtual machine" can get — with different amounts of confidence
behind each finding. Flagging that difference explicitly rather than
presenting both as equally solid.

## 1. Hard disk sizing — confirmed, concrete, and it's the classic one

`HDSETUP.ASM` hardcodes the DOS 3.x-era 32MB-per-logical-volume ceiling:

```
msg3e   db 'NOTE:        Logical disks larger than 32mb are inaccessable by DOS.   $'
```

Rather than just refuse larger disks, it works around its own limit: the
`Do_32meg_Vols` routine auto-slices a larger physical disk into multiple
32MB logical volumes, and prompts the user ("Shall I build multiple 32
megabyte partitions") when the whole-disk option would exceed that.

The disk-structure definitions in `DSKSTRUC.INC` (boot sector / BPB layout)
already carry the DOS 4+ "large disk" fields — `btHugeSectors`/`bsHugeSectors`
(`dd`, 32-bit) alongside the older 16-bit `btSectors`/`bsSectors` — so the
on-disk structure isn't itself the bottleneck. The 32MB ceiling looks like a
deliberate DOS-3.x-compatibility choice enforced in `HDSETUP.ASM`'s setup
logic, not a hard structural limit — which means it's a plausible thing to
revisit (larger single FAT16 volumes, bigger clusters) without a structural
rewrite, but I haven't traced how far downstream that assumption reaches
(filesystem driver code, `DIRSIZE`/`NCD`-style utilities, anything else that
assumes a 32MB-scale volume) — that needs its own pass before touching it.

## 2. Memory ceiling — one confirmed data point, and it's the wrong one

I went looking for a hardcoded total-memory ceiling in the 386-specific
memory manager (`_386.ASM`, the piece that actually matters for the
protected-mode/paging work) and didn't find one in a reasonable search —
`parmgran dw 4096,0` (4K page granularity) is there, but no obvious
fixed page-count or megabyte ceiling. That's tentatively good news, but
it's an absence-of-evidence result, not a confirmed "no limit" — worth
someone tracing the actual page-table allocation path (around
`build_page`, covered in the protected-mode assessment note) before relying
on it.

What I *did* find and can confirm is a hardcoded ceiling — but it's in the
wrong place to matter here:

```
IF GIZMO
parlimit equ    08a0h    ; support up to 8mb + 640k
```

This sits inside `IF GIZMO`/`IF GIZMO+CHARGE` conditional-assembly blocks
in `MOXMEM.INC` and `_386.ASM`. "Gizmo" and "Charge(Card)" are legacy,
specific third-party bank-switched memory-expansion boards from the
pre-386/286 era (see the revision-log comments in `_386.ASM`, e.g. "support
upper-60k for gizmo & chargecard" / "gizmo wraps at 1mb") — this is a
compatibility shim for old hardware, not part of the general 386 paging
path. It's very unlikely to be relevant to extending the protected-mode
work, but I'm noting it since it's the one concrete ceiling I actually
found, so it doesn't get mistaken for "the" memory limit later.

## 3. The 640K-per-session question is a different kind of thing

Every individual DOS task still runs against DOS's own 640KB conventional-
memory application model — that's not a bug to patch, it's what "running
unmodified real-mode DOS software" means. The existing architecture already
has the right lever for this, covered in the protected-mode assessment
note: each user session is a V86 task under `_386.ASM`'s paging-based
memory manager, and MOS already supports EMS/XMS-style backing pools beyond
the 640K conventional window for tasks that use them. "More space per
virtual machine" in a useful sense means:

- more/larger EMS or XMS pool per session (a `_386.ASM`-side memory
  manager question — ties into §2 above, since it's the same allocator),
- and, if the isolation goal is the real driver, leaning on the DPMI 1.0
  host (`_DPMI.ASM`, already fairly complete per the protected-mode
  assessment note) to give protected-mode-aware applications real access to
  more than 640K directly, rather than trying to stretch the 640K
  real-mode ceiling itself, which isn't a MOS limitation to fix — it's
  x86 real-mode addressing.

So the useful next step here isn't "raise 640K" (not fixable without
dropping DOS-app compatibility) — it's tracing the actual page-table/EMS-
pool allocation ceiling in `_386.ASM` referenced in §2, which is still an
open question rather than a confirmed number either way.
