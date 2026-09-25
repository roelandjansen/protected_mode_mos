# PC-MOS/386 — Handover

State of play and how to resume. Written to be the first thing read in
a fresh session.

## Headline

**PC-MOS/386 boots to a live, responsive prompt in protected mode with
paging active.** Verified by typing at the prompt and getting real
answers back, not by screen inspection. The tree started this session
hanging with no prompt at all.

`$DPMI.SYS` **installs** and a client **runs in protected mode on its own
code selector** (UPDATE 16–17). The `6FEB` return-address corruption and
the `7786h` handler crash are both solved: assembler encoding defects in
original TSL code, not monitor logic. All diagnostics are stripped from
every source.



## Current state (2026-09-20, after UPDATE 17)

`$DPMI.SYS` installs, and **a DPMI client runs in protected mode on its
own code selector** (`cs=008B`, `cpl=3`, `vm=0`, measured). Tree = the
UPDATE 13 baseline plus `_386.ASM`, `_DPMI.ASM`, `_DPMI.INC`,
`MAKEUTIL.MAK` and `DPMITST.ASM`. Kernel unchanged.

- `DEVICE=$DPMI.SYS`: banner, `Dos Protected Mode Insterface Installed.`,
  `0000000K of Extended Memory Available.`, SMP line, `[A:\]`
- no DPMI: date/time prompts, `$$SHELL.SYS version 5.04`, `VER` answers
- `DPMITST.COM`: host reports `ax=0000`, entry `C0DE:00A6`, flags `0001`,
  version `1.00`, 5 paragraphs; switches; resumes in protected mode;
  exits cleanly through `int 21h ah=4Ch` (measured, no exception)

**Next milestone: protected-mode DOS interception.** It is needed for two
reasons now:

1. a client's `int 21h` prints garbage, because `dx` is an offset into a
   selector and the call runs as a real-mode DOS call;
2. a client's descriptors can only be released at its own `int 21h
   ah=4Ch`. `tcbunreg` is task-level and the client is a program inside
   the shell's task, so `UnRegister` never runs for it (measured: `778Fh`
   never called; one `80h` slot left per client program).

TSL reserved the hook: `Interupt21` in CODE32 is a stub captioned
"Handler Protected Mode Termination".

Monitor additions: int 6Fh `778Eh` CODE_SELECTOR (executable sibling of
`7786h`, bitness from `cl`, tags its descriptor `80h|taskid`) and `778Fh`
FREE_CLIENT_SEL. `cleardti` needed no change: it matches the plain task
id, so tagged entries are skipped.

Not bugs: `0000000K` is original TSL code that never fills the digits;
`install not done` is a hardcoded `ECHO` in the test `AUTOEXEC.BAT`.

**The dominant defect class** is code assembled for one operand size
executing under the other, plus plain `offset` where `offset ddt:` is
needed. Anything running after `goprot` is in a 32-bit cs and needs
explicit `66h` overrides; MASM cannot encode a `use32` -> `use16` call at
all. Check such encodings **in the linked binary**, not the listing.

**Tooling:** `pmrig-toolkit.tar.gz` restores the debug emulator and the
rig in a fresh session (`./restore.sh`; see its `RIG.md`).

`nxtdrvr` is still unvalidated.
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
2. `addendum-session-entry.md` — 17 sections, chronological; append to
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

## UPDATE 18 (2026-09-22) — PM int 21h ah=09h translated

A DPMI client's protected-mode `int 21h ah=09h` now prints correctly
(measured: `DPMITST` shows "returned with carry CLEAR: client is in
protected mode" instead of garbage; twice in one boot; `VER` still
answers; no-DPMI boot unchanged). `$386.SYS` 21232 -> 21344 bytes.

Mechanism: TSL already built a native-mode DOS translation layer in
`_386.ASM` (`einative` -> `eintable`, AH `39h`-`5Ch`, plus `1Ch`), using
the per-task NCA staging buffer `ncabufer` and `senddsdx`. A DPMI client
already travels this path; anything not in the table falls to
`einstand` (raw reflection), which is why `09h` printed garbage.

Change (`_386.ASM` only, 106 lines added, none removed):

- new `einfun09`: stages the `$`-string from `ncands:(e)dx` into
  `ncabufer` (scan to `$`, capped at `ncabufsz`, 64 if unset, `$` forced
  at the cap), points v86 `ds:dx` at it, `dovmint`, restores `edx`
- 16-bit client: `lar` on `ncancs`, D bit clear -> `movzx esi,si`
- `einlt39` routes `al=09h` there via `66h`-prefixed `jmp`
- encodings verified in the listing (disp8s `ncancs=3Ch`, `ncands=2Ch`,
  `ncabufer=70h`)

Open: a string without `$` inside the client's segment limit can fault
in the monitor (ring 0). Other `ah<39h` pointer calls are still raw
reflections. `4Ch` descriptor release (`778Fh`) still not wired.

Also this session: `_DPMI.ASM` banner typo "Insterface" -> "Interface"
(size unchanged, 4941). Rig: `IMAGES/template/empty-bootable.img` lacks
the 524-byte `COMMAND.COM` stub the kernel execs as `A:\COMMAND.COM`
(`scbshell`); without it boot ends "Command processor cannot be found".
Take it from `IMAGES/v501/1_main.img`.

## UPDATE 19 (2026-09-22) — client descriptors released at int 21h ah=4Ch

A DPMI client's tagged descriptors are now released at its own
`int 21h ah=4Ch`, instead of never (`tcbunreg`, and with it the
driver's Unregister path to `778Fh`, does not run for a program inside
the shell's task). `$386.SYS` 21344 -> 21376 bytes.

Change (`_386.ASM` only):

- the `8fh` loop is factored into `freeclsel`, a near proc in the
  use16 region: `addrnca` for the tcb, sweeps `dtitable` for
  `80h|taskid`, preserves every register including `ebx` (einative's
  nca pointer, which `addrnca` clobbers)
- `e6f8f` (778Fh) now calls it, so both paths share one implementation
- new `einfun4c` calls it and falls through to `einstand`; `eintable`
  entry `4c` points there instead of `einstand`
- `e6f8f` is use32 and `freeclsel` use16, which MASM cannot call
  directly, so it goes through `fcs_ptr`/`fcs32`, exactly as
  `nca_ptr`/`nca32` already do
- inserting the block put `einstand` out of short-jump range from two
  dispatch sites (`A2053`); they now jump to a local `einstd0`
  trampoline rather than move existing code
- in this use16 region `push eax` is an A4057 warning; a plain
  `push ax` is what pushes 32 bits in a 32-bit cs. Confirmed in the
  trace: esp drops 4 per push

Measured with `PMTRACE_HOOK_LO/_HI` over `freeclsel` (image offsets
`3202h`-`322Dh`): entered once per client `4Ch`, loop runs exactly 30
times (`dtilen`), the store at `321Bh` executes once (one descriptor
freed, the client's `8eh` code selector), `ebx` returns unchanged
(`00018bb0`), stack balanced. Ten client runs in one boot, `VER` and
`DIR` after, and the no-DPMI boot: all unchanged.

Note for future tests: repeatedly running one client does NOT
demonstrate the leak or the fix. `makegdte` reuses a descriptor whose
base, access byte and task id match, and a program reloaded at the
same address asks for the same base. A control build without this
change also survived 35 runs. Distinguishing needs clients at
different load addresses, or reading `dtitable` (image offset `1789h`)
directly.

## UPDATE 20 (2026-09-22) — dtitable is observable; UPDATE 19 confirmed

The tracer can now peek an arbitrary table while the monitor runs, and
the `4Ch` release of UPDATE 19 is confirmed against a control build.

Tracer: `PMTRACE_PEEK_OFF` / `PMTRACE_PEEK_LEN` append up to 256 bytes
from a `$386.SYS` image offset to every hook line (cs base `0700h`).
Read-only page-table walk, emulator-side only, so nothing is added to
the guest image and code layout cannot shift. `dosbox-pmtrace.patch`
updated; rebuild needs `--wrap-mode=nodownload` and
`-Duse_fluidsynth=false -Duse_mt32emu=false -Duse_opengl=false
-Duse_alsa=false -Duse_zlib_ng=false -Dunit_tests=disabled`, since
WrapDB is unreachable from the build sandbox.

Measured, `dtitable` (offset `1789h`, 30 bytes) across one client's
termination, entry byte 6 being its `8eh` code selector:

| build | on entry | on exit |
| --- | --- | --- |
| UPDATE 19 (hook `einfun4c`/`freeclsel`, `31FA`-`3230`) | `80` | `ff` |
| control, UPDATE 18 (hook `einstand`, `31F6`-`31FA`) | `80` | `80` |

`80h` is `80h|taskid` for task 0. So the control leaks the descriptor
at termination and the current tree frees it. This is the discriminating
test the 35-run experiment could not provide.

## UPDATE 21 (2026-09-22) — 09h limit guard (inactive in this config)

`einfun09` now caps the copy at the client segment's own limit: `lsl`
on `ncands`, `sub eax,esi`, `inc eax`, cap `ecx`, `xor ecx,ecx` when
the offset is already past the limit, and a `jecxz` around the copy
loop so a zero count cannot wrap `ecx`. `$386.SYS` 21376 -> 21392
bytes, 0 warnings, 0 severe. Encodings verified in the listing
(`jecxz` rel8 `08` lands on `e09cap`).

Measured with a client printing from `dx=0fff0h` with no `$` ahead:
`lsl` returns `0fffffffh` (256 MB) for the client's data selector and
`ncabufsz-1` is `0ffffh`, so available (`0ffffce7h`) exceeds the count
and THE CAP NEVER ENGAGES here. Both the capped and the uncapped build
print the same garbage and survive: that is DOS behaviour for an
unterminated string, not a monitor fault.

So the ring-0 fault this guards against needs a small-limit selector,
which the host cannot currently give a client (DPMI 0008h set-limit is
not implemented). The guard is correct and cheap, but it is untested
in the firing direction. Exercising it needs either 0008h, or a
hand-built descriptor with a short limit handed to a test client.

## UPDATE 22 (2026-09-22) — PM int 21h ah=0Ah translated (both directions)

A DPMI client can now read a line in protected mode. Measured: the
client prints, reads with `0Ah`, and echoes what was typed back through
`09h` ("you typed: HELLO PM"). A control build without `einfun0a`
returns an empty buffer on the same floppy and test client, and the
typed line never reaches the client. `$386.SYS` 21392 -> 21504 bytes,
0 warnings, 0 severe.

`0Ah` is the first handler that stages in BOTH directions, which is the
shape the remaining pointer functions need:

- out: byte 0 of the client's buffer is its maximum length, so `max+2`
  bytes go through `senddsdx` (DOS must see the size byte)
- call `dovmint`
- back: DOS writes the actual length at byte 1, so `len+2` bytes are
  copied from `ncabufer` to the client's `es:edi`, following the
  `einfun3f` copy-back pattern
- the offset is zero-extended in place off the cs D bit, as in
  `einfun09`; note `senddsdx` itself does NOT do this, so it is done
  before the call (`einfun39` has the same latent gap, unaddressed)
- `einlt39` routes `al=0Ah`

Layout note: inserting the handler put `einstand` out of short-jump
range from three more dispatch sites and `einback` out of range from
`einfun1c` (`A2053` x4). The three now use the `einstd0` trampoline
from UPDATE 19; `einfun1c` uses a `66h`-prefixed near `jmp`, which is
what its commented-out `;##### db 66h` anticipated. Expect this every
time something is inserted ahead of `einstand`.

Regression: two client runs in one boot with input each time, then
`VER` and `DIR`. `DPMITST.ASM` was extended only in the scratch tree
for these tests and has been restored.

Next in this milestone: `1Ah`/`2Fh` (DTA set/get, where the pointer
DOS keeps must be a v86 address while the client holds a selector),
then the FCB group.

## UPDATE 23 (2026-09-22) — ABI finding; 48h attempted, reverted

Two results, no net source change: the tree is still UPDATE 22
(`$386.SYS` 21504).

**1Ah/2Fh are the wrong next step.** `einfun4e`/`einfun4f` do not use
whatever DTA the client set: the native-mode ABI passes the client's
DTA explicitly in `es:bx`, and TSL's handler issues its OWN `1Ah`
pointing DOS at `ncabufer`, runs the find, then copies 44 bytes back to
`es:bx`. So a DOS-semantics `1Ah` would be silently overridden on every
find, and `2Fh` would hand back a v86 address a client cannot load.
Making those honest means giving the DTA a selector, which is a design
change, not a handler.

**48h (allocate) is the real client-facing gap** and was attempted:
DOS returns a real-mode segment in `ax` that a client cannot load, so
the handler rebuilds it as a tagged data selector via `makegdte`
(tag `80h|taskid`, so `einfun4c` frees it). Work in progress kept at
`/tmp/einfun48-wip.txt`; reverted from the tree because it crashes.

Measured, hooking `3277h`-`32B0h`: the handler is CORRECT as far as it
goes. `dovmint` returns segment `18B1h`, the push/pop around `addrnca`
balances (`esp` `0fdc`->`0fd8`->`0fdc`), `makegdte` returns selector
`0073h`, it is stored in `ncavax`, and control reaches `e48done`. The
abort — dosbox `IRET:CS selector beyond limits` — happens AFTER, on the
return path to the client.

