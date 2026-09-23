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
