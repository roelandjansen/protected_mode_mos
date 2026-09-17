# PC-MOS/386 — Handover

State of play and how to resume. Written to be the first thing read in
a fresh session.

## Headline

**PC-MOS/386 boots to a live, responsive prompt in protected mode with
paging active.** Verified by typing at the prompt and getting real
answers back, not by screen inspection. The tree started this session
hanging with no prompt at all.

`$DPMI.SYS` still does not install. The failure is narrowed to a
corrupted return address, with one leading (unconfirmed) hypothesis.

## Read these, in this order

1. `pcmos386-protected-mode-fix-plan.md` — rewritten; the old version
   planned a hunt for a crash that turned out not to exist
2. `addendum-session-entry.md` — 8 sections, chronological; append to
   `pcmos386-protected-mode-addendum.md`
3. `CHANGES.md` — every code change, split into REAL FIXES vs
   DIAGNOSTICS TO STRIP
4. `pcmos386-changes.diff` — unified diff against the tree as
   uploaded; `patch -p0` from the repo root reproduces this state

## Four real fixes (keep)

All original-source bugs, all verified:

| fix | file | what |
| --- | --- | --- |
| `OFFSET ddt:` | `_DPMI.ASM` | MASM `OFFSET` is segment-relative, not group-relative; LINK does not fix it up despite the `R` flag. Verified in emitted bytes: `BA A7 01` -> `BA D7 0F` |
| `stc` restored | `_DPMI.ASM` | `CheckMOS`'s `NotMos` path returned SUCCESS on failure, leaving `scbadr` at 0:0 |
| MOS 5.x detection | `_DPMI.ASM` | the two-call `int 21h` ah=30h equality test rejects real MOS (measured `0005`/`0105` on the original 5.01 kernel, `0005`/`0205` on ours) |
| `memman` far pointer | `_DPMI.ASM` | never populated; now loaded from `scbmmsub` as two explicit word moves |

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

**`exe2bin` rebuilds from a stale `_386.EXE` when MASM fails.**
Byte-identical output, fresh timestamp, no visible error. Three builds
were silently stale before the unchanged file size gave it away. The
`.ASM.SYS` recipe has no error gate.

Always: `del _386.obj` + `del _386.exe`, assemble with a listing
(`masm _386,_386,_386;`), check the error count.

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

The confirming test was attempted and came back **inconclusive** —
the counter was unbalanced by construction because `eicommon` has
exits that bypass both `cgrm7` and `dohexit`. See the addendum for how
to redo it.

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

`_386.ASM`: A–G bisection markers, `V`/`W` vmstart markers, `R`/`A`/`I`
markers, `E`/`N`/`P` markers, `eidbgsp`/`eidbgbp`/`eidbgsp2`,
`e5dbgip`, `e6dbgcs`/`e6dbgip`/`e6dbgax`/`e6dbgn`,
`nestcur`/`nestmax`, the whole gateway.

`_DPMI.ASM`: `WriteLog` video markers, `PutHex`, the version dumps,
`Z`/`K`/`F`/`Q` markers, `retdbg`, `callseq`, the SP/SS readouts, the
disabled sign-on prints. Delete `DevLoadMsg` outright — it contains a
literal `'$'` inside `'$DPMI.SYS'` and is printed with ah=9, so it
could only ever have printed `>>> DEVICE=`.

`MOSDDINT.ASM` / `MOSINIT2.ASM` markers are from earlier sessions and
were not touched.

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
