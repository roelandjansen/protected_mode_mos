# Commit message

Rationale in CHANGES.md UPDATE 15 and the addendum.

---

    DPMI: clients reach protected mode; refuse the switch until a client
    code selector exists. Add DPMITST.

    GoProtect handed clients an entry point computed with a plain OFFSET
    (segment-relative, low by the group base), never tested carry after
    int 0D4h ah=10h, and its post-switch tail wrote to cs:[OrgCS] -- fine
    in real mode, a fault in protected mode. None of it had ever been
    reachable before the driver installed.

    With the entry point fixed the switch works: a client comes back
    vm=0, cpl=3, 32-bit ring 3. It then has nothing to return to.
    nmswitch builds its code descriptor from whatever was executing at
    switch time, which is this driver, and makegdte behind 7786h builds
    data descriptors only. Live GDT: 006B is code, base C0DE0 (driver);
    the client's own segment has the data alias 005B. Returning to either
    aborts the cpu.

    GoProtect therefore returns carry set, per DPMI 0.9: the client stays
    in real mode and survives. The code below the refusal is intact for
    when the host can supply an executable selector -- either a code
    variant of makegdte behind a new 7780h function, or nmswitch building
    CS from the caller's return frame. Either way descriptor lifetime has
    to be settled too, since cleardti frees task-owned descriptors on
    every switch.

    _DPMI.ASM
      - mov di,offset ddt:GoProtect in the 1687h response
      - test carry after the mode-switch call
      - GoProtect: refuse with carry set (interim, documented in place)

    DPMITST.ASM, MAKEUTIL.MAK
      - minimal DPMI 0.9 client: queries the host via int 2Fh 1687h,
        allocates the host data block, calls the mode-switch entry and
        reports which side of the switch it ended on. Added to ALL.

---

## Files in this change

    SOURCES/src/latest/_DPMI.ASM
    SOURCES/src/latest/DPMITST.ASM
    SOURCES/src/latest/MAKEUTIL.MAK
