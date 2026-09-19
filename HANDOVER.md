# PC-MOS/386 — Handover

State of play and how to resume. Written to be the first thing read in
a fresh session.

## Headline

**PC-MOS/386 boots to a live, responsive prompt in protected mode with
paging active.** Verified by typing at the prompt and getting real
answers back, not by screen inspection. The tree started this session
hanging with no prompt at all.

`$DPMI.SYS` **installs** and clients reach protected mode (UPDATE 15).
The `6FEB` return-address corruption and the `7786h` handler crash are
both solved: assembler encoding defects in original TSL code, not
monitor logic. All diagnostics are stripped from every source.

## Current state (2026-09-19, after UPDATE 15)

`$DPMI.SYS` **installs**, and a DPMI client **reaches protected mode**.
Tree = the UPDATE 13 baseline plus `_386.ASM`, `_DPMI.ASM`, `_DPMI.INC`,
`MAKEUTIL.MAK` and the new `DPMITST.ASM`. Kernel unchanged. Measured:

- `DEVICE=$DPMI.SYS`: sign-on banner, `Dos Protected Mode Insterface
  Installed.`, `0000000K of Extended Memory Available.`, SMP line,
  `[A:\]` prompt
- no DPMI: date/time prompts, `$$SHELL.SYS version 5.04`, `VER` answers
- `DPMITST.COM`: host reports `ax=0000`, entry `C0DE:00A6`, flags `0001`,
  version `1.00`, 5 paragraphs; the mode-switch entry returns carry set
  and the client survives

**C4 is blocked on architecture, not a bug.** The switch works — the
client really does come back `vm=0`, `cpl=3` — but there is no executable
descriptor for its own code. `nmswitch` builds its code descriptor from
whatever ran at switch time (the host), and `makegdte`/`7786h` build data
descriptors only. Live GDT: `006B` code base `C0DE0` (the driver),
`005B` data base `0008AA0` (the client). Returning to either aborts.
`GoProtect` therefore refuses with carry set, per DPMI 0.9; the code
below the refusal is intact for when a code selector can be supplied.
See UPDATE 15 and section 7 of the design note.

Not bugs: `0000000K` is original TSL code that never fills the digits;
`install not done` is a hardcoded `ECHO` in the test `AUTOEXEC.BAT`.

**The dominant defect class in this codebase** is code assembled for one
operand size executing under the other, plus plain `offset` where
`offset ddt:` is needed — seven bugs so far. MASM cannot encode a
`use32` -> `use16` call at all, and `addrnca`/`makegdte` both return 2
bytes, so such calls need a `res16` wrapper reached through a dword
pointer. Check any such transfer, and anything executing after `goprot`,
**in the linked binary** — the listing shows pre-link values and can look
right when the bytes are wrong.

`nxtdrvr` is still unvalidated.

Next: decide how the host supplies a client code selector — a
code-descriptor variant of `makegdte` behind a new `7780h` function, or
`nmswitch` building CS from the caller's return frame — and settle
descriptor lifetime at the same time (`cleardti` frees task-owned
descriptors on every switch, so client selectors must be permanent).

## Baseline (set 2026-09-17, supersedes the UPDATE 8 tree)

The working baseline is **UPDATE 8 source minus the trap-nesting
counter**. `pcmos386-baseline.diff` (`patch -p1` from the repo root) is
the whole change: the counter code, its comment and its label, 13
code lines plus comment, `_386.ASM` only. `nestcur`/`nestmax`
declarations stay for now (removing them shifts layout; strip with the
other diagnostics).

Why: the UPDATE 8 build, with the counter in, **never reaches
`$DPMI.SYS`**. It parks right after `$386.SYS` returns (`V W`,
`>{}()]`, no pass-2 device markers, v-86 spinning at `76CD:FC8x`),
2 of 2 boots. The measurements below were taken on the build *before*
the counter. Without it the tree reproduces them exactly, including
`6FEB 6FEB 0E07 2428 D120`, 2 of 2 boots. No DPMI config: live prompt,
`VER` answers.

Verified at each step, not assumed:

- rebuilt from scratch with an error gate (obj/exe deleted first,
  listing checked): 0 warnings, 0 severe errors
