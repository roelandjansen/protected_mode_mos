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


## CONSOLIDATION — ROOT CAUSE FOUND: the V86 monitor emulates only I/O instructions. This supersedes most of what precedes it, including three of my own conclusions

One defect explains the whole investigation. Several earlier entries
in this addendum — and several conclusions in the sections above —
are wrong and are retracted here.

### The finding

`uioplb` (`db 00110000b` = IOPL 3) is OR'd into `t2eflags+1` during
init (`or byte ptr [t2eflags+1],al`). That is what fills in the
`iopl=??` the TSS2 comment was unsure about. Set it to 0, rebuild,
boot:

```
row 23:  V              <- vmstart entered, NO 'W'
CS=0018 EIP=299D VM=0 vec=06 v86frame=76CD:0000A1E1
CS=76CD EIP=A1E1 VM=1 vec=06
```

`vec=06` is the `mov cl,6` "unsupported opcode -> reflect int 6" path.
**The monitor treats `STI` as an invalid opcode.**

The V86 monitor in this `$386.SYS` emulates **only I/O instructions** —
exactly what the opcode dispatch table at `2776h`/`27E2h` contains
(IN/OUT, DMA port translation, as disassembled in the first entry). It
has no emulation for the IOPL-sensitive instructions: `CLI`, `STI`,
`PUSHF`, `POPF`, `INT n`, `IRET`.

IOPL=3 is therefore a deliberate and self-consistent choice: at IOPL=3
none of those instructions trap, so the missing emulation never
matters. I/O still traps through the TSS permission bitmap
(`t2iopbm`), which is all the monitor can actually service.

### Why DPMI cannot work in this build

- `valloc` runs **in virtual mode by design** — the `dovmrh`/`rhentry`
  dispatch, commented in the source as "call allocation routine in
  virtual mode" — and re-enters native mode via `int 6fh` AX=7705h.
  That requires `INT n` to trap, i.e. **IOPL < 3**.
- The monitor cannot survive IOPL < 3, because `vmstart`'s first `sti`
  traps and is reflected as `#UD`.

Both cannot hold simultaneously. **No amount of work inside
`_DPMI.ASM` can make DPMI install on this `$386.SYS`.** Supporting
measurement: `IVT[6Fh]` = `F000:1060`, the untouched BIOS default stub,
identical to the unused `IVT[6Eh]`; `$386.SYS` never hooks it.

### RETRACTIONS — do not act on these any more

**1. There was never an `ivtable[6]==0` reflection bug (§3562), and the
`nmswitch` guard (§3700, "THE FIX") never fixed anything.**
Removing the guard restored the boot only because at IOPL=3 the `sti`
never traps in the first place. The guard was treating a symptom of
the incomplete monitor. This finally answers the question the fix plan
has carried since step 1: the guard did not help, and the earlier
entry above that credits guard removal as "the fix for the stall" is
overstated — it is a workaround that avoids the defect, not a fix.

**2. My own "V86 task loops on `HLT` at `0000:0008`" entry described a
symptom, not a cause.** The mechanism was right; the framing was
wrong. It is downstream of the same monitor gap.

**3. My own `AllocateExtend` conclusion was wrong** (already corrected
above, repeated here because it propagated): `WriteLog` fires *after*
a check returns but *before* its `jc`, so the last marker present
names the step that FAILED. The failing step was `CheckFor386SYS`.

**4. My own "`ErrorHandler`'s DX is clobbered by `FreeExtend`" reading
was wrong.** `FreeExtend` preserves DX on both paths. The garbage was
the MASM group/segment `OFFSET` bug.

The pattern across this whole investigation: **five confident
root-cause claims, four of them wrong** — `ivtable[6]==0`, the
mis-encoded `call eicommon`, `AllocateExtend`, the clobbered DX, and
finally this one. Every wrong turn came from plausible source reading
or a mid-cascade register dump. Only the ones backed by a mechanical
before/after measurement survived.

### What DOES survive as real fixes

These are independent of the monitor defect and all verified:

- **`OFFSET ddt:`** on message pointers in INIT16. MASM's `OFFSET`
  is segment-relative, not group-relative; `assume cs:ddt` does not
  change it, and LINK does not fix it up despite the `R` flag.
  Verified in emitted bytes: `BA A7 01` -> `BA D7 0F`.
- **`stc` restored** on `CheckMOS`'s `NotMos` path (was reporting
  success on failure, leaving `scbadr` at 0:0).
- **MOS 5.x version detection.** The two-call `int 21h` ah=30h
  equality test rejects real MOS: measured `0005`/`0105` on the
  original 5.01 kernel and `0005`/`0205` on ours.
