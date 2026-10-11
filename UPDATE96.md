# UPDATE 96 -- RTC century at boot; MSYS on big volumes (20261011)

Files: `MOXCPCOR.ASM` (the shell), CRLF. `$$SHELL.SYS` (`__SHELL.SYS`)
33,929 bytes, md5 `fd83d62c681c`, `ubuild.sh __SHELL.SYS`, MASM 0
warnings / 0 severe errors. Kernel as UPDATE 95.

## Century at boot (item 5 of the list, code read)

The kernel never reads the date. The primary shell of task 0 (`/P`)
does, in `MOXCPCOR.ASM`:

1. int 1Ah AH=04h;
2. BCD to binary;
3. year = century * 100 + yy;
4. `setdate`.

- CH=0 (no RTC) skips it.
- A BIOS from before 2000 with a CMOS century byte that never went to
  20 returns 19 with yy=26: year 1926. That is below 1980, `setdate`
  refuses it, and the system starts with whatever date it had. A
  well-known Y2K BIOS fault.

**Fix:** a year below 1980 from the RTC gets 100 added (yy 00-79 ->
20yy). That is the same window as DATE since UPDATE 89. 4 instructions.

Test: normal boot shows the correct date (`Sun 10-11-2026`). The faulty
BIOS case was not reproduced: DOSBox's RTC returns century 20.

## MSYS

`MSYS` (shares `scan_partitions` with FORMAT, UPDATE 95):

| case | result |
| --- | --- |
| `MSYS C:` on the 2 GB volume (old and new MSYS) | MOS boot sector written ("TSL 5.01"), BPB kept, no output (as before) |
| `MSYS D:` on a logical drive at 8.7 GB | nothing written, no message; same with the original MSYS (a logical drive cannot boot). No sector outside C: changed |

## Rig: four-task GO.BAT no longer completes here

After a container restart (now 2 vCPUs), the four-task `GO.BAT` stalls:

- T0 stays at "parent starting W4XTEST DJHELLO";
- a DPMI client (selector 02A3h) is busy, even after 25 minutes.

It is the same with the UPDATE 91 kernel and shell, and with the
original emulator binary, in both dynamic and normal core. So it comes
from the environment, not from UPDATE 92-96. It needs its own look
(timing-dependent: `cycles=max` on a slower host). Until then the
regression for UPDATE 96 is a normal boot only.
