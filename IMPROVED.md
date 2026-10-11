# PC-MOS/386 v5.01 -- what has been improved

Summary of the work recorded in `CHANGES.md`, `HANDOVER.md` and
`UPDATE62.md` .. `UPDATE97.md` (state 20261011). Per item: the update
number where the detail lives. UPDATE 90 is not in the archive.

Short version: PC-MOS/386 now has a **working DPMI 0.9 host** (DJGPP,
DOS/4GW and DOS/32A run real programs, nested and in several tasks at
once), a new **XMS 3.0 driver**, **disks up to 2 TB addressable via int
13h extensions** with 2 GB FAT16 partitions, a set of **DOS API
compatibility fixes**, **Y2K fixes** in DATE and at boot, and files and
directories made by other systems (FreeDOS, Windows, mtools) no longer
get a random security class.

---

## 1. Added -- new functionality

### DPMI host (`$386.SYS` + `$DPMI.SYS`)

| what | update |
| --- | --- |
| `$DPMI.SYS` installs for the first time (it never worked in the shipped 5.01) | 14 |
| DPMI clients enter protected mode on their own code selector (int 6Fh `778Eh` CODE_SELECTOR) | 15-16 |
| Client descriptor lifetime: own ownership class, freed at program end (`778Fh`) | 17, 19 |
| Protected-mode int 21h translation (09h, 0Ah, 48h/49h/4Ah, 4Ch, DTA calls 1Ah/2Fh/4Eh/4Fh, 42h, 5Ch) | 18-35, 80, 82 |
| int 31h wired up and implemented: descriptors (0000h-000Ch), DOS memory (0100h-0102h), vectors (0200h-0205h), real-mode calls (0300h-0302h), callbacks (0303h/0304h), 0305h/0306h, memory (0500h-0503h), 0600h-0604h, 0702h/0703h, 0800h, 0900h-0902h -- **DPMI 0.9 function set complete** | 36-61, 81 |
| Exception handlers (0202h/0203h), hardware IRQ delivery to clients | 54-55, 66 |
| Real-mode callbacks | 56-60 |
| 32-bit vs 16-bit clients handled correctly (frames chosen by client type) | 62, 82 |
| **Real extenders run**: DJGPP (GCC 12.2), DOS/4GW 1.97, DOS/32A 9.1.2 | 63-65 |
| Per-client ownership with client ids; nested clients 3 levels deep | 67 |
| Multiple tasks with DPMI clients at once (four-task `GO.BAT`) | 68-69 |
| int 31h 0800h physical address mapping (VBE linear framebuffer works, `LFBDRAW`) | 81 |
| Exception lookup via per-client bitmap | 85 |

### New drivers / tools

| what | update |
| --- | --- |
| `$XMS.SYS` -- XMS 3.0 driver on top of `$386.SYS` (alloc/free/move/lock/realloc, per-task cleanup on `REMTASK`) | 86 |
| `DPMITST.COM`, `DPMI32.COM` -- DPMI test clients | 15, 62 |
| ADDTASK prints the current maximum task size on errors / usage | 70, 85 |

### Disk support

| what | update |
| --- | --- |
| 2 GB FAT16 "big" volumes verified working (read, write, free space) | 87 |
| int 13h extensions (LBA, 41h/42h/43h): partitions beyond 8.4 GB reachable, 32-bit sector numbers (2 TB) | 93 |
| Extended partitions beyond 8.4 GB; partition types 0Eh / 0Fh accepted | 94 |
| `FORMAT` works on 2 GB and LBA partitions; generic IOCTL track calls beyond 8.4 GB | 95 |

### DOS API

| function | before | now | update |
| --- | --- | --- | --- |
| 60h TRUENAME | returned last opened file name | canonical path (DOS 3+) | 88 |
| 6501h, 6520h-6523h | invalid function | country info, upper-case, yes/no | 88 |
| 6601h/6602h | invalid function | code page 437 | 88 |
| 5802h/5803h | error | DOS 5 behaviour without UMBs | 88 |
| 6900h/6901h | silently did nothing | disk serial / label / FS type | 91 |
| int 2Fh 1A00h | "no ANSI" | FFh when console ANSI is on | 92 |
| MCB owner names | never written | written by EXEC (FreeDOS `MEM` shows names) | 87 |

---

## 2. Fixed -- bugs in the original TSL code or the kernel

### `$DPMI.SYS` / `$386.SYS` (original defects)

- Messages printed memory garbage: MASM `OFFSET` is segment-relative, not group-relative (CHANGES §2, 10, 14, 15).
- `CheckMOS` reported success on failure (`stc` commented out) (CHANGES §3).
- MOS 5.x version check rejected real MOS (written against 4.10) (CHANGES §4).
- MASM silently truncates `eax` to `ax` in USE16 segments -- `memman` far pointer half-written (UPDATE 2).
- `lea` on USE32 labels from 16-bit code desynchronised the instruction stream (`ENTER 0E9C1h,12`) -- corrupted return address (UPDATE 10).
- use32 -> use16 calls encoded with `66h` + rel32: #UD and 2-byte stack leak per call; fixed with wrappers (UPDATE 14). Five bugs of this class found in total.
- int 6Fh `7780h`-block not dispatched at all -> jumped through never-hooked vector, crashed emulator (UPDATE 1).
- `memman` never initialised (UPDATE 1); `InitProtect` `rep movsd` with ESI/EDI/ES never set (UPDATE 14).
- `GoProtect`: wrote through CS in protected mode, wrong selector register, no carry test after the switch (UPDATE 15-16).
- A TSL #GP bug in exception handling (UPDATE 55).
- Host under-reported its data size; live descriptor in a free slot (UPDATE 29-33).