- **`memman` far pointer**, and with it a MASM trap worth remembering:
  **E-register forms in a USE16 segment assemble 16-bit, silently** —
  no `66h` prefix, no warning. `mov eax,[si+scbmmsub]` became
  `mov ax,...`, loading only the offset half. Use word pairs in CODE16
  and INIT16. This class of bug may exist elsewhere in the driver and
  has never been audited; a naive grep cannot scope it, because the
  listing shows per-segment offsets and cannot separate USE16 hits
  from legitimate prefix-free USE32 ones.
- **int 6Fh DPMI block** in `$386.SYS`: second dispatch table,
  `SEGMENT_SELECTOR` (7786h) and `SELECTOR_SEGMENT` (7787h) on top of
  the existing `makegdte` allocator, and `e6funimp` so unimplemented
  functions fail cleanly rather than being reflected to the unhooked
  real-mode vector.

Also established and worth keeping: `valloc` **is** AH=1 in `rhtable`;
the memman ABI is AH=function, BX=handle, CX=count, ES=target;
`$386.SYS` publishes `rhentry` via `parmrhad`; `AllocateExtend`'s page
arithmetic is correct (both labels in CODE32, CX=1).

### Two ways forward

**(a) Implement the missing emulation.** Add `CLI`/`STI`/`PUSHF`/
`POPF`/`INT`/`IRET` to the monitor's opcode dispatcher with a virtual
interrupt flag. This is the correct fix and what a real V86 monitor
does. Substantial, and it makes every one of those instructions a
trap.

**(b) Keep IOPL=3 and give int 6Fh a path that still traps.** Hook
`IVT[6Fh]` with a small real-mode stub in `$386.SYS` that reaches
native mode by a mechanism which does trap at IOPL=3 — the I/O
permission bitmap being the obvious lever — then dispatch into the
existing `i6f_tbl`. Much smaller, contained, and it leaves the working
boot intact.

**(b) first.** It is testable in one rebuild and does not disturb a
system that currently boots to a live prompt.

### Tree state

`uioplb` reverted to `00110000b` and rebuilt; boots again (`V123456`,
`0070 04B6`, protected mode active, DPMI init reaching
`AllocateExtend`). The IOPL=0 rationale is kept as a source comment
above `uioplb`.

Status: root cause identified and reproduced on demand. PC-MOS/386
boots to a live prompt in protected mode with paging. DPMI is blocked
by an architectural gap in the V86 monitor, not by any remaining bug
in `$DPMI.SYS`.


## DESIGN NOTE — CLI/STI virtualization: read this before attempting option (a)

Recorded before anyone starts, because a partial implementation here is
worse than none and the failures are the kind that surface in
production rather than in a boot test.

### There is no foundation to build on

The only interrupt-related state in the entire monitor is `wshalt` —
one byte, "1 if hlt is pending", used solely to bump a return address
past a `HLT`. There is **no virtual interrupt flag, and no
pending-interrupt mask**, per-task or otherwise.

`contirq` reflects hardware interrupts **unconditionally**. It never
consults any IF state, because none exists.

### The instruction set is not {CLI, STI}

From the monitor's own opcode tables:

| opcode | instruction | handler |
| --- | --- | --- |
| `9C` | PUSHF | `0` |
| `9D` | POPF | `0` |
| `CF` | IRET | `0` |
| `FA` | CLI | `0` |
| `FB` | STI | `0` |
| `F4` | HLT | `t2hlt` (implemented) |

All five unimplemented, plus `INT n`.

**Why a subset is dangerous.** The universal DOS critical-section
idiom is:

```
        pushf
        cli
        ...
        popf
```

Virtualize CLI/STI but not PUSHF/POPF and `pushf` reads the REAL IF —
which the monitor must keep at 1 to retain control — pushing a flags
image claiming "interrupts enabled" at the exact moment the guest has
disabled them. `popf` then writes that back and VIF says enabled
inside the critical section. VIF desynchronizes from guest belief
precisely where it matters most, intermittently, and with no
attributable symptom.

`IRET` is the same hazard on the hottest path: every reflected
interrupt returns through it and it pops flags. Wrong IRET breaks
every interrupt return in the system.

### The STI one-instruction delay is load-bearing in THIS codebase

On real hardware STI enables interrupts only after the following
instruction, which is what makes `sti / hlt` safe. This monitor
implements `HLT` and carries `wshalt` machinery for it, and `contirq`
has an explicit `wshalt` return-address fixup — so the idiom is live
here and they were already bitten by a HLT edge case once.

A VIF implementation that delivers pending interrupts on STI itself,
rather than honouring the delay, produces the classic lost wakeup:
deliver, return, execute HLT with nothing pending, task sleeps
forever. Timing-dependent, shows up under load.

### What a correct implementation actually requires