- removing the comment and label is byte-identical to the tested
  code-only removal
- tree `$386.SYS` = that build; tree `$DPMI.SYS` = `DPMI.SYS.built`
  (itself byte-identical to a rebuild of the tree's `_DPMI.ASM`)

## Read these, in this order

1. `pcmos386-protected-mode-fix-plan.md` — rewritten; the old version
   planned a hunt for a crash that turned out not to exist
2. `addendum-session-entry.md` — 15 sections, chronological; append to
   `pcmos386-protected-mode-addendum.md`
3. `CHANGES.md` — every code change, split into REAL FIXES vs
   DIAGNOSTICS TO STRIP
4. `pcmos386-changes.diff` — unified diff against the tree as
   uploaded; `patch -p0` from the repo root reproduces the UPDATE 8
   state
5. `386-baseline.diff` — `_386.ASM` against the tree as uploaded: removes the nesting
   counter; `patch -p1` from the repo root gives the baseline
6. `pcmos386-protected-mode-entry-design.md` — **read before any
   further DPMI work**; the architecture and the ordered plan
7. `dpmi-all-changes.diff` — on top of 5, all `_DPMI.ASM` work: the three
   encoding fixes (UPDATE 10) and the strip (UPDATE 11); in the tree
8. `goprot-goreal.diff` — `_DPMI.INC` mode-switch macros; measured,
   **not applied** (see UPDATE 10)

## Seven real fixes (keep)

All original-source bugs, all verified. The last three are UPDATE 10
(see CHANGES.md for the measurements behind them):

| fix | file | what |
| --- | --- | --- |
| `OFFSET ddt:` | `_DPMI.ASM` | MASM `OFFSET` is segment-relative, not group-relative; LINK does not fix it up despite the `R` flag. Verified in emitted bytes: `BA A7 01` -> `BA D7 0F` |
| `stc` restored | `_DPMI.ASM` | `CheckMOS`'s `NotMos` path returned SUCCESS on failure, leaving `scbadr` at 0:0 |
| MOS 5.x detection | `_DPMI.ASM` | the two-call `int 21h` ah=30h equality test rejects real MOS (measured `0005`/`0105` on the original 5.01 kernel, `0005`/`0205` on ours) |
| `memman` far pointer | `_DPMI.ASM` | never populated; now loaded from `scbmmsub` as two explicit word moves |
| page count via label difference | `_DPMI.ASM` | `lea cx,EndProtect+4095` / `lea ax,BeginProtect` in INIT16 emit a 32-bit displacement with no `67h`; the bytes ran as `ENTER 0E9C1h,12`. Root cause of the `6FEB` return address |
| `offset ddt:No32` | `_DPMI.ASM` | error message pointer was segment-relative; the driver printed memory instead of its own text |
| `db 67h` before `mov [DriverRealCS],ax` | `_DPMI.ASM` | same missing prefix; trailing 2 bytes ran as `add [bx+si],al` |

Plus the `nmswitch` guard removal in `_386.ASM` — but see "corrected
history" below; it is a workaround, not a fix.

## Two MASM traps that will bite again

**E-registers in USE16 segments truncate silently.** No `66h` prefix,
no warning, no error. `mov eax,[si+x]` becomes `mov ax,[si+x]`.

**But this is segment-dependent, and the two cases are opposite:**

- `_386.ASM` / `res16` — declared USE16 but **runs 32-bit** (`gdtcode`
  has d=1). Prefix-free `mov eax,...` executes as a genuine 32-bit
  move. **Correct as written — do not "fix" it.**
- `_DPMI.ASM` / `INIT16` — genuinely runs 16-bit. Prefix-free
  `mov eax,...` really does truncate. Use word pairs.

**32-bit addresses in 16-bit segments emit no `67h` prefix.** Any
reference from CODE16/INIT16 to a label in a USE32 segment assembles as a
4-byte displacement with no address-size prefix, so the trailing bytes
execute as a separate instruction and the stream desynchronises. Three
instances existed in `_DPMI.ASM`, all original TSL code. A `ddt:` group
override does **not** help (byte-identical output); use a label
*difference* where only the difference is needed, `offset ddt:` for a
plain pointer, or an explicit `db 67h`. The linker fills these fields
group-relative, so a listing showing `0000000E` may still be correct in
the binary — always check the linked bytes, not the listing.

**`exe2bin` rebuilds from a stale `_386.EXE` when MASM fails.**
Byte-identical output, fresh timestamp, no visible error. Three builds
were silently stale before the unchanged file size gave it away. The
`.ASM.SYS` recipe has no error gate.

Always: `del _386.obj` + `del _386.exe`, assemble with a listing
(`masm _386,_386,_386;`), check the error count.

**Packaging: ship binaries built from the shipped source.** The
2026-09-17 tarball carried UPDATE 8 `.ASM` next to older `$386.SYS`/
`$DPMI.SYS` (21883/5410 vs 21915/5538), and the two boot differently.
Before trusting any tree, rebuild both drivers and `cmp` against what
is in `latest/`. A checker that renames over the target must do so
before comparing, or it compares the file with itself.

The usual failure is `A2053: Jump out of range` — `dooutali`'s short
jumps have **zero headroom**. Anything inserted between them and
`doout04i`/`doout81i`/`dooutald` breaks the build.

## Corrected history — several addendum entries are retracted

- there was never an `ivtable[6]==0` reflection bug (§3562)
- the `nmswitch` guard (§3700, "THE FIX") never fixed anything;
  removing it restores the boot only because at IOPL=3 the `sti` never
  traps
- the original crash and stall were **not** properties of PC-MOS: the
  shipped stack (`$386.SYS` 5.01.01/940421 from
  `IMAGES/PCMOS386-9-user.img`) boots clean. Caveat: that binary is a
  LATER revision than the source we hold (5.01/921119), so this proves
  "a later shipped build is fine", not "our source is fine"

Also retracted, all mine: the `HLT`-loop-as-cause framing,
`AllocateExtend` as the failing step, the clobbered-DX reading of
`ErrorHandler`, per-task IVT remapping, dual-mode `rhentry`/`valloc`,
"IOPL=3 severs int 6fh", and "the monitor does not advance the v-86
ip".

**Tally: eleven confident root-cause claims, eight wrong.** Every
survivor was backed by a mechanical before/after measurement; every
casualty came from reading source or from one ambiguous sample. Treat
this as the governing lesson.

## Where DPMI actually stands

Marker chain `M R A I E N P Z K Q` all fires. The extended-memory
allocation **succeeds** (`K` = success path). Execution reaches the
instruction before `AllocateExtend`'s `ret`. But marker 7 in
`InstallDriver` never fires, and neither does marker 10.

Measured, paired by sequence counter (both from the same, single
invocation):

```
                SS      SP        return slot
entry           D120    0E07      -
at Z            D120    2428      6FEB   (expected 1200)
at Q            -       -         6FEB
```

`0E07` is **odd** — the stack is already misaligned before
`AllocateExtend` is entered. SP then moves +1621h across one
push/pop-balanced call, same SS.

**Leading hypothesis (UNCONFIRMED):** the `s0` save area
(`s0ip`/`s0cs`/`s0flags`/`s0sp`/`s0ss`/...) is a **single global
frame** with no per-nesting-level saving, and `cgrm7`'s `iretd`
restores SS:ESP from it. Any trap nested inside another overwrites it,
so the outer return is destroyed. Fits every measurement including the
earlier live `s0ip` read that returned a BIOS timer context.

The confirming test was attempted and is **void**, not merely
inconclusive. The counter was unbalanced by construction (`eicommon`
has exits bypassing both `cgrm7` and `dohexit`), and the build that
read `nestcur=124` never loaded `$DPMI.SYS` at all, so it could not
have measured the DPMI path.

The counter's breakage is itself a lead, not yet a finding:

- **CH is ruled out.** The counter clobbered live CH after `push cx`.
  Keeping `inc`/`dec` but dropping every CH use still fails the same
  way.
- **Full removal restores the boot.**
- **So something downstream of `eicommon` does not tolerate a
  flag-modifying `inc`/`dec`** (or the code shift it causes). This
  contradicts the counter's own comment ("no flag-sensitive callers
  downstream"). Which of the two, and where, is unmeasured.

Any redo must keep flags intact on the trap path — `mov`-only latches
like `eidbgsp`, or the full flags saved around any arithmetic
(`lahf`/`sahf` does not cover OF, which `inc`/`dec` change) — and must
first show the instrumented build still boots
to the baseline screen. A reading from a build that does not is void.

## Known structural limits of the v-86 monitor

Two, both documented in the addendum with design notes:

1. **Only I/O instructions are emulated.** `CLI`, `STI`, `PUSHF`,
   `POPF`, `INT n`, `IRET` are all opcode-table `0`. IOPL=3 (`uioplb`)
   is a deliberate choice that makes the gap invisible. Read the
   CLI/STI design note before attempting anything here — a partial
   implementation is worse than none.
2. **The `s0` save area is single-level** (hypothesis above).

Neither is a DPMI bug. Neither should be fixed in `_DPMI.ASM`.

## Dead end — revert this

The int 6Fh gateway (`i6fstub`, `doi6fgate`, the `0E0h` bitmap bit,
the `IVT[6Fh]` hook) is **unnecessary**. Caller-aware latch shows
`count=16, caller=0070:05F4, ax=7705` — `05F4` is exactly the
instruction after `valloc`'s `int 6fh`, so int 6fh from v-86 reaches
the IDT dispatcher with a correctly advanced return ip. `S` and `G`
never fire because nothing needs them.

## Diagnostics to strip before committing

**DONE in UPDATE 13 — all four files are clean.** Historical notes:

**Do not strip the gateway** (`i6fstub`/`doi6fgate`/`dooutali9`): it is
load-bearing, not diagnostic. Its `S`/`G` markers are
safe to remove. (UPDATE 11 also claimed the `R` marker could not be
removed; that was a stripper bug, retracted in UPDATE 13.)

`_386.ASM`: DONE in UPDATE 13 — was: A–G bisection markers, `V`/`W` vmstart markers, `R`/`A`/`I`
markers, `E`/`N`/`P` markers, `eidbgsp`/`eidbgbp`/`eidbgsp2`,
`e5dbgip`, `e6dbgcs`/`e6dbgip`/`e6dbgax`/`e6dbgn`,
the `nestcur`/`nestmax` declarations (code already removed in the
baseline). NOT the gateway (see above).

`_DPMI.ASM`: DONE in UPDATE 11 — was: `WriteLog` video markers, `PutHex`, the version dumps,
`Z`/`K`/`F`/`Q` markers, `retdbg`, `callseq`, the SP/SS readouts, the
disabled sign-on prints. Delete `DevLoadMsg` outright — it contains a
literal `'$'` inside `'$DPMI.SYS'` and is printed with ah=9, so it
could only ever have printed `>>> DEVICE=`.

`MOSDDINT.ASM` / `MOSINIT2.ASM`: DONE in UPDATE 12 (teletype markers and
BDA recorders removed; kernel rebuilt and boot-verified).

## Still unvalidated

The `MOSDDINT.ASM` `nxtdrvr` fix — the only other functional change in
the tree, and its own comment says it needs validation. Now cheap to
isolate the same way the guard was.

## Test rig (headless, scriptable, no display)

- DOSBox Staging 0.82.2 debug build (`--buildtype=debug -Ddebug=true`)
- Xvfb, `output=texture`, `texture_renderer=software`
- screen read from `vga.mem.linear` **offset 0** (not `+0x18000`)
- guest RAM via `(char*)MemBase + <physical>`
- keystrokes via `xdotool`
- single-driver rebuild via `MAKEUTIL.MAK`'s `.ASM.SYS` recipe:
  `public` / `masm` / `link` / `exe2bin`, then rename `_X.SYS` to
  `$X.SYS`

**Direct video-memory writes beat every other marker in this
codebase** — no `int 21h`, no BIOS call, no v-86 reflection, and with
care no stack dependency. They work precisely when the thing under
investigation is the machinery a normal marker would rely on. Reading
values back out of guest memory repeatedly misled (image base, `s0ip`,
CODE16 residency); the screen never did.
