## UPDATE 67 (2026-09-30) — per-client ownership: nested DPMI clients

A DPMI program can now start other DPMI programs (`system()`, exec):
the parent survives its children, three levels deep, across DJGPP,
DOS/4GW and DOS/32A. Before, the parent hung when its first child
exited. `_386.ASM` only. Full regression clean.

### Why nesting failed (measured)

`XTEST` (a client doing `system(child)` twice) under PC-MOS: the child
ran, the parent never came back. The host was built for one client per
task ("a task runs one client at a time", dpmiclr's comment):

1. `e6f8e` (CODE_SELECTOR, every session start) called `dpmiclr`: it
   freed everything tagged for the TASK -- the parent's descriptors,
   memory blocks and hooks.
2. The task's nca pointer (`tcbncadr`) was switched to the child's host
   data block and never restored; the parent's pending exec (int 21h
   4B00h through `dovmint`) came back into the child's dead context.
3. The parent's initial ds/ss/es/fs/gs are made by `nmswitch` tagged
   with the plain task id; the child's `cleardti` freed them.
4. All ownership tags were the task id: `dtitable` (80h|task),
   `dblktab`, `phooktab`, `dcbtab`, `c32tab`, `envtab`.

### Change

**Client ids.** Each DPMI session gets an id 1..127 (a namespace of its
own; 0 = no client). Tables: `curcid` (task -> current client),
`cidtask` (client -> owner task + 1, 0 free), `parcid` (parent client),
`savnca` (the parent's `tcbncadr`), `cidpsp` (the client's PSP),
`pendsw` (task -> client whose switch is pending). `tcbpsp equ 2deh`.

- `e31tid` returns the client id: its 12 callers (hooks, memory
  blocks, callbacks) are per client. 14 direct `tcbid` reads in client
  paths use it too (`cidl`/`cidh` in res16, `cidof32` in res32):
  `e31desc`, `einfun48`, `freeclsel`, `e6f8e`, `e6f93` (descriptor
  tags), `dpmiclr`, `envrest`, `c32tab`/`envtab`, `e6f91s`/`e6fcbret`
  (callback owner). Kernel descriptors (`nmswitch`, `e6f86`) keep the
  task id.
- `e31sel`'s UPDATE 64 fallback (the client's kernel-made initial
  selectors) compares with the TASK id, read from the tcb -- with dh
  holding the client id, DOS/32A's 0008h on its ds failed again.
- **`cidstart`** (replaces `dpmiclr` + allocation in `e6f8e`): if the
  task's current client's PSP is on the new client's parent-PSP chain
  (`PSP:16h`, up to 8 levels: `system()` puts COMMAND.COM between), the
  new client nests: parent recorded, `tcbncadr` saved, nothing freed.
  Otherwise the current client is dead (no 4Ch): `dpmiclr` frees its
  resources, the new client inherits its parent.
- **`cidpop`** (at `e4cdone`, the client's 4Ch, after its resources
  are released, before the 4Ch is reflected): the parent is current
  again and the task's `tcbncadr` the parent's nca.
- **`cidtagsw`** (in `nmswitch`, after `cleardti`): for a pending DPMI
  switch the initial ds/es/fs/gs/ss are tagged `80h|client id`: a
  child's `cleardti` leaves the parent's alone; the client's own
  `freeclsel` frees them.
- `cidend` (unregister, `e6f8f`): every client id of the task is freed.
- **`DPHKN` 320 -> 1024.** A DOS/4GW client hooks 256 vectors and 32
  exceptions (288); under a DOS/4GW parent the child's 0205h failed
  from vector 28h on (232 of 370, cf=1; HDPMI32: 550 of 550 ok) --
  found by differential trace. +8448 bytes.

### Measured

| nesting (each child twice) | result |
| --- | --- |
| DJGPP -> DJGPP | rc 0, rc 0 |
| DJGPP -> DOS/4GW | rc 0, rc 0 |
| DOS/4GW -> DJGPP | rc 0, rc 0 |
| DOS/4GW -> DOS/4GW | rc 0, rc 0 (the child runs as its own nested client; under HDPMI32 it attaches to the parent's DOS/4G) |
| DOS/32A -> DJGPP | rc 0, rc 0 |
| DJGPP -> DOS/4GW -> DJGPP | six grandchild runs, every level rc 0 |

Dead predecessor: the kit's sN (a #DE ends it through the host's
default handler), then DJHELLO, twice in one boot: both follow-on
sessions run, sN's result identical both times.

### Regression

- DPMI32 kit, 19 clients: all pass. Changed values only from layout
  (driver +9.6 KB, DOS memory higher): sB bx `7E03`, sC/sD segments
  `20FC`/`2105`, sS rm->pm `79F6`.
- One boot per group, all three extenders:

| test | DJGPP | DOS/4GW | DOS/32A |
| --- | --- | --- | --- |
| FTEST | `1BE00000` | `1BE00000` | `1BE00000` |
| TTEST | 275 @ 91/s | 3020 @ 1000/s | 3021 @ 1000/s |
| KTEST | ok | ok | ok |
| MTEST | 11 MB | 11 MB | 12 MB |
| STEST (step 1 build) | 0 bad, 3 s | 0 bad | 0 bad, 24 s |

### Build

`$386.SYS` 42368 -> 52496, 0 warnings.

| file | md5 |
| --- | --- |
| `_386.ASM` | `f2dc56d98e2c06d16f761866ee9020b0` |
| `$386.SYS` (52496) | `471190f08a3ece48ed199599cf3b4bd6` |

### Tests (host side, `tests/`)

`xtest.c` (starts its whole command line twice via `system()` --
nest by giving it another XTEST), `stest.c` (60,000 malloc/free with
verification, 100,000-element qsort, directory listing, time),
`dbench.c` (per-call cost: cpu loop, 0400h, 0300h, 0501h+0502h; count
as argument), and the UPDATE 66 set `ftest.c`, `mtest.c`, `ttest.c`,
`ktest.c`, `fdiag2.c`. Build: DJGPP `i586-pc-msdosdjgpp-gcc -O2 -s`,
Watcom `wcl386 -bt=dos -l=dos4g` / `-l=dos32a`.

### Performance (measured, no change needed)

STEST took 444 s under PC-MOS against 8 s under HDPMI32 -- the rig, not
the host: `boot.sh` ran PC-MOS with `core=normal`, the debug build's
interpreter core (plain DOSBox with core=normal: 1M loop iterations in
34.5 s; dynamic core: 10M in 0.82 s). **`rig/boot.sh`: `CORE=dynamic
./boot.sh IMG`** (default stays `normal`: pmtrace needs it). With it:
DJSTEST 6 s. Our cost per int 31h is ~25-30x HDPMI32's in loop
iterations of the same run (native dispatch copies the frame) -- worth
optimising later, not a blocker.

### Lessons

- A host data structure sized for one client breaks the moment clients
  nest: count per client, and size for several.
- `pkill -x dosbox; pkill -x dosbox-trace` before builds and runs.
- `cls` between tests wipes the result you have not read yet.

### Next

- Several DPMI tasks at once (multiuser): the tables are per client
  now; test two tasks each running a client.
- Per-call cost of int 31h in the native dispatch.
- Why a DOS/4GW child does not attach to its DOS/4GW parent under
  PC-MOS (it runs nested instead; works, but differs from HDPMI32).
