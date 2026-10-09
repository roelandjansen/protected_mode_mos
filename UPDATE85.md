# UPDATE 85 -- exception lookup bitmap, DJGPP signals fixed, ADDTASK shows the maximum (2026-10-09)

Files: `_386.ASM` (on top of UPDATE 82, CRLF) and `ADDTASK.ASM`. Kernel
unchanged (UPDATE 84).

| file | size | md5 (first 12) |
| --- | --- | --- |
| `$386.SYS` | 37,680 | `85758d202772` |
| `ADDTASK.COM` | 2,826 | `1799debacd2e` |

MASM 5.10: 0 warnings, 0 severe errors, for both files. **MAXTASK: 596 KB**
(unchanged).

## 1. Exception lookup through a per-client bitmap (`_386.ASM`)

Before this update, `e31xfind` scanned the whole hook table (up to
`hookhwm`) for every 0202h/0203h call and for every client exception.
It now works like `e31hfind` (UPDATE 74). A "maybe hooked" bit per
client and exception, at `gs:[4400h + id*4 + exc/8]` (hook page 5,
behind the DTA table), lets it return "not hooked" at once. It scans
only when the bit is set.

- `e0203s` sets the bit when a handler is installed. The bit is never
  cleared there: resetting to the default stub keeps it, and the scan
  then finds no entry.
- `cidstart` clears the 4 bytes when a client id is (re)used, next to
  the DTA entry (UPDATE 80).

## 2. DJGPP never got SIGFPE / SIGILL (found while testing 1)

A DJGPP program with `signal(SIGFPE, ...)` that divides by zero ended
with MOS's own **"Divide by zero error"**, and its handler never ran.
UPDATE 84 behaves the same way. This bug was not caused by UPDATE 85.

**Cause.** The host builds the DPMI exception frame on the client's
own stack, directly below the faulting esp. DJGPP's handler
(`exceptn.S`) copies its 64-byte exception state to *fault esp - 92*.
Every other host keeps the frame on a separate locked stack, where
that copy is harmless. Here the copy overwrote the frame's return
eip. The handler's `lret` never reached the host's return stub, the
program was ended as an unhandled exception, and MOS's int 0 message
appeared.

**Fix** (`einxdl`, 32-bit clients). The frame is placed **128 bytes
below** the faulting esp, so the copy lands above it. The frame's esp
field still holds the faulting esp. Return (`einxret`) and the
default stub (`einxdef`) read the frame relative to the current esp,
so they need no change. The 16-bit frame is unchanged: `P16` still
passes.

Ruled out on the way:
- `djexc.c`: DJGPP's 0202h vectors are installed (its own cs).
- `djexc0.c`: the host delivers #DE to a DJGPP program's own 0203h
  handler correctly. The fault was in the return path after DJGPP's
  stack copy.

## 3. ADDTASK reports the current maximum (`ADDTASK.ASM`)

UPDATE 70's to-do 4. After a size error, an insufficient-memory error
or the usage text, ADDTASK now also prints the result of services 2Dh
(the same call `ADDTASK MAX` uses):

```
[A:\]addtask 900
Insufficient memory available
Maximum task size now: 596K
```

Also printed for `addtask` without arguments, `addtask 20` (below the
32 KB minimum), and the kernel's "insufficient memory" (error 8) when a
task cannot get its memory. `je nohelp` became `lje` (out of short
range).

Build: `ubuild.sh ADDTASK.COM` (new rig script, `make -f MAKEUTIL.MAK`;
`combuild.sh` cannot build it: it needs `public addtask` first).

## Tests (rig, `--testconfig`, dynamic core, UPDATE 84 kernel)

| test | UPDATE 84 host (82) | UPDATE 85 |
| --- | --- | --- |
| `djdiv` (C `100 / 0`, SIGFPE handler) | "Divide by zero error" | **SIGFPE caught** |
| `djdiv2` (`divl %ecx`, prints exc 0 vector first) | "Divide by zero error" | **SIGFPE caught** |
| `djill` (`ud2`, SIGILL handler) | | **SIGILL caught** |
| `djexc0` (own 0203h #DE handler, skips the div) | | OK, 1 hit |
| `P16` (16-bit, incl. #DE with a 16-bit frame) | 0 bad | 0 bad |
| DPMI32 (`32x #DE`) | ok | ok |
| `DJXTEST DJHELLO`, `W4XTEST W4HELLO`, `DOS32A WAXTEST DOS32A WAHELLO` | rc 0 | rc 0 |
| `GO.BAT`, four tasks | 6/6 clean | clean (all rc 0, STEST 0 bad, all DONE) |
| MAXTASK | 596 KB | 596 KB |
| `addtask` / `addtask 20` / `addtask 900` / `addtask 700 5` | no maximum shown | `Maximum task size now: 596K` |

A #GP cannot be provoked under DOSBox. It checks neither segment limits
nor null-selector loads: a load at `0FFFFFFF0h` beyond a 9FFFFh DS
limit and a load through a null ES both just returned data. The #GP
delivery path (int 6 with `parm6ec`) is shared code and unchanged.
Please run a DJGPP program that dereferences NULL or reads past its
limit on real hardware or your rig.

## Files

- `_386.ASM`: UPDATE 82 + this change, CRLF.
- `ADDTASK.ASM`: CRLF.
- `djdiv.c`, `djdiv2.c`, `djill.c`, `djexc0.c`, `djexc.c`: DJGPP
  exception tests.
- `ubuild.sh`: rig, builds one `MAKEUTIL.MAK` target.

## 4. Maximum task size without a memory manager (`MOSINT38.ASM`, kernel)

Reported on your rig: with a CONFIG.SYS of only `smpsize=64` /
`cache=16` (no `MEMDEV`), ADDTASK reported 595K, but the real limit
was about 390K. The figures were right with `MEMDEV=$386.SYS`.

**Cause.** `mosext2d` (services 2Dh, used by `ADDTASK MAX`, the new
ADDTASK line and MAXTASK) always returned `calclim - scbfree`: the
whole space a mapped task gets. Without a memory manager, `mositask`
(`mit110`) does something else. It carves the new task from the end
of the calling task's **last MCB** and refuses the request if that
block is too small.

**Fix.** Without a memory manager, `mosext2d` walks the caller's MCB
chain and returns the size of the last block (BX = its start). The
memory-manager case is unchanged.

`$$MOS.SYS` 130,081 bytes, md5 `9e1d68539d5c` (UPDATE 84 + this),
built with `kbuild.sh MOSINT38`.

| CONFIG.SYS | kernel | MAXTASK | ADDTASK says | real |
| --- | --- | --- | --- | --- |
| smpsize/cache only | UPDATE 84 | 911K | (911K) | ~389K |
| smpsize/cache only | **UPDATE 85** | 393K | **389K** | `addtask 390` refused, `addtask 389` starts |
| + `MEMDEV=$386.SYS`, `DEVICE=$DPMI.SYS`, `FREEMEM` | UPDATE 85 | 596K | 596K | `addtask 596` starts |
| + `MEMDEV=$386.SYS`, `FREEMEM` | UPDATE 85 | 596K | 596K | `addtask 596` starts |

The value is as seen by the caller. MAXTASK (393K) and ADDTASK (389K)
differ by the caller's own size, because both run inside that last
block. After `addtask 389`, MAXTASK reports 4K.

Updated file list: `MOSINT38.ASM` (kernel, CRLF) is new in this update.
