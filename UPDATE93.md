# UPDATE 93 -- hard disks beyond 8.4 GB: int 13h extensions (20261011)

Files: `MOSDDBLF.ASM`, `MOSINIT2.ASM` (kernel), CRLF.

- `$$MOS.SYS` 130,913 bytes, md5 `2a0c0fbf530e` (UPDATE 84-92 + this),
  `TREE=/home/claude/scr kbuild.sh MOSDDBLF MOSINIT2`.
- MASM 0 warnings / 0 severe errors.

Rig only (not part of the tree): `dosbox-int13ext.patch` (DOSBox
Staging int 13h 41h/42h/43h/48h), `mkmbr.c` (writes a test MBR).

## What changed

**1. The hard disk driver uses the BIOS extended calls when the BIOS
has them.**

- At init, `process_partition` asks each hard disk with int 13h
  41h/BX=55AAh. If the extensions are there (BX=AA55h, CX bit 0),
  `lbadrv[n]` is set.
- `i13x` (new, in `mos`) replaces the plain `int 13h` read and write
  calls:
  - the sector transfer loop of `hinput`/`houtput`;
  - `read_pbr`;
  - `hsetmedid`;
  - the boot sector read in `process_partition`.
- For a drive with extensions, `i13x` builds the 16-byte disk address
  packet on the stack and calls 42h/43h with the 32-bit sector number.
  That number is the logical sector plus the partition offset
  (`dibOffset`), kept in `xlba`.
- Other drives use the CHS call exactly as before.
- The transfer is still split at track ends (the existing logic), so
  CHS and LBA move the same pieces.

**2. Partitions are found by their LBA start, not by their CHS
fields.** `dibOffset` already came from the partition table's 32-bit
start sector. The boot sector of a partition is now read at that
sector (with extensions). Before, it was read with the CHS fields of
the partition table, which say 1023/254/63 beyond 8.4 GB.

**3. The hard disk init code moved to the init segment.** The UPDATE
92 note was wrong: `mos` is limited by the 64 KB segment as a whole,
including the init code after `CLOBBER`. So there were only 34 bytes
left, not 2.2 KB.

- `process_partition`, `next_dib` and `hinitblk` only run at boot, but
  they were in `mos`, resident in the HMA.
- They now live in `initseg`. Their calls to `mosheman`, `ldiv` and
  `i13x` go through `camos` (now public in `MOSINIT2.ASM`).
- The driver's init entry is a small stub, `hinitstub`, that makes the
  far call the way `cainit` does. It cannot use `cainit` itself:
  `cainit` sits after `CLOBBER`, and the drivers are initialised a
  second time after `mos` has been moved to the HMA. (The first
  attempt used `cainit` and the system hung right after `$386.SYS`.)
- `lbadrv` and `xlba` are in `gdata` (6 bytes). The second init pass
  runs in the old, low copy of `mos`, so data kept in `mos` would be
  lost.

**Space:**

| | before | now |
| --- | --- | --- |
| MOSSEG | 0FFDEh (34 bytes left) | 0FB56h (**1,194 bytes left**) |
| resident `mos` (`CLOBBER`) | 0F772h | 0F2EAh (1,160 bytes less HMA use) |
| `mo2` | unchanged | about 80 bytes left before the next 8 KB step |
| MAXTASK | 564K | **564K** |

## Tests

20 GB test disk (2,610 cylinders, 255 heads, 63 sectors, made with
`mkmbr` + `mformat`):

- `C:` = FAT16 100 MB at sector 63;
- `D:` = FAT16 512 MB at sector 20,000,000 (**10.2 GB**). Its CHS
  fields say 1023/254/63.

| test | result |
| --- | --- |
| UPDATE 92 kernel, `DIR D:` | "Cannot find file" (D: unreachable) |
| UPDATE 93, `DIR D:`, `TYPE D:HIGH.TXT` | `HIGHPART`, 536,576,000 bytes free; correct text |
| `COPY C:LOW.TXT D:COPY.TXT` | on Linux, `mtype` on the image at sector 20,000,000 shows the right text |
| 2 GB image (UPDATE 87) with extensions | TYPE, COPY 700K, DIR: all correct |
| 2 GB image, original emulator without extensions (CHS path) | same, correct |
| boot without a hard disk | ok |
| four-task `GO.BAT` | all rc 0, STEST churn/sort 0 bad, all DONE |

## Limits that remain

- Per partition: FAT16, 2 GB.
- 32-bit sector numbers: 2 TB addressable. The cylinder bookkeeping
  for generic IOCTL (`dibCylsFBeg`) works up to about 500 GB.
- Only the first two hard disks, as before.
- Not tested: logical drives in an extended partition beyond 8.4 GB.
  Their EBRs are still read with the partition table's CHS values.
  Next item if needed.
- Generic IOCTL track calls (440Dh 41h/42h/61h/62h) are CHS by nature
  and unchanged.

## Rig

DOSBox Staging 0.82.2 has no int 13h extensions. `dosbox-int13ext.patch`
adds them for hard disk images:

- 41h (version 2.1, fixed-disk subset);
- 42h/43h (via `Read/Write_AbsoluteSector`);
- 48h;
- 08h reports at most 1024 cylinders.

Rebuilt in `build-lba/` (meson, heavy debugger, optional libraries
off), installed as `build-dbg/dosbox`. The previous binary is kept as
`/tmp/claude-0/dosbox.orig` (CHS-only regression). Build dependencies
were fetched with `apt-get download` into `deps/root`, plus iir1 built
with cmake; no sudo.
