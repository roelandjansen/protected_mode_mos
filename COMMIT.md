# Commit message

Rationale in CHANGES.md UPDATE 16 and 17.

---

    DPMI: clients run in protected mode on their own code selector;
    client descriptor lifetime

    Add int 6Fh 778Eh CODE_SELECTOR and rebuild GoProtect around it.
    DPMITST now switches and resumes executing its own code at cs=008B,
    cpl=3, vm=0, and exits cleanly through int 21h ah=4Ch.

    nmswitch builds its code descriptor from whatever ran at switch time
    -- the host -- and 7786h builds data descriptors only, so a client
    had nothing to return to. 778Eh is the executable sibling of 7786h,
    with bitness from cl (0 = 16-bit clears g and d). GoProtect uses a bp
    frame on the client's stack instead of writing through cs, requests
    the code selector before switching, discards the stale real-mode fs,
    and carries explicit 66h overrides through its tail, because nmswitch
    hands the host a 32-bit cs.

    Client descriptors are tagged 80h|taskid: task-owned, but exempt from
    cleardti's per-switch sweep, which matches the plain task id. New
    778Fh releases them. GoProtect hooks tcbunreg so UnRegister calls it.
    Measured: that hook never fires for a client, because tcbunreg is
    task-level and the client is a program inside the shell's task. The
    correct release point is the client's int 21h ah=4Ch, which needs
    protected-mode DOS interception -- the next milestone, and also what
    makes a client's own int 21h output work.

    _386.ASM      778Eh CODE_SELECTOR, 778Fh FREE_CLIENT_SEL, 80h tag
    _DPMI.ASM     GoProtect rebuilt; HookUnreg; UnRegister releases
    _DPMI.INC     CODE_SELECTOR 778eh, FREE_CLIENT_SEL 778fh

---

## Files in this change

    SOURCES/src/latest/_386.ASM
    SOURCES/src/latest/_DPMI.ASM
    SOURCES/src/latest/_DPMI.INC
