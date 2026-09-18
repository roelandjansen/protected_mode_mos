# PC-MOS/386 — DPMI native-mode entry: survey and design options

Status: survey complete, no code written. Decision needed before
implementation.

Tree: baseline (UPDATE 9) plus the three `_DPMI.ASM` fixes from this
session (`AllocateExtend` page count, `offset ddt:No32`, `db 67h` before
`mov [DriverRealCS],ax`). Boot with `DEVICE=$DPMI.SYS` reaches the prompt;
the driver reports `Not Installed.` / `Protected Code Initialization
failed.` Boot without it answers `VER`.

Everything below marked **measured** was observed in the emulator (screen,
interrupt trace, or instruction trace). Everything marked **read** comes
from source or listings only.

---

## 1. Why `Init32Code` fails today

**Measured** (instruction trace from the `AllocateExtend` int 6Fh to the
`FreeExtend` int 6Fh; no interrupt or exception in between):

```
150C  push 1517          call32: return address
150F  add [bx+si],al     high word of the 32-bit immediate
1511  push 1570          call32: InitProtect
1514  add [bx+si],al
1516  ret                -> InitProtect (INIT32, USE32) in v-86, 16-bit
1570  mov eax,cs:[0049]  "mov ax,[scbseg]" decoded as 16-bit
1575  add [bx+si],al
1577  call 0AD4          rel32 read as rel16, lands 2 bytes before SegToSel
0AD4  pop es / ret       unwinds back to 1517
1517  cmp Bit32Ok,'Y'    'N' -> Init32Err -> No32
```

**Read:** `_DPMI.INC` defines `goprot` and `goreal` as **empty macros**.
`call32` is `db 68h / dw lbl,0` twice plus `ret` — a 32-bit push-and-ret,
correct only in native mode. Identical in upstream
`roelandjansen/pcmos386v501` (master): TSL original, not project damage.
The original driver never reached this code because `CheckFor386SYS`
tested `scbmmfea` bit 40h, which nothing sets.

**Correction to the addendum:** the recorded "`SegToSel` → int 6Fh 7786h
→ DOSBox crash" path is not reachable in this tree. `SegToSel` never
executes; what earlier sessions saw was USE32 code misrunning as 16-bit.
The need for a working selector primitive stands; that evidence for it
does not.

## 2. What `InitProtect` needs

**Read** (`_DPMI.ASM`, INIT32): the whole routine is

- `scbsel` ← `SegToSel(scbseg)`; `scboffset` ← `scboff`
- `rep movsd` of `ECX/4` dwords — CODE32 into the extended memory from
  `AllocateExtend`
- `Bit32Ok` ← `'Y'`

Its header contract: DS = selector for the driver's v-86 code segment,
ES = selector for the extended memory, ECX = size. **ESI and EDI are never
set** by anyone, and nothing produces the DS/ES selectors — `goprot` was
evidently meant to. `InitProtect` is itself unfinished.

## 3. What `$386.SYS` already provides

**Read** (`_386.ASM`):

| item | state |
| --- | --- |
| GDT | fixed: null, tss1, tss2, code32, data32, cod16, dat16, zero, zero3, video, page; then `gdtspace`, 30 user slots (`dtitable`) |
| `makegdte` | builds a descriptor for a real-mode segment; reuses one with the same base for the same task; tags it with the task id; DPL 3 data |
| `cleardti` | frees every descriptor a task owns; called by `nmswitch` on each native-mode switch |
| int 6Fh from v-86 | `7700h`–`770Fh` table; `7780h` block with `86h` SEGMENT_SELECTOR and `87h` SELECTOR_SEGMENT implemented (earlier session), rest return CF set |
| int 6Fh from native | goes to `ei38nat` → `einative`; the `77xxh` tables are **not** dispatched |
| v-86 → ring-0 "call this routine" | **does not exist** |
| native → v-86 call | exists (`dovmrh`/`rhentry`, used by the kernel's memman calls) |

Consequences:

- `SegToSel` called from native code (as `InitProtect` does) would not
  reach `e6f86` at all.
- Selectors from `86h` are task-owned and die on the next native-mode
  switch — wrong lifetime for a host's global selectors.

## 4. The client side is missing too

**Read:** `GoProtect` (the entry returned by int 2Fh `1687h`) switches a
client with `int 0D4h` `AX=1001h`. `int 0D4h` is `SERVICES`
(`OPTIONS.INC`) → `mosint38`. Its vector table `vct38` has `dw 0` for
functions `10h`–`15h`. **No kernel handler for `AH=10h`.**

What `mosint38` does with a zero vector is **not verified**.

So the TSL DPMI host is a skeleton at both ends:

1. the driver cannot enter native mode to initialize;
2. the kernel cannot switch a client task into protected mode.

Fixing only (1) would let `$DPMI.SYS` report `Installed.` with a client
entry that goes nowhere. That is the "silent wrong success" the addendum
warns against.

---

## 5. Options

### A — ring-0 call service in `$386.SYS` (the route proposed earlier)

A v-86 int 6Fh function (`7788h` or next free) that loads a caller-supplied
32-bit code/data context, calls a routine at ring 0 on the monitor stack,
and IRETs back to v-86 with results in registers.

- **Needs:** GDT descriptors for the driver's image (32-bit code, 32-bit
  data, base = driver segment × 16) with **global** lifetime, outside
  `cleardti`; a defined register/segment contract; a way back.