- per-task VIF **and** a pending-interrupt mask
- `contirq` retrofitted to defer rather than deliver when VIF=0
- STI draining the pending set with correct delay semantics
- PUSHF/POPF/IRET synthesizing and consuming VIF in the flags image
- INT n clearing VIF and pushing a VIF-bearing flags image
- the deliver-from-inside-STI path builds a V86 interrupt frame while
  already inside the trap handler on the `s0` frame; reusing
  `contirq`'s frame construction from a second entry point needs care
  about stack discipline

### Cost, and a reinterpretation

At IOPL=0 every one of those instructions traps, and DOS executes
PUSHF/POPF/IRET constantly — every `INT 21h` does. On period hardware
that is a heavy tax.

**IOPL=3 should therefore be read as a deliberate engineering decision
by TSL, not an oversight.** They built an I/O-virtualizing monitor,
not an interrupt-virtualizing one, and set IOPL to match. The
`uioplb` tunable and the `iopl=??` comment are consistent with that.

### Recommendation

**Do (b). Do not touch CLI/STI for it.** The I/O gateway needs no VIF,
keeps IOPL=3, and unblocks `valloc` and DPMI. Contained, and it leaves
a working system working.

If (a) is ever attempted:

1. implement the **entire** instruction set at once, never a subset
2. put it behind a build switch, with IOPL=3 remaining the default
   until it is proven
3. **build the test harness first.** "It booted" must not be the
   acceptance criterion — these bugs do not show up in a boot test.
   Targeted deterministic cases: `sti`/`hlt` wakeup; nested
   `pushf`/`cli`/`popf`; IRET restoring a masked state; an IRQ
   arriving while VIF=0. The headless rig can script all of these.

### One option worth knowing about, not recommending

On 486+ with `CR4.VME` the hardware provides VIF/VIP and an
interrupt-redirection bitmap, making all of the above nearly free. The
driver already distinguishes 386 from 486 (`MicroProcessor`, 3 or 4).
Costs: 386 hosts lose the feature, and it is unknown whether DOSBox
Staging emulates VME — check that before anyone gets attached to the
idea.


## GATEWAY ATTEMPT — built, unexercised; two of my hypotheses disproved; a build trap worth knowing about

### A build trap that invalidated three "builds"

`exe2bin` rebuilds `$386.SYS` from a **stale `_386.EXE`** when MASM
fails. Byte-identical output, fresh timestamp, no visible error, boot
behaves exactly as before. Three of my builds were silently stale
before I noticed the file size never changed.

The failing error was `A2053: Jump out of range`. `dooutali`'s short
jumps have **zero headroom** — anything inserted between them and
their targets (`doout04i`, `doout81i`, `dooutald`) breaks the build.

**Rule: delete `_386.obj` and `_386.exe` first, always assemble with a
listing (`masm _386,_386,_386;`), and check the error count.** The
`.ASM.SYS` recipe in `MAKEUTIL.MAK` has no error gate.

Consequence for the gateway: its body cannot live near `dooutali`. It
is placed next to `i6fstub` and reached by a near jump, with only the
existing `jmp` retargeted (`jmp dooutali9`, same encoding size) so
zero bytes are added inside the short-jump range.

### Built (option b)

- port `0E0h` force-protected in `t2iopbm` at all three sites that
  already force `04h`/`81h` (byte `1Ch`, bit 0), including inside
  `vsetiop`
- `i6fstub` hooked into `IVT[6Fh]` at init; `out 0e0h,al` to trigger
  the trap, then propagates CF into the caller's saved flags image at
  `[bp+6]` before `iret`
- `doi6fgate` advances `s0ip` past both bytes of `out imm8,al`, sets
  `debugint`/`iveccode`, `jmps32 e6fa`
- `oldint6f` stores the previous vector

Assembles clean. Hook verified live: `IVT[6Fh] = 0070:01B8`.

### DISPROVED — hypothesis 1: per-task IVT remapping

Guessed the v-86 task saw a different page 0 than the one patched at
init. **Wrong.** `CR3=00110000`, `PDE[0]=00111027`, `PTE[0]=00000067`
— linear page 0 maps to physical page 0, identity mapped. No per-task
remapping. The task does see the hooked vector.

### DISPROVED — hypothesis 2: rhentry/valloc are dual-mode

Guessed `res16` code on the v-86 path would have its `66h`/`67h`
prefixes invert meaning. **Wrong.** `rhentry`..`valloc` contains
**zero** prefixes — it is prefix-free throughout, hence correct 16-bit
code. `rhentry`'s stack discipline also checks out by inspection
(`rhe2` pops the two saved registers into `pop_junk`, `retf`s, and
deliberately preserves flags).

### Marker results, and why they are NOT conclusive

Markers: `R` rhentry entered, `A` valloc entered, `I` immediately
before its `int 6fh`, `S` i6fstub, `G` doi6fgate, `E` entint6f,
`N` e6f05 entered, `P` nalloc returned.

