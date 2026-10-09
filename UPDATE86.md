# UPDATE 86 -- $XMS.SYS: XMS 3.0 for PC-MOS/386 (2026-10-09)

New device driver `_XMS.ASM` -> `$XMS.SYS`, 4,452 bytes, md5
`4ce0279c7f53`. MASM 5.10, 0 warnings, 0 severe errors. No change to
the kernel or `$386.SYS`. Design: `XMS-DESIGN.md`.

Build: `MAKEUTIL.MAK` (in `ALL`, plus a `_XMS.SYS` dependency line) and
`BOSMAKE.BAT` (`ren _XMS.SYS $XMS.SYS`). In the rig:
`ubuild.sh _XMS.SYS`.

## Use

```
MEMDEV=$386.SYS                  ; required, before $XMS.SYS
DEVICE=$XMS.SYS [wwww] [/H:n]
```

| option | meaning | default |
| --- | --- | --- |
| `wwww` | 8 KB work window segment, 4 KB aligned (e.g. `DE00`) | inside the driver |
| `/H:n` | handles, 8..128 | 32 |

The boot line shows where the window went:
`PC-MOS XMS 3.0 Driver v1.00 (UPDATE 86) installed, window C400h, 32 handles`.

**Leave the window at its default.** The driver itself is loaded into
FREEMEM, and the default window follows it there (C400h in the
reference setup). Task size is unchanged:

| CONFIG.SYS (reference setup, smpsize=56) | MAXTASK |
| --- | --- |
| without `$XMS.SYS` | 564K |
| `DEVICE=$XMS.SYS` (window C400h, default) | **564K** |
| `FREEMEM=C0000,DE000` + `DEVICE=$XMS.SYS DE00` | 544K |

`XMS-DESIGN.md` expected the opposite, but cutting FREEMEM pushes
other things into task memory. `wwww` stays for setups without
FREEMEM room.

## What it does

- int 2Fh `4300h` -> `80h`; `4310h` -> entry. Other int 2Fh calls are
  chained. The entry starts with `jmp short` + 3 `nop`s (hookable, as
  the spec requires).
- The memory comes from `$386.SYS`'s page pool through the memory
  device (`$$MEMDEV`: valloc/vrelease/vremap/vunmap/vget0phy), like
  `$EMS.SYS` and `$RAMDISK.SYS`. It is taken only on allocation. An
  EMB is one contiguous run of 4 KB banks.

| fn | status |
| --- | --- |
| 00h | 3.00, revision 1.00, no HMA |
| 01h/02h | `90h` HMA does not exist |
| 03h-07h | A20: succeed / enabled (paging; A20 means nothing here) |
| 08h / 88h | largest free block and the real total (the free runs are taken one by one, up to 16, counted and given back) |
| 09h / 89h | allocate, rounded up to 4 KB; zero length allowed; `A0h`/`A1h` |
| 0Ah | free; `A2h`, `ABh` if locked |
| 0Bh | move, all four combinations, any alignment, through the window one 4 KB page per side per chunk (interrupts off per chunk); overlap within one block with destination above source runs downwards; `A3h`-`A7h` |
| 0Ch/0Dh | lock (32-bit physical in DX:BX via `vget0phy`, checked contiguous, else `ADh`; `ACh` overflow) / unlock (`AAh`) |
| 0Eh / 8Eh | handle info |
| 0Fh / 8Fh | reallocate: shrink frees the tail, grow copies to a new run; data kept; `ABh` if locked |
| 10h-12h | `B1h` no UMBs (FREEMEM is PC-MOS's own) |

## Task removal

Handles are system-wide, as in DOS: an EMB survives its program. When a
**task is removed**, `$XMS.SYS` frees every EMB that task allocated,
locked ones too. It uses the kernel's per-task removal hook (`tcbunreg`,
called by `MOSRTASK`) the way `$EMS.SYS` does. On a task's first
allocation, the handler that was there is kept and chained.

## Known limits

- 88h returns ECX = FFFFFFFFh (the highest ending address is not
  tracked; informational).
- No HMA, no UMBs (by design).

## Tests (rig, UPDATE 85 kernel + `$386.SYS`, reference CONFIG.SYS + `DEVICE=$XMS.SYS`)

`xmst.c` (DJGPP, the XMS entry through 0301h): **45 ok, 0 bad.**

- detection, version, HMA/A20/UMB answers
- 08h/88h; allocate 1024 KB and 3000 KB (89h), info (0Eh/8Eh), free,
  free again (A2h), all memory back
- handles: 32 zero-length EMBs, then A1h
- 0Bh: conventional -> EMB at offset 4093 (page crossing) -> EMB at
  8191 -> conventional, 30,000 bytes identical; conventional ->
  conventional
- 0Bh overlap in one EMB, up by 6000 (runs downwards) and down by
  5998: data intact
- 0Bh errors: odd length A7h, bad handles A3h/A5h, past the end A7h,
  offset beyond A4h
- 0Ch lock: physical 00206000. **Checked from outside:** the emulator's
  physical memory at that address (gdb `MemBase`) holds exactly the
  test pattern. DPMI 0800h cannot check this from inside: it maps only
  addresses outside RAM (UPDATE 81).
- locked free ABh, lock count 1, unlock, unlock again AAh
- 0Fh grow 64 -> 512 KB and shrink -> 32 KB: data kept

Regression with `$XMS.SYS` loaded:
- `emst` 0 bad (EMS alongside);
- the four-task `GO.BAT`: all rc 0, STEST 0 bad, all DONE;
- with the DE00 window, `xmst` 45 ok as well.

## Files

- `_XMS.ASM`: the driver, CRLF.
- `MAKEUTIL.MAK`, `BOSMAKE.BAT`: build lists, CRLF.
- `xmst.c`: the test client; `xmsl.c`: query free / allocate-and-keep (task removal test).
- `XMS-DESIGN.md`: the design (its window-cost guess is corrected
  above).

## Task removal test (`xmsl.c`, `L.BAT` = `XMSL 2048 > L.TXT`)

```
[A:\]xmsl
XMSL: free largest 14440 KB total 14440 KB
[A:\]addtask 300,2,,l.bat          ; task 2 allocates 2048 KB, exits, keeps it
[A:\]xmsl
XMSL: free largest 11880 KB total 11992 KB
[A:\]remtask 2
[A:\]xmsl
XMSL: free largest 14440 KB total 14440 KB
```

After the cleanup changes: `xmst` 45 ok, 0 bad (lock address checked
again from outside); MAXTASK 564K; four-task `GO.BAT` all rc 0, STEST 0
bad, all DONE.
