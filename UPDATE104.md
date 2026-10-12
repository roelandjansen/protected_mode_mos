# UPDATE 104 -- up to four hard disks (kernel) (20261012)

Files: `MOSDDBLF.ASM` (kernel), CRLF.

Rig: `pmrig-toolkit.tar.gz`, containing:

- `dosbox-hdd4.patch` (new);
- `rig.sh` (`HDIMG2`-`HDIMG4`);
- `restore.sh`, `RIG.md`;
- `dosbox.gz` rebuilt.

Kernel:

- `$$MOS.SYS` 131,169 bytes, md5 `6d83138354ce`, built with
  `TREE=/home/claude/scr kbuild.sh MOSDDBLF`.
- Resident size unchanged: DDT ends at 0CC89h, MOSSEG 0FA6Eh, `CLOBBER`
  0F202h.
- `lbadrv` +2 bytes and `pt1` -2 bytes in gdata.
- `INITSEG` is 64 bytes smaller (36F0h), because the duplicated
  drive-1 code is gone.
- MAXTASK unchanged.

Item 6b of `ITEM6-PLAN.md`, step 1 of 2 (HDSETUP follows).

## What changed (`hinitblk`, all init code)

The hard disk init handled drive 80h and 81h with separate, repeated
code. It is now one loop over up to **four** drives (80h-83h), the
count from int 13h 08h:

- **`readmbr` (new):** reads the MBR of drive 80h+n into that drive's
  stack table and chooses its primary (`pickpri`, UPDATE 101).
  - A drive whose MBR cannot be read, or has no 55AAh signature, gets an
    empty table: no drive letters, and the next drives still count.
    Before, a bad drive 81h simply ended the scan; a bad drive 80h still
    gave no hard disk letters at all.
  - The `trueboot` entry for a primary from slot 1-3 is only made for
    drive 80h, as before.
- **Stack tables:** four tables of 64 bytes (`pt0` + n×64) instead of
  `pt0`/`pt1`. `ptofdl` (new) gives the table of drive `dl`.
- **The three passes are loops over the drives:**
  1. primaries;
  2. logical drives;
  3. the other FAT primaries.

  So the drive letter order stays DOS order: primaries of all drives,
  then the logical drives drive by drive, then the remaining primaries.
- **`lbadrv`:** 4 bytes, indexed by `dl and 3` in `i13x` and
  `process_partition` (was `and 1`).
- **Per-drive primary slot:** `pri` is a 4-byte array (was `pri0`/`pri1`).

## Rig: four hard disks in DOSBox

DOSBox Staging 0.82.2 supports two hard disk images. The new
`dosbox-hdd4.patch` changes two things:

- `MAX_HDD_IMAGES` 2 → 4, so `imgmount 2`-`5`, BIOS drives 80h-83h. The
  80h-83h mapping was already in `GetDosDriveNumber`.
- int 13h 08h counts all mounted hard disks.

`rig.sh` attaches extra disks with `HDIMG2`, `HDIMG3` and `HDIMG4`
(geometry `HDGEOM2`-`4`).

## Tests

Four 2 GB images, each with a FAT16 primary `PRIn` and a logical drive
`LOGn` in an extended partition:

| test | result |
| --- | --- |
| UPDATE 103 kernel, four disks | `C:` `PRI0`, `D:` `PRI1`, `E:` `LOG0`, `F:` `LOG1`; disks 82h/83h unused |
| UPDATE 104, four disks | `C:`-`F:` = `PRI0`-`PRI3`, `G:`-`J:` = `LOG0`-`LOG3`, `K:` invalid |
| 81h blank (no MBR), 80h/82h/83h as above | `C:` `PRI0`, `D:` `PRI2`, `E:` `PRI3`, `F:` `LOG0`, `G:` `LOG2`, `H:` `LOG3` |
| same: `COPY` 700,000-byte file to `E:` and `H:` (both on drive 83h) | both md5 `7b79f512c665` on the image (mtools) |
| one disk: UPDATE 100/101 test images (2 GB HDSETUP layout, Linux in slot 0, no FAT primary, 20 GB 1 MiB aligned) | same drive letters as before |
| four-task `GO.BAT` | all rc 0, STEST churn/sort 0 bad, all DONE |

## Next (step 2)

HDSETUP is still limited to two drives:

- `hard_drives` is capped at 2;
- drive 81h is hard coded in the probe;
- F2 "change drive" assumes two drives.