Observed: **`R A I E N P`** — all except `S` and `G`.

Read naively that says int 6fh reaches the IDT dispatcher directly,
the whole service chain works, and the stub/gateway are unnecessary.
**Do not bank that.** The markers do not identify the CALLER. `E`,
`N`, `P` fire on any `int 6fh` AX=7705h, including the kernel's own
memory-manager traffic, so they may be recording kernel activity
rather than the DPMI call.

Decisive against the naive reading: `s0ip` latched at `e6f05` entry
reads **0000**, not `05F2` (valloc's `int 6fh`) nor `05F4` (the next
instruction). So the trap that reached `e6f05` had no v-86 frame at
all — it was not our v-86 caller.

`R`/`A`/`I` are prefix-free 16-bit code, so those three ARE the v-86
DPMI path. It still dies at or around its `int 6fh`.

Also note `s0ip` is far too volatile to sample live — a read at 24s
returned a BIOS timer context (`FFF8:D048`). Anything about a specific
trap must be latched at the handler.

### Status

Boot still parks at `[<`; `AllocateExtend` never returns; marker 7
never fires. The gateway is built, installed, and **unexercised** — it
may be correct or not.

### Next step

Make the markers caller-specific before drawing any conclusion: gate
`E`/`N`/`P` on the latched `s0cs` matching the DPMI driver's segment,
or latch `s0cs:s0ip` per entry and read both. Until the caller is
identified, the `int 6fh` question is open.

Running tally of confident root-cause claims in this investigation:
seven made, six wrong. The ones that survived were backed by a
mechanical before/after measurement; every casualty came from reading
source or from a single ambiguous sample.


## LEADING HYPOTHESIS — the `s0` save area is single-level, so nested traps destroy the outer return context

Not yet confirmed. Recorded because it accounts for every measurement
in this investigation with one mechanism, and because it is the same
*shape* of defect as the CLI/STI gap: a monitor built for a simpler
world than DPMI puts it in.

### The measurement that prompted it

Paired samples (sequence counter proves both are from the SAME
invocation — `AllocateExtend` is entered exactly once; the earlier
`count=16` was kernel traffic):

```
                SS      SP
entry           D120    0E07     <-- ODD
at Z (after the D120    2428
memman far call)
```

Same SS, but SP moved by +1621h inside a single call whose code is
push/pop balanced. That is not a leak or an off-by-N shift. The v-86
task came back from its `int 6fh` on a different stack position.

Return address in that slot reads **`6FEB`** at both Z and Q, where
`1200h` is expected (`call AllocateExtend` = `E8 057D`, 3 bytes, at
INIT16 `03CD`; INIT16 base `0E30h`).

### The mechanism

`cgrm7` ends `mov sp,offset mmgrp:s0ip` / `iretd`. For a v-86 return
that `iretd` restores **SS:ESP from the `s0` frame**.

`s0error`/`s0ip`/`s0cs`/`s0flags`/`s0sp`/`s0ss`/`s0es`/`s0ds`/`s0fs`/
`s0gs` is a **single global save area**. There is no per-nesting-level
save.

So any trap taken while another is being handled — a timer IRQ during
our `int 6fh`, with interrupts enabled — overwrites `s0*`, and the
outer `iretd` then restores the INNER trap's context. The task resumes
with the wrong SP, the wrong return address, or both.

### What it explains

- the odd `SP` (`0E07`) on entry
- the return slot wrong (`6FEB`) from the instant the far call returns
- `SP` `0E07` -> `2428` across one balanced call
- the earlier live `s0ip` read returning a BIOS timer context
  (`FFF8:D048`) rather than ours — that was this, visible directly
- why the allocation SUCCEEDS but the return is destroyed: `nalloc`
  completes fine; only the return path is corrupted

### Confirming test (do this before acting on it)

A nesting counter incremented at `eicommon` entry and decremented
before `cgrm7`, with maximum depth displayed. **If it ever exceeds 1,
traps nest on a single-level save area and the monitor is
re-entrant-unsafe by construction.**

### If confirmed

This is not a DPMI bug and must not be fixed in `_DPMI.ASM`. It
belongs with the CLI/STI design note as a second structural limit of
the v-86 monitor. Any fix means giving the save area depth — a stack
of frames rather than one — which touches every exception path, so it
carries the same "implement it properly or not at all, and build the
test harness first" warning as the CLI/STI work.

### Confirming test ATTEMPTED — result INCONCLUSIVE

Counters added: `inc ss:[nestcur]` at `eicommon` entry, `dec` at both
`cgrm7` and `dohexit`, with `nestmax` tracking the peak.

Result: `nestcur=124  nestmax=255`.

