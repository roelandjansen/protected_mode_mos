# UPDATE 106 -- FREEMEM leaves ROM out (hang on VMware) (20261012)

Files:

- `latest/MOSINIT2.ASM` (kernel init), CRLF;
- `makefloppy.sh`, `pcmos386-howto-boot.md` (top of the tree), LF.

Rig: `pmrig-toolkit.tar.gz`, with `qemu.sh` (new) and `RIG.md` (QEMU
section).

Kernel:

- `$$MOS.SYS` 131,441 bytes, md5 `7dc4ef4ed4bb`, built with
  `TREE=/home/claude/scr kbuild.sh MOSINIT2`.
- All changes are in init code: DDT 0CC89h and MOSSEG 0FA6Eh are
  unchanged; INITSEG grew to 3800h.
- MAXTASK is unchanged.

## The problem

On VMware Workstation, PC-MOS hung during boot as soon as a driver was
loaded after `$386.SYS`: `$DPMI.SYS`, `$EMS.SYS`, `$XMS.SYS`. For
example:

```
smpsize=64
cache=16
memdev=$386.sys
device=$dpmi.sys
device=$ems.sys
device=$xms.sys
freemem=c0000,e0000
```

The cause is the **`FREEMEM` line**, not the drivers:

- FREEMEM maps RAM into the given upper memory range.
- On a real PC or VM, C0000-C7FFF (QEMU: up to CCFFF) is the **video
  BIOS**, and E0000-FFFFF the system BIOS.
- With RAM mapped over the video BIOS, the next int 10h, i.e. the first
  message printed after the memory lines, jumps into RAM, and the
  system hangs.
- DOSBox handles int 10h inside the emulator, so `FREEMEM=C0000,F0000`
  in our test config always worked there.

**Reproduced in QEMU** (SeaBIOS, set up in the rig without sudo):

| `FREEMEM` | before (UPDATE 105) |
| --- | --- |
| `C0000,E0000`, `C0000,F0000` | hang after "640K allocated to first megabyte" |
| `D0000,E0000`, none | boots |

For automatic FREEMEM (no FREEMEM line), the 1992 code (`fmsrch`)
already tested each 4 KB block for ROM. Ranges given in `CONFIG.SYS`
were used without any test.

## Fix (`dmadjst`, new `dmclip` and `fmblk`)

**`fmblk`** gives each 4 KB block of a FREEMEM range the same ROM test
as `fmsrch`:

- a block whose bytes all share a set bit (FFh: nothing there) is
  empty;
- so is a block whose checksum changes between two reads (floating
  bus);
- a stable, non-zero checksum is ROM.

`fmsrch`'s RAM test is deliberately not used here. RAM under a range is
harmless, and DOSBox has its EMS page frame (RAM) at E000; rejecting
it broke the regression (see Tests).

**`dmclip`** reduces a range to its first run of free blocks. `dmadjst`
then adds an entry for the rest of the range (up to the 5 entries the
table holds), and that entry is clipped in its own turn. So **every
ROM-free part** of a range is used, not just the first one.

**Messages:**

- A reduced range is reported as `FREEMEM holds ROM; using xxxx,yyyy`.
- A range without a single free block gets the existing "Invalid
  FREEMEM" message.

## makefloppy.sh

MAKEMOS leaves the XMS driver as `_XMS.SYS`, like `__SHELL.SYS`. So
`device=$xms.sys` failed with "Cannot find device driver : $XMS.SYS".
With `--all`, it is now copied to the floppy as `$XMS.SYS`.

## Tests

**QEMU**, the configuration above:

| `FREEMEM` | result |
| --- | --- |
| `C0000,E0000` | "FREEMEM holds ROM; using ..."; DPMI, EMS (4 pages at E0000), XMS installed; `[A:\]` |
| `C0000,F0000` | ROM above E700 left out too; boots. `$EMS.SYS`: "Work address conflicts with freemem!", correct, because the range now covers its E000 work area |
| `D0000,E0000` | unchanged, boots |

**DOSBox**, test config `FREEMEM=C0000,F0000`:

- used: C400-C700, CA00-D000, D100-F000;
- left out: video BIOS and fonts at C000-C3FF, C700-C9FF and D000.

| version | four-task `GO.BAT` |
| --- | --- |
| first version (first run only, with the RAM test) | the three `ADDTASK 500` tasks could not start: too little upper memory |
| final | all rc 0, STEST churn/sort 0 bad, all DONE |

## Notes

- **EMS message without FREEMEM:** `$EMS.SYS` can say "Work address
  conflicts with freemem!" even without a FREEMEM line. That comes from
  the automatic search (`fmsrch`), which finds E000 free and maps it.
  This is old behaviour, unchanged here.
- **QEMU in the rig:** now a second test machine with a real BIOS; see
  `RIG.md`, "QEMU". It would have shown the UPDATE 103 problem class
  earlier too.
- **For your VM:** with this kernel, your `CONFIG.SYS` works as
  written. `freemem=d0000,e0000` gives the same result without the
  message.
