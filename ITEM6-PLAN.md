# ITEM 6 -- more than two hard disks, FAT32: feasibility (20261012)

Checked against the UPDATE 98 kernel (`MOSDDBLF.ASM`, `MOSFUTIL.ASM`,
`MOSFUTL4.ASM`) and the rig emulator. No source change.

## Found on the way: drive 80h must start with a FAT partition

`hinitblk` reads the MBR of drive 80h. **Entry 0** must be one of these
types:

- 01h, 04h, 06h, 0Eh;
- bootable flag 80h or 0.

Otherwise it jumps to `init290`: **no hard disk drive letters at all**.
Neither for drive 80h nor for 81h, and not for logical drives.

Drive 81h has the same rule; there it only drops drive 81h.

**Example:** a disk with a Linux partition (83h) or an EFI or recovery
partition in slot 0, and a FAT16 partition in slot 1 or in the extended
partition. PC-MOS then shows no `C:` at all.

DOS 5/6 instead take the first FAT primary in any slot, and still use
the logical drives when there is none.

**Size:** small, about 60-100 bytes in `initseg` (not resident). It
also helps disks set up with modern tools.

**Proposed as 6a.**

## 6b: more than two hard disks

What limits it to two today:

| place | limit |
| --- | --- |
| `hinitblk` | int 13h 08h count capped at 2; two partition tables on the stack (`pt0`, `pt1`); drive 80h and 81h handled by repeated code |
| extended partition walk (`init100`...) | `cmp dl,81h` / `cmp [drives],2` loops |
| `lbadrv` | 2 bytes (gdata) |
| `i13x` / CHS path | indexes `lbadrv[dl & 1]` |
| HDSETUP | `hard_drives > 2` capped, second drive hard coded (0x81) |
| rig | DOSBox Staging: `MAX_HDD_IMAGES 2` (`include/bios_disk.h`); `imgmount` only 2/3 |

**Work:**

- **Kernel:**
  - turn the drive 80h/81h code in `hinitblk` and the extended walk
    into a loop over N drives (N = 4 is enough: BIOSes of the era
    report up to 4);
  - partition tables in an `N*64` stack block;
  - `lbadrv[N]`, indexed `dl & 3`.
  - All of this is in `initseg` except `i13x`, so resident growth is a
    few bytes (`lbadrv` +2, gdata).
  - Drive letter order as DOS: primaries of all drives first, then the
    logical drives drive by drive.
- **HDSETUP:** the drive list is already a linked list. Only the probe
  (08h count, second drive hard coded) changes. The F2 "change drive"
  and `drive_num` (byte, 0/1 in places) need a check.
- **Rig:** patch DOSBox `MAX_HDD_IMAGES` to 4, plus the BIOS 40:75 count
  and `imgmount 4/5`. About 20 lines. Without it there is no test.

**Estimate:** medium, 2 updates (kernel, HDSETUP) plus the emulator
patch. Low risk for existing setups: with 1 or 2 disks the loop does
the same as today.

## 6c: FAT32

What FAT32 needs in the kernel, all resident (`mos`/`mo2`):

| area | change |
| --- | --- |
| BPB/DPB | FAT32 BPB (`bpb_FATSz32`, `RootClus`, `FSInfo`); DPB with 32-bit cluster count and FAT size (DOS 7.1 extended DPB) |
| cluster numbers | 16-bit everywhere: directory entries (`dirclst` + the high word at offset 20), FCB/SFT fields, the cluster cache, `cmap`/`cfree`, `fat12`/`fat16` readers (`MOSFUTL4`), chain walking (`MOSFUTIL`, ~116 places mention clusters), `MOSFUN39` (76), `MOSFUN0F` |
| root directory | is a cluster chain, not a fixed area: every "root" special case in the directory code |
| free space | FSInfo sector, 32-bit free counts; int 21h 36h saturates, 7303h (extended free space) new |
| API | int 21h 7302h (get extended DPB), 7304h/7305h (absolute disk read/write) |
| utilities | FORMAT (FAT32 layout), CHKDSK/fatchk, DIRMAP, HDSETUP type 0Bh/0Ch |

**Size:** easily 3-6 KB of resident code.

- `mos` has 1,426 bytes free.
- `mo2` is about 118 bytes from its next 8 KB step.

So FAT32 needs the shrink plan's phase 3 (evicting a code block)
first, or it costs a full 8 KB step of every task's memory (MAXTASK
564K → 556K).

**Estimate:** large, 8-12 updates, high risk (every file system path).
The FAT16 limit of 2 GB per partition is the practical gain. With
6a/6b and LBA, a big disk already works as many 2 GB drives (C: to Z:,
24 letters: about 48 GB).

## Recommendation

1. **6a now:** small, real compatibility gain, no resident cost.
2. **6b next:** medium, all in init code; needs the emulator patch first.
3. **6c parked:** cost too high for the gain while `mos`/`mo2` are this
   tight. Revisit only after shrink phase 3 frees an 8 KB step.