**This does not confirm the hypothesis.** `nestmax` is a `db` and
saturated at 255, so it carries no information. `nestcur` drifting up
to 124 shows only that increments vastly outnumber decrements — i.e.
`eicommon` has exit paths that bypass BOTH `cgrm7` and `dohexit`
(`contirq`, `nmswitch`, the `dovmint`/`dovmrh` routes). The counter
was never balanced by construction, so the drift is an artifact of
incomplete instrumentation, not evidence of nesting.

To redo it properly: make the counter a word, place the `dec` at every
exit from `eicommon` (enumerate them from the source first — at
minimum `cgrm7`, `dohexit`, `contirq`, `nmswitch`), and only then
read `nestmax`. Alternatively, instrument far more narrowly: set a
flag on entry to the int 6fh handler, check-and-report it if a second
trap arrives while set.

The nesting hypothesis therefore remains **unconfirmed but still the
best fit** for the measurements in the section above.


## BASELINE: the UPDATE 8 nesting counter broke the boot before `$DPMI.SYS`; removed. The nesting test is void, not inconclusive

### How it surfaced

The tree as handed over (UPDATE 8 source) did not match the
`$386.SYS`/`$DPMI.SYS` shipped with it: rebuilding gave 21915/5538
bytes against 21883/5410, 9737 differing bytes in `$386.SYS`. The
handover zip's `386.SYS.built`/`DPMI.SYS.built` are byte-identical to
the rebuild, so the source is UPDATE 8 and the shipped binaries were an
earlier build.

The two boot differently, repeatably:

```
UPDATE 8 build (2/2):
row 17:  >{}()]
row 23:  V W                                      RAIENP
v-86 at 76CD:FC8x, VM=1, no further progress

older shipped binaries (3/3):
row 17:  >{}()]1[<>)]2[<>)]3[<>)]4[<>)]5[<>)][<
row 23:  V123456             00050205  0070  0M1E RAIENPZK Q
```

The UPDATE 8 build never runs the pass-2 driver loop, so `$DPMI.SYS`
is never loaded.

### Isolation — one variable at a time, `$DPMI.SYS` held fixed

UPDATE 8 added only the nesting counter to `_386.ASM`. It also
clobbers live CH (`mov ch,ss:[nestcur]` after `push cx`), and the
memman ABI carries a count in CX, so CH was the obvious suspect.
**Tested before believing it:**

| `$386.SYS` variant | result |
| --- | --- |
| A: `inc`/`dec` kept, CH use removed | fails exactly like UPDATE 8 |
| B: counter removed entirely | `V123456 … RAIENPZK Q 6FEB 6FEB 0E07 D12428 D120` |

B reproduces the UPDATE 7 screen exactly, including the paired SS/SP
readouts. **CH is not the mechanism.** The flag-modifying `inc`/`dec`
alone (or the code shift they cause) is enough to break the
post-`$386.SYS` kernel path. The counter's own comment claimed nothing
downstream of `eicommon` is flag-sensitive; this measurement
contradicts it. Which effect it is, and where, is not measured.

### What this retracts

UPDATE 8 recorded `nestcur=124 nestmax=255` as "inconclusive". It is
**void**: the build that produced it never reached `$DPMI.SYS`, so it
cannot have measured nesting on the DPMI path. The single-level `s0`
hypothesis is back exactly where it was before UPDATE 8 — best fit,
untested.

### Tree state

Baseline = B, with the orphaned comment and `eicnomax:` label also
removed (byte-identical rebuild, verified). `nestcur`/`nestmax`
declarations remain for now. Rebuilt from scratch in the tree with
obj/exe deleted first: 0 warnings, 0 severe errors. Boot with DPMI: B
screen (second run). Boot without DPMI: live prompt, `VER` answers.

### Rules this adds

- **Instrumentation must prove it is inert** before its readings count:
  the instrumented build must still reach the baseline screen.
- **On the trap path, preserve all flags.** `lahf`/`sahf` does not
  cover OF, which `inc`/`dec` modify.
- **Rebuild and `cmp` shipped binaries against shipped source** before
  trusting a tree.

Status: baseline set and verified. DPMI failure point unchanged from
UPDATE 7 — corrupted return address after a successful allocation, SP
odd on entry to `AllocateExtend`.


## `$DPMI.SYS`: the corruption was an assembler encoding defect, and the native-mode entry already exists in the monitor

### Method note

This session measured from inside the emulator instead of from inside the
guest. A private DOSBox patch logs every interrupt, exception and IRETD
(and, on demand, every v-86 instruction) in a window around each v-86
int 6Fh, with read-only page-table walks for stack peeks. Guest
instrumentation perturbs the trap path — UPDATE 9 showed that vividly —
and this does not: the screens are identical with tracing on and off.

### The monitor is not the culprit

