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
