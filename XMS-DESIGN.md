# $XMS.SYS -- design (2026-10-09)

An XMS 3.0 driver for PC-MOS/386, as a separate device driver
`_XMS.ASM` -> `$XMS.SYS`. It follows the pattern of `$EMS.SYS` and
`$RAMDISK.SYS`: it reaches the memory manager through the `$$MEMDEV`
call interface and needs no change in `$386.SYS` or the kernel.

## Why a separate driver

`$EMS.SYS` and `$RAMDISK.SYS` already show the way. Open `$$MEMDEV`,
IOCTL-read the far pointer to `rhentry`, then use the memory-device
API:

| `ah` | call | used for |
| --- | --- | --- |
| 01h | `valloc` cx banks -> bx start, cx got (largest block if short) | allocate an EMB; query the largest free block |
| 02h | `vrelease` bx, cx | free an EMB |
| 03h | `vremap` bx bank, cx count, es = 4 KB-aligned segment | map EMB pages into the work window |
| 04h | `vunmap` es, cx | restore the window |
| 12h | `vget0phy` cx = linear page -> edx physical | physical address for Lock (0Ch) |

A bank is a 4 KB page. `valloc` returns contiguous runs, so an EMB is
one run (start bank, page count).

The memory comes from the same pool as tasks, DPMI clients and EMS.
XMS memory is taken when a program allocates it, not reserved at boot.

## CONFIG.SYS

```
MEMDEV=$386.SYS
DEVICE=$XMS.SYS [wwww] [/H:n]
```

| option | meaning | default |
| --- | --- | --- |
| `wwww` | segment of the 8 KB work window, 4 KB-aligned, outside FREEMEM and the EMS frame | none: the window sits in the driver's own resident part (costs up to 12 KB of conventional memory below the tasks) |
| `/H:n` | handles | 32 (8..128) |

The work window is like `$RAMDISK.SYS`'s 16 KB work area (default
B400h). It is two 4 KB pages: source and destination, so an
extended-to-extended move needs no bounce buffer. The page contents
are mapped in and out per move. Nothing is stored in the window.

With the reference setup (`FREEMEM=C0000,E0000`, EMS frame E000) the
recommended form is `FREEMEM=C0000,DE000` plus `DEVICE=$XMS.SYS DE00`:
the window costs 8 KB of FREEMEM instead of conventional memory.

## Interface

- int 2Fh `ax=4300h` -> `al=80h`; `ax=4310h` -> `es:bx` = the far
  entry. Other int 2Fh calls are chained.
- Entry: far call, `ah` = function, XMS 3.0 register conventions.

| fn | function | plan |
| --- | --- | --- |
| 00h | version | 3.00, driver revision 1.00, HMA: none (dx=0) |
| 01h/02h | request/release HMA | `90h` HMA does not exist |
| 03h-06h | A20 global/local enable/disable | succeed (no real A20 under PC-MOS paging) |
| 07h | query A20 | ax=1 (enabled) |
| 08h | query free | largest block / total, KB (valloc probe and release) |
| 09h | allocate EMB, dx KB | valloc, rounded up to 4 KB; `A0h` out of memory, `A1h` no handles |
| 0Ah | free EMB | `ABh` if locked |
| 0Bh | move EMB | ES:SI structure; conventional and extended in any combination, through the window; odd lengths refused (`A7h`) as the spec says |
| 0Ch/0Dh | lock/unlock | lock count; 32-bit physical address via `vget0phy` (checked contiguous) |
| 0Eh | handle info | lock count, free handles, size |
| 0Fh | reallocate | new run, copy, free old (`ABh` if locked) |
| 10h/11h/12h | UMB | `B1h` none available (FREEMEM is PC-MOS's own) |
| 88h/89h/8Eh/8Fh | XMS 3.0 32-bit versions of 08h/09h/0Eh/0Fh | same, with eax/edx |

## Ownership

Handles are system-wide, as in DOS: an EMB stays allocated until it is
freed, also after its program ends. Each handle records the task id
that allocated it. Cleanup when a task is removed (as `$EMS.SYS` does
through `TCBUNREG`) is step 2, not v1.

## Moves

A move processes up to 4 KB at a time: the page holding the next
source byte goes into window page 0, the destination's into page 1
(extended side only; a conventional side is addressed directly). It
runs with interrupts off per chunk and restores the window with
`vunmap` at the end. Overlap within one EMB: copy downwards when
destination > source, as the spec allows (it only guarantees forward
moves).

## Steps

1. Skeleton: device header, init (`$$MEMDEV`, parameters, window),
   int 2Fh hook, functions 00h-08h, 10h-12h. Test client `xmst.c`
   (DJGPP through 0300h/0301h).
2. 09h/0Ah/0Eh/0Fh (+ 32-bit 88h/89h/8Eh/8Fh).
3. 0Bh move, every combination, plus overlap; 0Ch/0Dh lock.
4. Regression (MAXTASK, GO.BAT, EMS alongside), notes, handover.
5. Later: free a removed task's handles.

## Test plan

`xmst.c`: version, query free, allocate 1 MB, move a pattern
conventional -> EMB -> second EMB -> conventional and compare, odd and
unaligned offsets, overlap, lock (physical address, then a DPMI 0800h
mapping of it compared with the data), unlock, reallocate (data
kept), free, handle exhaustion. A real XMS user: if one is available
on your side (a disk cache or a program that requires XMS), run it as
the final check.