So the fault is not in building the descriptor but in what the
GDT write or the register state does to the return. Next step: rerun
with the test client NOT writing through the returned selector (print
only) to separate "descriptor is bad" from "returning after a GDT
write is bad"; and peek `dtitable` (`1789h`) plus the client's own cs
descriptor across the call, since `makegdte` picks the first
`0ffh` slot and its interaction with a live client's descriptors has
never been exercised mid-run.

Also note `makegdte` clobbers `ecx`, and `bp` is 0 on return from
`dovmint`; neither is documented anywhere else.

## UPDATE 23b (2026-09-23) — 48h diagnosed, not yet fixed

Tree unchanged (UPDATE 22, `$386.SYS` 21504). `einfun48` work in
progress still at `/tmp/einfun48-wip.txt`; it applies cleanly to the
scratch tree and builds (21552, 0 warnings, 0 severe).

Isolation, measured:

- client allocates and only PRINTS the returned value: no crash
- client loads it into `es`: dosbox `ABORT: IRET:CS selector beyond
  limits`

The event log shows the real failure: the client takes `INT 0d` (#GP)
at `cs=008b cpl=3` when it loads the value, and the monitor's own
handler then takes `INT 0e` (`ebx=fa008c7e`, a PTE-shaped value) while
servicing it. The dosbox abort is the aftermath, not the fault.

The value the client received was `0973h`. That cannot be a selector
from `makegdte`: `gdtspace-gdt` is `58h` and `dtilen` is 30, so its
selectors run about `58h`-`143h`. Tracing `makegdte` (`35B3h`-`3626h`)
shows it returning `edi=60h`, i.e. selector `0063h`. `0973h` is a
plausible real-mode SEGMENT.

Hypothesis, to check first next session: the client is getting DOS's
raw segment, i.e. the selector written to `ncavax` never reaches the
client's `ax`. `ncavax` sits inside `ncairegs` (the v86 set,
`ncavflag`..`ncavbp`), and the native-mode return value may come from
the `p0stack`/`ncap0stk` side instead. Read `einback`'s write-back and
find which slot feeds the client's `ax`, then store the selector there.
Also worth confirming: in the traced `makegdte` call `edx` was
`000000f2` (dh=0, so tag 0, not `80h|taskid`), but that trace window
may belong to a later `8eh` call rather than `einfun48` — verify before
concluding the tag is wrong too.

## UPDATE 24 (2026-09-23) — 48h returns a selector; the crash was the test

`einfun48` is in the tree. `$386.SYS` 21504 -> 21552, 0 warnings, 0
severe.

UPDATE 23b's crash was NOT a driver defect: the test client called
`puts` between `int 21h` and `mov es,ax`, and `puts` uses `ah=9`, so it
clobbered `ax`. The client then loaded leftover junk (`0973h`, which
is why it looked like a raw segment) as a selector and took #GP. With
`ax` preserved across `puts` the same driver build works. The
hypothesis in UPDATE 23b about `ncavax` not reaching the client was
therefore wrong: `einback` copies `ncairegs+4` (di,si,dx,ax,bx,cx,es,
ds,bp) to `p0stack`, so `ncavax` IS the client's `ax`.

What 48h does: reflect to DOS, and on success rebuild the returned
real-mode segment as a data selector via `makegdte` (`dl=11110010b`,
tag `dh=80h|taskid` from `addrnca`), storing it in `ncavax`. Table full
is reported the way DOS reports insufficient memory: `ax=8`, carry set.

Measured: client allocates 4 paragraphs, gets selector `0073h`, writes
`1234h` through it and reads it back. `dtitable` (peek at `1789h`)
across the client's `4Ch` shows TWO tagged entries, indexes 3 and 6 --
its code selector and this allocation -- both `80h` on entry to
`freeclsel` and both `0ffh` on exit, so UPDATE 19 already frees what
48h hands out. The tag is `80h`, confirming the `edx=000000f2` seen in
UPDATE 23b belonged to a different `makegdte` call, as suspected.

Regression: three client runs in one boot, then `VER` and `DIR`.

Still open: 49h (free) takes a segment in `es`, so a client passing its
selector needs the reverse conversion (read the descriptor base, shift
right 4); 4Ah (resize) likewise. Those two should come next, since 48h
without 49h leaks blocks until termination.

## UPDATE 25 (2026-09-23) — 49h attempted; PM path refused, reverted

Tree is UPDATE 24 (`$386.SYS` 21552, 48h in, 49h out). `einfun49` work
in progress at `/tmp/einfun49-wip.txt`; applies cleanly, builds to
21648, 0 warnings, 0 severe.

What it does: client holds a SELECTOR in `es` where DOS wants a
segment, so the descriptor base is read from the gdt (`gdt+2` bits
0-15, `gdt+4` bits 16-23), shifted down 4 into `ncaves`, reflected,
and on success the `dtitable` slot is released (same idiom the int 38h
deallocator uses). A selector outside `gdtspace` is passed through
untouched, so a client holding a genuine real-mode segment still works.

Measured, hooking `32C4h`-`330Ch`: the conversion is CORRECT. Base
`00008B10` -> segment `000018B1`, written to `ncaves`, `dovmint`
entered. DOS then returns with CARRY SET and `ax` UNCHANGED (client
saw `4933h`, i.e. its own `ah=49h` with stale `al`). An error return
would have put 7 or 9 in `ax`, so this looks like the request not
reaching the `49h` handler at all rather than a rejection.

Baseline, same client, same block, BEFORE the mode switch: real-mode
`48h` returns `18B1h` and `49h` succeeds. So MOS's 49h works and the
segment is right; only the protected-mode path fails.

Next step: `PMTRACE_STEPS` after the `int 6fh` to watch the reflected
v-86 instructions and see what the kernel does with `ah=49h`,
i.e. whether `ncaves` survives into the v-86 `es` or something in
`dovmint`/`einative` overwrites it from `ncanes` on the way out.

Test-harness note, third time this has cost a cycle: `puts` clobbers
`ax`; and code inserted just above `do_switch:` never runs, because
`have_host` JUMPS there. Check reachability and register clobbering in
the test client before suspecting the driver.

## UPDATE 25b (2026-09-23) — 49h: carry is the open question

Still reverted; tree is UPDATE 24 (21552). Work in progress unchanged
at `/tmp/einfun49-wip.txt`.

Ruled out this session: `dovmint` DOES load the v-86 `es` from
`ncaves` (read it at `dovmint`+~90), so the converted segment reaches
DOS. The conversion itself was already verified correct.

New measurement, client ignoring carry and doing alloc/free/alloc:

	1st sel: 0073   49h flags: 3297   2nd sel: 007B

`3297h` has bit 0 set, so carry really is set on return. Because the
handler tests `ncavflag` and skips the slot release when carry is set,
`0073h` stayed marked in use and the second allocation took the next
slot -- that part is the handler behaving as written, not a second
bug.

What is NOT yet known: whether DOS actually freed the block. The two
selectors differ, but that follows from the skipped slot release; it
says nothing about the underlying memory. Decide it by comparing the
two descriptors' BASES in the gdt (entry for selector `0073h` is at
image offset `17C0h+70h` = `1830h`, `007Bh` at `1838h`); equal bases
mean DOS freed and handed the same block back. An attempt this session
mis-set the hook offset and peeked at an unrelated moment, so the
question is open.

Leading hypothesis for the carry: `ncavflag` may be stale rather than
seeded from the client's flags on entry to `einative`, in which case
`dovmint` ORs a leftover carry into the v-86 flags and DOS returns it
untouched. That also fits `ax` being unchanged. Check whether anything
on the `einative` entry path writes `ncavflag` from the client's
`p0stack` flags; if not, seed it there (or clear carry before
reflecting) and retest. Note a later run also ended with MOS printing
"Internal error #0 Unexpected error during function #00", which may be
the same stale-flags issue surfacing elsewhere.

## UPDATE 26 (2026-09-23) — 49h works; a 48h defect found

`einfun49` is in the tree. `$386.SYS` 21552 -> 21648, 0 warnings, 0
severe.

The UPDATE 25 "failure" was not a failure. `einative` DOES seed
`ncavflag` from the client's flags (`p0stack-12`), and MOS returns CF
UNCHANGED on a successful 49h. So a client that happened to carry CF=1
into the call got it back and read it as an error -- and the handler,
testing the same bit, skipped its slot release. Both symptoms, one
cause.

Fix: clear CF in `ncavflag` before reflecting (`and [ebx+ncavflag],
0fffeh`), so the returned CF means what it says. Measured worst case,
client executes `stc` immediately before `int 21h ah=49h`: carry comes
back CLEAR, the slot is released, and the next 48h reuses selector
`0073h`. Without the fix and with the client doing `clc` by hand the
same sequence also worked, which is what isolated it.

Real-mode control, same client, same block: 48h `18B1h`, 49h ok,
second 48h `18B1h` again, clean exit.

### Open defect (in 48h, already shipped in UPDATE 24)

A client that allocates TWICE in protected mode and then terminates
makes MOS print:

	Internal error #0 Unexpected error during function #00

Measured: two 48h calls with NO 49h reproduce it (selectors `0073h`
and `007Bh`), so it is 48h, not 49h. One allocation then exit is
clean; alloc/free/alloc in REAL mode is clean. Not yet run: the
real-mode alloc/alloc/exit control, which decides whether this is
MOS-generic or specific to the protected-mode path. Do that first next
session, then look at what 4Ch/`freeclsel` and MOS's task termination
each do with two live blocks and their descriptors.

## UPDATE 27 (2026-09-23) — the 48h defect is PM-specific, and not about live blocks

No source change; tree is UPDATE 26 (`$386.SYS` 21648, 48h + 49h in).

Controls run for the "Internal error #0 Unexpected error during
function #00" reported in UPDATE 26:

| sequence | mode | result |
| --- | --- | --- |
| alloc, exit | PM | clean |
| alloc, alloc, exit | PM | Internal error #0 |
| alloc x2, free both, exit | PM | Internal error #0 |
| alloc, free, alloc, exit | PM | Internal error #0 |
| alloc, alloc, exit | real | clean (`18B1h`, `18B6h`) |
| alloc, free, alloc, exit | real | clean |

So: real mode is fine with the same DOS calls, and freeing the blocks
before exit does NOT help. The trigger is making a SECOND protected-
mode allocation, i.e. creating a second client data descriptor, not
what is left allocated at termination. The error appears after the
program finishes (the prompt returns and the system keeps running).

Note on `dtitable` values, from the peek dumps: free is `0ffh`, a
client's is `80h|taskid`, and entries also appear as plain `00h` and as
`0feh` -- so the byte carries more meanings than "free or this task's
client". `0073h` is index 3, `007Bh` index 4. Worth reading what writes
`00h` and `0feh` before assuming a free slot is safe to hand out:
the suspicion is that the second `makegdte` slot collides with
something MOS uses for the shell task itself.

Next: run the client under `PMTRACE_STEPS` from the `int 6fh` so the
v-86 instructions after termination are visible, and identify which
function #00 MOS is complaining about; peek `dtitable` (`1789h`) and
the two new descriptors right after each 48h. Until that is understood,
treat 48h as usable for a single allocation only.

## UPDATE 28 (2026-09-23) — root cause: 48h aliases the client's own ds

No source change; tree is UPDATE 26 (21648). UPDATE 27's suspicion
about `dtitable` values was WRONG and is withdrawn: `0feh` is a
permanent entry (set by `makegdtx`) and `00h` is simply task 0's tag,
so `makegdte`'s "free or mine" test is sound.

The actual cause, measured. `dtitable` peeked at `e48done` after each
of two allocations:

	after 1st:  00 00 00 80 ff fe 80 ff ...
	after 2nd:  00 00 00 80 80 fe 80 ff ...

The FIRST allocation adds no entry. `makegdte` deliberately REUSES an
existing descriptor when task id, access byte AND base all match, and
the block MOS returned (`18B1h`, base `18B10h`) has the same base as
the client's own data selector handed out by `8eh`. So 48h gave the
client back its own `ds` descriptor under a different name. Only the
second allocation allocates a new slot -- which is precisely when
"Internal error #0" appears.

This also reinterprets UPDATE 26: the 49h test was freeing the
descriptor that backs the client's own data segment, and it "worked"
only because nothing used ds afterwards.

Two questions before coding anything:

1. Why does MOS's 48h return a block whose base equals the client
   program's own segment? Check what the real-mode 48h at that point
   actually owns -- the .COM should hold all free memory, so a
   successful 48h returning `18B1h` needs explaining. If MOS is
   handing out memory inside the program's own arena, the defect is
   below us and 48h translation is not the place to fix it.
2. If the allocation is legitimate, 48h must NOT share a descriptor
   with an existing one: it needs a fresh slot per block so that 49h
   and `freeclsel` release exactly what they should. `makegdte`'s
   reuse is by design for sharing, so this needs either a variant that
   skips the reuse check while still tagging `80h|taskid` (NOT
   `makegdtx`, whose `0feh` permanent tag would leak past 4Ch), or a
   different limit/access so the match fails honestly.

Question 1 first: it decides whether 2 is worth doing at all.

## UPDATE 29 (2026-09-23) — real root cause: a live descriptor with a free dti slot

No source change; tree is UPDATE 26 (21648). UPDATE 28's explanation
was also wrong and is withdrawn: the client sits at `cs=08AAh`, so its
data base is `08AA0h`, nothing like the allocation's `18B10h`. 48h does
not alias the client's ds.

