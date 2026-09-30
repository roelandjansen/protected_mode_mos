## UPDATE 66 (2026-09-29) — interrupts on for clients; IRQ flags; PC-MOS commit bug

Real programs per environment (file I/O, keyboard, time, memory) found
four bugs: three in the DPMI host, one in the PC-MOS kernel. All fixed;
full regression clean.

### Test programs (host side)

`ftest.c` (256 KB `fwrite` one-shot and in 32 KB chunks, read back,
compare, checksum), `mtest.c` (1 MB `malloc`s to 64 MB, touch, free,
one big block), `ttest.c` (3 s of `clock()`), `ktest.c` (`fgets` from
the keyboard), `fdiag2.c` (fill a 256 KB buffer, check it six times,
report the first mismatch with ds/es/ss/fs/gs). Built for DJGPP
(`djftest`..), DOS/4GW (`w4ftest`..) and DOS/32A (`waftest`..).
Reference: plain DOSBox (DJGPP under HDPMI32; Watcom with its own
hosts): FTEST sum `1BE00000`, TTEST ~3 s.

### 1. Clients ran with interrupts off after most host services

`einback` builds the client's EFLAGS from `ncavflag & 0FD7h`, IF
included. `dovmcont` saves the v-86 registers into `ncairegs` after a
v-86 service -- flags included -- and PC-MOS's memory device and DOS
run with IF=0. Every call that went through `dovmint` (0501h..0503h,
0100h..0102h, DOS translations) handed the client IF=0: no timer, no
keyboard. DJGPP/DOS/4GW `clock()` hung; DJMEM/W4MEM passed only
because they never wait.

**`dovmcont`**: after the switch back, copy IF/TF from `ncanflag` (the
client's EFLAGS at entry; `dovmint` never writes it) into `ncavflag`.
CF and the arithmetic flags stay as the service left them.

(First attempt patched `s0flags` -- the wrong variable: the return
builds from `ncavflag`.)

### 2. Stub return lost the caller's IF

The UPDATE 64 `retf 2`/`retf 4` stubs skip the frame's flags.
DOS/4GW's int 31h hook runs with IF=0 and chains to the default: the
application got IF=0 after every int 31h.

**`einvst`** (stub re-entry): take IF from the frame on the client
stack (`[sp+4]`, 16-bit stub; `[esp+8]`, 32-bit) into `ncavflag` and
`ncanflag`. **IF only**: copying TF too made DOS/4GW programs exit
silently. ecx/esi/edi/eax preserved (`eindisp` needs them).

### 3. A hardware IRQ through the default stub corrupted the flags

With interrupts finally on, DOS/4GW computed wrong results: FTEST
sums varying per run, MTEST crashing in v-86 garbage, TTEST stopping
at 0.3 s. `fdiag2` showed "got C9 want C9": a mismatch where memory
was right. Its loop, disassembled from memory:

	2FF069  cmp al,[esp+1Ch]
	2FF06D  je  2FF04B          ; the timer IRQ arrived HERE, ZF=1 --
	                            ;  and the je was not taken after it

DOS/4GW hooks int 08h and chains to the default stub; the `retf 4`
stub returned the host's result flags (the v-86 int 08h handler's) to
the interrupted code. Right for int 21h/31h (cf), wrong for an IRQ.

**0204h**: hardware IRQ vectors (08h..0Fh, 70h..77h) get the old
`int 0E6h / N / iret` stub (N*4); `iret`/`iretd` restores the
interrupted code's whole EFLAGS. All other vectors keep the retf stubs.

### 4. PC-MOS kernel: commit on a character device hung the system

`DOS32A WAFTEST` after one DOS/4GW program printed its result and
hung. Instruction-stepped (new `PMTRACE_STEP_AX`): DOS/32A's exit
commits stdout (int 21h 68h, bx=1); `mosfun68` (`MOSFUN39.ASM`) goes on
to `mediachk` with `ds = gfbbdb` -- for the console no real bdb
(`2E1E`), which yields segment 0 -- and a `call far [070B]` through
`0000:070B` = `'$MEM'` (part of a device name) = `4D45:4D24`, free
memory, zeros. Reproduced without any DPMI: an 8-byte real-mode
`COMMIT.COM` (`mov ah,68h / mov bx,1 / int 21h / ret`) hangs the
original kernel.

