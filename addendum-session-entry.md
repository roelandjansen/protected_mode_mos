## ROOT CAUSE OF THE NO-PROMPT STALL: the V86 task loops forever on a `HLT` at `0000:0008`, inside the IVT

The crash is gone and stays gone. What replaced it is not a crash, a
hang, or a halt: it is a closed, self-sustaining `#GP` loop in which
the V86 task executes interrupt-vector-table bytes as if they were
code. The machine is healthy — protected mode active, paging on,
exception delivery correct, the I/O-trap dispatcher doing exactly what
it was designed to do — and it will spin like this indefinitely.

### Method (reproducible, no GUI needed)

Booted `run.sh --testconfig`'s exact floppy image under a
debug-instrumented DOSBox Staging 0.82.2 (`--buildtype=debug
-Ddebug=true`), headless via Xvfb with `output=texture` +
`texture_renderer=software`, then attached `gdb` to the running
emulator and read guest state directly:

- screen text from `vga.mem.linear` (offset 0, **not** `+0x18000` —
  in Staging's `M_TEXT` the buffer is at linear 0)
- guest CPU from `cpu_regs`, `Segs`, `cpu.pmode`, `cpu.cr0`
- guest RAM from `(char*)MemBase + <physical address>`

This reproduces the reported screen byte-for-byte. It is now possible
to take clean measurements of this failure without a display and
without racing a crash handler.

### The screen decodes to one missing character

Line 10 of the text buffer:

```
1[<>{}()]2[<>{}()]3[<><>...<>{}()]4[<>{}()]5[<>{}()][<Loading $386.SYS  version 5.01  (921119)
```

Against the marker definitions in `MOSDDINT.ASM`, a *complete* driver
init is `[<>{}()]` — `[` mosddint entry, `<` before `ddinit0`, `>`
after it returns, `{}` around `adj_smp_alloc`, `()` the two
`calc_size` calls, `]` the return after all pops.

Devices 1–5 each show the full `[<>{}()]`. Then `[<` for `$386.SYS`,
the driver's own banner, and **no `>`**.

`ddinit0` for `$386.SYS` never returns. Everything downstream is not
failing — it is never reached: no `}`, no `()`, no `]`, no return to
the CONFIG.SYS driver loop, no `$DPMI.SYS`, no shell, no prompt.

Row 24 shows `ZQA1 ZQB2 ZQC3 ZQD4 ZQE5 ZQF6 ZQG7` — **all seven
bisection markers fire, including G**, which sits immediately after
paging is enabled. `build_page` runs to completion. The failure is
strictly after it.

### Guest CPU state at the stall

```
CR0        = 0x80000011      PG + ET + PE
cpu.pmode  = true
FLAGS      = 0x3082          IOPL=3, IF clear, VM clear
CS         = 0x18  base 0x700
SS, ES     = 0x20  base 0x700 ;  DS = 0x38 base 0
EIP samples: 2769, 2759, 2774, 2785, 28d4, 34eb, 27AC
```

EIP moves between samples, so this is **executing, not halted**. The
emulator log is clean: seven benign `test_extmem` probe writes at
`1000000h` and nothing else. No `#PF` flood, no `#GP` cascade, no
segfault.

The code at `CS` base `0x700` is `$386.SYS`'s own 32-bit segment
(segment `0x0070`). Disassembled, the EIP samples are unambiguous:

| EIP | instruction | meaning |
| --- | --- | --- |
| `0x2000` | gate entries, access byte `EE`, sel `0x18` | the IDT itself |
| `0x2650`–`0x26bc` | `66 e8 xx 00` → `callw 0x26c0` | the 28 exception stubs |
| `0x26c0` | `popw %ss:0xd9f` | `eicommon` — recovers vector from return addr |
| `0x2755` | `callw 0x34eb` | handler prologue |
| `0x2759` | `mov $0xd,%cl` | **vector 0x0D — `#GP`** |
| `0x2774` | `mov (%ebx),%ecx` | fetch the faulting instruction |
| `0x2785` | `mov %ss:0x2776(%bx),%bl` | opcode table lookup |
| `0x278b` | `jmpw *%ss:0x27e2(%bx)` | dispatch to opcode emulator |
| `0x28d0` | `mov $0xf8c,%sp` ; `iret` | resume the V86 task from the frame at `0xf8c` |

This is the by-design V86 I/O-trap path, working correctly. It is not
the bug; it is the bug's engine.

### The loop, measured

The V86 resume frame at `SS:0xf8c` (`iret` pops IP/CS/FLAGS/ESP/SS/
ES/DS/FS/GS from there) is **constant across every sample**, while the
native EIP keeps moving:

```
v86 CS:IP = 0000:0008   FLAGS = 0x00023006  (VM=1, IOPL=3)
```

Linear `0x0008` is inside the IVT — it is the storage for vector 2.
The IVT dump gives `IVT[2] = 0x007000F4`, so the bytes at `0x0008`
are `F4 00 70 00`. The first byte is `0xF4` — **`HLT`**.

The cycle is therefore:

1. V86 task resumes at `0000:0008`
2. executes `HLT`, privileged, always `#GP` in V86 mode
3. the `#GP` handler runs (the `0x2755`/`0x2785`/`0x27AC` activity)
4. it cannot advance past the instruction, `iret`s back to `0000:0008`
5. repeat, forever

`vmstart` never runs, which is why its message never prints; the
`>` marker never prints for the same reason.

### `$DPMI.SYS` is never attempted — confirmed, not inferred

The `ldloop` iteration counter at `0040:00F4` (incremented once per
generic driver-load pass by `MOSINIT2.ASM`) reads **`0x00`**.
`MEMDEV=` is handled on its own early path, but `DEVICE=$DPMI.SYS`
goes through `ldloop`, and that loop has not run once.

So DPMI is not loading-and-failing. It is never reached. Same for the
shell. There is nothing to debug on either of them yet.

### Measured vs. inferred — keep these apart

**Measured, mechanical, not to be re-litigated:**

- all markers A–G fire; `build_page` completes; paging is enabled
- protected mode + paging are active at the stall (`CR0=0x80000011`)
- the guest is executing, not halted (EIP moves)
- the V86 resume frame is `0000:0008`, `VM=1`, and is stable
- the byte at linear `0x0008` is `0xF4` (`HLT`)
- `ldloop` counter is 0
- the emulator log is clean — no host-side fault of any kind

**Inferred, NOT established:**

- that the V86 task was *entered* at `0000:0008` rather than drifting
  there later. It fits (`vmstart`'s message never appeared, so the
  task plausibly never reached `vmstart` at all), but only the steady
  state was captured, never the transition. Entering correctly and
  being redirected afterwards is not excluded.

**Suggestive, one number only, do not patch on this yet:**

`0008` is the *address* of `IVT[2]`, not its *contents*. A reflection
path that computed `vector*4 = 8` for vector 2 and then used that
address as the target — instead of loading the far pointer stored
there — would produce exactly this. Vector 2 is NMI, and `build_page`
specially manipulates the NMI IDT entry (`idt+16`) around the memory
tests, saving it to `oldnmi` and pointing it at `newnmi`. `IVT[2]`
reads `0070:00F4`, which points into `$386.SYS`'s own segment (base
`0x700`), so MOS did install its own NMI handler there. Coherent
chain, single data point. Same class of plausible-but-unconfirmed
reasoning that the ascending-heap-byte pattern and the `5272h` decode
both turned out to be.

