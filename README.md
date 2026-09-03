# This is the home of PC-MOS/386; based off the last released commercial version (v5.01), development now continues under a GPLv3 license in the hope that it will be both an educational and useful project.

Active development -- protected mode support, the Linux-native build toolchain, and everything that goes with it -- now happens in a separate repo:

https://github.com/roelandjansen/proteted_mode_mos

Builds there target openSUSE Leap 15.x, Leap 16.x, and Tumbleweed only. Languages are x86 assembly (MASM dialect, the OS itself), C (host-side helper tools, compiled with gcc), and bash (scripting) -- no Perl, no Python. No sudo in scripts, small self-contained commits. See that repo's docs for the full tooling policy. This tree stays as the v5.01 source release itself.

This tree:

* includes sources
* includes the executables
* includes the cdrom driver from Rod Roark (sources)
* maybe more

See also.....  https://en.wikipedia.org/wiki/PC-MOS/386

In concert with Gary Robertson and Rod Roark it has been decided to place all under GPL v3.
This does only apply to the PC-MOS/386/The Software Link inc/CDROM code. Does not apply for helper files that
are included and publically available.

The PC-MOS386 v5.01 API itself has been documented in Ralf Brown's interrupt list.


http://www.cs.cmu.edu/~ralf/files.html

(and yes my name is still in the book as well...)


Roeland
