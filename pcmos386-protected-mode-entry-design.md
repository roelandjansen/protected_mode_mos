# PC-MOS/386 — protected-mode entry: architecture and plan

Read this before any further DPMI work. Facts marked **measured** were
observed in the emulator; **read** means source or listing only.

Earlier design notes proposed building a native-mode entry from scratch,
or avoiding one. Both are obsolete: the survey found the mechanism
**already exists in `$386.SYS`**. What remains is wiring plus one missing
service.

---

## 1. The monitor already implements native mode

**Read** (`_386.ASM`):

| piece | what it does |
| --- | --- |
| `entintd4`, `AH=10h` from a v-86 task | jumps to `nmswitch` |
| `nmswitch` | rebuilds ds/es/ss/fs/gs/cs as descriptors over the task's own segments (`g=1,d=1`), `lgdt`, clears VM, `iret` to privilege level 3 |
| same `AH=10h` from native mode | `einative` -> `eixtable[10h]` -> `einfun90`, "switch from native mode to v-86 mode" |
| `eixtable` | `10h` mode change, `11h` allocate extended memory **and return a selector**, `12h` deallocate, `13h` gdt alias |
| `dtitable` | `0FFh` free, task id = task-owned (freed by `cleardti` on every `nmswitch`), **`0FEh` permanent** (`makegdtx`, `einfun93`) |

"Native mode" here is a **32-bit, ring 3 task context** whose segments
alias the task's real-mode segments. `_DPMI.INC`'s empty `goprot`/`goreal`
macros are the two ends of `AH=10h`, and `call32` is valid in the `d=1`
code segment `nmswitch` creates.

## 2. C1 — `goprot`/`goreal` (implemented, measured, NOT applied)

Both macros are `mov ax,1001h` / `int 0d4h`, which is what `GoProtect`
already does for clients. `goprot-goreal.diff`.

**Measured**, DPMI boot:

```
330 INT  d4  vm=1 cpl=3 cs=c0de ss=d120:0e05 eax=1001
331 IRET     -> vm=0 cpl=3 cs=007b ss=0073 ds=005b es=0063   <- native, 32-bit
332 INT  6f  vm=0 cpl=3 cs=007b eax=7786                     <- InitProtect runs
333 IRET     -> reflected to the v-86 int 6Fh vector (0070:01b8)
334 INT  0d  ... 335 INT 06 ... task exits
```

The switch works; `InitProtect` executes as genuine 32-bit code for the
first time. Boot then parks, so this is held back: on its own it replaces
a clean failure with a hang. Apply it together with C2a.

## 3. C2 — the missing service: segment -> selector in native mode

**Read:** `einative` dispatches only vectors `38h`, `D4h`, `21h`. Vector
`6Fh` in native mode always falls through to `einstand`/`dovmint`, which
reflects to the never-hooked real-mode int 6Fh vector. The `7700h`/`7780h`
tables (including `86h` SEGMENT_SELECTOR, implemented in an earlier
session) are reachable **only from v-86**. `einfun93` (`13h`) aliases an
existing *selector*, so it is not a substitute.

**C2a — driver side (do this first).** `InitProtect` needs `scbsel` only
as a value. Compute it in v-86 *before* `goprot`, where `7786h` works,
store it, and delete the `SegToSel` call from `InitProtect`. Needs a small
16-bit helper in INIT16 and `db 67h` for stores into CODE32 variables. No
monitor change.

**C2b — monitor side (later).** Dispatch `77xxh` from `einative` when
`iveccode=6Fh`. The exit path differs: v-86 handlers end at `cgrm7`, which
reloads `sp` to `s0ip` and returns flags via `s0flags`, while a native
caller's frame is at `p0stack`. A native dispatch needs its own return and
carry handling (`einback`). Required eventually — a client calling
`SegToSel` at run time is in native mode — but not for init.

## 4. C3 — finish `InitProtect`

**Read:** it is incomplete beyond `SegToSel`; its `rep movsd` runs with
**ESI, EDI and ES never set** by anyone.

- **ES:** `AH=11h` (`einfun91`) allocates extended memory for a native
  task and returns a **permanent** (`0FEh`) selector — the intended
  source. It allocates, so the driver's earlier v-86 `AllocateExtend`
  becomes redundant; decide which one goes before writing code.
- **ESI:** `offset ddt:BeginProtect` (a `lea` in 32-bit code is fine).
- **EDI:** zero.
- **ECX:** already computed by `Init32Code`.

## 5. C4 — the client path

`GoProtect` issues the same `AH=10h`, but `entintd4` only takes it when
the application has no int D4h handler of its own (it compares the int D4h
vector's segment against int 6h's). Whether that holds for a client under
MOS is **not measured**.

If `$386.SYS` declines, the call is reflected to the kernel's `mosint38`,
whose `vct38` has `dw 0` for `10h`-`15h`: it returns `AX=1` with carry
set, "invalid function code". `GoProtect` never tests carry and returns as
if it had switched. Fixing that — honest carry-set failure per DPMI 0.9 —
is worth doing regardless.

## 6. Order of work

1. **C2a + C1 together** (C1 alone hangs). Expected new failure: the
   `rep movsd`.
2. **C3**: ES via `AH=11h`, ESI/EDI, resolve the duplicate allocation.
   Expected: `Bit32Ok='Y'`, `Installed.`, resident code copied.
3. **C4**: `GoProtect` carry handling, then measure a real client.
4. **C2b**: native-mode `77xxh` dispatch.
5. `_386.ASM` diagnostics — blocked, see UPDATE 11 (`R` marker).

Each step is one build, one boot, one trace with the rig.

## 7. Risks

- `nmswitch` calls `cleardti`, freeing every task-owned descriptor **on
  each switch**. Anything a DPMI host hands a client must be permanent
  (`0FEh`). `7786h` (`makegdte`) returns task-owned descriptors, so DPMI
  function `0002h` would hand clients selectors that die at the next
  switch. Unresolved; affects C2b.
- Only 30 user descriptor slots (`dtitable`), shared by all native tasks.
  A DPMI host will exhaust them.
- The native context is ring 3; anything in the resident CODE32 assuming
  ring 0 will fault.
- Unexplained sensitivity to inert changes on the trap path (UPDATE 9's
  counter, UPDATE 11's `R` marker). Treat any change near `eicommon` or
  `rhentry` as requiring a full baseline boot comparison.