### Next step — one character splits the remaining possibilities

Add one marker at `vmstart`'s very first instruction, in the same
style as the existing A–G harness.

- marker never appears ⇒ the task never entered `vmstart`; the bug is
  in the V86 entry setup (TSS2 / initial frame)
- marker appears ⇒ entry was correct and something redirects the task
  afterwards — a different bug and a different fix

One rebuild, one character, and the inference above becomes a fact or
is discarded.

### Second, now-cheap item

This boot is stable and non-crashing, so the addendum's long-standing
step 1 — establishing what the **truly unpatched** `$386.SYS` does —
is finally cheap and safe to run. The current state is a clean
"before" for that comparison, which is what settles whether the
`nmswitch` guard ever helped or was solving a misdiagnosis.

Note the tree as measured still **has** the guard (`_386.ASM`
~5189–5191, `jnz cirqhndl` / `jmp nmswitch`); this is the
pre-TEST-v2 state, not the guard-removed variant.

Status: the no-prompt symptom is fully explained mechanically — V86
task spinning on `HLT` at `0000:0008` inside the IVT, `#GP` handler
resuming it unchanged. `$386.SYS`'s `ddinit0` never returns, so DPMI
and the shell are never reached. Remaining unknown: whether the task
entered at that address or arrived there. One marker at `vmstart`
answers it.


