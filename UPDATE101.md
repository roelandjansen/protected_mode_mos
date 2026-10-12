# UPDATE 101 -- hard disks: the primary partition may be in any slot (20261012)

Files: `MOSDDBLF.ASM` (kernel), CRLF.

- `$$MOS.SYS` 131,233 bytes, md5 `d2b903c9957f` (UPDATE 84-100 + this).
  Built with `TREE=/home/claude/scr kbuild.sh MOSDDBLF`.
- Resident size unchanged: MOSSEG 0FA6Eh, `CLOBBER` 0F202h, DDT ends at
  0CC89h. Only `initseg` grew. MAXTASK is unchanged.

Item 6a of `ITEM6-PLAN.md`.

## The problem

`hinitblk` required **partition table slot 0** of drive 80h to be FAT
(01h, 04h, 06h, 0Eh) with a bootable flag of 80h or 0.

- If not, the driver gave up: **no hard disk drive letters at all**,
  also not for drive 81h and not for logical drives.
- Drive 81h had the same rule; there it only dropped drive 81h.
- A disk with a Linux, EFI or recovery partition in slot 0 therefore
  showed no `C:` in PC-MOS.
- DOS takes the first FAT primary in any slot, and still uses the
  logical drives when there is none.

## What changed (all in `initseg`)

- **`pickpri` (new):** finds the first FAT entry in slots 0-3 of a
  copied partition table and swaps it into slot 0, where the rest of
  `hinitblk` expects the primary partition. It returns the original
  slot, or 0FFh when there is none. It is used for drive 80h and drive
  81h. The bootable flag of slot 0 is no longer checked.
- **A drive without a FAT primary** gets no primary drive letter, but
  its logical drives are still used.
  - Every dib is now opened with `next_dib`, so the first one no longer
    has to be the primary of drive 80h.
  - `dib_cnt` starts at -1, and `dib_ptr` one dib before the first.
  - When no dib at all was made, the init reports no units, as before.
- **The extended partition is looked for in all four slots** (it was
  slots 1-3), because slot 0 may now hold it.
- **Boot drive:** when the primary came from slot 1-3 of drive 80h,
  `trueboot` maps that slot to `C:`. `MOSINIT2` uses `trueboot` to turn
  "booted from partition 2-4" into a drive letter.

Drive letter order is unchanged:

1. primary of 80h;
2. primary of 81h;
3. logical drives of 80h, then of 81h;
4. the other FAT primaries of 80h, then of 81h.

## Tests (`PM_ROOT=/home/claude/scr`, images made with `mkpt` + `mformat`)

| disk | old kernel | UPDATE 101 |
| --- | --- | --- |
| slot 0 Linux (83h), slot 1 FAT16 `SLOT1`, slot 2 extended with logical `LOGI1` | `C:` and `D:` "Invalid drive identifier" | `C:` = `SLOT1`, `D:` = `LOGI1` |
| slot 0 Linux, slot 1 extended (0Fh) with 0Eh logical `LOGI2`, no FAT primary | (no drives) | `C:` = `LOGI2`, `D:` invalid |
| 2 GB, C: D: E: made by HDSETUP (UPDATE 100 test disk) | | `C:` `CEE`, `D:` `DEE`, `E:` present, `F:` none: unchanged |
| 20 GB, 1 MiB aligned (UPDATE 100 test disk) | | `C:` `PRIM` ... `F:` `LOGI` at 9.5 GB: unchanged |
| four-task `GO.BAT` | | all rc 0, STEST churn/sort 0 bad, all DONE |

**Not tested:** booting PC-MOS from a primary in slot 1-3, which is the
`trueboot` path. The rig boots from floppy.
