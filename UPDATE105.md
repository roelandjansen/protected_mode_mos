# UPDATE 105 -- four hard disks in HDSETUP, FORMAT and MSYS (20261012)

Files (CRLF):

- `cutils/HDSETUP.C`;
- `latest/FMCOMMON.INC` (included by `FORMAT.ASM` and `MSYS.ASM`).

Builds:

| file | bytes | md5 | built with |
| --- | --- | --- | --- |
| `HDSETUP.EXE` | 47,958 | `0506137088d0` | `cutils/HDBUILD.SH` |
| `FORMAT.COM` | 8,624 | `ea979dbe7aef` | `ubuild.sh FORMAT.COM`, MASM 0 warnings / 0 errors |
| `MSYS.COM` | 4,976 | `1ad0e5b71203` | `ubuild.sh MSYS.COM`, MASM 0 warnings / 0 errors |

The kernel is unchanged.

Item 6b, step 2 of 2: the utilities follow the kernel of UPDATE 104.

## HDSETUP

- **Drive probe:** a loop over up to four drives (80h-83h). Before,
  the count was capped at 2 and drive 81h was hard coded.
- **`force_dn(n)`** replaces `force_d2()`. `F2` steps through all
  drives (1 → 2 → 3 → 4 → 1). "Drive *i* of *j*" now comes from the
  drive number and the count.
- **The `/n`, `/d`, `/m` and `/c` paths** loop over all drives.
- **Only drives the user changed are written** (new `drDirty`, set at
  every change point).
  - Before, `write_tree` rewrote every drive. On a disk you did not
    touch, that replaced its MBR boot code with HDSETUP's, and
    recomputed its extended partition (on the test disks it shrank to
    end at the last logical drive).
  - Now an untouched disk stays byte for byte as it was.
- **`gen_gaps`: endless loop on layouts from other tools** (1992 bug).
  - The gap before a partition was computed in an unsigned word.
  - When a partition starts in the cylinder where the previous one ends
    (normal with 1 MiB alignment), `start - end - 1` wrapped to 65,535.
    A bogus gap was inserted, and the scan started over forever:
    HDSETUP hung with an empty screen.
  - Now there is no gap in that case, and the end of the previous
    partition is tracked as a maximum.

## FORMAT and MSYS (`FMCOMMON.INC`, `scan_partitions`)

FORMAT and MSYS turn a drive letter into a partition with their own
copy of the kernel's partition scan. That copy still had the old rules:

- two drives only;
- the primary partition only in slot 0, and the whole scan failed when
  slot 0 was not FAT;
- extended partitions looked for in slots 1-3 only.

So `FORMAT K:` on the fourth disk gave "Error during scan of
partitions". Worse, with another disk layout the numbering could differ
from the kernel's, and **FORMAT would format a different partition
than the drive letter the user gave**.

It now mirrors the kernel exactly (UPDATE 101 and 104):

- **`fmrdmbr` (new):** reads each drive's MBR and moves its first FAT
  entry, in any slot, to slot 0 (as `readmbr`/`pickpri`).
- **`fmptofdl` (new):** gives the table of drive `dl`.
- **Three passes over up to four drives:**
  1. primaries;
  2. logical drives (extended partition in any slot);
  3. the other FAT primaries.
- **Volume counter:** -1 at the start, incremented before each
  comparison, the same in all three passes.
- **Return value:** unchanged. `al` = 80h for a volume on the first
  drive, 0 otherwise; `bx` -> entry, or 0 for a logical drive.

## Tests

| test | result |
| --- | --- |
| four disks (`PRIn` + `LOGn` each, primary and extended in the same cylinder): UPDATE 104 HDSETUP | hangs, empty list (the `gen_gaps` wrap) |
| same, UPDATE 105 | "Drive 1 of 4"; `F2` steps 2, 3, 4, 1; letters `C:`-`F:` primaries, `G:`-`J:` logical drives, as the kernel |
| drive 4: add a 500 MB logical drive, write | disk 4: chained behind the existing logical drive, kept partitions and files intact; **disks 1-3 byte-identical** (`cmp`) |
| PC-MOS: `FORMAT K:` (new drive on disk 4), `COPY` 700 KB, `DIR` | "Format complete" 509,665,280 bytes; file md5 `7b79f512c665`; `J:` (`LOG3`, same disk) untouched |
| one disk, 2 GB `C:`/`D:`/`E:` layout: `FORMAT E:` | `E:` formatted with exactly its own size (1,413,657 sectors); `C:` and `D:` files and labels intact |
| install from scratch with `makefloppy.sh`: HDSETUP, `FORMAT C:`, `MSYS C:`, `COPY *.* C:`, boot from the hard disk | `[C:\]` prompt |
| blank 2 GB disk: `C:` + `D:` + `E:` created with the same keystrokes as the shipped HDSETUP (UPDATE 99 test) | image **byte-identical** to the shipped HDSETUP's |

## Open

- MSYS on a primary of disk 2-4 is untested (it is not bootable anyway:
  the BIOS boots 80h).
- HDSETUP's message "Prepare system for reboot" is the same with one or
  four drives.