## RESOLVED: `vmstart` IS entered — the `sti` is fatal. V86 entry is correct; the `0000:0008` loop is a consequence, not the cause

The one-character test proposed at the end of the previous entry was
built, run, and answered. Result: **marker `V` appears, marker `W`
does not.**

### What was instrumented

Two markers at `vmstart`, written straight to video memory at
`b800:0e60` and `b800:0e64` (row 23):

- `V` at `vmstart`'s very first instruction, **before** the `sti`
- `W` immediately **after** the `sti`

Deliberately not `int 10h`: `vmstart` runs in v-86 mode, where a BIOS
call is trapped and reflected by the monitor, so a broken reflection
would suppress the marker even if `vmstart` had been entered — a
false negative on precisely the question being asked. A plain memory
write traps nothing. Also deliberately no `push`/`pop`, so the
markers do not depend on `SS:SP` being valid at v-86 entry; `ax` and
`es` are both reloaded by the code that follows.

Rebuilt `$386.SYS` alone (not the whole kernel) with the original
MASM/LINK under DOSBox, via the `.ASM.SYS` recipe from
`MAKEUTIL.MAK`: `public` / `masm` / `link` / `exe2bin`. Output grew
21211 → 21243 bytes, consistent with the two marker blocks.

### The result is real, not an assembly artifact

Verified in the assembled binary that both blocks exist with the
`sti` between them:

```
0f 22 c0              mov   cr0,eax
ea c0 4d 18 00        jmp   far 0018:4dc0      ; -> build_page
b8 00 b8 / 8e c0      mov   ax,0b800h / mov es,ax
26 c6 06 60 0e 56     mov   byte ptr es:[0e60],'V'
26 c6 06 61 0e 07     mov   byte ptr es:[0e61],07h
fb                    sti                       ; <-- dies here
b8 00 b8 / 8e c0      mov   ax,0b800h / mov es,ax
26 c6 06 64 0e 57     mov   byte ptr es:[0e64],'W'
```

`W`'s code is present and never executes. Screen row 23 reads `V`
and nothing else. (Note the 386 `sti` interrupt-recognition delay:
the interrupt is taken after the following instruction, i.e. between
`mov ax,0b800h` and the `W` store. The conclusion is the same either
way.)

### What this closes

