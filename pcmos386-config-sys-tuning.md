# PC-MOS/386: CONFIG.SYS Tuning — SMPSIZE / FREEMEM / MEMDEV

Working session tuning a DOSBox test config for multiple concurrent full
DOS sessions. Started from a misreading of what `SMPSIZE=` actually
controls, worked through the source to find the real levers, and ended
on a config that gives 9 tasks at ~612K each. Writing up what each
directive actually does, the parser gotchas that cost real time, and
the load-order dependency between them — so this doesn't need
re-deriving from `_386.ASM`/`_EMS.ASM` next time.

## Starting point and the misconception

Initial test config:
```
smpsize=32
cache=16
```
The assumption going in was that a low `SMPSIZE=` was capping the number
of concurrent tasks, and that with SMP at 32 only one or two tasks could
be added before conventional memory got split into slivers. That's
half right, for the wrong underlying reason — and there were two
separate mechanisms being conflated.

## What SMPSIZE= actually is

`pcheps` (`MOSINIT2.ASM`) parses `SMPSIZE=` directly into `scbhpsiz` —
the **System Memory Pool**, clamped 8–440K. This is the kernel's own
heap (SCBs, buffer control blocks, task runtime structures) — not a
task count and not user-task memory.

It does gate task count indirectly, though: `vertask` (`MOSITASK.ASM`)
checks free space across `scbhpadr`/`scbhp2adr` before allowing a task
switch/admission, requiring roughly 8K+ free per task (plus 8087/80287
overhead if present). So a too-small pool silently caps how many tasks
can be admitted — at `SMPSIZE=16` maybe one or two tasks before
`vertask` refuses admission with "Need larger SMPSIZE= in CONFIG.SYS".
In practice actual steady-state consumption per task came in well under
the 8K floor once several tasks were resident — 9 tasks fit inside
`SMPSIZE=48` (48K), well below the naive `48÷8=6` estimate.

**Actual task-count ceiling** is `MAXUSERS`, a compile-time `equ`
selected by which `xUSERS.INC` gets assembled into the kernel
(`1USERS.INC`=1, `5USERS.INC`/`MAXUSERS.INC`=5, `25USERS.INC`=100 in
this tree) — not runtime-configurable via CONFIG.SYS at all.

## Why tasks were splitting one shared 640K

