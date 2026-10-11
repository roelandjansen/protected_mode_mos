# UPDATE 97 -- foreign directory entries no longer get a random class; FILEMODE with redirection (20261011)

Files, CRLF:

- kernel: `MOSFUTL2.ASM`, `MOSFUN0F.ASM`, `MOSFUN39.ASM`, `MOSFUTIL.ASM`,
  `MOSMIMAN.ASM`, `MOSINT38.ASM`, `MOSFUTL4.ASM`;
- shell: `MOXCPINT.ASM`;
- utility: `FILEMODE.ASM`.

| file | bytes | md5 |
| --- | --- | --- |
| `$$MOS.SYS` | 131,121 | `18dad9596a09` |
| `$$SHELL.SYS` | 33,945 | `262b64e2992f` |
| `FILEMODE.COM` | 1,758 | `3a6f92a42a30` |

MASM 0 warnings / 0 severe errors. `mo2` (DDT) ends at 0CC89h, 38 bytes
**smaller**. MOSSEG 0FBDEh.

## The problem

PC-MOS keeps a security class in directory entry byte 13, the user id
in 14-17 and the creation time and date in 18-21. DOS 7, Windows,
FreeDOS and mtools use the same bytes for:

- creation time tenths (byte 13, 0-199, often 'A'-'Z');
- creation time and date (14-17);
- access date (18-19);
- the FAT32 high cluster (20-21).

A file or directory written by another system could therefore get a
random class. With the default class map (0AAh, level 2) that means
**read-only**, or no access at all with a stricter map. Test: a
directory made by mtools with byte 13 = 'B'.

| | `COPY ... C:\FOREIGN` |
| --- | --- |
| UPDATE 96 kernel | "Access not allowed" |
| UPDATE 97 | copied |

DIR showed junk in the CLS and USER columns (`B  L.K]`).

## The rule

**PC-MOS sets the system attribute on every entry it gives a class**
(`maken` in `MOSFUTIL.ASM`). So the class byte only counts when the
entry has the system attribute. Entries without it are unclassified.

### Kernel

- New `dclasslvl` (`MOSFUTL2.ASM`, `mo2`): reads the class of
  es:[dbbbuf+si], treats it as none without the system attribute, then
  calls `classlvl`. It replaces "mov al,[dbbbuf+si+dclass0] / call
  classlvl" at 12 places:
  - `MOSFUN0F` 3, `MOSFUN39` 6 (chdir, delete, attributes, find,
    rename...), `MOSFUTIL` 2, `MOSMIMAN` 1;
  - `MOSINT38` function 83h (access level), through `callmos2`.

  That is 4 bytes less per place.
- `MOSFUTL4` (class of an open file, `gfbclass`) and `MOSINT38` 8Dh
  (path class): the same check.
- `MOSINT38` 83h "set" on a directory: a non-blank class also sets the
  system attribute, so classes given later keep the rule. Files cannot
  change class there, as before.
- `MOSINT38` 83h "get": returns class 0 for entries without the system
  attribute.

### Shell (`DIR`)

- The CLS column needs the system attribute.
- USER is shown only when there is a creation date (bytes 20-21; 0 on
  FAT16 entries written by other systems).

### Caveat

A directory that was given a class before this update without the
system attribute (only possible through int 38h 83h on a directory) is
now unclassified. To restore it, set its class again, or set the
system attribute. Files with a class always had the attribute.

## FILEMODE

The shell leaves a blank at the end of the command tail when output
is redirected. `FILEMODE +r file >out` then said "Syntax error". It now
drops trailing blanks and tabs first.

## Tests

On the 2 GB volume:

- `FOREIGN`: directory, byte 13 = 'B', no system attribute;
- `SECURE`: byte 13 = 'B' plus the system attribute.

| check | UPDATE 96 | UPDATE 97 |
| --- | --- | --- |
| `COPY A:COMMAND.COM C:\FOREIGN` | Access not allowed | copied |
| `COPY A:COMMAND.COM C:\SECURE` | Access not allowed | **Access not allowed** (class still enforced) |
| `DIR`, FOREIGN line | `B  L.K]` | CLS/USER blank |
| `FILEMODE +r c:\mark.txt >c:\f.txt` | Syntax error | `c:\MARK.TXT set attribute, read-only` |
| four-task `GO.BAT` (release emulator) | | all rc 0, STEST churn/sort 0 bad, all DONE |

## Rig

- `ubuild.sh` timeout 900 s;
- builds with `DOSBOX_BIN=` set to the release emulator (much faster on
  this host).
