# UPDATE 99 -- HDSETUP step 1: reads disks beyond 8.4 GB; Watcom build (20261011)

Files (CRLF kept):

- `cutils/HDSETUP.C`
- `cutils/ULIB.H`, `ulib/ULIB.H` (same file, two copies)
- `cutils/HDSETUP.MSG`, `latest/SIDECAR/HDSETUP.MSG`

Rig: `hdbuild.sh` (new).

Build:

- `HDSETUP.EXE` 45,990 bytes, md5 `065971c21876`, built with
  `TREE=/home/claude/scr hdbuild.sh`.
- Shipped Borland build for reference: 48,510 bytes, md5 `647b5799c4bd`.

## Why a new build path

HDSETUP is Borland C (1992) linked with `ULIB.LIB`. There is no Borland
compiler in the rig, so HDSETUP could not be rebuilt at all.

`hdbuild.sh` builds it with Open Watcom (`wcc -ms`, `wlink system dos`):

- it compiles the 33 ulib modules HDSETUP uses and `ULSVRSWN.ASM`;
- it copies the sources with CR and ^Z removed, so the tree is not
  touched.

The Watcom differences are behind `#ifdef __WATCOMC__`, so the Borland
build is unchanged:

| what | where |
| --- | --- |
| `_DS`/`_SS` pseudo registers (inline `mov ax,ds`) | `ULIB.H` |
| `movmem` mapped to `memmove` | `ULIB.H` |
| `ul_save_window`/`ul_restore_window` are cdecl asm (`UL_ASM`) | `ULIB.H` |
| the `_AH = 0` far call in `reboot()` (inline `farcall_ah0`) | `HDSETUP.C` |
| `regs.x.flags & 1` became `regs.x.cflag` (valid in both compilers) | `HDSETUP.C` |

**Baseline check:** the unmodified source, built with Watcom, shows the
same screens as the shipped `HDSETUP.EXE` on the 20 GB image.

## What was wrong (shipped HDSETUP on the 20 GB test disk)

```
C:    Y 1  DLG-p     94     12      0     11
-- UNALLOCATED --  7930   1011     12   1022
-:    N    OTH        7      1   1023   1023     <- the logical drive at 8.7 GB
Maximum size:        8024   1023
```

- The disk size came from int 13h 08h, which reports at most 1024
  cylinders, so the disk looked like 8 GB.
- Partitions and EBRs were located by their CHS fields. Beyond 8.4 GB
  those fields say 1023/254/63, so the extended partition looked like
  one 7 MB "OTH" cylinder.
- HDSETUP would have offered all of that "free" space, and written
  partitions over existing data.

## What changed

- **`lba_probe`:** checks for the BIOS extensions (41h). When they are
  there, it takes the disk size from 48h. `drCylds` becomes the real
  size in cylinders of the BIOS geometry (255 heads, 63 sectors).
  - The size is capped at 65,535 MB, because the megs column and its
    arithmetic are 16-bit words. The first 64 GB of a disk can be
    managed.
- **`lba_io`:** reads or writes one sector by its absolute sector
  number.
  - With the extensions: int 13h 42h/43h (disk address packet).
  - Without them: CHS conversion through the old
    `read_sector`/`write_sector`, cylinders 0-1023 only.
- **Partition locations come from the 32-bit start fields:**
  - MBR entries;
  - the PBR read for the MLG check;
  - the EBR chain, using the same rule as the kernel and FORMAT:
    - logical drive = EBR + entry 1 start;
    - next EBR = extended start + link entry start.

  `pe_from_lba` sets the full begin and end cylinder (`BC`/`EC`, 16 bits)
  and the absolute first sector (`ABS`) of each entry.
- **`get_pe_data`/`set_pe_data`** use `BC`/`EC`. A CHS field beyond
  cylinder 1023 gets 1023/254/63. Every place that decoded cylinders
  from the CHS bytes now uses `BC`/`EC`:
  - `write_tree` (extended root and link entries);
  - `insure_ext_sync`;
  - the extended chain insert.
- **`check_pbr`** and the MBR/EBR writes go through `lba_io`, by `ABS`
  (and `BC` for the EBR).
- **Types 0Eh/0Fh** (FAT16 LBA, extended LBA) are shown as DLG and
  extended. The type read from disk is kept in `OrigPTC`, for step 2.
- **Write guard:** `write_tree` refuses before writing anything when a
  disk has more than 1024 cylinders. It shows the new message:

  ```
  Error - Writing to disks larger than 8 GB is not supported yet
  ```

  `HDSETUP.MSG` ERRORTAGS goes from 12 to 13 lines.

## Tests

| test | result |
| --- | --- |
| 20 GB disk (`hda.img`: C: 94 MB, extended at sector 17,028,900 with a 0Eh logical drive) | see below |
| same disk: F9 (delete all), Esc, Y (write) | "Writing to disks larger than 8 GB is not supported yet"; MBR md5 unchanged |
| blank 2 GB disk: C: 86 MB + extended D: 486 MB + E: 1,466 MB, written once with the shipped HDSETUP and once with the new build (same keystrokes) | the two 2 GB images are **byte-identical** (`cmp`) |
| that 2 GB layout read back with the CHS-only emulator (no extensions) | same display as the shipped HDSETUP |
| F1 help | same as the shipped HDSETUP |

The new build shows the 20 GB disk as:

```
C:    Y 1  DLG-p     94     12      0     11
-- UNALLOCATED --  8220   1048     12   1059
D:    x    DLG-e    101     13   1060   1072     <- 0Eh logical drive at 8.7 GB
-- UNALLOCATED -- 12056   1537   1073   2609
```

`D:` checks out against the EBR on the image: start 17,028,963, 208,782
sectors, cylinders 1060-1072.

## Limits / next (step 2)

- Writing to big disks:
  - remove the guard;
  - write 0Eh/0Fh for entries that end beyond cylinder 1023;
  - test create, delete and resize beyond 8.4 GB, checked with
    `mkpt`-style dumps of the image and with PC-MOS `DIR` after FORMAT.
- Existing partitions that do not start on a cylinder boundary (modern
  tools align to 1 MiB) would be moved to the cylinder boundary by
  `write_tree`. Shipped HDSETUP does the same: it rebuilds every entry
  from cylinder numbers. Step 2 should keep the start and size of
  entries the user did not touch.
- Only the first two hard disks, as before.

## Rig

- xdotool was missing on the new host. It was fetched with
  `apt-get download xdotool libxdo3` into `/tmp/claude-0/xd/root`.
  `rig/bin/xdotool` is a wrapper; put `rig/bin` on `PATH` and source
  `env.sh` (for mtools) before `rig.sh`.
- Typing right after boot loses keys. Wait about 65 s after `start`.
