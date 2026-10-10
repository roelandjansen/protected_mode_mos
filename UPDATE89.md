# UPDATE 89 -- year 2000 test; DATE with 2-digit years 00-79 (20261010)

Files: `MOXCPINT.ASM` (the shell), CRLF. `$$SHELL.SYS` (`__SHELL.SYS`)
33,913 bytes, md5 `525e7031ca2b`; `TREE=/home/claude/scr ubuild.sh
__SHELL.SYS`, MASM 0 warnings / 0 severe errors. Kernel unchanged
(UPDATE 88, `4be8fcbff98e`).

## Test (UPDATE 88 kernel and shell, rig, floppy A:)

| check | result |
| --- | --- |
| boot prompt `12-31-99`, time `23:59:30`, wait | `Sat 1-01-2000`, `0:00:25` |
| new file after the rollover | DIR `1-01-00 0:00`; Linux `mdir`: **2000-01-01** |
| `date 2-29-2000` (leap, century rule) | accepted |
| `date 2-29-2024`, `2-29-1996` | accepted |
| `date 12-31-2099` | accepted, `Thu 12-31-2099` |
| `date 1-1-2100` | "Date not valid" (limit 2099, as MS-DOS) |
| `date 2-29-24`, `date 1-1-24` | **"Date not valid": bug** |

## Fix

DATE turned a 2-digit year into 19yy, always (`cda14`). `24` became
1924, below 1980, so it was refused: every date typed with a 2-digit
year after 1999 failed, at the boot prompt and on the command line.
Now as MS-DOS: 80-99 -> 1980-1999, 00-79 -> 2000-2079; 4-digit years
unchanged.

| input | before | now |
| --- | --- | --- |
| `2-29-24` | not valid | Thu 2-29-2024 |
| `1-1-79` | not valid | Sun 1-01-2079 |
| `1-1-80` | 1980 | Tue 1-01-1980 |
| `1-1-99` | 1999 | Fri 1-01-1999 |

## Not an issue

- DIR shows 2-digit years (`1-01-00`): display only, the disk has 2000.
- Kernel and FAT dates: 1980-2099 accepted, rollover and leap years
  correct.
- Boot-time date: taken correctly in the rig. Not checked: real
  hardware with an old BIOS RTC century byte.
