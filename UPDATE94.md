# UPDATE 94 -- extended partitions beyond 8.4 GB, partition types 0Eh/0Fh (20261011)

Files: `MOSDDBLF.ASM` (kernel), CRLF. `mkpt.c` (rig: writes an MBR or
EBR at any sector).

- `$$MOS.SYS` 130,993 bytes, md5 `a785d52b41fb`,
  `TREE=/home/claude/scr kbuild.sh MOSDDBLF`.
- MASM 0 warnings / 0 severe errors.
- All changes are in the init segment: MOSSEG (0FB56h), `CLOBBER` and
  `mo2` unchanged, MAXTASK unchanged.

## Changes (`hinitblk`)

1. **The EBR chain is read with `i13x`**, so it uses LBA on drives with
   int 13h extensions. Each EBR's absolute sector goes into `xlba`.
2. **The EBR chain is followed by the rule DOS uses:**
   - a logical drive starts at its EBR plus the start in entry 1;
   - the next EBR is at the start of the extended partition plus the
     start in entry 2.

   Before, the next EBR was assumed to follow the previous logical
   drive directly ("this EBR + start + size of entry 1"). That only
   holds for partitions packed without gaps.
3. **Partition types 0Eh (FAT16, LBA) and 0Fh (extended, LBA)** are
   accepted next to 01h/04h/06h and 05h. Modern partitioning tools use
   them on big disks.
   - The first MBR entry of each drive may now also be 0Eh.
   - Equates `PTCl16`/`PTClext` are local to `MOSDDBLF.ASM`, so
     `DSKSTRUC.INC` and the modules that use it are not touched.

`extbase`/`curebr` live in the init segment (gone after boot).

## Tests

**1. 20 GB disk, LBA layout:**

- `C:` = FAT16 at 63;
- extended 0Fh at sector 16,000,000 (8.2 GB);
- `D:` = EBR at 16,000,000, logical 0Eh, 200 MB;
- `E:` = EBR at 17,000,000, logical 0Eh, 200 MB. There is a gap after
  `D:`, so the old rule would have missed it.

| check | result |
| --- | --- |
| `DIR D:`, `TYPE D:L1.TXT` | LOGICAL1, correct |
| `DIR E:`, `TYPE E:L2.TXT` | LOGICAL2, correct |
| `COPY D:L1.TXT E:C.TXT` | copied |

**2. Classic layout:** 2 GB disk, extended 05h, two packed logical 06h
drives (the case the old rule handled).

| emulator | result |
| --- | --- |
| with extensions (LBA) | `D:`, `E:` correct |
| original, CHS only | `D:`, `E:` correct |

**Regression:**

- UPDATE 93 tests (20 GB, partition at 10.2 GB): still pass;
- four-task `GO.BAT`: all rc 0, STEST churn/sort 0 bad, all DONE.

## Note on logical drives

Their boot sector must give hidden sectors relative to their EBR (63
here), as DOS writes them. Otherwise `process_partition` falls back to
the default BPB, as before. mtools: `mformat -H 63` for logical
drives.

## Still open

- More than two hard disks.
- FAT32.
