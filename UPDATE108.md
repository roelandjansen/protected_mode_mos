# UPDATE 108 -- $DPMI.SYS wrote through its code segment (VMware hang) (20261014)

Files: `latest/_DPMI.ASM`, CRLF.

Rig: `pmrig-toolkit.tar.gz` with `rig/bochs.sh` (new) and `RIG.md`
("Bochs: a strict CPU").

Build:

- `$DPMI.SYS` 5,164 bytes, md5 `8d4b8b1c903b`, built with
  `TREE=/home/claude/scr dosbuild.sh _DPMI`.
- MASM 0 severe errors, 4 warnings (as before).
- Kernel and `$386.SYS` unchanged.

## The problem

On VMware Workstation, PC-MOS stopped at `Dos Protected Mode Interface`
as soon as `$DPMI.SYS` was loaded, with or without FREEMEM, EMS or XMS.
Sometimes it hung; sometimes garbage followed, or VMware stopped the VM
with "tried to execute an invalid part of memory".

The cause is in `InitProtect`, the driver's first code in native mode
(privilege level 3):

```
0021  2E: C6 05 00000256 R    mov [Bit32Ok],'Y'
```

`init32` only had `assume cs:ddt`, so MASM put a **CS: override** on the
store. In protected mode a code segment is never writable; a real CPU
answers with #GP(0). That fault came back to V86 mode with a wrong
frame, and the boot hung.

QEMU (TCG) and DOSBox do not check this, so the driver always worked
there.

## How it was found

1. **Diagnostic builds on VMware** (marks written straight into video
   memory) narrowed the stop down to `InitProtect`, then showed the
   fault itself: `#GP, error code 0000, EIP 00001461, CS 0083`. EIP 1461
   is offset 21h in `init32`: the store above.
2. **Bochs** checks protection like a real CPU. It reproduces the hang
   here (`write_virtual_checks(): no write access to seg`, then millions
   of `read beyond limit`). Its debugger stops at the exact instruction:

   ```
   cs:0x0083  Code segment, base=0x000cade0, Execute/Read
   ds:0x0063  Data segment, base=0x000cade0, Read/Write
   next:      mov byte ptr cs:0x00001126, 0x59
   ```

## The same flaw elsewhere

The resident 32-bit code (`code32`, runs when DPMI clients call int
31h) had the same 1991 design: it wrote its own variables through CS.

- **`Interupt31`:** set `ds = cs` (`mov ax,cs` / `mov ds,ax`), then
  wrote through DS: `[Function]` on every call, `[DataSel]` in
  `GetDataSelector`.
- **`ScanBanks`:** `mov [SmallestBank],...` with a CS: override
  (`assume ds:nothing`), on memory allocation.

## Fix

- **`init32`:** `assume cs:ddt,ds:ddt`. `Bit32Ok` is now written
  through DS, which `nmswitch` builds as a writable data descriptor
  over the driver segment (the same base as CS).
- **`DrvData` (new, in `code32`):** a data selector for the driver
  segment. `Init32Code` gets it in V86 mode with int 6Fh
  `SEGMENT_SELECTOR`, the same way as `scbsel`.
- **`Interupt31`:** `mov ds,cs:[DrvData]` instead of `ds = cs`. Reading
  through CS stays; writing goes through the data alias.
- **`ScanBanks`:** `assume ds:ddt` around the procedure, so
  `SmallestBank` goes through DS. `assume ds:nothing` is restored after
  it, as it was.

All remaining CS: stores are in `code16`/`init16`, which run in V86
mode, where that is legal.

## Tests

**Bochs** (strict CPU), 16 MB:

| configuration | UPDATE 107 | UPDATE 108 |
| --- | --- | --- |
| `memdev=$386.sys`, `$DPMI.SYS` | hangs at `Dos Protected Mode Interface`; 1 write error, then 9.3 million limit errors | `Installed.`, `[A:\]`; no CPU errors |
| same, AUTOEXEC: DJHELLO, DJXTEST, DJSTEST, W4HELLO (DOS/4GW), W4XTEST, WAHELLO and WAXTEST (DOS/32A) | | all run, STEST churn/sort 0 bad, `ALL DONE`; no CPU errors |
| your VMware configuration (FREEMEM `C0000,E0000`, DPMI, EMS, XMS) plus the same clients | | all drivers installed, all clients run; no CPU errors |

**DOSBox**, four-task `GO.BAT`: all rc 0, STEST churn/sort 0 bad, all
DONE.

**QEMU**, your configuration: FREEMEM `CD00,E000`, DPMI, EMS and XMS
installed, `[A:\]`.

## Notes

- **XTEST:** in the Bochs tests it was started without arguments, so it
  only printed its usage line. The nested case (`DJXTEST DJHELLO`) runs
  in `GO.BAT` under DOSBox.
- **Diagnostic builds:** the early deaths before the DPMI banner seen
  on VMware came from my diagnostic `$386.SYS` builds; the committed
  `$386.SYS` did not show them.
- **Rig:** Bochs now covers this class of bug (write-protected code
  segments, segment limits, descriptor rules) without VMware. See
  `RIG.md`.