Across 2054 v-86 traps in one DPMI boot, `$386.SYS` returns SS:SP exactly:
reflected interrupts 6 bytes lower (the frame it builds), int 6Fh
unchanged, all 16 calls. The failing `AllocateExtend` call enters the
monitor at SS:SP `D120:241E` and comes back at `D120:241E`, with **no
nested trap between entry and exit**. The single-`s0`-frame hypothesis is
refuted for this call.

The stack pointer changed with no trap at all, so the cause was in v-86
code.

### Root cause: a 16-bit/32-bit encoding defect in original TSL code

`AllocateExtend` lives in INIT16 but references `EndProtect`/`BeginProtect`,
which are in a USE32 segment. MASM emits a 32-bit displacement and **no
`67h` prefix**. Executed 16-bit, the byte stream desynchronises:

```
13E0  lea cx,[di] / and bx,[0000] / lea ax,[di] / push ax
13E9  add [bx+si],ax / add [bp+di],ch
13ED  enter 0E9C1h,12
13F1  push cx
```

`ENTER 0E9C1h,12` predicts three values that were measured independently:
SP `0E07` -> `242A`, saved bp `0E03`, and the wrong return address `6FEB` at
`[242A]`. The famous `6FEB` was never a monitor bug; it was whatever lay at
a stack address 0x1621 bytes away.

Three instances of this defect exist in `_DPMI.ASM`'s 16-bit segments; all
three are in upstream `pcmos386v501` master, unmodified. Fixes: use the
label *difference* (an assembly-time constant, no fixup) for the page
count; `offset ddt:` for the message pointer; an explicit `db 67h` for the
`DriverRealCS` store. A `ddt:` group override does **not** fix the `lea`
case — it produced a byte-identical binary.

With those three lines changed: return slot `1200` as expected, stack
balanced, install markers to `;`, boot reaches the prompt, and the driver
reports `Not Installed.` / `Protected Code Initialization failed.` — its
own error text, for the first time.

### `Init32Code`: the mode switch was never written, but the monitor has one

A per-instruction trace showed `call32` pushing 16-bit immediates in v-86
and jumping into `InitProtect`'s USE32 bytes, which decode as 16-bit; a
`call rel32` read as `rel16` lands two bytes before `SegToSel` on a
`pop es / ret` that unwinds straight back to the caller. Nothing trapped;
`Bit32Ok` stayed `'N'`.

`_DPMI.INC`'s `goprot`/`goreal` are empty macros — in upstream too. But
`$386.SYS` implements exactly what they need:

- `int 0D4h AH=10h` from a v-86 task -> `entintd4` -> `nmswitch`, which
  rebuilds the task's segments as `g=1,d=1` descriptors and irets to ring 3
  in 32-bit mode;
- the same call from native mode -> `einative` -> `einfun90`, the switch
  back;
- `AH=11h` allocates extended memory and returns a **permanent** selector,
  which is what `InitProtect`'s ES needs;
- `dtitable` already distinguishes permanent (`0FEh`) from task-owned
  descriptors.

Implemented as two instructions each, the switch **works**: measured
`vm=0`, `cpl=3`, `cs=007b`, `ss=0073`, and `InitProtect` running as real
32-bit code. It then calls int 6Fh `7786h` from native mode, `einative`
dispatches only vectors `38h`/`D4h`/`21h`, so the call is reflected to the
never-hooked real-mode int 6Fh vector, and the task dies.

That **restores** this addendum's earlier `SegToSel` finding, which the
first design note demoted: reflection is real, it was simply unreachable
while `goprot` was empty. `InitProtect` is unfinished in one more way: its
`rep movsd` runs with ESI, EDI and ES never set by anyone.

The `goprot`/`goreal` change is therefore **not in the tree**: alone it
turns a clean failure into a hang. It goes in with the driver-side
`scbsel` change.

### Client side

`GoProtect` issues the same `AH=10h` call, but `entintd4` only takes it
when the application has no int D4h handler of its own. If `$386.SYS`
declines, the kernel's `mosint38` returns `AX=1` with carry set —
functions `10h`-`15h` are `dw 0` in `vct38` — and `GoProtect` never tests
carry, so a client would believe it had switched.

### Where this leaves the project

The protected-mode entry is not missing architecture; it is wiring plus one
service (segment-to-selector reachable from native mode) plus finishing
`InitProtect`. See `pcmos386-protected-mode-entry-design.md` for the
ordered plan and the open risks: `cleardti` frees task-owned descriptors on
every switch, there are only 30 descriptor slots, and the native context is
ring 3.


## Stripping the diagnostics: `_DPMI.ASM` is clean; one `_386.ASM` marker turns out to be load-bearing

