# UPDATE 95 -- FORMAT on big and LBA partitions; generic IOCTL beyond 8.4 GB (20261011)

Files: `MOSDDBLF.ASM` (kernel), `FORMAT.ASM`, `FMCOMMON.INC` (FORMAT
and MSYS), CRLF.

| file | bytes | md5 |
| --- | --- | --- |
| `$$MOS.SYS` | 131,089 | `d315fea80b2c` |
| `FORMAT.COM` | 8,496 | `1d7267a407e5` |
| `MSYS.COM` | 4,832 | `5ef9bc01a3e5` |

- MASM 0 warnings / 0 severe errors.
- MOSSEG 0FBB6h (1,098 bytes left), `CLOBBER` 0F34Ah, `mo2` unchanged.

## What was wrong

| case | before |
| --- | --- |
| `FORMAT C:` on the 2 GB volume | "Divide by zero error" |
| `FORMAT` of a drive in a 0Fh extended partition | "Error during scan of partitions" |
| after the scan fix: `FORMAT E:` on a logical drive at 8.7 GB | **wrote boot sector and FAT at sector 546,273**: generic IOCTL write track is CHS, the cylinder wrapped at 1024. Data loss on a real disk. |
| after that fix: partition not cylinder aligned | wrote one track **before** the partition (FORMAT counts tracks from the cylinder start) |
| partition size not a multiple of a cylinder | boot sector said 417,627 sectors for a 409,600-sector partition: the file system reached past the partition end |
| `COPY` to a drive just formatted beyond 8.4 GB | "Divide by zero error": set device parameters re-read the boot sector with CHS (wrapped), so the kernel took a garbage BPB |

## Fixes

### Kernel, `MOSDDBLF.ASM` (runtime, `mos`)

- **Generic IOCTL track read/write (440Dh 41h/61h) through `i13x`.**
  On a drive with extensions the sector is:

  `xlba = partition start - hidden sectors + (cyl * heads + head) * spt + sector`

  That is the origin FORMAT uses: it counts from the EBR, or from the
  start of the disk for a primary partition. No 1024-cylinder limit,
  and correct for partitions that are not cylinder aligned. The CHS
  path is unchanged.
- **Verify and format track (int 13h 04h/05h) on an LBA drive:**
  nothing to do, `i13x` returns success. They have no meaning on such
  disks, and a CHS verify beyond cylinder 1023 would read the wrong
  place.
- **`hgsetparms`** (set device parameters, default BPB) reads logical
  sector 0 through `i13x` at `dibOffset`.

### FORMAT (`FORMAT.ASM`)

- **Cylinder count:** total / (spt * heads) in one division. Before it
  was total / spt first, which overflowed beyond 65,535 tracks (2 GB).
- **Bad-cluster track check:** the remainder by spt in two steps
  (same overflow).
- **Hard disk BPB:** the total sector count is the partition's own
  count from the driver, not cylinders * heads * spt minus hidden
  sectors.

### `FMCOMMON.INC` (FORMAT and MSYS `scan_partitions`)

- Types 0Eh/0Fh accepted.
- The EBR chain is read with `rdsec`: int 13h 42h when the BIOS has
  the extensions, CHS otherwise.
- It follows DOS's chain rule (the same as the kernel in UPDATE 94).

## Tests

| disk | check | result |
| --- | --- | --- |
| 2 GB volume (UPDATE 87) | `FORMAT C:` | complete, 2,138,243,072 bytes; `fatchk`/`minfo` clean (64 spc, 255 spf, 4,176,837 sectors). `COPY` + `DIR` afterwards ok |
| 20 GB, logical drive at cylinder 1060 (8.7 GB), cylinder aligned | `FORMAT D:` | complete. Then in the same session `COPY`, `DIR`, `TYPE`: ok. No sector outside C: and D: changed (`cmp` over the whole image); `fatchk` clean |
| 20 GB, logical drive at 17,000,063, not aligned, 409,600 sectors | `FORMAT E:` | only sectors inside E: written; big size 409,600; 51,145 clusters fit the 200-sector FAT; `COPY`/`TYPE` ok; `D:` untouched |
| | four-task `GO.BAT` | all rc 0, STEST churn/sort 0 bad, all DONE |

## Not covered

- `MSYS` assembles with the new `FMCOMMON.INC`, but was not run.
- `HDSETUP` still makes cylinder-based 32 MB volumes (CHS, 1024
  cylinders). Use FreeDOS `FDISK` or another tool for big disks, then
  PC-MOS `FORMAT`.
- `VERIFY` and other tools that read sectors directly with int 13h:
  not checked beyond 8.4 GB.
- On LBA disks FORMAT no longer verifies tracks (there is no bad-track
  check left). Modern disks remap bad sectors themselves.