- **The V86 task entry is CORRECT.** TSS2, the initial frame, the
  entry EIP — all fine. The entire TSS-clobber / bad-entry-EIP line
  of investigation (§3960, §4027, §4090, and the "TSS2 eip is never a
  valid 0x0887" entry) is closed, as is the previous entry's own
  leading inference that `vmstart` was never reached. That inference
  was explicitly flagged as unestablished; the measurement went
  against it. Working as intended.
- **The `0000:0008` `HLT` loop is a CONSEQUENCE, not the cause.** The
  task enters `vmstart` properly, enables interrupts, takes the very
  first interrupt, and *that* is what leaves it spinning at
  `0000:0008`. Do not look for a bad V86 entry any more.
- This confirms the §4222 mechanism in outline: the first enabled
  interrupt at the `sti` takes the task down.

### One wrinkle — do NOT treat the vector as established

§4222 read this as the guard forcing int 8 native and thereby losing
`VM=1`. But the frame measured in the previous entry still had
**`VM=1` set** (`FLAGS=0x00023006`). The task is still marked v-86
where it spins. So "the guard forces it native" is not obviously the
whole story, and the identity of the fatal vector (timer int 8? NMI
int 2? something else) is **not** established. Treat §4222 and §4289
as still in disagreement on this point.

### Chosen next step: run the TEST v2 comparison, with the markers in

Two candidates were on the table:

- (a) add a marker in `contirq` that writes `ss:[iveccode]` before
  dispatch, identifying the fatal vector directly — the measurement
  that would actually *explain* it and settle §4222 vs §4289
- (b) remove the `nmswitch` guard (`_386.ASM` ~5189–5191, back to an
  unconditional `jmp short cirqhndl`), rebuild, boot — a direct test
  of the leading fix candidate

**(b) is being run first.** It is one edit and one rebuild, it tests
the fix candidate directly, and a positive result narrows (a)
considerably. The V/W markers are now in the tree, so the outcome is
unambiguous either way:

- `V` + `W` + "486 Protected mode and paging are now active."
  ⇒ the earlier TEST v2 result reproduces; the guard is the problem
- `V` only, again ⇒ the guard is NOT what kills the `sti`, the
  earlier TEST v2 result needs re-examining, and (a) becomes the
  required next measurement

Status: `vmstart` entry confirmed correct; the `sti` is the kill
point; the `0000:0008` `HLT` loop is downstream of the first
interrupt, not of a bad entry. Fatal vector still unidentified.
Running the guard-removal test next, with V/W in place.


## GUARD REMOVED = PROMPT. Original stack boots clean, so neither "fix" was fixing PC-MOS. DPMI isolated: it fails in `AllocateExtend` and never installs

Three things were settled this session: the guard-removal test (b), the
long-deferred original-stack comparison, and the origin of the DPMI
screen garbage. All by measurement.

### (b) Removing the `nmswitch` guard boots to a live prompt

`contirq` reverted to unconditional fall-through to `cirqhndl` (the
original real-mode-IVT reflection). Rebuilt `$386.SYS` alone.

```
[A:\]VER

PC-MOS Version  5.02   (X0-X0X0X0X0)

[A:\]
```

Typed with real keystrokes (`xdotool` into the emulator window), real
answer back. Not a frozen screen. Protected mode + paging active,
`$DPMI.SYS` reached, `AUTOEXEC.BAT` ran, shell live.

`ddinit0` returns, so `>` appears, `{}()]` complete, `ldloop` runs,
and the whole chain from the previous two entries unblocks with one
edit.

Size arithmetic worth recording: original `$386.SYS` 21211 bytes with
the guard; 21243 with the V/W markers added; 21211 again with the
guard removed. **The guard block was exactly 32 bytes, the same as
the markers.** So what booted is, in the `contirq` path, the original
shipped behaviour plus diagnostics.

### The original stack boots perfectly — step 1, finally run

Extracted the shipped binaries from `IMAGES/PCMOS386-9-user.img`
(`$$MOS.SYS`, `$$SHELL.OLD` as the shell, `$386.SYS`, `COMMAND.OLD`)
and booted them with `MEMDEV=$386.SYS`:

```
Loading $386.SYS  version 5.01.01  (940421)
486 Protected mode and paging are now active.
  640K RAM found in first megabyte;
16000K total RAM found;
  640K allocated to first megabyte.
[A:\]VER
PC-MOS Version  5.01   (09-50003953)
```

Clean screen, live prompt, **no crash, no stall, no garbling**.

**Therefore the crash and the stall were never properties of PC-MOS.**
Both were introduced by the rebuild. §3562's `ivtable[6]==0` root
cause and §3700's "THE FIX" were diagnosing a problem the shipped OS
does not have. Re-read §4289 in that light too.

**Caveat that must not be lost:** the shipped binary is version
**5.01.01 (940421)**; our source tree builds **5.01 (921119)**. The
shipped binary is a *later revision than the source we hold*, and it
is the 9-user variant. This proves "a later shipped build is fine",
NOT "our source is fine". If a genuine 921119 `$386.SYS` exists
anywhere, getting it would close this gap properly.

### Cross-tests: neither component is broken against the original counterpart

| | kernel | `$386.SYS` | result |
| --- | --- | --- | --- |
| C | ours (MOSDDINT fix) | original | boots to prompt, clean |
| D | original | ours (guard removed + markers) | boots to prompt, clean |

Test D is the one that matters: row 23 reads **`V W`** — *both*
markers. vmstart is entered AND survives the `sti`. Row 24 has all of
`ZQA1`–`ZQG7`. This is the first direct confirmation that guard
removal cures the `sti` kill, rather than an inference from the
absence of a stall.

Also visible in C: second-pass device markers read `[<>)]` against
first-pass `[<>{}()]`, consistent with §1549 (pass 2 skips the
chain-walk by design).

### The DPMI garbage: isolated, explained, and fixed

**Isolation first.** The garbage reproduces with the **original**
`$386.SYS` and the original kernel:

| config | result |
| --- | --- |
| original `$386.SYS`, no DPMI | clean |
| ours `$386.SYS`, no DPMI | clean |
| original `$386.SYS` + our `$DPMI.SYS` | **garbage** |
| ours `$386.SYS` + our `$DPMI.SYS` | **garbage** |

So the garbage is entirely `$DPMI.SYS`'s own doing — independent of
the guard removal, the MOSDDINT fix, and `$386.SYS`. Note also that
**no shipped `$DPMI.SYS` binary exists anywhere in the distribution
media** (checked every image, plus the `MOSFILES.EXE` and
`AUXFILES.EXE` archives — `AUXFILES` has `$386.SYS`, nothing has
DPMI). So there is no reference binary to compare against, and it is
possible this source has never produced a working driver in this
configuration. Hypothesis, not conclusion.

**Two clean negatives, recorded so they are not re-investigated:**

- The sign-on prints are NOT the source. Disabled both the
  `DevLoadMsg` and `Copyright` `int 21h` ah=9 calls in
  `InstallDriver`; garbage unchanged, in the same place.
- `WriteLog` is NOT the source. It only increments a counter byte in
  `cs:`; no output of any kind.

(`DevLoadMsg` is still independently broken: it contains a literal
`'$'` inside the text `'$DPMI.SYS'`, and ah=9 terminates on `'$'`, so
it could only ever have printed `>>> DEVICE=`. Project-added
instrumentation, our bug, worth deleting.)

**The actual source** is `ErrorHandler`'s final print:

```
ErrorHandler:
        push  dx
        mov   al,10
        call  WriteLog
        pop   dx
        call  FreeExtend          ; <-- between the pop and the push
        push  dx
        mov   dx,offset MsgNotIns
        mov   ah,9
        int   21h
        pop   dx
        mov   ah,9                ; display error message
        int   21h                 ; <-- prints whatever dx happens to be
```

The last `int 21h` prints from **DX as passed in by the caller**, with
`FreeExtend` called in between. DX is not guaranteed to be a valid
message pointer, so ah=9 runs from a bogus address and dumps driver
memory until it hits a `'$'` byte. That is exactly the observed
output: the driver's own image, with `HostInfo` (image offset 0181h)
and the `Copyright` text (0E30h) appearing amid raw code bytes.

With both `ErrorHandler` prints disabled the screen is **completely
clean**, and `$DPMI.SYS` now completes `[<>{}()]` and returns from
`ddinit0` properly.

### The garbage was never cosmetic — DPMI does not install

Reaching `ErrorHandler` at all means init FAILED. Confirmed
independently at the prompt:

```
[A:\]DUMPLOG
No DPMI host found (int 2Fh 1687h failed)
```

So every earlier boot that "reached a prompt with DPMI loading" was
in fact reaching a prompt with DPMI **failing**, and the garbage was
its failure report failing to print itself.

### Failure point pinned: `AllocateExtend`

`DUMPLOG` cannot diagnose this by construction — it locates
`Counters` via int 2Fh 1687h, i.e. via the DPMI host, and when init
fails there is no host. The counters are also unreadable from memory:
`Counters` lives at image offset 00A6h in CODE16, and **CODE16 is
never resident in conventional memory at any sample** (only INIT16 is
found, consistently at implied base 3FB0h).

Solution: made `WriteLog` also write a visible per-step marker
straight to video memory (`b800:0e60 + step*2`, row 23) — no host, no
`int 21h`, no reflection, the same technique that worked for vmstart.
Steps print as `'1'`..`'9'` and `':'` for 10.

Row 23 (the `[A:\]` prompt overwrites columns 0–4):

```
col:  0 1 2 3 4 5 6 7 8 9 10
      [ A : \ ] 5 6       :
```

Steps 5 and 6 fired. Steps 7, 8, 9 did not. Step 10 (ErrorHandler)
fired. So:

```
        call    CheckFor386SYS
        mov     al,6
        call    WriteLog        ; <-- marker 6 fired
        jc      ErrorHandler
;
; Allocate extended memory for Protected Mode code
;
        call    AllocateExtend  ; <-- dies here, marker 7 never fires
```

**`$DPMI.SYS` fails in `AllocateExtend`.** Everything before it
passes: `CheckMOS`, `CheckDPMI`, `CheckMicroProcessor` and
`CheckFor386SYS` all succeed, so the driver correctly detects MOS,
the 386, and `$386.SYS`'s memory manager. It is the extended-memory
allocation request to that manager that is rejected.

### Techniques worth keeping

- **Direct video-memory writes beat every other marker** in this
  codebase: no `int 21h`, no BIOS call, no V86 reflection, no stack
  dependency (the vmstart markers deliberately use no push/pop). They
  work when the thing being diagnosed is exactly the machinery a
  normal marker would rely on.
- **`DUMPLOG` is unusable for init-failure diagnosis** — it needs the
  host it is trying to diagnose. Do not reach for it again on this.
- The whole session ran **headless**: DOSBox Staging 0.82.2 debug
  build under Xvfb with `output=texture` + `texture_renderer=software`,
  screen read from `vga.mem.linear` (offset 0), guest RAM via
  `(char*)MemBase + <physical>`, keystrokes via `xdotool`. Fast,
  scriptable, no display needed.

### Open

1. What does `AllocateExtend` ask `$386.SYS` for, and what error comes
   back? The marker technique can report the returned code directly.
2. CODE16 is never resident while INIT16 sits at implied base 3FB0h —
   which falls inside `$386.SYS`'s region. Could not distinguish
   "overlap/corruption" from "`$386.SYS`'s low-memory copy is a
   relocated duplicate". Since `AllocateExtend` is precisely about
   memory, this may or may not be related. Needs its own measurement.
3. The `MOSDDINT.ASM` `nxtdrvr` fix is still in and still unvalidated;
   its own comment says so. It deserves the same isolation treatment
   the guard just got.
4. All diagnostics (A–G, V/W, the `MOSDDINT`/`MOSINIT2` markers, the
   DPMI step markers, the disabled prints) must come out before any
   of this is committed.

Status: guard removal is the fix for the stall and is confirmed by
V+W; the original stack proves neither "fix" was fixing PC-MOS; the
DPMI screen garbage is explained and gone; DPMI itself does not
install and fails specifically in `AllocateExtend`, which is the next
thing to open up.


## CORRECTIONS + ROOT CAUSE OF THE GARBAGE FOUND (MASM `OFFSET` is segment-relative, not group-relative). DPMI's real blocker is `CheckFor386SYS`, and a previous session wired it to refuse on purpose

Two claims in the section above are **wrong** and are corrected here.
Both were stated with more confidence than the evidence supported.

### Correction 1 — the failing step is `CheckFor386SYS`, not `AllocateExtend`

`WriteLog` is called *after* each check returns but *before* the
`jc ErrorHandler`:

```
        call    CheckFor386SYS
        pushf
        mov     al,6
        call    WriteLog        ; fires whether or not CF is set
        popf
        jc      ErrorHandler
```

So "marker 6 fired, marker 7 did not" means step 6 **returned**, not
that it succeeded. The last marker present names the step that
FAILED, not the last one that passed. `AllocateExtend` is never
reached and is not implicated.

### Correction 2 — `FreeExtend` does NOT clobber DX

It does `push dx` / `pop dx`, and the `SkipFree` path does not touch
DX at all. DX is preserved on both paths. The earlier "DX exposed to
FreeExtend" reading of `ErrorHandler` was wrong; the caller's error
pointer was never the problem.

### Actual root cause of the screen garbage

**`OFFSET var` in MASM yields the offset within var's SEGMENT, not
within its GROUP, and `assume cs:ddt` does not change that.**

Every message lives in INIT16, whose link base is `0E30h`, while `ds`
is set to `cs` = the DDT **group** base. So `ds:dx` landed `0E30h`
too low and ah=9 ran forward dumping memory until it hit a `'$'`.

From `_DPMI.LST`:

```
NOMEM      L BYTE  01A7  INIT16      -> mov dx,offset NoMem = BA 01A7
MSGNOTINS  L BYTE  0080  INIT16      -> mov dx,offset MsgNotIns = BA 0080
HOSTINFO   L BYTE  0031  CODE32      -> image offset 0181h
```

`MsgNotIns` printing from image offset `80h` runs straight through
CODE32 and over `HostInfo` at `0181h` — which is exactly why
`HostInfo` kept appearing in the garbage. Prediction and observation
match.

**The `R` (relocatable) flag in the listing is a red herring.** LINK
does NOT fix these up to group-relative. Verified in the built
binaries:

| | before | after `offset ddt:` |
| --- | --- | --- |
| `NoMem` | `BA A7 01` | `BA D7 0F` |
| `MsgNotIns` | `BA 80 00` | `BA B0 0E` |

**Fix applied:** qualified every message-pointer load in INIT16 as
`offset ddt:<msg>`. Screen garbage is **gone**, and the driver now
prints real messages. `lea`-based arithmetic (e.g. `AllocateExtend`'s
`EndProtect - BeginProtect` size computation) is unaffected, since the
segment/group bias cancels in a difference.

### What the driver actually says now

```
Not Installed.
386 Memory Manager required.
```

That is `No386Sys`, reached via `NoMemdev` — i.e. **`scbmmfg` is not
`'Y'`**: `$386.SYS`'s memory-manager flag is not set in the SCB, even
though "486 Protected mode and paging are now active." has printed.

Reproduced with the **original** `$386.SYS` (5.01.01/940421) as well
as ours, so this is **not** a regression from the guard removal.

### The bigger blocker: `CheckFor386SYS` refuses by design

A previous session rewrote `CheckFor386SYS` so that it **never
succeeds**:

- `scbmmfg != 'Y'` -> `NoMemdev` -> "386 Memory Manager required" (what
  we hit now)
- `scbmmfg == 'Y'` -> falls through to an explicit `NotFin` refusal

Its own comment gives the reason: the old gate on `scbmmfea` bit 40h
("io protection enable") was never set by this `$386.SYS` build, so
DPMI install failed safely *by accident* — and that accident was the
only thing preventing a worse bug. `InitProtect` depends on
`SegToSel`, which has no working implementation: it calls int 6Fh
with `SEGMENT_SELECTOR=7786h`, which nothing implements, falls
through to generic native-mode interrupt reflection, and executes
whatever sits at the never-hooked real-mode int 6Fh vector. That was
confirmed to crash DOSBox outright, not just the guest.

**So "a working `$DPMI.SYS`" needs two things, in order:**

1. `scbmmfg` to actually be `'Y'` — find out why `$386.SYS` does not
   set it (or why the driver reads the wrong SCB: check `lds si,
   [scbadr]` and the `scbmmfg` offset before assuming the flag is
   genuinely unset).
2. **`SegToSel` genuinely implemented** — build a real GDT descriptor
   for the segment. Until then the explicit refusal must stay, because
   removing it walks straight into the int 6Fh crash.

Item 2 is the real work. Item 1 may turn out to be a red herring if
the SCB read is simply wrong.

Status: screen garbage root-caused and FIXED (`offset ddt:`), which
also made the driver report its own errors. Two earlier claims
corrected. DPMI does not install because `CheckFor386SYS` refuses —
currently on the `scbmmfg != 'Y'` path, and by explicit design on the
other path pending a real `SegToSel`.