Question 1 from UPDATE 28 is answered: the allocation IS legitimate.
Measured in real mode before the switch: `cs: 08AA`, largest free block
`874Fh` paragraphs, `48h bx=4` returns `18B1h` with CF clear. MOS does
not hand a .COM all of memory, so a successful 48h well above the
program is normal and nothing below us is at fault.

The defect, measured by peeking the gdt at `1830h` (slot 3 onward)
after each of two allocations:

	after 1st:  slot 3 = base 018b10 f2 (our block)
	            slot 4 = base 0c0de0 fa (CODE, dpl3)
	after 2nd:  slot 4 = base 018b60 f2 (our 2nd block)

Slot 4 held a live CODE descriptor for segment `C0DE` -- the DPMI
host's mode-switch entry, the `C0DE:00A7` DPMITST reports -- while its
`dtitable` entry read `0ffh`, i.e. free. `makegdte` therefore handed
that slot out and the second 48h overwrote a descriptor still in use.
That is exactly why the error needs TWO allocations and only appears at
termination, when the host uses that selector again.

So this is not a 48h bug: ANY caller of `makegdte`/`makegdtx` can steal
that slot. 48h just made it reachable from a client.

Next: find who builds the `C0DE` code descriptor (`_DPMI.ASM` switch
path, or the `8eh`/`86h` handlers in `_386.ASM`) and why its
`dtitable` byte is left `0ffh`. Either it should be tagged
`80h|taskid` like the client's cs/ds so `freeclsel` releases it at
4Ch, or `0feh` permanent if the host keeps it for the session. Tag it,
then re-run: two allocations plus exit should be clean, and the
UPDATE 26 49h results need re-checking afterwards since they were
measured with this hazard present.

## UPDATE 30 (2026-09-23) — the free-but-live slot traced to source

No source change; tree is UPDATE 26 (21648).

Item 5 (MOS 5.x detection) needs no work: it is ALREADY FIXED in
`_DPMI.ASM` `CheckMOS` -- equality test dropped, version floor checked
against the second call's `ax` -- along with the `stc` restoration on
the `NotMos` path. Both appear in the fixes table near the top of this
file. Every boot exercises it: the DPMI banner only appears because
CheckMOS passes on 5.02. The earlier "next steps" listing it as open
was wrong.

Source-level cause of UPDATE 29's free-but-live descriptor:

- `nmswitch` translates the switching code's `s0cs` with `makegdte`
  using `dl=11111010b` (executable) and `dh` = the PLAIN task id
- `nmswitch` also calls `cleardti` on every native-mode switch, which
  frees every entry carrying that plain tag
- client selectors survive because `8eh`/`86h` tag them `80h|taskid`,
  which the sweep skips; the HOST's own cs descriptor does not get
  that tag

So after the client's first v-86 excursion the `C0DE` code descriptor
is still loaded and still used by the host's return path, while its
`dtitable` byte reads `0ffh` and any `makegdte` caller may take it.
TSL flagged the underlying behaviour themselves in the comment above
`e6f8f` ("A DPMI client's selectors will not survive that. Not
addressed here").

Two candidate fixes, neither trivial enough to pick blind:

1. Tag the `nmswitch` cs descriptor `80h|taskid` as well. Small and
   local, and `freeclsel` would release it at 4Ch. RISK: it changes
   behaviour for EVERY native-mode task, not just DPMI ones -- those
   descriptors would stop being swept per switch, so a long-running
   int 38h application could accumulate entries until `dtitable`
   fills.
2. Tag it only while a DPMI client is active. Correct but needs state
   the switch path does not currently carry.

Recommend measuring first: count how many entries a plain native-mode
(int 38h) task turns over per switch, with the `dtitable` peek, to see
whether option 1's risk is real or theoretical. If a task reuses the
same slot each time (same base, same access -> makegdte matches), the
sweep is not what keeps the table small and option 1 is safe.

## UPDATE 31 (2026-09-23) — option 1 protects slot 4; the error remains

No source change in the tree (still UPDATE 26, 21648). Option 1 from
UPDATE 30 was built in the SCRATCH tree only and is kept at
`/tmp/_386.opt1.asm` (21664, 0 warnings, 0 severe): in `nmswitch`,
`or dh,80h` before the cs `makegdte`, `and dh,7fh` after.

Measured, two PM allocations then exit:

| build | selectors | exit |
| --- | --- | --- |
| UPDATE 26 | `0073`, `007B` (slot 4 overwritten) | Internal error #0 |
| option 1 | `0073`, `0093` (slot 4 skipped, slot 7 taken) | Internal error #0 |

So option 1 does exactly what it was meant to: the host's live cs
descriptor is no longer handed out. But the error is UNCHANGED, which
means the slot-4 overwrite was a real hazard and NOT the cause of the
"Internal error #0" -- or not the only cause. UPDATE 29's conclusion
("That is exactly why the error needs TWO allocations") is withdrawn.

Status of the theories on this one error, so nobody re-walks them:

| theory | status |
| --- | --- |
| dtitable `00h`/`0feh` misread by makegdte (UPD 27) | disproved (UPD 28) |
| 48h aliases the client's own ds (UPD 28) | disproved (UPD 29) |
| slot-4 host cs overwrite causes the error (UPD 29) | disproved (here) |
| slot-4 host cs is free-but-live (UPD 29/30) | TRUE, fixed by option 1 |

Option 1 is not shipped: its risk for plain int 38h tasks (UPDATE 30)
is still unmeasured, and it does not fix the error it was aimed at.

Next, and stop theorising from the descriptor layer: trace the
termination itself. The message names "function #00", and MOS prints it
after the client's 4Ch, so run `PMTRACE` with a wide window over the
4Ch path of the two-allocation client and find the call that fails.
Compare against the one-allocation client, which exits clean, event by
event. That diff is the answer; everything so far has been inference.

## UPDATE 32 (2026-09-23) — ROOT CAUSE: the host under-reports its data size

`_DPMI.ASM` only: the `1687h` reply now reports `si = 28` paragraphs
instead of 5. `$DPMI.SYS` size unchanged (4941). `$386.SYS` unchanged
(21648, UPDATE 26). The four A4057 warnings in `_DPMI.ASM` (lines
~4412-4421, `scbmmsub` dword read as words) are PRE-EXISTING and
unrelated.

### How it was found

Stopped theorising and diffed the event trace from the client's `4Ch`
for a one-allocation client (exits clean) against a two-allocation
client (errors), same driver. At termination MOS walks the MCB chain;
the two-allocation run gets DOS error 7 (MCBs destroyed) and then
prints the message. Peeking memory at `4Ch`: the free-remainder MCB
the second 48h wrote at `18BA0` held a STACK FRAME instead (`18B6`,
`D120`, `005B`, `0070`, `3246`).

### Cause

`GoProtect` passes the client's host-data block (from `1687h`'s `si`)
to `int 0D4h ax=1001h` as the task's native control area. `nmswitch`
lays out there: a 256-byte v86 stack, then the nca (`ncalen = 70h`),
then the staging buffer sized by the `cx` GoProtect passes (`5*16`).
That is 256+112+80 = 448 bytes = 28 paragraphs. The host told clients
5. So the monitor ran 368 bytes past the client's block into the DOS
arena. One allocation's MCB happened to land below the damage; the
second's landed inside the v86 stack and was overwritten.

This bug predates everything this session: any DPMI client that
allocated DOS memory after switching was exposed, and 48h merely made
it reachable.

### Verified

