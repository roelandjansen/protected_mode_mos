# UPDATE 107 -- FREEMEM: find option ROMs by their header (20261013)

Files: `latest/MOSINIT2.ASM` (kernel init), CRLF.

Kernel:

- `$$MOS.SYS` 131,521 bytes, md5 `4ddc908eb721`, built with
  `TREE=/home/claude/scr kbuild.sh MOSINIT2`.
- Init code only (`fmblk`, new `fmorom`); resident size unchanged.

## The problem

With UPDATE 106, VMware Workstation still stopped right after
`FREEMEM holds ROM; using ...`, with "This virtual machine has tried to
execute an invalid part of memory". The configuration:

```
freemem=c0000,d0000
```

`fmblk` (the 1992 `fmsrch` test) calls a 4 KB block ROM when its 8-bit
byte sum is stable and **non-zero**. A ROM block whose bytes add up to
0 (mod 256) passes as empty:

- by chance, 1 block in 256;
- always, for a block of zeros or of FFh padding inside a ROM.

Such a block inside the video BIOS was mapped over with RAM. The next
int 10h jumped into it.

QEMU showed the same flaw: with `freemem=c0000,d0000`, UPDATE 106 used
`CB00,CC00`, one block in the middle of QEMU's video BIOS (C000-CCFF).
QEMU happened not to execute that block; VMware did.

## Fix (`fmorom`)

Before the checksum test, `fmblk` now calls `fmorom`, which finds
option ROMs by their header:

- `55h AAh` on each 2 KB boundary from C000 to DFFF;
- length in 512-byte units in byte 2.

A block that overlaps such a ROM is never used. The checksum test stays
as the fallback for ROM without a header.

## Tests

**QEMU**, `memdev=$386.sys`, `$DPMI.SYS`, `$EMS.SYS`, `$XMS.SYS`:

| `FREEMEM` | UPDATE 106 | UPDATE 107 |
| --- | --- | --- |
| `C0000,D0000` | using `CB00,CC00` (inside the video BIOS) | using `CD00,D000`; all drivers installed, `[A:\]` |
| `C0000,E0000` | | using `CD00,E000`; all drivers installed |
| `C0000,F0000` | | using `CD00,E700`; EMS "Work address conflicts with freemem!", correct |

**DOSBox**, four-task `GO.BAT`: all rc 0, STEST churn/sort 0 bad, all
DONE.

## Notes

- **Your `zz` config:** the line `freemem-d0000,e0000` has a `-`
  instead of `=` and no CRLF at the end. PC-MOS reports it as "Invalid
  command in CONFIG.SYS" and ignores it.
- **If VMware still stops:** `vmware.log` names the address it tried to
  execute (search for "invalid"). That address tells which ROM is still
  being missed.
