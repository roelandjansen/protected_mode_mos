# UPDATE 100 -- HDSETUP step 2: writes disks beyond 8.4 GB, keeps partitions it did not change (20261012)

Files:

- `cutils/HDSETUP.C` (CRLF)
- `cutils/HDBUILD.SH` (LF)
- `cutils/HDSETUP.MSG`, `latest/SIDECAR/HDSETUP.MSG` (CRLF): back to
  the original files

Rig only: `ptdump.sh`, which prints the MBR and the EBR chain of an
image.

Build:

- `HDSETUP.EXE` 47,702 bytes, md5 `6c77cff3ef1c`;
- `WATCOM=... cutils/HDBUILD.SH`.

## Fix to UPDATE 99: the build needs byte packing (`-zp1`)

Open Watcom aligns structure members to 2 bytes by default. Borland C
packs them to 1 byte. So in the UPDATE 99 build the following
structures were read at the wrong offsets:

- the boot sector BPB (`bt_type`);
- the IOCTL blocks (`dp_type`).

**Effect:** `check_pbr` decided that every valid boot sector had the
wrong size. It then overwrote the boot sector with F6h. On any write,
even on a small disk, the boot sectors of formatted partitions would
have been destroyed. The MLG check read a wrong field too.

**Found by:** the keep-layout test below.

**Fix:** `HDBUILD.SH` now compiles with `-zp1`.

**Do not use a HDSETUP built from the UPDATE 99 package.** The UPDATE
99 tests did not show it: they wrote only to blank disks, where both
builds blank the boot sectors anyway.

## What changed

**1. `write_tree` lays out in absolute sectors.** It was rewritten. For
each drive:

- **Logical drives first.**
  - **New or changed drive:**
    - EBR at head 0 of its first cylinder;
    - drive at head 1;
    - size = whole cylinders minus one track.

    This is the same layout as before.
  - **Kept drive:** its EBR and its start and size stay as they were
    read.
- **Extended partition:** runs from the lowest EBR to the end of the
  last logical drive.
- **Link entries:**
  - start = next EBR minus the start of the extended partition;
  - size = up to the end of the next logical drive.

  Before, the start was the running sum of the logical sizes. That was
  only right when the logical drives were contiguous.
- **Primaries:**
  - new or changed: on cylinders (slot 0, or cylinder 0, starts at
    head 1);
  - kept: start and size as read.
- **CHS fields:** computed from the absolute sectors (`pe_chs`).
  Beyond cylinder 1023 they get 1023 / last head / last sector.
- **Types:**
  - a FAT16 or DLG partition that ends beyond cylinder 1023 is written
    as **0Eh**;
  - an extended partition that does is written as **0Fh**;
  - an entry that was 0Eh/0Fh on disk keeps that type;
  - link entries stay 05h.
- `ext_ndx` is now reset for each drive. Before, a second drive without
  an extended partition used the first drive's index.

**2. Partitions the user did not touch keep their exact place
(`pe_kept`).**

- An entry read from disk whose cylinders and type are unchanged keeps
  its exact start and size.
- This holds even when it does not start on a cylinder boundary. Other
  tools align to 1 MiB (start 2048).
- Shipped HDSETUP rebuilt every entry from cylinder numbers. Such a
  partition would have been moved to the next cylinder boundary, losing
  its data.
- New fields in the entry records hold what was read: `LBC`, `LEC`,
  `LPTC`, `LABS`, `LSIZE`, plus `EBR` per extended record.

**3. A logical drive owns the cylinder that holds its EBR.** A 1 MiB
aligned EBR can sit in the cylinder before its drive's first sector.
That cylinder was shown as free, so a new partition there would have
overwritten the EBR.

**4. FAT partitions are capped at the FAT16 maximum** (`cap_fat`,
4,190,000 sectors, 2,039 MB with 255/63). This applies when adding a
primary, adding a logical drive, and resizing.

- Shipped HDSETUP offered the whole free space. On a disk larger than
  2 GB that made partitions FORMAT cannot handle; on the 20 GB disk it
  offered 20,387 MB.
- On a 2 GB disk the cap equals the disk, so nothing changes there.

**5. The UPDATE 99 write guard and its message are gone.**
`HDSETUP.MSG` is back to the original.

## Tests

**Rig setup:**

- 20 GB images, 2,610 cylinders, 255 heads, 63 sectors.
- Kernel and FORMAT from the UPDATE 98 tree (`PM_ROOT=/home/claude/scr`).

| test | result |
| --- | --- |
| blank 2 GB disk, create C: + D: + E:, shipped HDSETUP vs new build | images **byte-identical** |
| that disk formatted (mformat), delete E:, add 690 MB + 776 MB, shipped vs new | images **byte-identical**; C: and D: files intact |
| blank 20 GB disk: C: 86 MB + five 2,039 MB logical drives (G: crosses cylinder 1023, H: lies beyond it) | MBR and EBR chain as below; `DIR` shows C:-H: |
| `FORMAT H:` (8.6 GB from the start of the disk) | "Format complete", 2,138,243,072 bytes; `COPY`, `DIR`, `TYPE` correct; mtools on Linux reads the file back |
| 1 MiB aligned disk (mkpt + mformat): C: at 2048, extended at 20,000,768 with a 0Eh logical at +2048 holding `HIGH.TXT`; add two new logical drives below it | C: and the old logical drive keep start, size, 0Eh type and **boot sector md5**; new EBRs chained in front; extended partition grown from 208,845; PC-MOS `DIR C:` / `DIR F:` show the files |

The chain on the 20 GB disk (`ptdump.sh`):

```
MBR  06 start 63 size 176652                  0/1/1-10/254/63
     0f start 176715 size 20884500            11/0/1-1023/254/63
EBR 176715    06 +63 size 4176837             11/1/1-270/254/63
              05 -> 4353615
...
EBR 12707415  0e +63 size 4176837             791/1/1-1023/254/63
EBR 16884315  0e +63 size 4176837             1023/254/63-1023/254/63
```

## Limits

- The megabyte arithmetic is 16-bit: the first 64 GB of a disk.
- New partitions are still placed on whole cylinders. Space before a
  kept 1 MiB aligned partition, up to the next cylinder boundary, is
  not used.
- New partitions are placed first-fit (shipped behaviour). A new
  logical drive goes into the first gap that is large enough, which may
  be below an existing one.
- Only the first two hard disks.

## Rig notes

- The rig defaults to `PM_ROOT=/home/claude/pm`, which boots an
  **older kernel** (md5 `16fc9d34ac6c`). That kernel does not see the
  0Fh extended partition. Use `PM_ROOT=/home/claude/scr`.
- xdotool on this host:
  - drops shifted characters with `type`; use `rig.sh key ... shift+semicolon`;
  - the grey arrow keys do nothing in HDSETUP; use `KP_Down`/`KP_Up`.
- FORMAT needs an extra Enter after `Y`.
- DOSBox buffers image writes. Wait a few seconds before `rig.sh stop`,
  or the last sector written may be missing from the image.
