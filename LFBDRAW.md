# LFBDRAW -- a real graphics client of int 31h 0800h (2026-10-08)

`lfbdraw.c` (DJGPP, `gcc -O2 -s -Wall -o LFBDRAW.EXE lfbdraw.c`):

1. VBE 4F01h for mode 101h (640x480x8): it reads the LFB attribute and
   the physical address.
2. 0800h maps the frame buffer, and an LDT selector is set on it.
3. VBE 4F02h sets mode 4101h (LFB on).
4. It draws a 307,200-pixel pattern through the mapping and reads it
   back.
5. It switches to banked mode 101h without clearing (8101h) and reads
   every pixel through the A000h window (4F05h bank switching). This
   path does not touch the mapping, so it checks independently that the
   mapping reaches real video memory.
6. It returns to mode 3. 0801h is reported for information only:
   DPMI 0.9 has no 0801h, and the host refuses it.

## Result (rig, UPDATE 84 kernel + UPDATE 82 `$386.SYS`, `--testconfig`)

```
    307200 pixels: 0 differ via LFB, 0 via the A000h window
OK  LFB read back
OK  same pixels through the banked window
    0801h (DPMI 1.0, not in 0.9): refused
LFBDRAW: 0 bad
```

This was the "real LFB program" item, done with a self-written
client. A commercial VESA program on your rig would still be a good
extra check.
