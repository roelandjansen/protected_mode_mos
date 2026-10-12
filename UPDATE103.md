# UPDATE 103 -- $386.SYS stages int 13h 42h/43h (hard disk DMA under paging) (20261012)

Files: `_386.ASM`, CRLF.

- `$386.SYS` 38,096 bytes, md5 `43a8aaa323b8`, built with
  `TREE=/home/claude/scr dosbuild.sh _386`.
- The kernel is unchanged.

## The problem (found in a VMware Workstation VM)

On VMware, with `MEMDEV=$386.SYS` in `CONFIG.SYS`:

- `FORMAT C:` reported a correct size, but `DIR C:` then listed garbage
  entries (`stacksta.cks`, `tackstac.kst`). That is the shell's stack
  fill pattern from `MOXCPDAT.INC`, i.e. memory, not disk data.
- After `MSYS C:` and copying the system, booting from the disk gave
  the MBR's "Invalid boot signature".
- **Without `$386.SYS`** the same steps worked, and PC-MOS booted from
  C:.

**Cause:**

- Since UPDATE 93 the kernel reads and writes hard disks with int 13h
  42h/43h when the BIOS has the extensions.
- Under `$386.SYS`, memory above `dmabank` is remapped by paging, so a
  buffer's address is not its physical address.
- A BIOS that transfers with **bus-master DMA** uses physical addresses.
  VMware's does; so do many real machines. Reads land in the wrong
  memory, and writes take the wrong data.
- `$386.SYS` already solves this for the old calls with its staging
  (bounce) buffer: `entinr13`, always for floppies, for hard disks with
  `/P`, `/M`, `/E`, `/X` or `/D=nn`. But only for functions 00h-1Bh;
  42h/43h passed straight through.
- DOSBox does not do DMA, so the rig never showed it.

## Fix

**`entinr13`** sends 42h/43h to the new **`x13ext`**, before the
diskette/hard disk switch. So it applies to every disk, with or without
a `$386` switch:

- **Pass-through:** the end of the caller's buffer is computed as
  segment + offset/16 + count×32 paragraphs. If it is below `dmabank`,
  the call is passed through unchanged (`i13pass`), as for the other
  functions.
- **Staging:** otherwise the transfer goes through the staging buffer
  in pieces of up to `buffsize`, one int 13h call per piece, using its
  own disk address packet:
  - a write copies the caller's data into the buffer before its call;
  - a read copies from the buffer to the caller after its call;
  - each piece advances the 64-bit sector number and the caller's
    segment.
- **Errors:** the error code and carry are returned as the BIOS gave
  them, and the caller's packet count is set to the sectors done (as
  the extensions specify).

The new data (packet, counters) is about 30 bytes in the `$386` data
area. The code is about 400 bytes.

## Tests (rig, `PM_ROOT=/home/claude/scr`)

| test | result |
| --- | --- |
| test build that **always** stages (pass-through disabled), 2 GB disk with C:, D:, E:: `COPY` 700,000-byte random file A: → C:, C: → D: | both copies md5 `7b79f512c665`, identical to the original (checked with mtools on the image) |
| same build: the staging counters read from guest memory after the copy (via a marker, test build only) | `xdone` = 4, `xleft` = 0: the staged path ran |
| final build: four-task `GO.BAT` | all rc 0, STEST churn/sort 0 bad, all DONE |
| final build: 20 GB disk, LBA, `DIR C:` / `F:` (9.5 GB) | correct |

Not testable in the rig: real DMA.

**Confirmed on VMware Workstation (20261012):** with this `$386.SYS` and
`MEMDEV=$386.SYS` in `CONFIG.SYS`, the whole install ran through the new
code: HDSETUP, `FORMAT C:`, `MSYS C:` and `COPY *.* C:` from the floppy
(with `$386.SYS` loaded), then a boot from C:. Reads and writes are
correct under real DMA.

## In the VM

1. Rebuild (`build.sh`) and make the floppy (`makefloppy.sh --all`). Its
   `CONFIG.SYS` has `memdev=$386.sys` again.
2. Boot from the floppy, then `DIR C:` on the disk you already
   installed. It should show the files, not garbage.
3. Copy the new `$386.SYS` to C:, add `MEMDEV=$386.SYS` to C:'s
   `CONFIG.SYS`, and boot from C:. Then copy and compare a few files
   (`COPY`, then `COMP` or `TYPE`).

If it still shows garbage, `$386.SYS` with `/P` is the next thing to try:
it stages the CHS calls (02h/03h) as well. The kernel only uses those
on a disk without extensions.