`_DPMI.ASM` stripped without incident, and the driver's own sign-on print
was restored with a group-relative operand. It now prints its real banner
and its real error text, which is independent confirmation that the old
screen garbage was the segment-relative `OFFSET` defect and nothing else.

`_386.ASM` did not strip. With the markers gone the boot stops right
after `$386.SYS` loads. Bisection landed on a single 11-line block: the
`R` marker in `rhentry`.

The discriminating measurements:

- replacing the block with 16 NOP bytes, so the image is byte-for-byte
  the same size and everything after it sits at the same offset, still
  fails -- so it is not layout and not size;
- keeping the block but writing to `B000` (unused mono page) instead of
  `B800` boots fine, all the way to the DPMI messages, with nothing
  visible on screen -- so it is not the video page either.

What remains is that those instructions must execute. The block has no
net register or flag effect: `push ax/push es/lahf/push ax`, a segment
load, two byte writes, then `pop ax/sahf/pop es/pop ax`. NOPs of equal
byte count do not substitute for it, but a memory write elsewhere does.

That is the third change in this project that should have been inert and
was not (the UPDATE 9 nesting counter and the `nmswitch` guard being the
others), all of them on or near the trap path. It is worth treating as
one open question rather than three curiosities: something in this
monitor depends on timing or on memory traffic in a way not yet
understood.

Not chased further this session. The remaining cheap discriminators are a
segment load with no write, a write to ordinary RAM, and a same-length
delay that touches no memory.

One correction: the strip list said to remove "the whole gateway". It is
load-bearing -- `i6fstub` is the hooked IVT[6Fh] entry and its
`out 0e0h` is the only route from a v-86 int 6Fh into the dispatcher.
Only its `S` and `G` markers are diagnostic, and removing those is
verified safe.


## Kernel diagnostics stripped; the screen is finally clean

The bracket noise on every driver-load line came from `MOSDDINT.ASM` and
`MOSINIT2.ASM`, not from either driver: 13 BIOS-teletype marker blocks
(`[`, `<`, `>`, `{`, `}`, `(`, `)`) and 3 recorder blocks writing to the
BIOS data area for DUMPLOG. All removed, with the strippers refusing any
block that contains a line which is not a marker instruction.

Two things worth recording about the kernel build, which nothing had
exercised before this point:

- `MAKEMOS.BAT` begins with `del $*.*`. Running it would delete
  `$386.SYS`, `$DPMI.SYS` and every other built driver in `latest/`. The
  rig drives `make -f KERNEL.MAK $$MOS.SYS` directly instead and deletes
  only what it means to rebuild.
- The tree's `$$MOS.SYS` was **stale**, exactly as the drivers were:
  129457 bytes shipped against 130225 rebuilt from unmodified sources.
  So the rebuilt-but-unmodified kernel was boot-verified first, and it
  booted identically. Only then was anything stripped. Without that step
  the strip would have been measured against a binary that did not come
  from these sources — the same trap as the 09-17 tarball.

Result: no marker characters from the kernel anywhere, `$386.SYS` and the
DPMI driver announce themselves normally, and the no-DPMI boot reaches a
live prompt through the date/time prompts and `$$SHELL.SYS version 5.04`.

`_386.ASM` keeps its markers, still blocked by the `R`-marker sensitivity.
They sit at absolute rows 22-23, so they now appear against scrolled shell
output rather than in a wall of brackets.


## `_386.ASM` stripped after all — and the "load-bearing marker" was my own bug

The previous section reported that the `R` marker in `rhentry` could not
be removed without stopping the boot, and treated that as a third instance
of this monitor reacting to a change that should be inert. **That was
wrong, and the cause was my stripper.**

Those marker blocks nest a `push ax`/`pop ax` inside the outer pair, to
carry the flags across `lahf`/`sahf`:

```
push ax / push es / lahf / push ax / ... / pop ax / sahf / pop es / pop ax
```

The filter matched from the first `push` to the *first* `pop ax`, which is
the inner one, and cut there — leaving `sahf / pop es / pop ax` stranded.
Three unbalanced pops on the trap path will stop a boot, and they did.

Worse, the two tests I ran to "confirm" the finding could not have caught
it. Padding with NOPs and redirecting the write to `B000` both leave the
surviving pops exactly where they were, so both reproduce the hang for the
same reason. They looked like independent confirmation and were nothing of
the kind. The lesson is narrower than "measure everything": a test only
discriminates if it varies the thing actually under suspicion, and I never
varied the edit itself — only its contents.

Rewritten with push/pop balance tracking, the block removes cleanly and
the system boots. The check that would have caught it immediately is
trivial: the global `push`/`pop` count of the stripped file is `-8`,
exactly as in the original. It is now part of the procedure.