**`MOSFUN39.ASM`**: `mosfun68` returns success when `gfbdev` != 0
(character device) -- as DOS; `mosfun40`'s commit-on-write gets the
same check. (First attempt tested `gfbbdb` = 0: wrong, it is non-zero
for the console.) Why DOS/32A only commits stdout after a DOS/4GW run
is a runtime decision of its own, not investigated further.

### False leads (measured, keep)

- Segment reload after 0009h (UPDATE 64 `32d`): no.
- Page remapping under the client: PTEs for `0x300000..0x36F000`
  stable (linear - `0xB0000` = physical) before/during/after.
- Foreign writes: gdb hardware watchpoints on the affected bytes saw
  only legitimate writers with correct values.
- Saving all of `ncairegs` across an IRQ in `einstand`: no effect, and
  the machine then hung at boot (real mode, `0000:0009`). Reverted.
- Stale IVT entries / host tables after DOS/4GW: task IVT (page 0 is
  physical `0x141000`, not 0) and hook/callback/descriptor tables clean.
- Damaged MCB chain: intact (`mcbwalk.sh`); DOS/32A carves the host
  data block from the end of its own block at exactly the 1687h size.
- Disk cache as cause: hang also without `CACHE=16`.

### Regression (new `$$MOS.SYS`, `$386.SYS`, `$DPMI.SYS`)

- DPMI32 kit, 19 clients: all pass. Only change: s3's flags after
  0502h/0503h `30173047` -> `32173247` (IF now set -- fix 1).
- Each environment alone, and mixed in one boot:

| test | DJGPP | DOS/4GW | DOS/32A |
| --- | --- | --- | --- |
| FTEST | `1BE00000` | `1BE00000` | `1BE00000` |
| TTEST | 275 @ 91/s | 3021 @ 1000/s | 3021 @ 1000/s |
| KTEST | ok | ok | ok |
| MTEST | 11 MB | 11 MB | 12 MB |

  plus `W4FDIAG` 0 bad in six passes, `COMMIT.COM` returns, `SET` ok.

### Files

| file | size | md5 |
| --- | --- | --- |
| `_386.ASM` | | `ac0ebb3861c185cd351fe0c4999f0849` |
| `MOSFUN39.ASM` | | `9d108e70119fc3c5f5b3aed485b5432f` |
| `$386.SYS` | 42368 | `156d0e734ff76ecd7cc48c824e6fd7b9` |
| `$$MOS.SYS` | 130017 | `16fc9d34ac6c15f6ec0ccc94c5fd3ea8` |
| `$DPMI.SYS` | 5149 | `f84240795eaad457dc4a208ba147ae1d` (unchanged) |

### Rig

- `pmtrace-update66.patch` (on top of UPDATE 64's): `PMTRACE_STEP_AX=hex`
  starts v-86 step mode at an IRET into v-86 or a v-86 `int 21h` with
  that ax. Step mode needs the **heavy** debugger:
  `meson configure build-trace -Denable_debugger=heavy`.
- `mcbwalk.sh DUMP`: the DOS MCB chain from a `mem.sh 0 a0000` dump.
- `dosbuild.sh` timeout 300 -> 600, `kbuild.sh` 300 -> 900 (a full
  kernel build takes longer; a timeout mid-MASM leaves a truncated
  `.OBJ` that `kbuild.sh` does not delete -- remove it by hand).

### Lessons

- **dash `printf` has no `\x`**: the first `COMMIT.COM` (and the earlier
  `TRIG.COM`) contained the escape text and ran garbage. Octal escapes,
  and `od` the file before using it.
- Awk here is mawk: `strtonum` and hex literals need `gawk`.
- Killing the emulator while a test writes to the floppy corrupts its
  FAT ("Can't run DOS/4G(W)"): restore a clean image before each run.
- A full floppy fails `fwrite` (FTEST code 2): check free space.
- Keystrokes typed before the prompt returns are lost.
- The container restarts at times: the emulator dies, files survive.
- "got X want X" in a check loop is a flags/register effect, not memory.

### Next

Per-client ownership of hooks, descriptors and memory (parked); larger
real programs; why DOS/32A commits stdout only after DOS/4GW (optional).