- **Solves:** driver init (1). `goprot`/`call32`/`goreal` collapse into one
  macro around the int.
- **Does not solve:** client switching (2). A client is a *task* running in
  protected mode across task switches and interrupts, not a single call.
- **Risk:** medium. New ring-0 entry on the trap path, which this project
  has already seen is fragile (UPDATE 9).

### B — rewrite `InitProtect` as 16-bit v-86 code, no native mode

- `scbsel` via int 6Fh `7786h` from v-86 (implemented, v-86 path).
- The copy via existing memman services (remap the allocated banks into
  the v-86 address space, `rep movsb`, unmap) — exact service to be picked
  from `vremap`/`vblkcpy` after reading their contracts.
- **Solves:** driver init (1) with **no new monitor code**.
- **Does not solve:** (2); and `scbsel` would still be task-owned.
- **Risk:** low for the change itself. Must be paired with a clean refusal
  at the client entry (below), or it produces an "Installed" host that
  cannot host anything.

### C — design the monitor primitive first: a protected-mode task context

The one thing both ends need is `$386.SYS` running a task in 32-bit
protected mode (ring 3 client, or ring 0 for init) and getting it back:

- global and per-task descriptors with correct lifetimes (`cleardti`
  interaction);
- saving and restoring a protected-mode context across `nmswitch` and
  hardware interrupts;
- reflecting interrupts from a protected-mode task.

Driver init then uses a trivial case of it, and the kernel's `AH=10h`
becomes a thin call into it.

- **Solves:** (1) and (2), eventually.
- **Risk:** high and long. It is the real "protected mode support" work,
  of which DPMI is one consumer.

---

## 6. Recommendation

**Treat DPMI as a consumer, not the goal. Do C as a design first, and
keep `$DPMI.SYS` failing loudly until the client switch exists.**

- The survey shows no shortcut to a *working* host: A or B alone only move
  the failure from install time to the first client.
- The current state is already the correct interim behaviour: clean
  `Not Installed.` / `Protected Code Initialization failed.`, boot
  continues.
- If an installable driver is wanted as a milestone before C, do **B**,
  plus a small change so `GoProtect` returns CF set (the DPMI 0.9 failure
  indication for the mode-switch entry) instead of calling empty
  `int 0D4h` `AH=10h`. Honest end state: installed host, every client
  told "cannot switch". Do not do A for init alone.

## 7. Before any design work on C — facts to establish

1. What `mosint38` does with a zero vector-table entry (`AH=10h`).
2. How `nmswitch` and `cleardti` interact with the fixed and user GDT
   entries; whether any existing descriptor is global by design.
3. Whether `$386.SYS` already has any protected-mode *task* support beyond
   the kernel's own native mode (`realsw`/`realhent`, func 00h "go to
   real mode").
4. What the resident CODE32 (the int 31h handlers) assumes at run time:
   ring, DS/ES/SS, and who installs its IDT entries.
5. Whether the 0.9-heritage pieces in `_386.ASM` (LDT, `CreateAlias`,
   `AllocateLdt` mentioned in the addendum) are reachable and working.

Each is a read-and-measure task with the current rig; none needs code
changes to the tree.

## 8. Rig notes (private tooling, for reproduction)

- DOSBox Staging 0.82.2, meson debug, `enable_debugger=heavy`, with a
  private `pmtrace` patch: `PMTRACE=<file>` logs every
  interrupt/exception/IRET in a window after each v-86 int 6Fh;
  `PMTRACE_STEPS=<n>` logs the next *n* v-86 instructions after an int 6Fh
  `AX=7705h`. Stack and code peeks use a read-only page-table walk.
- Verified inert: plain boot and DPMI boot screens identical with tracing
  on and off.
