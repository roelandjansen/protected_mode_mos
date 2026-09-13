# PC-MOS/386 Protected-Mode — Fix Plan

Rewritten. The previous version of this document planned the hunt for
a `$386.SYS` protected-mode crash. **That crash is resolved**, and the
central hypothesis the old plan was built on turned out to be wrong,
so patching it would have been misleading. This is a clean replacement
drawn from the current state of `pcmos386-protected-mode-addendum.md`.

The old plan is superseded in full. Its steps 1–5 either completed,
were answered in the negative, or became moot.

## Where this actually stands

**PC-MOS/386 boots to a live, responsive prompt in protected mode with
paging active.** Verified by typing at the prompt and getting real
answers back, not by screen inspection alone. That is the headline and
it did not require most of what the old plan proposed.

### Established, mechanically measured, not to be re-litigated

- The `$386.SYS` crash and the later no-prompt stall were **never
  properties of PC-MOS**. The original shipped stack
  (`$$MOS.SYS` + `$386.SYS` 5.01.01/940421 from
  `IMAGES/PCMOS386-9-user.img`) boots clean to a prompt with
  `MEMDEV=$386.SYS`: no crash, no stall, no garbling. Both were
  introduced by the rebuild.
- The stall was caused by the `nmswitch` guard added in an earlier
  session (§3700's "THE FIX"). Removing it — reverting `contirq` to
  the original unconditional real-mode-IVT reflection — restores a
  working boot. The guard block was exactly 32 bytes.
- `vmstart` is entered correctly and, with the guard removed, survives
  its `sti`. Confirmed directly by the `V`/`W` video-memory markers,
  not inferred. The V86 task entry, TSS2 and entry EIP are all fine.
- The `0000:0008` `HLT` loop was a *consequence* of the first enabled
  interrupt, not of a bad V86 entry.
- `$386.SYS` and the rebuilt kernel each work against the original
  counterpart (cross-tests C and D), so neither component is
  fundamentally broken.
- The DPMI screen garbage was a MASM group/segment `OFFSET` bug, now
  fixed and gone (see below).

### The one caveat that must not be lost

The shipped binary that boots clean is **5.01.01 (940421)**; our source
tree builds **5.01 (921119)**, and the shipped one is the 9-user
variant. So we have proven *"a later shipped build is fine"*, **not**
*"our source is fine"*. Every "the original works" statement above
carries this asterisk.

## The plan

### Step 1 — Close the version gap (cheap, do it first)

Find a genuine 921119 `$386.SYS` if one exists, and boot it the same
way. Nothing else in this document is apples-to-apples until this is
done. Searched so far: all loose images, plus `MOSFILES.EXE` and
`AUXFILES.EXE` (the latter has a `$386.SYS`, 20640 bytes, v5.02 era).
If no 921119 binary exists anywhere, say so explicitly in the addendum
and treat the caveat as permanent rather than pending.

### Step 2 — Validate the `MOSDDINT.ASM` `nxtdrvr` fix

This is the only other functional change in the tree and it is still
unvalidated — its own comment says "hypothesis-driven and needs
validation, not assumed correct."

It is now cheap to isolate, exactly the way the guard was: build a
kernel with and without it and boot both against a fixed `$386.SYS`.
Either it is load-bearing or it is not, and we should know which
before anything is committed.

### Step 3 — `$DPMI.SYS`: implement `SegToSel`

This is the real remaining work, and it is larger than everything
above.

Current state: `$DPMI.SYS` does not install. `DUMPLOG` confirms it
(`No DPMI host found (int 2Fh 1687h failed)`). The driver now reports
its own failure honestly since the `OFFSET` fix:

```
Not Installed.
386 Memory Manager required.
```

`CheckFor386SYS` was deliberately rewritten by an earlier session so
that it **never succeeds**, on either path:

- `scbmmfg != 'Y'` -> "386 Memory Manager required" (the path we hit)
- `scbmmfg == 'Y'` -> explicit `NotFin` refusal

The refusal is not a bug to remove. Its comment records why: the old
gate on `scbmmfea` bit 40h was never set by this build, so DPMI failed
safely *by accident*, and that accident was the only thing standing
between here and a worse failure. `InitProtect` depends on `SegToSel`,
which has no working implementation — it calls int 6Fh with
`SEGMENT_SELECTOR=7786h`, nothing implements it, it falls through to
generic native-mode reflection and executes whatever sits at the
never-hooked real-mode int 6Fh vector. Confirmed to crash DOSBox
outright, not just the guest.

Order of work:

**3a.** Determine whether `scbmmfg` is genuinely unset or simply read
wrong. Check `lds si,[scbadr]` and the `scbmmfg` field offset before
concluding `$386.SYS` fails to set the flag. Note the symptom
reproduces against the *original* `$386.SYS` too, which makes a
driver-side read error at least as likely as a `$386.SYS` omission.
This may dissolve entirely.

**3b.** Implement `SegToSel` properly: build a real GDT descriptor for
the segment rather than routing through an unimplemented int 6Fh
function. This is the gating item for DPMI and should not be attempted
by relaxing the refusal in `CheckFor386SYS`.

**3c.** Only once 3b is real, remove the explicit refusal and let
`InitProtect` run. Expect the next problem to surface immediately;
that is fine and expected, not a regression.

### Step 4 — Strip the instrumentation

There is a lot of it now, and none of it belongs in a commit:

- `_386.ASM`: bisection markers A–G, `vmstart` markers V/W
- `MOSDDINT.ASM`: the `[`, `<`, `>`, `{`, `}`, `(`, `)`, `]` markers and
  the `nxtdrvr` / counter recordings
- `MOSINIT2.ASM`: the numbered device markers and `ldloop` counter
- `_DPMI.ASM`: the `WriteLog` video markers, the disabled sign-on
  prints, `DevLoadMsg`

Keep the `OFFSET ddt:` fix and the guard removal — those are real
fixes, not diagnostics.

`DevLoadMsg` should simply be deleted rather than repaired: it is
project-added, and it contains a literal `'$'` inside `'$DPMI.SYS'`
while being printed with ah=9, so it could only ever have printed
`>>> DEVICE=`.

## Techniques that worked, and should be reused

- **Direct video-memory writes beat every other marker in this
  codebase.** No `int 21h`, no BIOS call, no V86 reflection, and — if
  written carefully — no stack dependency. They work precisely when
  the thing under investigation is the machinery a normal marker would
  rely on. The `V`/`W` markers use no `push`/`pop` for exactly this
  reason.
- **Read the emitted bytes, not the listing.** The `R` relocatable
  flag in `_DPMI.LST` looked like it meant LINK would fix up group
  offsets. It does not. Comparing `BA A7 01` against `BA D7 0F` in the
  built binaries settled in seconds what source reading had left
  ambiguous for far longer.
- **Cross-test against the original binaries.** Swapping one component
  at a time between the original and rebuilt stacks isolated faults
  far faster than static analysis did.
- **The whole loop runs headless**: DOSBox Staging 0.82.2 debug build
  under Xvfb with `output=texture` + `texture_renderer=software`,
  screen read from `vga.mem.linear` (offset 0), guest RAM via
  `(char*)MemBase + <physical>`, keystrokes via `xdotool`. Scriptable,
  fast, no display required.

## Guardrails

- **Trust mechanical measurements over decoded snapshots and over
  static reasoning.** Every wrong turn in this investigation came from
  a plausible reading of source or of a mid-cascade register dump.
  Three separate root-cause claims (`ivtable[6]==0`, the mis-encoded
  `call eicommon`, and `AllocateExtend`) were each stated confidently
  and each proved wrong.
- **Marker semantics matter.** `WriteLog` fires *after* a check
  returns but *before* its `jc`, so the last marker present names the
  step that FAILED, not the last one that passed. Read any marker
  sequence against the code that emits it before drawing conclusions.
- **A fix that removes a symptom is not automatically correct.** The
  `nmswitch` guard removed a crash and introduced a stall. Always
  cross-test against the original binaries before believing a fix.
- **Do not remove a safety refusal to make progress.** The
  `CheckFor386SYS` refusal exists to prevent a confirmed
  emulator-killing crash.
- `_386.ASM` must be built with the original MASM/LINK; UASM cannot
  assemble it (`nca segment at 386h`, hand-encoded opcodes).
- Single components can be rebuilt without a full `MAKEMOS.BAT` run
  using the `.ASM.SYS` recipe from `MAKEUTIL.MAK`:
  `public` / `masm` / `link` / `exe2bin`. Much faster to iterate.
