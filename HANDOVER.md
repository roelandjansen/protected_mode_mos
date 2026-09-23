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