### DPMI host (found with real extenders)

| bug | update |
| --- | --- |
| `cidtagsw` took task id from clobbered `esi` (multi-user) | 68 |
| `NLDW` + `eax` bugs, five sites | 71-72 |
| .COM client after another client got its PSP as DS | 78 |
| DOS/4GW clock wrong (selector 0040h now = BIOS data area) | 79 |
| 16-bit client int 21h crashed the host (high words not cleared) | 82 |
| DJGPP SIGFPE / SIGILL never delivered (handler overwrote the exception frame) | 85 |

### Kernel (`$$MOS.SYS`)

| bug | update |
| --- | --- |
| Commit (68h) on a character device | 66 |
| Compat-mode read open vs deny-write share conflict (DJGPP "can't open") | 83 |
| EXEPACK pad block owned by shell -> 13.6 KB lost after first DJGPP program | 84 |
| Max task size wrong without memory manager (911K reported, ~389K real) | 85 |
| Generic IOCTL *read* calls marked media changed -> hidden int 24h "general failure" wait | 92 |
| EBR chain assumed packed partitions | 94 |
| FORMAT beyond 8.4 GB wrote boot sector/FAT at a wrapped CHS address (**data loss**) | 95 |
| Set device parameters re-read boot sector via CHS -> garbage BPB | 95 |
| Directory entries written by DOS 7 / Windows / FreeDOS / mtools got a random security class from their creation-time byte -> read-only or "Access not allowed"; class now only counts with the system attribute | 97 |

### Shell (`$$SHELL.SYS`) and utilities

| bug | update |
| --- | --- |
| DIR: "Divide by zero" on files >= 1 GB and totals >= 1 GB | 87 |
| `hibin2dec` lost leading zeros (`1, 64,042,496`) -- 1992 bug | 87 |
| DATE: 2-digit year always 19yy -> every date after 1999 refused | 89 |
| Boot: RTC century 19 on old BIOS -> wrong date; now windowed 00-79 = 20yy | 96 |
| DIR: junk in CLS / USER columns for entries made by other systems | 97 |
| FILEMODE: "Syntax error" with redirected output (trailing blank) | 97 |
| FORMAT: cylinder count / bad-track check overflow > 2 GB; BPB size past partition end | 95 |
| FORMAT/MSYS `scan_partitions`: 0Eh/0Fh, LBA, DOS EBR chain rule | 95 |

---

## 3. Improved -- performance and resources

| what | result | update |
| --- | --- | --- |
| int 31h hook lookup (`hookhwm`) | 10x cheaper | 69 |
| 0300h call cost | 479 -> 401 monitor instructions | 75-77 |
| Fast paths for 0300h-0302h, 0501h-0503h, 0900h-0902h, vectors 08h-E5h | | 76-77 |
| Default stubs and hook table moved to extended memory | +16 KB per task | 71, 73 |
| Max task size | 596 KB with `$386.SYS` | 71-82 |
| Hard-disk init code moved out of resident `mos` | 1,160 bytes less HMA, MOSSEG room 34 -> 1,194 bytes | 93 |
| Hook table 320 -> 1024 entries | | 67 |
| Class lookup through one helper (`dclasslvl`) | `mo2` 38 bytes smaller | 97 |

---

## 4. Cleaned up

- All diagnostic markers removed from `_386.ASM`, `_DPMI.ASM`, `MOSDDINT.ASM`, `MOSINIT2.ASM`; boot screen clean (UPDATE 11-13).
- Project-added `DevLoadMsg` removed; original sign-on restored (UPDATE 11).
- Stale binaries in the tree identified; builds now reproducible (same md5 in two containers).

---

## 5. Known limits / open

- One `GO.BAT` run in twelve: DOS/4GW task stuck after banner (not attributed).
- Four-task `GO.BAT` on the 2 vCPU rig: too slow with the debug emulator; passes with the release build (UPDATE 96-97).
- FAT16 2 GB per partition; no FAT32, no LFN; max two hard disks.
- `HDSETUP` still makes 32 MB CHS volumes -- partition with another tool.
- `mo2` has ~118 bytes before the next 8 KB per-task step (UPDATE 97).
- #GP delivery not testable under DOSBox; needs real hardware.
- 6502h-6507h table pointers left out (cost 8 KB per task).
- MSYS on logical drives: does nothing (same as original).
- Directories classed through int 38h 83h before UPDATE 97 without the system attribute are now unclassified; set the class again.