Two allocations then exit: clean (was Internal error #0). Stress run,
twice in one boot then `VER`: DPMITST reports `paras (si): 001C`,
three allocations each written through, a free, a realloc that reuses
the freed slot, the second block's `2222h` intact, clean exit both
times.

### Theory table, final

| theory | status |
| --- | --- |
| dtitable `00h`/`0feh` misread (UPD 27) | disproved |
| 48h aliases client ds (UPD 28) | disproved |
| slot-4 host cs overwrite causes the error (UPD 29) | disproved |
| host cs slot free-but-live (UPD 29/30) | TRUE, separate defect, option 1 unshipped |
| host data block too small for the nca (here) | TRUE, the cause, fixed |

### New, from the same reading -- verify before relying on them

- `ncabufsz` is the `cx=5*16` GoProtect passes, i.e. the staging buffer
  is 80 bytes. UPDATE 21's reading that `ncabufsz-1` was `0ffffh` was
  taken at an instruction BEFORE `ecx` was loaded from `ncabufsz`, and
  is withdrawn. So `einfun09` truncates `$`-strings at 79 bytes.
- `einfun0a` stages `max+2` bytes (up to 257) through `senddsdx`, which
  does not check `ncabufsz`: an input buffer larger than 78 bytes
  overruns the staging buffer, past the end of the (now correctly
  sized) block. Needs a cap, or a larger `cx` in GoProtect with `si`
  raised to match -- the equation above is written to make that a
  one-line change.

## UPDATE 33 (2026-09-23) — the control area sized properly; UPDATE 32 corrected

`_DPMI.ASM` only. `$DPMI.SYS` 4941 (unchanged size). Same four
pre-existing A4057 warnings, 0 severe.

UPDATE 32's arithmetic was wrong, and right only by accident. Measured
`ncabufsz` at runtime (hook after `mov ecx,[ebx+ncabufsz]` in
`einfun09`): `FFFFFEE0h`, i.e. -288. `nmswitch` computes

	ncabufsz = cx - (256 + ncalen)

so the `cx` GoProtect passes is the TOTAL control-area size, not the
buffer size. With `cx=80` the buffer size was negative, which as an
unsigned count means no bound at all: `einfun09`'s cap never engaged
and every staging copy was unbounded. A 120-character `$`-string from
protected mode printed in full and then produced "Internal error #0" at
exit -- the copy ran past the end of the (UPDATE 32) block into the
next MCB. UPDATE 32's second "new" point (09h truncates at 79) is
therefore also withdrawn: nothing truncated, it overran.

Fix, with named sizes near `dpmi2f`:

	NCABUF    equ 272              ; largest staged request: 0Ah 255+2
	NCATOTAL  equ 256+70h+NCABUF   ; 640 bytes
	1687h:    mov si,NCATOTAL/16   ; 40 paragraphs (was 5, then 28)
	GoProtect: mov cx,NCATOTAL     ; was 5*16

Measured: `ncabufsz` now `00000110h` = 272 exactly. The 120-character
string prints in full and exits clean. A 0Ah input with a 200-byte
buffer returned 111 characters (the rig's key injector drops some of a
long typed line -- a rig limit, not the driver), well past the old
80-byte buffer, followed by two allocations; exit clean, `VER` after.

`einfun0a` still has no explicit cap of its own; it is safe because
NCABUF >= 257 covers any 0Ah request. `einfun09` truncates at
NCABUF-1 = 271 characters, where real DOS would print on to the `$`.
Both are consequences of NCABUF and are documented at its definition.
The `70h` in NCATOTAL duplicates `ncalen` in `_386.ASM` by hand.

## UPDATE 34 (2026-09-23) — host cs descriptor tagged (option 1 shipped)

`_386.ASM`: in `nmswitch`, `or dh,80h` before the cs `makegdte` and
`and dh,7fh` after, so the host's own cs descriptor is tagged
`80h|taskid` like a client selector. `$386.SYS` 21648 -> 21664, 0
warnings, 0 severe. With `$DPMI.SYS` from UPDATE 33.

Why: UPDATE 29/30. The host cs was tagged with the plain task id, so
`cleardti` freed its slot on the next native-mode switch while the
descriptor stayed loaded; any `makegdte` caller could then take and
overwrite it (measured: the second 48h did, UPDATE 29).

Risk assessed before shipping, since the change affects every
native-mode switch, not only DPMI:

- `80h` entries are exempt from the per-switch sweep and are released
  only by `freeclsel` (client 4Ch, and 778Fh on the driver's
  Unregister path). A non-DPMI native-mode task would therefore keep
  its cs slot past its lifetime.
- In THIS tree that case does not arise. The only caller of the switch
  (`int 0D4h ax=1001h`) is `_DPMI.ASM`. The other `int 38h` users
  (`_PIPE`, `IMPORT`, `ALIAS`, `ADDTASK`, `FORMAT`, ...) use int 38h as
  the MOS service API -- the `80h+` calls TSL renumbered in 1987 -- not
  as a native-mode switch.
- For an EXTERNAL native-mode program it would be bounded: `makegdte`
  reuses an entry with the same tag, access and base, so the cost is at
  most one slot per distinct code segment per task id.

Measured: six client runs in one boot with `dtitable` peeked at each
`freeclsel` entry -- three tagged entries each time (host cs, client
cs, client ds), all released, no growth. Earlier (UPDATE 31) the
second 48h was measured to skip the host's slot instead of overwriting
it. Regression, two boots: the two-allocation client twice, the base
client, `VER`, `DIR`: no "Internal error", all clean.

## UPDATE 35 (2026-09-23) — 49h and 4Ah are DOS-level no-ops in PM

Tree unchanged: UPDATE 34 (`$386.SYS` 21664). `einfun4a` written and
builds (21712, 0 warnings, 0 severe) but NOT shipped; kept at
`/tmp/einfun4a-wip.txt`.

### The finding

Watched the segments DOS hands out (hook right after
`mov ax,[ebx+ncavax]` in `einfun48`, `3285h`) across one client:

| step | segment | if the previous call had taken effect |
| --- | --- | --- |
| A = 48h(4) | `18D4` | |
| 4Ah A->8, then B = 48h(4) | `18D9` | `18DD` (after a grown A) |
| 49h B, then C = 48h(4) | `18DE` | `18D9` (B's space reused) |

So in protected mode 49h and 4Ah both RETURN SUCCESS WITHOUT EFFECT:
A never grew and B was never freed. Real mode, same calls: 4Ah with an
impossible size fails properly (`ax=0008`, `bx=872C` largest, CF set),
and 48h/49h/48h reuses the freed block.

**UPDATE 26's "49h works" is withdrawn at the DOS level.** What was
measured then -- the carry coming back clear and the next 48h reusing
the SAME SELECTOR -- was only this driver's own `dtitable` bookkeeping.
The DOS block stayed allocated. (Blocks are still reclaimed at
termination, when MOS frees everything the PSP owns; that is why no
exit error appeared.) Likewise the "grown area is writable" check for
4Ah proved nothing: every descriptor has a 256 MB limit.

### Ruled out

- the conversion: segment `18D4` measured going into `ncaves`, and
  `dovmint` loads v86 `es` from `ncaves` (UPDATE 25b)
- a register/test-harness artefact: result read from DOS's own
  allocation sequence, not from anything the client prints

### Not yet known

What MOS does with a reflected 49h/4Ah from a native-mode task. 48h
(no segment input) works; 49h and 4Ah (segment in `es`) silently do
nothing. MOS may route memory calls from a native-mode task through a
separate path (TSL's old native-mode memory services) that treats `es`
differently and reports success on no match. Next step is a v-86 step
trace (`PMTRACE_STEPS`) from the reflected 49h into the kernel, then
reading that path in `MOSFUN*.ASM`.

### State of the memory trio

- 48h: works (block and descriptor)
- 49h: in the tree; releases the descriptor slot correctly, but the DOS
  block is NOT freed until termination
- 4Ah: not shipped; same no-op

## UPDATE 36 (2026-09-23) — int 31h is not wired: the host's API is unreachable

No source change; tree is UPDATE 34. Found while starting on the int 31h
functions (plan: 0400h, then 0500h-0503h, then 0100h-0102h, then 0008h).

Measured: a client calling `int 31h ax=0400h` from protected mode is
reflected like any other interrupt -- `eicalled` -> `einative` ->
`einstand` -> `dovmint` -> the REAL-MODE vector 31h, which points at
nothing useful. The event log then shows a garbage v-86 frame
(`ss=ffff`, `ds=3246`, a flags value in a segment register), `int 3`,
an invalid-opcode fault, and an `int 21h` from `cs=0000`; the screen
fills with junk. The system stays up.

Cause, from the source: `_DPMI.ASM` has a complete int 31h dispatcher
(`Interupt31`, walking `Intr31Tab`: the full DPMI 0.9 set -- 0000h-000Dh
descriptors, 0100h-0102h DOS memory, 0200h-0205h vectors, 0300h-0306h
real-mode calls and callbacks, 0400h version, 0500h-0503h memory,
0600h-0604h, 0800h, 0900h-0902h, 0A00h, 0B00h-0B02h), but `Interupt31`
is REFERENCED NOWHERE. Nothing installs it. Its siblings `Interupt21`
and `Interupt2f` are the same: stubs chaining to `OrgProt21` /
`OrgProt2f`, which are never set. TSL wrote the host's protected-mode
interrupt hooks and never finished the routing that would reach them.
So the host currently offers exactly one working service: the mode
switch. Every DPMI function is unreachable from a client.

Also noted: the `0000000K of Extended Memory Available.` banner is a
constant string (`MsgMem`) that nothing ever fills in; `AllocateExtend`
only reserves the pages for the host's own protected-mode code
(`ExtendMem`).

This is the real core of "a usable DPMI host", and it needs design
decisions before code:

1. where `Interupt31` runs: the host's protected-mode code sits in the
   extended-memory block from `AllocateExtend` (`BeginProtect` ..
   `EndProtect`); it needs a code selector for that block that the
   monitor can far-call
2. how the monitor gets that address: an int 6fh registration call at
   install time, stored beside `ivtable`, is the natural shape
3. dispatch: in `einative`, `dl=31h` goes to the registered handler
   instead of `einstand`
4. calling convention: `Interupt31` ends `retf 2` (discards a flags
   word), and DPMI functions return results in registers and CF; the
   monitor's native frame (`ncairegs` / `p0stack`) must carry them back
   the way `einback` does for `int 21h`
5. privilege: the client is cpl 3; decide whether the host runs at the
   client's privilege (simplest, a dpl-3 code selector) or needs more

## UPDATE 37 (2026-09-23) — int 31h: the host's PM side has never run

No source change; tree is UPDATE 34.

Before wiring int 31h (UPDATE 36 design, agreed: run the host at the
client's privilege), read what the dispatcher actually needs. It is
not a routing job; the host's protected-mode side has never executed:

1. **It writes through cs.** `Interupt31` does `mov ax,cs / mov ds,ax`,
   then `GetDataSelector` does `mov [DataSel],ax` via that ds. A code
   selector is readable, never writable: the first int 31h would #GP
   before reaching any function.
2. **Group-relative offsets.** `code32` is in the `ddt` group
   (`assume cs:ddt`), so its offsets are ddt-relative. `InitProtect`
   copies `BeginProtect`..`EndProtect` to offset 0 of an extended-
   memory block, so every absolute reference in the copy is wrong by
   `BeginProtect`'s ddt offset, and `Function` (`code16`, line ~398) is
   not copied at all. Running the code IN PLACE in the resident image,
   with a use32 code selector based at the ddt segment and a separate
   writable data alias, avoids both 1 and 2.
3. **Per-task host data.** `GetDataSelector` needs `TCBDPMI` in the
   task's tcb and fails ("No Memory") if it is zero. Whether and where
   that area is allocated is unverified.

Plan, smallest first: (a) in-place use32 code selector plus a data
alias for the host, registered with the monitor through int 6fh at
install; (b) `einative` routes `dl=31h` to it; (c) `Interupt31`
switched from `ds=cs` to the data alias; (d) prove with 0400h only,
which touches none of the per-task state; (e) then `TCBDPMI` and the
rest.

### The "0000000K" banner and a memory policy (idea, for later)

`MsgMem` is a constant string nothing fills in. The monitor's memory
device API can supply a real figure: `valloc` (memman `ah=1`) returns
the LARGEST available block in `cx` when a request cannot be met, and
`parmused` tracks extended memory in use. A request for everything,
then an immediate `vrelease` (`ah=2`), measures free memory without
keeping it.

Sizing, from Roeland's numbers: 32 MB machine, `smpsize=64` KB,
twelve 612 KB tasks = ~7.3 MB, leaving roughly 24 MB. Proposed policy:
DPMI must not starve task creation, so report and hand out
`free - reserve`, where the reserve is a `$DPMI.SYS` parameter (tasks
x size, or KB directly), defaulting to something conservative. The
banner then shows `free - reserve` at install, and 0500h reports the
same live. This lands with 0500h, after int 31h routes.

## UPDATE 38 (2026-09-23) — int 31h routes; 0400h answered by the monitor

`_386.ASM`: `$386.SYS` 21664 -> 21712, 0 warnings, 0 severe.

A client's protected-mode `int 31h` no longer falls through to the
real-mode vector. In `einative`, `dl=31h` now dispatches to a new
`einint31` (inserted before the `dl=21h` test; `75 04` over a `66h`
`E9 rel16`), which answers from the monitor itself, the same way
`einative` already answers int 21h. Results go into the v86 register
slots (`ncavax`..`ncavdx`, `ncavflag`), which `einback` copies to the
client.

Implemented: `0400h` get version -> `ax=005Ah` (0.90), `bx=0001h`,
`cl=03h`, `dh/dl=08h/70h`, CF clear. Any other function: CF set,
registers unchanged (not yet exercised by a test).

Why the monitor and not the host's `Interupt31`: `einative` runs at
ring 0 with the client's frame on the monitor stack, so handing the
call to a ring-3 host handler means rewriting the client's return
frame so the client "returns" into the host, and building a frame on
the client's 16-bit stack for the host's use32 `retf 2`. That, plus the
repairs UPDATE 37 lists, is a separate step. Answering in the monitor
proves the dispatch point first with no ring transfer at all.

Measured: `0400h` client prints `ax 005A bx 0001 cx 0303 dx 0870`,
flags `3246` (CF clear; `ch=03` is the client's leftover, DPMI defines
only `cl`). Previously the same client produced a garbage v86 frame,
int 3 and an invalid opcode. Regression: the two-allocation client
twice, the base client and `DIR`, no "Internal error".

Open decision for the next functions: keep implementing int 31h in the
monitor (einint31 grows a table like `eintable`), or do the ring-3
handoff and repair TSL's `Interupt31` so its full table is used. The
monitor route is proven and incremental; the host route reuses a lot
of written code that has never run.

## UPDATE 39 (2026-09-23) — route 1 chosen; int 31h 0500h implemented

Decision (Roeland): int 31h functions are implemented in the monitor
(`einint31` grows its own dispatch), not by repairing TSL's ring-3
`Interupt31`.

`_386.ASM`: `$386.SYS` 21712 -> 21872, 0 warnings, 0 severe.

`0500h` get free memory information, in `e310500`:

- the figure comes from the memory device itself, reached the way
  `einfun91` reaches it (`dovmint` with `dx = offset rhentry`):
  `valloc` (ah=1) asked for `0FFFFh` pages returns the largest block it
  could give in `cx`; it is released at once with `vrelease` (ah=2).
  Nothing stays allocated. The page count is kept in `ncabufer` across
  the second call because `dovmint` resets the monitor stack
- buffer at the client's `es:(e)di` (offset zero-extended for a 16-bit
  client, D bit of its cs as elsewhere): +00 largest block in bytes,
  +04/+08 that many pages, +14 free pages, every other dword
  `0FFFFFFFFh` as DPMI 0.9 allows
- client `di/ax/bx/cx` saved in `ncauregs` and restored, CF clear

Defect hit and fixed on the way, the handover's dominant class again:
MASM encoded `or ax,-1` as `0D FFFF` (imm16). Under the 32-bit cs `0D`
takes an imm32, so it swallowed the next two `stosw` (`AB AB`) and
every later store shifted: the page count landed at +0C and +14 read
-1. Now hand-encoded `83 C8 FF` (sign-extended imm8, same length in
both modes). Anything writing an `or/and/cmp r,imm` in this region
should prefer the `83` form or hand-encode.

Measured (rig = 16 MB DOSBox): largest free block `00EB6000h` =
15,425,536 bytes, free pages `0EB6h` = 3766 (x 4096 = the same
figure), identical on two consecutive calls -- so the probe releases
what it grabs. `bx`/`cx` preserved, CF clear. Regression: allocating
clients twice, the base client, `DIR`, `VER`: no "Internal error".

Next: apply the reserve policy (UPDATE 37) to this figure, and have
`$DPMI.SYS` print it in the install banner in place of `0000000K`.
Then 0501h/0502h/0503h and 0100h-0102h.

## UPDATE 40 (2026-09-23) — DPMI task reserve; the banner shows a real figure

`$386.SYS` 21872 -> 21904, `$DPMI.SYS` 4941 -> 5117. 0 severe; the
same four pre-existing A4057 warnings in `_DPMI.ASM`.

### What

- `DEVICE=$DPMI.SYS /R:nnnn` -- KB of extended memory DPMI leaves for
  task creation. Default `RSVDEFKB` = 2048. Twelve 612 KB tasks want
  about `/R:7400`.
- `$DPMI.SYS` `SetupReserve` (called just before the banner prints,
  after the host's own extended memory is allocated): parses `/R:`
  from the device init request (`[request]`, `+18` = the text after
  `DEVICE=`, either case), tells the monitor the reserve in pages via
  new int 6fh `7790h` SET_DPMI_RESERVE (`e6f90`), measures free memory
  (memman `valloc` for `0FFFFh` pages then `vrelease` -- the contract
  says `cx` is the number actually ALLOCATED on a short request, so the
  release is required, which also confirms 0500h's), and writes
  `free - reserve` in KB into `MsgMem`, leading zeros blanked.
- `0500h` subtracts `dpmirsv` from the page count, clamped at 0.

### Measured (rig, 16 MB)

| reserve | banner at install | 0500h at client run |
| --- | --- | --- |
| default 2048 KB | `13052K` | `00CB6000h` = 13016 KB |
| `/R:7400` | `7700K` | `0077C000h` = 7664 KB |

Both columns differ by exactly 5352 KB = 7400 - 2048. Each 0500h
figure is 36 KB (9 pages) below its banner: memory used between
install and the client run. Regression: allocating clients, the base
client, `DIR`, `VER`: no "Internal error", keyboard fine.

### Layout trap, found the hard way

`dpmirsv` was first added next to `parmused`, inside the
`parmgran / parmtot / parmused / parm6ec ...` block. That block is read
BY LAYOUT (the memory device's status call hands it out), so the
insertion shifted `parm6ec` and everything after it, and the guest
stopped taking keyboard input while the prompt still displayed. Moved
to the code region, after `einint31`'s final unconditional jump (image
offset `3354h`), reached through `ss:` like the other monitor data;
`parm6ec` is back at `0DAAh`. Every earlier insertion this session was
in the code region, where offsets are only ever reached by label:
**never add a field inside the monitor's data area.**

## UPDATE 41 (2026-09-23) — int 31h 0501h/0502h/0503h (extended memory blocks)

`_386.ASM`: `$386.SYS` 21904 -> 22496, 0 warnings, 0 severe.

Also recorded from Roeland's machine (32 MB): the install banner shows
about 29 MB. Correct: at boot only the startup task exists. The
reserve (UPDATE 40) is a FIXED FLOOR -- DPMI may use `free - R` whatever
is running -- so once planned tasks exist, the floor double-counts
them. Accepted for now; `/R` should be read as "always leave this much
free", i.e. one or two tasks' worth. A shrinking reserve
(`planned - current tasks` x size) needs MOS's live task count; later.

### Design

- handle = `SI:DI`: `SI` = pages, `DI` = starting bank. Linear address
  = (bank + `110h`) x 4096, the mapping `einfun91` already uses
- `0501h`: size `BX:CX` -> pages (round up, >65535 pages refused);
  probe = memman `valloc` for `0FFFFh` pages (the largest block,
  allocated); if `request + dpmirsv` fits, keep the head and
  `vrelease` the tail, else release all and fail
- `0502h`: `vrelease(bank=DI, count=SI)`
- `0503h`: shrink or same size releases the tail in place (address and
  bank unchanged); grow allocates a new block through the same path,
  copies the old pages across with `rep movsd` through the flat
  `ds`/`es` (absolute zero), then frees the old block -- a failed grow
  leaves the original intact
- failure: CF set, `ax/bx/cx` restored; success: CF clear, `ax` kept
- scratch: `ncauregs` for the saved registers and the request (bit 31
  flags a 0503h grow); `ncabufer+00..0Fh` only, because `[ebx+disp8]`
  must stay below `80h` or the displacement goes negative
- hand encodings through small macros at the top of the block (`NLD`,
  `NST`, `NLDW`, `NSTW`, `NADD`, `NSUB`, `NCMP`, `EAXI` for true imm32,
  `MEMDEV`): the bytes are exactly what the file writes by hand
  elsewhere, reviewable in one place. Verified in the listing
  (`05 0FFF 0000`, `A9 0000 FFFF`, `66 E8` / `66 C3` pairing)

### Measured (rig, default reserve)

| step | linear | handle (pages, bank) | largest free |
| --- | --- | --- | --- |
| start | | | `CB6000` |
| 0501h 64 KB | `1FA000` | `0010`, `00EA` | `CA6000` |
| 0503h -> 128 KB | `20A000` (moved) | `0020`, `00FA` | `C86000` |
| 0503h -> 16 KB | `20A000` (in place) | `0004`, `00FA` | `CA2000` |
| 0502h | | | `CB6000` |
| 0501h `BX=FFFFh` | | | CF set |

The -192 KB after the grow is fragmentation, not a leak: the freed
64 KB at bank `EA` is a hole BEFORE the new block, and 0500h reports
the largest CONTIGUOUS block. After the final free the figure is back
to `CB6000` exactly. Regression: allocating int 21h clients, base
client, `DIR`, `VER`: no "Internal error".

### Open

- blocks are NOT released at the client's 4Ch (`freeclsel` only frees
  descriptors): a client that exits without 0502h leaks until reboot
- no ownership check: any client can 0502h any bank range
- the 0503h grow copy is untested for content: a client cannot touch
  its block yet, because the descriptor functions (0000h alloc LDT
  descriptor, 0007h set base, 0008h set limit) are not implemented --
  they are the natural next step, and make 0501h actually usable
- 0503h grow always moves; growing in place when the following banks
  are free would avoid the copy and the hole

## UPDATE 42 (2026-09-23) — int 31h descriptors: 0000h/0001h/0006h/0007h/0008h

`_386.ASM`: `$386.SYS` 22496 -> 22912, 0 warnings, 0 severe.

A client can now reach the memory 0501h gives it.

### Design

- no LDT: client descriptors are `gdtspace` slots tagged `80h|taskid`
  in `dtitable`, like those `8eh`/`86h`/48h make, so `freeclsel`
  already frees them at the client's 4Ch
- the tag is also OWNERSHIP: `e31sel` accepts a selector only inside
  `gdtspace` and tagged for the calling task; 0001h/0006h/0007h/0008h
  refuse anything else with CF set, so a client cannot rewrite the
  host's, the monitor's or another task's descriptors
- 0000h: `CX=1` only for now; first free slot, data r/w, present,
  dpl 3, base 0, limit 0, byte-granular, 16-bit; `AX` = selector|3
- 0006h / 0007h: base in `CX:DX` (gdt +2 word, +4 and +7 bytes)
- 0008h: limit in `CX:DX`; up to 1 MB byte-granular, above that the
  low 12 bits must be all ones and G is set; D/B and AVL preserved
- dispatch: `AX < 0010h` goes to `e31desc`; no `dovmint` in this block,
  so near subroutines (`66h call` / `66h ret`) are safe
- MASM hazards met and handled: short `jc`/`jne` to a shared failure
  label out of range (A2053) -> local `jnc` over a `66h`-prefixed near
  `jmp`; byte access to the word-typed `gdt` needs `byte ptr` (A4031).
  Store widths verified in the listing: word stores `66 67 36 C7 85`,
  byte stores `67 36 C6 85`

### Measured -- this also closes UPDATE 41's untested 0503h copy

0501h 64 KB, 0000h -> selector `0073h`, 0007h base = the block's
linear address (0006h reads back `001FA000`), 0008h limit `FFFFh`,
write `1234h` at 0 and `ABCDh` at `FFFEh`. Then 0503h to 128 KB moves
the block (`0020A000`); 0007h re-bases the selector, 0008h limit
`1FFFFh`; reads give `1234h` and `ABCDh`: THE GROW COPY IS CORRECT.

Refusals: 0001h on `18h` (monitor cs) -> CF set; 0008h with limit
`00100000h` (above 1 MB, low 12 bits not all ones) -> CF set. 0001h on
the client's own selector -> CF clear. 0502h frees the block.
Regression: allocating int 21h clients, base client, `DIR`, `VER`: no
"Internal error".

### Open

- 0000h with `CX>1` (contiguous descriptors) not supported
- memory blocks still not released at 4Ch (descriptors are); no block
  ownership check in 0502h/0503h -- both need a per-task block list,
  which this descriptor tagging does not give
- 0008h cannot lower a limit below a live segment register's use (the
  CPU checks on the next load, which is DPMI's rule too)

## UPDATE 43 (2026-09-23) — per-task DPMI memory blocks: ownership and release at 4Ch

`_386.ASM`: `$386.SYS` 22912 -> 23504, 0 warnings, 0 severe.

### Design

- `dblktab`: `DBLKN` (32) entries of 8 bytes -- +0 in use, +1 task id,
  +4 dword handle (`start bank << 16 | pages`, the same packing as
  `SI:DI`). Lives in the code region after an unconditional jump, next
  to `dpmirsv`, NOT in the monitor's data area (UPDATE 40)
- helpers `e31tid` (dl = task id via `addrnca`), `e31new` (free
  entry), `e31find` (entry for this task and handle, eax preserved) --
  no `dovmint`, so near subroutines are safe
- 0501h: after a successful allocation, records the block; if the
  table is full the fresh block is released and the call fails, so
  untracked memory is never handed out
- 0502h / 0503h: refuse (CF set) a handle not recorded for the calling
  task -- the ownership check; 0502h clears the entry, 0503h updates it
  to the new handle (the 0503h path finds it by the old handle held in
  `ncabufer+08`)
- 4Ch (`einfun4c`): after `freeclsel`, releases every block recorded
  for the task. Inline loop, not a subroutine, because the memory
  device call goes through `dovmint`; loop index in `ncauregs+04`,
  task id in `+00`, and the client's `ax` (4C00h) saved in `+08` and
  put back before `einstand` reflects the termination

### Defect hit on the way -- the imm16 trap a third time

`add ax,8` in the 4Ch loop assembled as `05 0008`. Under the 32-bit cs
`05` takes an imm32, so it swallowed `08 00 89 43`, fell into `50`
(`push eax`) and looped until the monitor stack wrapped to `FFFFF900`;
the event log showed int 0Eh repeating at `3A2F`, and DOSBox itself
died with SIGSEGV from the recursion. Now `83 C0 08`. After fixing,
the whole new region was SWEPT in the listing for accumulator-
immediate opcodes (05/0D/25/2D/35/3D/A9) carrying a 16-bit immediate
without a `66h` prefix: that was the only one. Recommend this sweep
after any change in the 32-bit-executed, use16-assembled region.

### Measured

Leak test: a client prints the largest free block, allocates 64 KB and
exits WITHOUT freeing; three runs in one boot.

| build | runs start at | handle bank | forged 0502h / 0503h |
| --- | --- | --- | --- |
| this | `CB6000` every run | `EA` every run | CF set / CF set |
| control, UPDATE 42 | `CB6000` ... `C86000` | drifts to `11A` | -- |

The descriptor/grow client (UPDATE 42) twice in one boot: grow copy
still `1234h`/`ABCDh`, refusals and own-free unchanged. Regression:
allocating int 21h clients, base client, `DIR`: no "Internal error".

### Open

- the driver's Unregister path (int 6fh 778Fh -> `e6f8f`) frees
  descriptors but NOT blocks: it runs from v-86 and cannot use
  `dovmint`. Blocks of a task removed that way still leak
- 32 blocks system-wide; `0000h` with `CX>1` still unsupported

## UPDATE 44 (2026-09-23) — UPDATE 43's open items closed

`_386.ASM`: `$386.SYS` 23504 -> 24448, 0 warnings, 0 severe.

### 1. Blocks released on the Unregister path (int 6fh 778Fh, `e6f8f`)

`e6f8f` runs from v-86 and cannot use `dovmint`, but the release is
monitor code: `e6f06` (behind memman's `vrelease`) is just `adrpage` +
`nrelease(ebx=start, ecx=count)`, both in the same use32 int 6fh
region. `e6f8f` now reads the task id (before `adrpage` moves ds),
walks `dblktab` and calls them directly. Plain use32 code, so MASM
encodes it correctly -- none of the imm16 traps apply there.

It must preserve every register: int 6fh handlers do (see `e6f8e`'s
push/pop), and this loop uses all of them plus ds/es. First version
did not, and the caller got garbage back. Now pushes eax..edi, ds, es.

Measured: client with 42 blocks calls `int 6fh ax=778Fh` directly
(reflected into the monitor exactly as the driver's Unregister is):
largest free `C7E0` -> `C6E0` -> `CB60`, all released. UPDATE 43 with
the same client: the block stays allocated.

**Test-method warning:** calling 778Fh from inside a RUNNING client
ends with MOS's "Divide by zero error" (`mosint00`) at exit. UPDATE 43
does the same with nothing allocated, so it is not this change:
Unregister frees the task's descriptors, the host's own cs included
(tagged since UPDATE 34), while they are still in use. It is only
valid at task teardown. The proper test -- REMTASK of a task running a
DPMI client -- has not been done; the rig does not yet drive it.

### 2. Table: `DBLKN` 32 -> 128 (1 KB)

A client allocated 40 x 4 KB blocks; the next run started from the
same free figure, so all were released at 4Ch.

### 3. 0000h with CX>1, and 0003h

0000h searches for CX contiguous free `dtitable` slots (`CX` 1..
`dtilen`), claims and initialises each; AX = first selector. 0003h
returns 8. Measured: three selectors (`006B`, increment `0008`) set
16 KB apart into one block, written through each, read back
`1111h`/`2222h`/`3333h` through the first. Note `dtilen` is 30 for the
whole system, so large requests will fail.

### Regression

Descriptor/grow client still reads `1234h`/`ABCDh` after the move; the
leak-test client starts from `CB6000` every run; allocating int 21h
clients: no "Internal error". The imm16 sweep (UPDATE 43) over the
32-bit-executed region found nothing.

The test clients live only as patches to `DPMITST.ASM` in the scratch
tree; the shipped `DPMITST.ASM` is the original.

## UPDATE 45 (2026-09-23) — before 0100h-0102h: PM 49h does not reach MOS

No source change; tree is UPDATE 44. Investigated UPDATE 35 first,
because DPMI 0101h/0102h go through DOS 49h/4Ah.

`mosfun49` (MOSFUN00.ASM) takes the caller's es from the task save
area (`tes`), validates the chain (`mmsetup`), checks the MCB at
`es-1` for 'M'/'Z', sets its owner to 0, and on success puts the MCB
segment into `ax` -- a fingerprint.

Measured, the client reading the MCB itself (0006h gives the 48h
selector's base; a 0000h/0007h/0008h selector aimed 16 bytes below it
reads the MCB):

	MCB lin 00019D30, type 'M', owner before/after 49h: 09AA / 09AA

and `ax` after the protected-mode 49h is the client's own `4973h`
(`ah=49h`, stale `al`), CF clear. So `mosfun49` never ran its success
path, and the block is not freed.

Experiment: 49h routed back to plain reflection (`einstand`, the raw
selector in es) in a scratch build: same result, owner unchanged. So
it is NOT the selector-to-segment conversion in `einfun49`, and NOT
MOS expecting a selector. A 49h reflected from a native-mode task does
not take effect in either form, while 48h through the same reflection
works.

Next: a v-86 level trace of the reflected 49h into MOS's int 21h entry
(PMTRACE_STEPS currently triggers only after int 6fh 7705h or int
0D4h ah=11h -- add a trigger for the reflection of int 21h ah=49h), to
see where it goes instead of `mosfun49`. Until then 0101h/0102h would
inherit the no-op; 0100h alone would work (48h does).

## UPDATE 46 (2026-09-23) — int 31h 0100h; a regression since UPDATE 43 found and fixed

`_386.ASM`: `$386.SYS` 24448 -> 24624, 0 warnings, 0 severe.

### 0100h allocate DOS memory block

Reflects DOS 48h (as `einfun48`), then builds a selector: base =
segment * 16, limit = size - 1, byte-granular, data r/w, dpl 3, tagged
`80h|taskid` (freed at 4Ch; DOS reclaims the block at termination).
CF set on failure with DOS's `ax` (error) and `bx` (largest available)
passed through, as DPMI specifies. No descriptor free: ax = 8, CF set.

**Deviation:** a block over 64 KB gets ONE selector with the full limit
(up to 1 MB) instead of one per 64 KB as DPMI 0.9 describes. Fine for
32-bit clients, not for 16-bit clients needing more than 64 KB.

Measured: 256 paragraphs -> segment `19D4`, selector `007B`, CF clear;
0006h base `00019D40` = `19D4` x 16; writes at 0 and `FFEh` read back;
`BX=FFFFh` -> CF set, `ax=0008`, `bx=852B`.

0101h/0102h NOT implemented: they need DOS 49h/4Ah, which do not take
effect from a native-mode task (UPDATE 45).

### Regression: "Divide by zero error" after EVERY client exit since UPDATE 43

Every DPMI client, including the unmodified base DPMITST, ended with
MOS's `mosint00` message. Missed by UPDATES 43-45 because their
regression runs only grepped for "Internal error". Bisected on the
saved sources with the base client: UPDATE 34/40/42 clean, UPDATE 43
not.

Cause: `einstand` -> `dovmint` takes the VECTOR in `edx`. The 4Ch
block-release loop added in UPDATE 43 overwrote it -- `e31tid` puts the
task id in `dl`, the memory-device calls put `rhentry` in `dx` -- so
the client's termination was reflected through vector <task id>:
vector 0 for task 0, MOS's divide handler. No divide ever happened.
Fix: `xor edx,edx / mov dl,21h` before `jmp einstand` in `e4cdone`.

**UPDATE 44 corrected:** its "Divide by zero" after a mid-run 778Fh was
attributed to Unregister freeing live descriptors. Wrong -- it was this
bug, present on every exit. On the fixed build the same 778Fh test
releases the block (`CB60`/`CA60`/`CB60`) and exits clean.

Rule, from this: any handler that ends in `einstand` or `dovmint` must
leave `edx` = the vector. And regression runs must check the screen
for EVERY failure text (Divide, Internal, and so on), not one.

### Regression (all with Divide/Internal counts)

| client | result | Divide | Internal |
| --- | --- | --- | --- |
| base DPMITST + two-48h int 21h client | clean exit | 0 | 0 |
| 0100h | as above | 0 | 0 |
| descriptors + 0501h/0503h | grow copy `1234h`/`ABCDh` | 0 | 0 |
| leak test, twice | `CB6000` both runs, forged handles refused | 0 | 0 |
| mid-run 778Fh | block released, exits clean | 0 | 0 |

Next: the 49h investigation (UPDATE 45) -- a PMTRACE_STEPS trigger on
the reflection of int 21h ah=49h, and follow it into MOS.

## UPDATE 47 (2026-09-23) — 49h investigation, first results

No driver change; tree is UPDATE 46. Tracer extended (see RIG.md):
`PMTRACE_STEP_AH` arms step mode on a protected-mode client's int 21h
with that `ah`.

Stepped the reflected 49h and, for comparison, the reflected 48h, from
the same client, and cut each at the first return into the monitor:

| call | v-86 steps | where it runs |
| --- | --- | --- |
| 48h (works) | 968 | entirely in segment `fff8`, entry `fff8:5008`; never enters MOSINT21 |
| 49h (no effect) | 313 | enters `fff8:a8f5`, then `MOSINT21` -> helper -> `FUN00A` -> console and int 24h/25h code |

- MOS receives the right registers: `ax=49AAh`, `es=19D4h` (the
  segment `einfun49` converted), `ss=19ABh` (the task's control area).
- The 49h path never reaches `MOSFUN49` (`0CB0:5BB0` = `d230:5BB0`);
  the register holding `19D3h` (the MCB) never appears.
- `FUN00A` is, per `MOSFUN00.ASM`, "entry point for mosfun4c" --
  termination code. MOSINT21 dispatches on `[tah]` after `mossaver`
  and goes through a `tcbnest` check (nest level 1 -> `mos21k`, else
  `mos21b`).
- `$$MOS.MAP`: `0CB0` = MOSSEG, which runs at `d230`. `fff8` does NOT
  correspond to the kernel's `DDT` group (`0230`): offsets there map to
  nonsense (`CRTINT3`), so `fff8` is some other resident code.

Reading: something resident in `fff8` hooks int 21h and services 48h
itself; 49h is passed on into MOSINT21, where it is handled as a
termination-path call rather than dispatched to `mosfun49`. Unproven.

Next:
1. identify the `fff8` code: read IVT[21h] at the time of the call,
   and find which driver or kernel part loads at `FFF80h`
2. read MOSINT21 from `mossaver` to the dispatch: what `[tah]` holds
   for this call, and whether the `tcbnest` path sends it to `mos21b`
3. compare with a real-mode 49h (works), stepped the same way

## UPDATE 48 (2026-09-24) — the 49h mystery solved; 4Ah, 0101h, 0102h in

`_386.ASM`: `$386.SYS` 24624 -> 24912, 0 warnings, 0 severe.

### Root cause of "PM 49h/4Ah do nothing" (UPDATES 25, 35, 45, 47)

`einfun49` converts the client's selector to a segment with

	mov dl,byte ptr ss:[si+gdt+4]	; base bits 16-23
	shl dl,4

and then calls `dovmint`, which takes the VECTOR in `edx`. For a block
at `19D4h` (base `19D40h`) `dl` became `10h`: the call was reflected
through int 10h, the video BIOS, and never reached DOS. That is why the
UPDATE 47 trace showed console routines, BIOS code and MOS's int 10h
hook instead of MOSINT21 -> MOSFUN49, and why the register values
looked right (they were; only the vector was wrong). Every theory in
UPDATES 45/47 about MOS rerouting the call is withdrawn.

Fix: `xor edx,edx / mov dl,21h` immediately before `dovmint`. Same
class as UPDATE 46; the rule stands: **anything that ends in
`dovmint` or `einstand` must set `edx` = the vector right before the
call.**

The UPDATE 47 tracer work stays useful: `PMTRACE_STEP_AH` (RIG.md)
arms step mode on a protected-mode int 21h, and it was the comparison
of two entry points (`fff8:5008` for 48h vs `fff8:a8f5` for "49h")
that pointed at the vector.

### Now working

- 49h: owner of the freed block goes `09AAh` -> `0000h` (read by the
  client through a 0000h/0007h/0008h selector aimed at the MCB)
- 4Ah (`einfun4a`, parked since UPDATE 35, same fix): UPDATE 35's
  sequence now gives A = `19D4`, B = `19DD` (after the grown A), C =
  `19DD` (B's space reused); an impossible grow returns CF, `ax=0008`,
  `bx=0008` -- A cannot pass the block behind it, DOS's own answer
- 0101h free DOS memory block: `dx` = selector; ownership via
  `e31sel` (a forged selector, `18h`, is refused with CF); base ->
  segment -> 49h; on success the descriptor slot is freed too
- 0102h resize DOS memory block: `bx` = new size, `dx` = selector;
  4Ah; on success the descriptor's limit follows (bits 16-19 into byte
  6, G/D/AVL kept); on failure DOS's `ax`/`bx` pass through
- common code `e31dsel` for both; the client's `bx` is restored after
  the ownership check borrows `ncavbx`

Measured: 0100h 256 paragraphs -> `19D4` / `0073`; 0102h to 512 ->
CF clear and a write at `1FFEh` reads back (`7E7Eh`); 0102h `FFFFh` ->
CF, `ax=0008`, `bx=862C`; 0101h forged -> CF, own -> CF clear; the next
0100h gets `19D4` back.

### Regression (Divide / Internal checked on every run)

| client | result | Div | Int |
| --- | --- | --- | --- |
| two-48h int 21h client | clean | 0 | 0 |
| descriptors + 0501h/0503h grow copy | `1234h`/`ABCDh` | 0 | 0 |
| 0501h leak test | `CB6000` both runs, forged refused | 0 | 0 |
| mid-run 778Fh | block released | 0 | 0 |
| 0100h | `5A5Ah`/`A5A5h`, huge refused | 0 | 0 |
| 48h/4Ah/49h sequence | `19D4 19DD 19DD` | 0 | 0 |
| 0100h/0101h/0102h | as above | 0 | 0 |

The memory side of DPMI 0.9 is now complete: 0100h-0102h, 0500h-0503h,
plus int 21h 48h/49h/4Ah from protected mode.

## UPDATE 49 (2026-09-24) — int 31h 0200h/0201h; design for 0202h-0205h

`_386.ASM`: `$386.SYS` 24912 -> 24992, 0 warnings, 0 severe.

### 0200h/0201h get/set real-mode interrupt vector

`bl` = vector, `cx:dx` = segment:offset. Read/written at linear
`bl*4` through `ds`, the absolute-zero flat selector einative leaves
loaded, i.e. the current task's real-mode vector table. `[esi]` is
hand-encoded (`8B 06` / `89 06`): MASM's `[si]` (rm=100) is a SIB form
under the 32-bit cs. 0201h writes the dword with interrupts off.

Measured: DOS 35h in real mode before the switch gives int 21h =
`FFF8:5008`; 0200h from protected mode gives the same. 0201h sets
vector 60h to `1234:5678`, 0200h reads it back, then it is restored
(second run in the same boot is identical). This also confirms
`fff8:5008` as DOS's int 21h entry -- the address the working 48h
trace in UPDATE 47 started at. Regression: clean (Divide/Internal 0).

### 0202h-0205h: design, not yet built

Setting a protected-mode vector is only honest if the monitor then
DELIVERS the client's `int N` to that handler, and 0204h must return a
default handler a client can chain to. Plan:

- per-task hook table (like `dblktab`): task id, vector, sel:off32
- delivery for SOFTWARE interrupts raised by the client: in `einative`,
  before the int 21h / int 31h dispatch, look the vector up; if hooked,
  build an iret frame on the client's stack (16- or 32-bit by the D bit
  of its cs, as elsewhere) and redirect the frame on `p0stack` to the
  handler; the handler's `iret` returns straight to the client, ring 3
  to ring 3
- default handlers returned by 0204h: small ring-3 stubs, one per
  vector, that re-enter the monitor through a PRIVATE path meaning
  "reflect vector N to real mode now" -- NOT `int N` itself, or a
  client chaining to the default would re-enter its own hook forever
- hardware IRQs while a client runs are NOT covered by this and need
  their own path; 0202h/0203h (exception handlers) likewise need
  delivery from the monitor's exception entry with the DPMI exception
  frame, and should not claim success before that exists

## UPDATE 50 (2026-09-24) — int 31h 0204h/0205h: protected-mode vectors, delivered

`_386.ASM`: `$386.SYS` 24992 -> 27216, 0 warnings, 0 severe (about
1.4 KB is the stub table and the hook table).

### What

- **0205h** hooks vector `bl` for the calling task with `cx:(e)dx`
  (16-bit client: `dx` only). The selector must be a present dpl-3
  code descriptor inside the gdt. Setting a default stub back (see
  below) unhooks.
- **delivery**: `einative` now jumps to `einvhook` right after loading
  the vector into `dl`, before the normal dispatch (now labelled
  `eindisp`). If the task has hooked that vector, `einvdl` writes an
  iret frame on the client's own stack (16- or 32-bit by the D bit of
  its cs) and redirects the client's return to the handler; the
  handler's iret goes straight back to the client, ring 3 to ring 3.
- **0204h** returns the hook, or a DEFAULT handler: `dpmistub`, 256
  stubs of 4 bytes (`int 0E6h` / N / `iret`) reached through two
  permanent (`0FEh`) stub selectors, 16- and 32-bit, made on first use.
  The monitor accepts int 0E6h only when the client's cs is a stub
  selector: it reads N from the stub, steps eip onto the iret, and
  re-enters `eindisp` with vector N. So chaining to the default behaves
  exactly like an unhooked int N -- int 21h translations included --
  and cannot re-enter the client's hook.
- **cleanup**: a task's hooks are cleared at 4Ch (`e31hclr`, called
  from `einfun4c`) and on the driver's Unregister path (inline in
  `e6f8f`); otherwise a later program in the same task would get
  interrupts delivered to a dead handler.
- `phooktab`: `DPHKN` (32) entries of 12 bytes, in the code region
  next to `dblktab`.

### einback rebuilds the WHOLE return frame -- read this before touching returns

`einback` does `rep movsw` with `cx=18`, which under the 32-bit cs is
`rep movsd`: 18 DWORDS, 72 bytes, from `ncairegs+4` to `p0stack-72..-1`.
That covers the entire iret frame, rebuilt from the NCA's copy
(`ncanip`, `ncancs`, `ncanflag`, `ncansp`, `ncanss`) taken at einative
entry. The first delivery version wrote `ss:[p0stack-20]` etc. and the
client simply returned to its own code: einback had overwritten it.
Measured with the tracer: the frame held the handler address right
up to einback, the IRET event's popped frame showed the original.
Anything that changes where a client returns (delivery, stubs,
future callbacks) must write the `ncan*` copy, never `p0stack`.

### Measured

Client, twice in one boot: 0204h(60h) default = `0073:0180` (stub16,
60h x 4); 0205h(60h) -> CF clear; two `int 60h` -> the counting handler
reached 2; 0204h(60h) -> the client's `cs:0285`. Then int 21h hooked
with a handler that counts and chains to the default via `jmp far`:
a string printed through the hook appears on screen and the count is 1.
Unhook both, exit; the second run behaves identically (hooks cleaned).

Regression, all nine clients, Divide/Internal 0 everywhere. Segments
and largest-block figures moved up by 4 KB (`19D4` -> `1AD4`, `852B`
-> `842B`): the larger `$386.SYS` shifts everything above it; the
relations the tests check are unchanged.

### Scope limits

- delivery covers what reaches `einative`; hardware IRQs arriving
  while a client runs are expected to go the same way but are NOT
  verified
- IF/TF are not cleared for the handler: a ring-3 handler could not set
  IF back when IOPL < 3
- 0202h/0203h (exception handlers) not implemented
- 32 hooks system-wide

## UPDATE 51 (2026-09-25) — int 31h 0300h: simulate real-mode interrupt

`_386.ASM`: `$386.SYS` 27216 -> 27520, 0 warnings, 0 severe.

The call DOS extenders route nearly all their DOS I/O through: real-
mode registers in, real-mode registers out, no translation.

### How

`bl` = vector, `es:(e)di` = the 50-byte DPMI real-mode call structure
(+00 EDI, +04 ESI, +08 EBP, +10 EBX, +14 EDX, +18 ECX, +1C EAX, words
+20 FLAGS, +22 ES, +24 DS). The structure's linear address is the es
descriptor's base plus (e)di (zero-extended for a 16-bit client).

1. the client's protected-mode register set -- `ncairegs`, 10 dwords
   -- is parked in `ncabufer` with one `rep movsd` through the flat
   ds/es
2. the v-86 set (`ncav*`) is loaded from the structure
3. `dovmint` reflects the vector like any other interrupt, `edx` set
   to the vector right before the call (the UPDATE 46/48 rule)
4. the resulting `ncav*` are written back into the structure
5. the client's registers are restored; only CF (clear) changes

Nothing is translated: pointers in the structure are real-mode
segment:offset pairs, which is what a DPMI client expects here (and
what makes this simpler than the int 21h translation layer).

### Limits

- `CX` (stack words to copy) must be 0, otherwise CF set
- the structure's `SS:SP` is ignored: `dovmint` always supplies the
  real-mode stack, as DPMI specifies for `SS:SP` = 0
- `FS/GS/IP/CS` in the structure are not used by an interrupt and are
  left as they were; `BH` (reserved flags) ignored
- 0301h/0302h (call real-mode far procedure / iret procedure) not yet

### Measured

- `ah=30h` via 0300h returns the same `ax` (`0005`) as a direct
  protected-mode `int 21h ah=30h`; CF clear
- the real test of real-mode semantics: 0100h allocates DOS memory, a
  `$`-string is written through the SELECTOR, then 0300h with `ah=09h`
  and `DS` = the REAL-MODE SEGMENT prints it
- `CX=1` refused with CF

Test-client lesson: the first run allocated 1 paragraph and copied a
~45-byte string into it -- an overrun into the next MCB that produced
"Internal error #0" at exit, UPDATE 32's symptom. Allocate what you
write.

Regression, all ten clients including the UPDATE 50 hook client:
Divide/Internal 0.

## UPDATE 52 (2026-09-25) — int 31h 0301h/0302h: call real-mode far procedure

`_386.ASM`: `$386.SYS` 27520 -> 27616, 0 warnings, 0 severe.

### How

`dovmint` takes its real-mode target from the vector table (or, for
the memory device, `mysegadr:dx`) and builds a real-mode IRET frame on
the NCA stack: flags, `mysegadr`, `dovmcont`. A far call needs only a
third target source, so:

- **`dovmfar`** (next to `dovmrh`, before `dovmint`): the same prologue
  (`pop [ncaretad]`, `sp` reset), then `cs:ip` from `ncauregs+08`
  (`cs<<16|ip`), joining dovmint at `dovmrbak`
- **0301h / 0302h** (`e310301`, one entry for both): the same `CX=0`
  check as 0300h, set `ncauregs+04 = -1` as a far-call marker, and
  join 0300h after its vector step (`e0300s`); once the structure's
  address is known, `CS:IP` is read from `+2Ch`/`+2Ah` into
  `ncauregs+08`; at the reflect step the marker selects `dovmfar`
  instead of `dovmint`

One frame serves both: the iret frame is exactly right for 0302h; a
0301h procedure returns with `retf`, leaving the flags word behind,
which `dovmcont` discards when it resets `sp` to a fixed value before
saving anything. Registers in/out, parking of the client's own
registers and the limits (`CX` must be 0, `SS:SP` ignored) are those
of 0300h (UPDATE 51).

`jmp dovmrbak` in `dovmfar` assembled SHORT (`EB 43 90`), which is
correct under either operand size; a near `E9 rel16` would not have
been. Check any unprefixed near jump in this region in the listing.

### Measured (twice in one boot)

Two real-mode routines written through a 0100h selector into DOS
memory: `add ax,cx / iret` at offset 0, `add bx,cx / retf` at 8.
Structure `AX=1000h`, `BX=5000h`, `CX=0234h`:

	0302h -> CF clear, AX = 1234h
	0301h -> CF clear, BX = 5234h

Regression, all eleven clients (incl. hooks and 0300h): Divide/
Internal 0.

### Open in 0300h-0306h

0303h/0304h (allocate/free real-mode callback), 0305h (state
save/restore addresses), 0306h (raw mode switch addresses), and the
stack-copy (`CX>0`) / explicit `SS:SP` cases of 0300h-0302h.

## UPDATE 53 (2026-09-25) — the cheap batch: 0002h, 0009h, 000Ah-000Ch, 0600h-0604h, 0702h/0703h, 0900h-0902h

`_386.ASM`: `$386.SYS` 27616 -> 28256, 0 warnings, 0 severe.

| function | behaviour |
| --- | --- |
| 0002h | real-mode segment -> data selector, base seg*16, limit 64 KB; a repeat for the same segment returns the SAME selector (this task's existing data descriptor with that base, 64 KB, byte-granular), as DPMI asks |
| 0009h | set access rights, `CL` = access byte, `CH` = G/D/AVL; refused unless DPL 3 and S=1; limit bits 16-19 kept |
| 000Ah | data alias of an owned selector: same base and limit, data r/w, dpl 3 |
| 000Bh / 000Ch | get / set the 8-byte descriptor at `es:(e)di`; 000Ch refused unless DPL 3 and S=1 |
| 0600h-0603h, 0702h/0703h | succeed as no-ops: nothing pages to disk on this host |
| 0604h | page size, `BX:CX` = `0000:1000h` |
| 0900h / 0901h / 0902h | disable / enable / get the virtual interrupt flag; `AL` = the state before the call. IF lives in `ncavflag`, which `einback` folds into the client's returned flags |

All selector-taking functions go through `e31sel`: only this task's
`80h|taskid` descriptors are accepted. New helpers (no dovmint, so
near subroutines): `e31base` (gdt offset -> base), `e31free1` (claim
one free slot for tag `dh`), `e31ptr` (linear address of the client's
`es:(e)di`, edi preserved).

Still returning CF on purpose: 0800h (physical address mapping),
0A00h (vendor API), 0B00h-0B03h (debug watchpoints).

Checks on the new code: the imm16-accumulator sweep, plus a new sweep
for unprefixed near `E8`/`E9` in the 32-bit-executed region; both
empty.

### Measured (second run in one boot)

	0002h  B800h twice -> 007B, 007B; base 000B8000
	0009h  valid -> CF clear; access 92h (DPL 0) -> CF set
	000Ah  alias of cs: [100h] via alias = cs:[100h] = 00BBh
	000Ch  round-trip with base 1000h -> CF clear, 0006h low word 1000h;
	       access 92h -> CF set
	0604h  0000:1000; 0600h CF clear
	0900h -> 1, 0902h -> 0; 0901h -> 0, 0902h -> 1

Regression, all twelve clients: Divide/Internal 0.

## UPDATE 54 (2026-09-25) — 0305h; hardware IRQ delivery verified; exceptions examined

`_386.ASM`: `$386.SYS` 28256 -> 28336, 0 warnings, 0 severe.

Plan agreed with Roeland: the small and medium items first (option B),
then real-mode callbacks as their own project (see "Callbacks" below).

### 0305h get state save/restore addresses

No per-switch state needs saving, so size 0 and both routines are a
bare far return, as DPMI allows:

- real mode `BX:CX` = `mysegadr:rhe1`, the `retf` that ends the memory
  device dispatcher in this driver's real-mode code
- protected mode `SI:(E)DI` = stub selector (by client bitness) :
  `400h`, a `retf` (`CBh`) appended after the 256 stubs; the stub
  limit went from `3FFh` to `400h`

Measured: CF clear, size 0, rm `0070:051C`, pm `0073:0400`; the client
far-called the pm routine and it returned; the rm routine via 0301h
(retf frame) returned with CF clear.

### Hardware IRQ delivery -- VERIFIED for IRQ0

UPDATE 50 listed this as unverified. A client hooked vector 08h with a
handler that counts and chains to the default stub, then busy-waited:
the count reached 5 after about 40K loop iterations, the timer kept
running (the chain reflects to the BIOS handler, which does the EOI),
and the client exited cleanly. Hardware interrupts arriving while a
client runs DO reach its hooked handler through `einvhook`.

### Exceptions today, and a trap -- 0202h/0203h still open

A client `div` by zero: the event log shows `INT 00 t=2` from
`cs=008B`; it travels the same `einative` path as an interrupt,
reaches MOS's int 0 handler, which prints "Divide by zero error" and
terminates the program cleanly. A sane default (DPMI also terminates
on an unhandled exception).

TRAP: because faults use the interrupt path, a client that hooks
vector 0-1Fh with 0205h gets the fault with an INTERRUPT frame; an
iret re-executes the faulting instruction for ever. Proper 0202h/0203h
needs the DPMI exception frame (return address to a host stub, error
code, then the client's ip/cs/flags/sp/ss), the handler's `retf` into
that host stub, and the host resuming from the possibly modified frame
-- written into the `ncan*` copy (UPDATE 50), not `p0stack`. Also
needed: telling a fault from a software `int N` for vectors 0-1Fh, and
the error code for #GP and friends, which the entry path has but
`einative` does not currently keep.

### Callbacks (0303h/0304h) -- analysis, not started

All reflection state is single-level: `dovmint` resets the monitor
stack to `s0ip-28` and keeps one return address (`ncaretad`); the
real-mode stack is always the same 256-byte `ncastack`; `dovmcont`
saves into the one `ncairegs` and the client frame lives in the one
`ncan*` copy. A callback re-enters the client from INSIDE a v-86
excursion and, if the callback itself calls DOS (usual), `dovmint`
would restart the real-mode stack on top of the one the caller is
still using. Callbacks therefore need nested reflection first: a
per-level save area and a real-mode stack per level, as a separately
tested stage, before the callback entry and 0303h/0304h.

Regression, all thirteen clients: Divide/Internal 0.

## UPDATE 55 (2026-09-25) — int 31h 0202h/0203h exception handlers; a TSL #GP bug fixed

`_386.ASM`: `$386.SYS` 28336 -> 29472, 0 warnings, 0 severe. This
completes option B (UPDATE 54).

### Where client faults arrive

- vectors 0, 1, 3-7 come through the generic stubs and reach
  `einative` with the vector in `dl`, like an interrupt
- a client #GP goes to `entint0d`; an instruction the monitor does not
  emulate goes to `dobad`, which sets `parm6ec = 2` and continues as
  INT 6 into `entirq`. So #GP arrives as `dl = 6`, `parm6ec = 2`, the
  error code (`[bp+4]`) already dropped
- 8-0Fh reaching `einative` are IRQs: the monitor splits exceptions
  off earlier by error-code position. `dl = 0Dh` here is IRQ5
  (`jentirq2`) and must never be taken for #GP

### Design

- `phooktab` entries gain a KIND byte at `+3`: 0 = interrupt (0205h),
  1 = exception (0203h); `e31hfind` now requires kind 0, `e31xfind`
  kind 1; 0205h writes kind 0
- `einvhook` -> `einvh0`: int 0E7h/0E8h from a stub selector go to
  `einxret` / `einxdef`; everything else to `einxcpt`, which picks out
  client faults (0, 1, 3-7; int 6 with `parm6ec = 2` -> exception 0Dh)
  and delivers a hooked one, else falls through to the interrupt-hook
  path (`einvh1`) unchanged
- delivery (`einxdl`): the DPMI exception frame on the CLIENT's own
  stack -- return address stub:401h, error code (0: the entry path has
  dropped it), ip, cs, flags, sp, ss; words for a 16-bit client,
  dwords for 32-bit -- and the handler entered via the `ncan*` copy
  (UPDATE 50)
- the handler's `retf` lands on stub `401h` = `int 0E7h`; `einxret`
  resumes the client from the frame as the handler left it (ip, cs,
  flags into both `ncanflag` and `ncavflag`, sp, ss)
- defaults (0202h, unhooked): 32 stubs at `404h + N*4` =
  `int 0E8h / N`; `einxdef` restores the client from the frame and
  re-dispatches the fault through `eindisp` as it was (0Dh back as int
  6 with `parm6ec = 2`) -- i.e. exactly the behaviour without DPMI
- the stub table grew: `401h` E7 stub, `404h`-`483h` E8 stubs; stub
  limit `483h`

Two self-review catches before the first build: `parm6ec` is a WORD
(`db 66h,67h` on its compare and store, else a dword compare / an imm32
store under the 32-bit cs), and the IRQ5 trap above.

### The TSL bug: every native-mode #GP corrupted memory

The first test died in the monitor itself: `INT 0d` from the client,
then a page fault at `27C4` (`mov ecx,[ebx]` right after `calcinad`),
`ebx = FA00AC8D`. In `calcinad`'s native branch TSL wrote

	and	bx,0ffffh
	dw	00ffh		; "32-bit data": meant and ebx,00FFFFFFh

relying on MASM's imm16 form `81 E3 FFFF`. MASM chose the sign-extended
`83 E3 FF` (0FFFFh = -1), so the 32-bit cs ran `and ebx,-1` (no-op) and
then `FF 00` = `inc dword ptr [eax]`: every native-mode #GP since 1992
corrupted a dword and page-faulted with the descriptor's access byte
(`FA`) still in the top of ebx. Now spelled out as `81 E3 FFFF 00FF`.
A listing sweep for any `83`-form instruction directly followed by a
`dw` line found no other instance. (This is also what the early
UPDATE 23b trace saw at `27C4`.)

### Measured

- 0202h(0) default = `0073:0404`
- 0203h hooks 0Dh and 0 with a handler that adds 2 to the frame's IP
  and counts; `mov es,0FFF8h` (#GP) and `div cl` with `cl = 0` (#DE)
  are both delivered and skipped: count 2, the client resumes
- a #DE handler that chains to the default: MOS's "Divide by zero
  error", termination, `VER` works afterwards
- regression, all fifteen clients (incl. 0305h, IRQ0): Divide/Internal
  0 (the only Divide in any run is the deliberate one above)

### Limits

- the frame lives on the client's stack, not a host-locked one (differs
  only for stack faults)
- error code always 0 (the entry path drops it before `einative`)
- exceptions that do not reach `einative` (page faults, double faults,
  #GP from emulated instructions) are not delivered
- 0205h on vectors 0-7 still gets faults with an INTERRUPT frame --
  clients should use 0203h for faults, as DPMI intends

## UPDATE 56 (2026-09-25) — callbacks, step 1 (NCA2 space); a cleanup gap found

`_DPMI.ASM`: `$DPMI.SYS` unchanged in size (5117), same four
pre-existing A4057 warnings. `_386.ASM` unchanged (29472).

### Callback design (0303h/0304h), from an inventory of the state

- `dovmcont` finds the nca from `s0ss` (the v-86 ss) + `256/16`, not
  from a fixed variable, and saves the real-mode results by resetting
  `sp` to a fixed spot inside `ncairegs` -- never into the live v-86
  stack
- all reflection state is nca-relative (`ebx` from `addrnca` via the
  task's `tcbncadr`): `ncairegs`, the `ncan*` frame copy, `ncaretad`,
  `ncauregs`/`ncabufer` scratch, and the real-mode stack in the nca's
  first 256 bytes (the size is hard-wired in six places)

So nesting needs no save stack through the central path: while a
callback runs, point `tcbncadr` at a SECOND nca. Every inner
`dovmint`/`dovmcont`/`einative`/`einback` then uses NCA2 and the paused
outer call in NCA1 is untouched; swap back when the callback returns.

Steps:
1. NCA2 space (THIS UPDATE): 1687h reports `NCAPAIR` = 2 x `NCATOTAL`
   (80 paragraphs); GoProtect still passes `cx = NCATOTAL`, so the
   monitor sizes NCA1 exactly as before; NCA2 is the second half of
   the client's host-data block
2. real-mode trap: per callback a real-mode stub
   (`push ax / mov ax,7791h / push idx / int 6fh`); the new int 6fh
   function saves the outer v-86 frame, swaps to NCA2, fills the
   client's structure and enters its protected-mode procedure with
   `ds:(e)si` = real-mode stack, `es:(e)di` = structure
3. return: the procedure's iret lands on a new stub (int 0E9h); the
   monitor swaps back to NCA1 and resumes the real-mode caller at the
   structure's CS:IP with its registers
4. 0303h/0304h, tested with a real-mode routine in DOS memory that
   far-calls the callback, invoked through 0301h -- the nested case

Measured for step 1: `1687h` `si = 0050h`. Regression, all fifteen
clients: clean except as below. Segments moved up by `28h` paragraphs
(`1AD4` -> `1AFC`) and the largest DOS block shrank by the same
(`842B` -> `8403`): NCA2's 640 bytes, as expected.

### Gap found: cleanup only happens at int 21h ah=4Ch

The UPDATE 55 client, run twice in one boot: the first run ends by
chaining a #DE to the default handler, so MOS terminates it through
its divide handler -- NOT through the client's own int 21h ah=4Ch.
`einfun4c` never runs, so the client's exception hook, descriptors and
DPMI memory blocks survive it; the second run's 0202h returned the dead
handler `008B:0256` instead of the default `0073:0404`. The same holds
for every MOS-initiated termination: default exception handler,
Ctrl-C, critical-error abort, int 20h, int 21h ah=00h.

Fix planned: ALSO clean up at the START of a DPMI session. A task runs
one DPMI client at a time, so anything tagged `80h|taskid` (hooks,
descriptors, blocks) when a new client switches in belongs to a dead
predecessor. First confirm that `nmswitch` runs exactly once per
session (int 0D4h ax=1001h), not on every return to native mode, then
call the same release that `e6f8f` does (with the host's own new cs
descriptor built AFTER the sweep).

## UPDATE 57 (2026-09-25) — cleanup also at the start of every DPMI session

`_386.ASM`: `$386.SYS` 29472 -> 29488, 0 warnings, 0 severe.

Closes UPDATE 56's gap: a client ending without int 21h ah=4Ch (MOS's
default exception handling, Ctrl-C, critical-error abort, int 20h)
left its hooks, descriptors and DPMI memory blocks behind.

### Why the session start is a safe place

Measured with a hook on `nmswitch`: it runs once at boot
(`$DPMI.SYS`'s `InitProtect`) and once per client session -- never
per DOS call (3 hits over two client runs making 52 protected-mode DOS
calls; 1 hit booting alone). And `GoProtect` calls `778Eh`
(CODE_SELECTOR) BEFORE `int 0D4h ax=1001h`, so at that moment the new
client has allocated nothing; a task runs one client at a time, so
anything still tagged `80h|taskid` belongs to a dead predecessor.

### Change

`e6f8f`'s release body is now a shared use32 routine, `dpmiclr`
(descriptors via `fcs_ptr`, blocks via `nrelease`, interrupt and
exception hooks; preserves all registers). `e6f8f` calls it, then
returns as before; `e6f8e` calls it first, before building the new
client's code selector. `nmswitch` (use16) was the other candidate but
cannot reach `nrelease` (use32) without a new cross-segment pointer.

### Measured

- the UPDATE 55 exception client twice in one boot: the second run's
  0202h(0) now returns the default `0073:0404` (before: the dead
  first run's handler `008B:0256`)
- a client that allocates 64 KB with 0501h and then dies by #DE (no
  4Ch), three runs: largest free block `CB6000` every run; on UPDATE 55
  the same client leaks 64 KB per run (`CA6000`, `C96000`)
- regression, all fifteen clients: clean (the exception client's
  Divide=2 is its deliberate chained #DE, once per run)

### Limit (pre-existing, now documented)

Resources are tagged per TASK, not per client. A DPMI program that
EXECs another DPMI program in the same task is unsupported: the child's
4Ch has always freed the parent's descriptors, blocks and hooks, and
now the child's START does the same. Supporting it needs per-client
ownership (e.g. the client PSP) instead of the task id.

## UPDATE 58 (2026-09-25) — callbacks step 2: the facts the implementation rests on

No source change; tree is UPDATE 57.

### How an excursion gets home (e6f02, int 6fh 7702h)

`e6f02` pops the int 6fh frame's registers and does `jmp ss:[s0ip]`
with `s0ip` = the v-86 IP just after `dovmcont`'s `int 6fh`. The
driver's real-mode code segment (`mysegadr`) and the monitor's cs have
the same base (`700h`), so the same bytes after that `int 6fh` simply
continue in native mode. That continuation finds its nca from `s0ss`
(the v-86 ss, + `256/16`) and returns to that nca's `ncaretad`.

Consequence for callbacks: the OUTER excursion goes home through its
own `int 6fh 7702h` from its own stack (NCA1's), so its way back does
not depend on any global the callback disturbs. Resuming it after a
callback = iret back into v-86 with the saved outer frame.

### The int 6fh handler frame (from v-86)

- below `p0stack`: the v-86 iret frame `s0ip s0cs s0flags s0sp s0ss
  s0es s0ds s0fs s0gs`, 9 dwords
- pushed by the entry, above that: `ebp ds es ecx ebx` (the caller's
  `bx` at `[bp-16]`, as `e6f8e` reads it); `cgrm7` pops `ebx ecx es ds
  ebp`, sets `sp = s0ip` and does `iretd` back to v-86
- live in the CPU: `eax edx esi edi` (handlers preserve them)

### Step 2 plan (int 6fh 7791h, `e6f91`)

Real-mode stub per callback, in the driver's real-mode code:
`push ax / mov ax,7791h / push <index> / int 6fh`.

1. capture the WHOLE outer v-86 state into the callback's save record:
   the 9 `s0*` dwords, `ebx ecx es ds ebp` from the frame, `eax edx esi
   edi` from the CPU, and the stub's pushed `ax` and index from the
   v-86 stack (then drop them from `s0sp`)
2. fill the client's real-mode call structure (registered at 0303h)
   with the real-mode registers
3. swap the task's nca pointer (`tcbncadr`) to NCA2 = NCA1 + NCATOTAL
4. build NCA2's native frame: `ncanip/ncancs` = the procedure,
   `ncanss/ncansp` = the client's stack from NCA1's `ncan*` minus a
   margin (the client is blocked in its outer call, its stack below is
   free), `ncanflag` with IF clear; `ds:(e)si` = a data selector for
   the real-mode `SS:SP`, `es:(e)di` = the structure; on the procedure's
   stack an iret frame pointing at a new return stub (int 0E9h)
5. `ebx` = NCA2 and leave through `einback` -- it builds `p0stack` from
   the nca and irets into the procedure

Step 3 (int 0E9h): copy the structure back into the saved v-86 state
(including CS:IP and SS:SP as DPMI specifies), swap `tcbncadr` back to
NCA1, rebuild the `s0*` frame and the pushed registers, and leave via
`cgrm7`'s pops + `iretd` into v-86.

Open question to settle first in step 2: NCA2 must be initialised
(`ncabufsz` and the fields `nmswitch` sets for NCA1) before its first
use -- do it once at the session switch, next to where `nmswitch` sets
up NCA1.

## UPDATE 59 (2026-09-25) — callbacks step 2a: 0303h/0304h bookkeeping

`_386.ASM`: `$386.SYS` 29488 -> 30688, 0 warnings, 0 severe. The
callback does NOT fire yet: its stub traps into int 6fh 7791h, which is
step 2b.

### Where NCA2 gets initialised

`nmswitch` writes only two things into NCA1: `tcbncadr` and
`ncabufsz`; every other nca field is written right before each use. So
NCA2 needs only `ncabufsz`. NOT in `nmswitch`: that also serves
`$DPMI.SYS`'s own `InitProtect` at boot, whose block has no second
half. Instead in 0303h, which only a DPMI client (with the doubled
block, UPDATE 56) reaches: NCA2 = NCA1 + 256 + `ncalen` + `ncabufsz`.

### What exists now

- `dcbtab`: `DCBN` (8) records of `DCBSZ` (96) bytes -- +0 in use, +1
  task, +4 procedure offset, +8 procedure selector, +10 structure
  selector, +12 structure offset, +16.. room for the outer v-86 state
  step 2b saves
- `dcbstub`: 8 real-mode stubs in this driver's real-mode code,
  `push ax / mov ax,7791h / push idx / int 6fh` (`50 B8 91 77 6A nn CD
  6F`), reached from real mode as `mysegadr:offset`
- 0303h: `ds:(e)si` = procedure (must be a present dpl-3 code
  descriptor), `es:(e)di` = real-mode call structure; returns `CX:DX` =
  the stub's real-mode address; initialises NCA2's `ncabufsz`
- 0304h: frees by real-mode address, own task only (`e31cfind`)
- callbacks are released with the hooks: at 4Ch (`e31hclr`), at
  Unregister and at session start (`dpmiclr`)

### A trap class the sweep had missed

`mov di,offset dcbstub` assembled `BF iw`; under the 32-bit cs `BF`
takes an imm32 and swallows two bytes. Caught in self-review and
hand-encoded (`BF imm32`). The standing listing sweep only looked at
accumulator-immediate opcodes; it now also covers `mov r,imm16`
(`B8`-`BF`) without a `66h` prefix. The widened sweep over the whole
32-bit-executed region -- older code included -- is clean.

### Measured (twice in one boot)

0303h -> CF clear, real-mode address `0070:3CCC`; the stub read through
a 0002h selector is `50 B8 91 77 6A 00 CD 6F`; 0304h -> CF clear; again
-> CF set. The second run reused record 0, so the first run's callback
was released at exit. Regression, all fifteen clients: clean.

Next: step 2b, `e6f91` (int 6fh 7791h) per UPDATE 58.