Without a `MEMDEV=` line, MOS runs in the "non memory management"
task-switch model (`MOSCNTXT.ASM`'s own terminology) — plain physical
copy/bank-switch of task RAM within one shared real-mode 640K. Every
task genuinely was fighting over the same pool.

`MEMDEV=$386.SYS` loads the V86/paging supervisor (`_386.ASM`). Once
active, `CR0.PE` gets set, paging comes up, and each task becomes a
page-table-isolated V86 view instead of a bank-switch slot. `$386.SYS`
takes an optional bare KB value (`meg0new`, range 64–704, rounds to
4K) as its own first parameter for the conventional-memory size of
each mapped view — defaults to whatever BIOS reports at load time.

## FREEMEM= and the parser gotcha that ate the first attempt

`FREEMEM=` (`pcfree`, `MOSINIT2.ASM`) declares up to 5 address ranges
MOS can relocate its own resident footprint (kernel, disk buffers,
heap) into — normally segments C000–F000 (upper memory, adapter
ROM/shadow region), which `fmsrch` auto-scans for free 4K blocks if no
`FREEMEM=` is given at all. Relocating MOS's own resident structures
out of low conventional memory is what raises the per-task ceiling —
this is the mechanism that got the ~612K figure, not a full 640K
(fixed low-memory overhead — IVT, BIOS data area, an unrelocatable
resident stub — accounts for the remaining gap).

**First attempt used `FREEMEM=C0000-F0000` (dash) and it silently did
nothing.** `getparm`'s numeric parser only recognizes a comma as the
separator between two values, and caps each number at 4 digits. Traced
through:
- First value: reads `C000` (4 digits; the trailing `0` in `C0000` and
  the `-` both get skipped as junk while scanning for a terminator)
- Second value: never reached — `do2nd` only fires on a comma, so the
  parser just skips straight past `F0000` to end-of-line
- Result: `ax=0xC000`, `cx=0` — a start address with a zero end address

`dmadjst` then finds that zero end value, takes the `dmabad` branch,
prints `Invalid FREEMEM values`, and nulls the whole entry
(`0xFFFF/0xFFFF` — marked unused). **Correct syntax: comma-separated,
`FREEMEM=C0000,F0000`.** (The 4-digit cap isn't a problem in practice —
`C0000`/`F0000`'s truncated-to-4-digit reads, `C000`/`F000`, are
exactly the segment/paragraph values `fmsrch`'s C000–F000 scan range
already uses.)

## The deeper gate: FREEMEM does nothing without a MEMDEV driver either

Independent of the dash/comma issue: `fmsrch`/`dmadjst` only run at
all if `scbmmfea` (memory-manager feature flags) has bit `0x80` ("full
mapping supported") set:
```
test [scbmmfea],80h    ; is full mapping supported?
jz   exit4p              ; no, skip
call fmsrch
call dmadjst
```
`scbmmfea` is statically zero-initialized (`MOSSCBDF.INC:
scbmmfea db 0`) and only gets populated by `mminit` when a `MEMDEV=`
driver is loaded and reports its features back. **So `FREEMEM=` is
inert with no `MEMDEV=` line present, regardless of syntax** — the
~610K/task seen in an earlier run with `FREEMEM=` set but no
`MEMDEV=` line was baseline MOS behavior, not FREEMEM doing anything.

`initp4` (`MOSINIT2.ASM`) confirms the required order: it loads and
initializes the `MEMDEV=` driver *first*, then processes `FREEMEM=` —
so `MEMDEV=` must appear before `FREEMEM=` takes effect, though not
necessarily before it in the file textually (`initp4` handles both
regardless of their order in CONFIG.SYS; what matters is driver load
happening internally before the FREEMEM pass, which the code
guarantees on its own).

## Working config (9 tasks × ~612K)

```
smpsize=48
cache=16
MEMDEV=$386.SYS
FREEMEM=C0000,F0000
```

Confirmed: 9 concurrent tasks, ~612K conventional memory each — close
to the practical ceiling given fixed low-memory overhead that
`FREEMEM=` can't relocate away.

**Not yet verified at boot**: absence of the `Invalid FREEMEM values`
message (confirms the comma fix took), and `$386.SYS`'s own
startup banner confirming protected mode/paging genuinely came up
under DOSBox's CPU core rather than silently falling back to
bank-switch mode. Worth checking both next time this config is
touched.

## $EMS.SYS — dependency, not yet added

Considered adding `DEVICE=$EMS.SYS [size]` on top of this. Findings,
not yet acted on:

- **Hard dependency on `MEMDEV=`**: `$EMS.SYS`'s init code opens a
  device named `$$MEMDEV` (the reserved handle for whatever driver
  `MEMDEV=` loaded) and reads memory info back from it. If that open
  fails, it prints an error and self-neuters (blanks its own device
  name so it can't be opened at all). **`MEMDEV=$386.SYS` must be
  loaded before `DEVICE=$EMS.SYS`.**
- **Shares the same extended-memory budget as per-task paging**:
  `$EMS.SYS` draws its page pool from the same driver (`$386.SYS`)
  backing the per-task conventional views. It's not a separate memory
  source — EMS capacity trades directly against per-task ceiling
  and/or max task count, not something added "for free."
- **Per-task EMS handle state, shared global pool**: revision comments
  reference "Task Specific EMS 4.0 data areas" — each task tracks its
  own EMS handles/mappings independently, but they all draw from one
  shared system-wide page pool, not 9 separate private EMS
  allocations.
- **Not traced yet**: the exact `[size]` parameter's units/parsing in
  `_EMS.ASM` — unlike `$386.SYS`'s parser, this wasn't walked through
  line-by-line. Needed before picking an actual size value.
- **Decision**: held off for now — nothing currently planned to run in
  these sessions is EMS-aware. Add only when a specific application
  needs it, or to move something like a disk cache/RAM disk out of a
  task's conventional 612K into EMS-backed space.