So `_386.ASM` is stripped: 15 marker blocks, `V`/`W`, the `eidbg*`,
`e6dbg*` and `e5dbgip` latches, every declaration including
`nestcur`/`nestmax`, and the orphan comments. The gateway stays, as before
— that part of the earlier note was right.

The screen is now clean from power-on to prompt, with no diagnostics left
in any of the four files. The open-question framing of "three inert
changes that broke this code" collapses to one: UPDATE 9's nesting
counter, which was a genuine source change measured 2 of 2 boots and is
unaffected by any of this.


## `$DPMI.SYS` installs. The wall was an assembler limitation, and I spent most of the session treating its symptoms

The driver initializes: `Dos Protected Mode Insterface Installed.`, boot
through to the prompt, no-DPMI boot unaffected, kernel binary untouched.

### What the entry actually needed

`$386.SYS` already implements the mode switch (`entintd4` -> `nmswitch`
out, `einative` -> `einfun90` back, `ah=11h` to allocate extended memory
with a permanent selector). `goprot`/`goreal` are two instructions each.
Three things then had to be true that were not:

1. the SCB segment-to-selector call had to happen in v-86, because
   `einative` never routes vector 6Fh to the `77xx` tables;
2. the size computation had to move into the USE32 segment, because it
   sat in INIT16 but executed after `goprot` under `d=1`, inverting every
   operand size — ECX came out 0, the native ESP was garbage;
3. `InitProtect` had to be finished: its `rep movsd` ran with ESI, EDI and
   ES never set by anyone.

### The defect that was actually stopping everything

MASM cannot encode a call from a `use32` segment to a `use16` label: it
emits a `66h` operand-size override together with a `rel32` field, the cpu
consumes `rel16`, and the trailing two bytes execute. That was the `#UD`
in the `7786h` handler, and `7786h` had therefore never worked from either
mode.

Dropping the prefix fixes the decode and breaks the contract instead:
`addrnca` and `makegdte` both end with a `66h`-prefixed `ret` and pop two
bytes, so each 4-byte push leaks two. Four bytes across two calls, and
`cgrm7`'s pops then return every caller register holding its neighbour's
value — BP among them. BP is what `mosddint` keeps its locals in, so the
kernel's `les bx,[bp-28]` read `SS:FFE4`, got `0000:0000`, dispatched a
device header in the null segment, and looped on `#GP` at `0000:0008`.

One chain, from an assembler encoding to a kernel crash three layers away.

### How badly I went about it

Before finding that, I made four changes that fixed nothing: amending the
`nxtdrvr` zero-segment substitution (the amended code never ran), pre-
initialising `nxtdrvr` to `-1` (the walk was not reading `nxtdrvr` at
all), preserving BP across `goprot` (BP was lost earlier, in the handler),
and the int 2Fh vector (real, but not the hang). Each was plausible from
the symptom and none was measured first.

Then I made it worse. I instrumented the handler to record its frame, read
zeros, and reported "bp=0" as a finding — but that instrumentation had
never compiled in, and I had read back the initialisers of the three data
words. Everything built on that reading, including the theory that these
handlers pass registers through `ntrash*`, was wrong. Two later insertion
attempts landed at the wrong line, because `awk` with `RS="\r\n"` counts
records differently from the line numbers I had derived from a CR-stripped
copy, and one of them broke the boot outright. I also ran a build without
`TREE` set, which rebuilt `$386.SYS` in the real tree; it came out
byte-identical to the verified build, so nothing was lost, but only by
luck.

What finally worked was moving the measurement out of the guest entirely:
a hook in the DOSBox build that logs `bp`, `esp` and the frame slots for
every instruction executed in a given code range. It cannot shift guest
layout, which the source instrumentation kept doing, and it answered the
question in one run: `bp=0fd8`, `[bp-16]=0000d000`, and `esp` two bytes
low on exit.

The rule this earns: when a measurement and a theory disagree, verify the
measurement exists before believing either. A value read back from memory
that equals its initialiser is not evidence.

### Rules and corrections

- Check encodings **in the linked binary**, not the listing: the listing
  shows pre-link values and looked correct while the bytes were wrong.
- Operand size must match the callee's `ret`, and an indirect call with a
  `66h` override does not give a 16-bit push — measured, it still pushed 4.
  Use a `res16` wrapper per callee.
- `makegdte` returns 2 bytes, not 4, contrary to what I wrote earlier.
- `nxtdrvr` remains untouched and unvalidated; both edits are reverted and
  the install re-verified against the tree's own kernel.
- `0000000K` and `install not done` are not bugs: the first is original
  TSL code that never fills the digits, the second a hardcoded `ECHO` in
  the test `AUTOEXEC.BAT`.

Status: driver installs. Client path (C4) untested and known incomplete —
`GoProtect` never tests carry after the mode-switch call, so a client that
fails to switch will believe it succeeded.
