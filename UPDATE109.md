# UPDATE 109 -- hard disk lost on VMware after a floppy boot (20261014)

Files, CRLF:

- `latest/_386.ASM`: hard disk int 13h 02h/03h staging;
- `latest/FORMAT.ASM`: "network drive" for a drive that does not exist.

Rig: `pmrig-toolkit.tar.gz` with `rig/bochs.sh` (`BOCHS_HD`,
`BOCHS_HDGEOM`, Xvfb check) and `RIG.md`.

Builds:

| file | bytes | md5 |
| --- | --- | --- |
| `$386.SYS` | 38,128 | `7115ab825c44` |
| `FORMAT.COM` | 8,640 | `4e93064b74f1` |

- MASM: 0 warnings, 0 errors for both.
- Kernel unchanged.

## The problem

On VMware Workstation, booted from the install floppy with
`MEMDEV=$386.SYS`, PC-MOS had no C: ("Invalid drive identifier";
`FORMAT C:` said "Cannot FORMAT a network drive!").

- Without `$386.SYS`: C: was there.
- Booted from the hard disk: C: was there.
- QEMU and Bochs, with the VMware disk geometry: C: was there.

## Cause

The kernel scans the partitions twice during boot: before `MEMDEV`
loads and again after it. A diagnostic kernel printed each read on
VMware:

```
 D01 M00n00AA55 P01n00AA55     first scan: MBR ok, boot sector ok
 D01 M00n00AA55                second scan: MBR "ok", no partition
```

The second MBR read (int 13h 02h into the kernel's `ourbuf`) reported
success and the right signature, but no partition was found in it. The
kernel saw the **boot sector from the first scan**, still in `ourbuf`:
it also ends in AA55, but has no partition table.

VMware's BIOS transfers with bus-master DMA, to the physical address of
the buffer. Under `$386.SYS`'s paging that is not the page the CPU sees.
`$386.SYS` stages such transfers through its bounce buffer, but for
int 13h 02h/03h **only for diskettes**:

```
	cmp	dl,80h			; ***** exit if dma not used *****
dmajump label word		; this is nop'ed out if hard disk uses dma
	jae	fastex13
```

The 1992 code assumed hard disks transfer by PIO, unless a switch
(`/D=nn`, `/P`, `/M`, `/E`, `/X`) said otherwise. UPDATE 103 covered the
extended read/write (42h/43h), the kernel's normal disk I/O. The plain
CHS read at boot was still left out.

Confirmed on VMware: with `MEMDEV=$386.SYS /D=4` the second scan finds
the partition (`P01n00AA55`) and C: is there.

## Fix

**`_386.ASM`, `entinr13`:** hard disk calls now go to `i13hd` instead of
straight to the BIOS.

- 02h and 03h take the same address check as diskette transfers: a
  buffer below `dmabank` passes straight through, a buffer in remapped
  memory goes through the staging buffer.
- Transfers larger than the buffer (default 9K) are split by the
  existing hard disk code: geometry from int 13h 08h, `advance_sect`.
- Every other hard disk function (reset, verify, format, parameters,
  ...) passes straight through, as before.
- With a DMA switch, `dmajump` is NOPed out as before, and the switch
  behaviour stays unchanged.

**`FORMAT.ASM`:** IOCTL 4409h ("is the drive remote") on a drive that
does not exist returns carry; FORMAT ignored it and tested the leftover
DX. Now it says "Invalid drive specification!".

## Tests

| test | result |
| --- | --- |
| VMware, floppy boot, `MEMDEV=$386.SYS /D=4` (the same staging path, switched on) | second scan finds the partition, C: there |
| QEMU, VMware-like 2 GB disk (MBR 519 cylinders × 128 heads), your configuration, new `$386.SYS` without a switch | C: there; `FORMAT C:` "Format complete", 2,142,502,912 bytes |
| same: `COPY $$MOS.SYS C:\K.SYS`, `COPY C:\K.SYS C:\K2.SYS` | both md5 identical to the original |
| same: `FORMAT Q:` | "Invalid drive specification!" |
| Bochs (strict CPU), the same disk | C: and both files there; no CPU errors |
| DOSBox, four-task `GO.BAT` | all rc 0, STEST churn/sort 0 bad, all DONE |

## Notes

- **Still to confirm on VMware:** a floppy boot with this `$386.SYS`
  and *without* `/D=4`. Then the switch can go from your CONFIG.SYS.
- **Kernel size, a correction:** the real kernel image is **130,753
  bytes** (map: `FCSEG` ends at 1FFC1h, origin 100h). Your build is
  right. The rig's DEBUG writes the stripped image into the linked EXE
  without truncating it, so my kernels had 768 bytes of the EXE left
  at the end (131,521 bytes). The bytes past 130,753 are never used.
  The kernel md5s in UPDATE 104-107 (`6d83138354ce`, `7dc4ef4ed4bb`,
  `4ddc908eb721`) are of those longer files; compare the first 130,753
  bytes (`head -c 130753`). UPDATE 107's kernel is `7f759e0cfbed`.
- **XMS window at 0D00h/0F00h on VMware:** not a bug. Since UPDATE 86
  the window is placed right behind the driver. With the small FREEMEM
  on VMware the drivers load in low memory, so the window does too.
- **Memory on VMware:** `smpsize` counts one for one in the largest
  program size, and FREEMEM only has C800-DC00 (80K). More upper memory
  only by giving up the EMS page frame at E000.
