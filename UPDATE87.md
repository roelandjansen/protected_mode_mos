# UPDATE 87 -- 2 GB FAT16 volume test; DIR fixes for 1 GB+ (2026-10-09)

Files: `MOXCPINT.ASM`, `MOXCPSUB.ASM` (the shell), `MOSFUN00.ASM` (kernel), CRLF.
`$$SHELL.SYS` (`__SHELL.SYS`) 33,897 bytes, md5 `0a220b586f91`;
`ubuild.sh __SHELL.SYS`, MASM 0 warnings / 0 severe errors. Kernel and
drivers unchanged. Rig: `rig.sh` gains `HDIMG=` (below).

## The disk limit: what PC-MOS actually does

| layer | limit | evidence |
| --- | --- | --- |
| `HDSETUP` (PC-MOS's partition tool) | 32 MB per logical drive | hard-coded message, slices bigger disks into 32 MB volumes |
| kernel file system | **FAT16 "big" volumes (> 65,535 sectors) work: 2 GB per volume** | `MOSDDINT.ASM` reads the 32-bit `bsHugeSectors`; tested below |
| disk access | BIOS int 13h CHS only, no LBA: a disk beyond about 8.4 GB is not reachable | no `ah=41h/42h` in `MOSDD*.ASM` |
| FAT32, long file names | none | |

So: prepare the disk with another tool (FreeDOS `FDISK`/`FORMAT`,
`mformat` on Linux) and PC-MOS uses a 2 GB FAT16 partition.

## Test

A 2 GB image (CHS 260/255/63, MBR, one type-06 partition at sector 63,
4,176,837 sectors), FAT16 with 64 sectors (32 KB) per cluster,
65,261 clusters, made on Linux with `mformat`. Files placed with
`mcopy` so that `MARK.TXT` lands at cluster 60,803, about 1.9 GB into
the volume. Booted PC-MOS (UPDATE 85 kernel) from floppy with the
image as BIOS disk 80h.

| check | result |
| --- | --- |
| `C:` recognised | yes, label BIGDISK |
| `TYPE C:MARK.TXT` (read at ~1.9 GB) | correct text |
| `COPY XMST.EXE C:NEW.EXE` (write; lands at clusters 60,804-60,806) | copied; on Linux `NEW.EXE` is **byte-identical** |
| free space | 1,330,053,120 and 1,064,042,496 bytes: match `mdir` exactly |
| files 25 B .. 734 MB in `DIR` | correct |
| a file of 1,000,000,000 bytes or more in `DIR` | **"Divide by zero error"**: fixed, below |

## Shell fixes

1. **DIR, file size of 1 GB and more** (`MOXCPINT.ASM`, `cdr42`):
   `bin2dec` handles at most 999,999,999 ("max dx:ax=999,999,999" in
   its header); above that its `div` overflows: "Divide by zero error"
   and DIR stops. Such sizes are now shown in KB in the same column:
   `G1 .DAT 976562K`.
2. **DIR, bytes total of 1 GB and more:** the same overflow. The total
   now uses `hibin2dec` (the routine the free-space figure has used
   since the 1992 "1.4 gig drive" change), but only from 1,000,000,000
   on. Below that it is `bin2dec` as before, so the line keeps its width.
3. **`hibin2dec` lost leading zeros** (`MOXCPSUB.ASM`): after the
   leading billions digit, the remainder was printed with blanks:
   `1, 64,042,496 BYTES REMAINING`. Now `1,064,042,496`. This was a
   1992 bug in the free-space line of every disk over 1 GB.

Results:

```
G1      .DAT    976562K  10-09-26  19:54 *
DISKID  BIGDISK     1,074,117,183 BYTES     5 FILES 1,064,042,496 BYTES REMAININ
G
DISKID  NOT FOUND       326,949 BYTES    15 FILES     1,125,376 BYTES REMAINING
```

The floppy line is unchanged. With two 10-digit figures the summary
line is 81 characters and wraps by one character (cosmetic; the old
shell did the same whenever free space passed 1 GB).

## Rig

`rig.sh start` takes `HDIMG=file` (and optional `HDGEOM=512,63,255,260`)
to attach a hard-disk image as BIOS disk 80h and boot the floppy
(DOSBox `imgmount 2 ... -t hdd -fs none`, then `boot -l a`).

## Not covered

- Beyond about 8.4 GB (CHS) and FAT32: not supported, kernel work.
- Utilities on big volumes (CHKDSK-like tools, `DIRMAP`): not checked.
- `HDSETUP` still creates 32 MB volumes; use another tool for bigger ones.

## Kernel: program names in memory blocks (FreeDOS MEM garbage)

FreeDOS `MEM /U`, `/C`, `/DEBUG`, `/FULL` showed garbage names
(`M-^Kv M-^LM-S...`). DOS 4+ EXEC writes the program's file name (no
path, no extension, upper case, zero-padded) into bytes 8-15 of the
program's MCB; tools read the owner name from there. PC-MOS's EXEC
never did. `MOSFUN00.ASM`: new `f4bname`, called from `fun4bpsp`
(both the .COM and .EXE path), from the EXEC path string.

`$$MOS.SYS` 130,177 bytes, md5 `2d18d22d0479` (UPDATE 84 + 85 + this).

```
  1300         64    (0K)  COMMAND       data area
  1305      6,496    (6K)  COMMAND       program
  149c        128    (0K)  COMMAND       environment
  14a5         48    (0K)  MEM           environment
  14a9     54,944   (54K)  MEM           program
```

Regression on this kernel: four-task `GO.BAT` all rc 0, STEST 0 bad, all
DONE; `xmst` 45 ok; MAXTASK 564K.

Left as they are (harmless):
- "device appears to be owned by multiple memory blocks (IO and )":
  `$386.SYS`'s header sits at 0070:0000, the boundary of the block MEM
  calls "IO system data".
- `/FREE` lists MEM's own block as free: MEM counts itself as free.
- `/DEBUG` "Memory is not accessible using Int 15h (code ?h)": int 15h
  88h reports no extended memory, because the memory manager owns it
  (as under HIMEM).
- `/DEVICE` shows two NUL entries and a "(no drv)" block device: the
  list-of-lists NUL copy plus the kernel's own, and a disk driver
  without units.
