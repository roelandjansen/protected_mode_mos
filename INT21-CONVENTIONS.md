# Host int 21h translation: TSL native-mode conventions (2026-10-08)

Measured on UPDATE 79. No code change.

## What was tested

`pm21.c` / `pm21n.c` (DJGPP) issue raw `int 21h` from protected mode;
DJGPP installs no pm int 21h handler, so these reach the host's own
translators (`einfun39` .. `einfun5C`). None of the three extenders
uses this path: DOS/4GW and DOS/32A translate int 21h themselves,
DJGPP goes through 0300h.

## Works

3Ch create, 40h write 100,000 bytes (>64 KB), 42h seek, 3Fh read
100,000 bytes and data equal, 3Eh close, 43h attributes, 56h rename
(ds:edx -> es:edi), 41h delete, 39h/3Bh/3Ah mkdir/chdir/rmdir, 47h
getcwd (ds:esi), 5Ah temporary file.

By the host's own conventions also: 42h returns the 32-bit position in
EAX (70,000 exact); 4Eh/4Fh with the DTA in ES:EBX find both files and
then return CF=1, AX=12h.

## Differs from translating DPMI hosts (Windows, HDPMI)

| function | this host (TSL native API) | Windows / HDPMI |
| --- | --- | --- |
| 1Ah set DTA | not translated | DTA = client ds:edx |
| 4Eh / 4Fh | DTA from **es:ebx** at each call (44 bytes copied in and out) | the DTA set by 1Ah |
| 42h | position in **eax** (`einfun42`: "translate dx:ax to eax") | DX:AX, as DOS |

These are TSL's original design (the native-mode API predates DPMI),
not bugs. A DPMI client written against a translating host would get
an empty DTA from find-first and a truncated position from 42h.

Decision for the owner: keep TSL's conventions, switch to the
Windows/HDPMI ones (breaks programs written for TSL's native API, if
any exist), or both (e.g. by client type: native task vs DPMI session).

## Files

- `pm21.c` -- DOS/HDPMI conventions (1Ah DTA, DX:AX); shows the three
  differences.
- `pm21n.c` -- TSL conventions; all correct.
