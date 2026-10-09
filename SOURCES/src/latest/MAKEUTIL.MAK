###############################################################################
#
#       MAKEFILE FOR:           PC-MOS utility programs
#
#       Creation date:          11/15/89
#
#       Revision date:          10/10/91
#
#       Programmer:             The Software Link, Inc
#
#       ----------------------  >> Revision Log <<  --------------------------
#
# Date          Prog    Description of Revision
# ----          ----    -----------------------
# 11/15/89      BWR     Cleanup and verification that the makefile
#                       checks for ALL dependencies.
#
# 1/8/90        BWR     Added a few missing file dependencies as
#                       suggested by MJS.
#
# 1/12/90       SAH     Added INIT.COM and place MOXCPCOR.COM           
#                       into this make file
#
# 1/15/90       BWR     Builds $$SHELL.SYS instead of MOXCPCOR.COM
#
# 3/01/90       BWR     COMPFILE build must now include reference to
#                       C applications library UTIL.LIB
#
# 3/09/90       BWR     Added builds for HELPGEN.EXE
#
# 4/4/90        BWR     $$SHELL.SYS is now part of the "ALL" target.
#                       It is built as __SHELL.SYS because of the
#                       make utilitie's use of the '$' as a macro
#                       symbol.  (All the device drivers are similarly
#                       named.)  Simply rename after building.
#
# 4/18/90       BWR     Dependencies for SPOOL.COM are changed.
#
# 4/25/90       BWR     Added build for ED.EXE
#
# 5/03/90       BWR     ED.EXE now builds in LARGE model.
#
# 05/04/90      mjs     added MACROS.INC dependency to verify
#
# 05/17/90      mjs     add dependency to MACROS.INC to MOS.ASM
#
# 6/6/90        BWR     Command processor builds as $$SHELL.SYS instead
#                       of __SHELL.SYS
#
# 7/2/90        BWR     MAKE still having trouble with $$ macro on
#                       $$SHELL.SYS.  Builds __SHELL.SYS as before.  We'll
#                       just have to rename the file after the build.
#
# 7/25/90       BWR     C programs now built to use RSACLIB.
#
# 8/2/90        BWR     Added HELP.EXE to the build.
#
# 08/13/90      MJS     make ADDTASK.COM dependent on MACROS.INC
#
# 02/26/91      BWR     Fixed some missing dependencies.
#                       Also ... IMPORT and EXPORT are now C utilities
#                       and must be obtained from MOS utility directory.
#                       They each have their own respective MAKEFILES
#                       and are no longer part of this build file.
#
# 03/25/91	mjs	removed moxcpcor's dependency on XIFMACS.INC
#
# 04/17/91      BWR     Build for ED.EXE split out into its own make
#                       group because ED is being split into modules.
#
# 10/10/91	SAH	added depencies on PILDS.INC and LLREC.INC for
#			new SERIAL.SYS driver
#
# mjs 12/16/91	dlg mods:
#		  FORMAT.ASM depends on DSKSTRUC.INC, MACROS.INC, FMCOMMON.INC
#		  FORMAT.ASM doesn't depend on VERSION.INC anymore
#		  MSYS.ASM depends on DSKSTRUC.INC, MACROS.INC, FMCOMMON.INC
#
# mjs 12/31/91	VERIFY.ASM depends on DSKSTRUC.INC
#
# SAH 01/02/92	Remove changes so that _386.SYS does not depend on MOXMEM.INC
#
# SAH 03/04/92  Added Arnet driver to dependences
#
# SAH 05/05/92	Added SERINFO.COM 
#
# cbk 05/19/92  changed PRINT.COM
#
###############################################################################
#
# Default rules for this makefile.
#
.ASM.COM : 
        public $<
        masm $*;
        del $*.pub
        link $*;
        del $*.obj
        exe2bin $* $*.com
        del $*.exe

.ASM.SYS :
        public $<
        masm $*;
        del $*.pub
        link $*;
        del $*.obj
        exe2bin $* $*.sys
        del $*.exe

.ASM.OBJ :
        public $<
        masm $*;
        del $*.pub

.ASM.EXE :
        public $<
        masm $*;
        link $*;
        del $*.pub
        del $*.obj

ALL:    ADDDEV.COM  ADDTASK.COM  DIRMAP.COM  ALIAS.COM  CLASS.COM  DEBUG.COM \
        DIRMAP.COM  DISKCOPY.COM  DISKID.COM  FILEMODE.COM  \
        FORMAT.COM  KEYMAP.COM  MONITOR.COM SERINFO.COM \
        MORE.COM MOS.COM  MOSADM.COM  MOSDD7F.SYS  MOXCPTSK.COM  MSYS.COM  \
        NETNAME.COM  PRINT.COM  REMDEV.COM  REMTASK.COM  SEARCH.COM \
        SETMOUSE.COM  SPOOL.COM  VERIFY.EXE  _286N.SYS  _386.SYS  _ALL.SYS \
        _CHARGE.SYS  _DPMI.SYS  _EMS.SYS  _XMS.SYS  _GIZMO.SYS  _KBBE.SYS  _KBCF.SYS  _KBDK.SYS \
        _KBFR.SYS _KBGR.SYS  _KBIT.SYS  _KBLA.SYS  _KBNL.SYS  _KBNO.SYS \
        _KBPO.SYS  _KBSF.SYS  _KBSG.SYS  _KBSP.SYS  _KBSV.SYS  _KBUK.SYS \
        _MOUSE.SYS  _NETBIOS.SYS  _PIPE.SYS  _RAMDISK.SYS  _SERIAL.SYS \
        INIT.COM   __SHELL.SYS _ARNET.SYS FILTER.COM  PATCHID.COM \
        MINBRDPC.SYS  MISPEED.COM COMPFILE.EXE HELPGEN.EXE \
	VIDPATCH.COM ED.EXE DPMITST.COM DPMI32.COM

############ General purpose publics #############

MOSTCB.PUB : MOSTCB.INC
        public MOSTCB.INC

MOSSCBDF.PUB : MOSSCBDF.INC
        public MOSSCBDF.INC

MBOOT.PUB : MBOOT.INC
        public MBOOT.INC

############ General purpose publics #############

VERSCHK.INC : VERSION.INC

MOXUTIL.OBJ : MOXUTIL.ASM MOXUTL.INC


############ DPMI host test client #############

DPMITST.COM:    DPMITST.ASM
        masm dpmitst;
        link dpmitst;
        exe2bin dpmitst DPMITST.COM
        del dpmitst.obj
        del dpmitst.exe

DPMI32.COM:     DPMI32.ASM
        masm dpmi32;
        link dpmi32;
        exe2bin dpmi32 DPMI32.COM
        del dpmi32.obj
        del dpmi32.exe

ADDDEV.COM:     ADDDEV.ASM PAGE.INC OPTIONS.INC MACROS.INC VERSION.INC

ADDTASK.COM:    ADDTASK.ASM PAGE.INC OPTIONS.INC MOSTCB.INC MOSSCBDF.INC \
                VERSION.INC MACROS.INC

ALIAS.COM:      ALIAS.ASM MOXUTIL.OBJ PAGE.INC MOXUTL.INC VERSION.INC
        public alias
        masm alias;
        del ALIAS.PUB
        link alias + moxutil;
        exe2bin alias ALIAS.COM
        del ALIAS.OBJ
        del ALIAS.EXE

CLASS.COM:      CLASS.ASM PAGE.INC MOSTCB.INC MOSSCBDF.INC OPTIONS.INC \
                VERSION.INC

#******************************************************************************
#       MOS Debugger.
#******************************************************************************
DEBUG.COM:      DEBUG.OBJ DEBUGMAN.OBJ DEBUGCON.OBJ DEBUGEXT.OBJ \
                DEBUGTRA.OBJ DEBUGSUP.OBJ DEBUGEND.OBJ
        link debug +debugman +debugcon +debugext +debugtra +debugsup \
        +debugend/m;
        exe2bin debug DEBUG.COM
        del DEBUG.EXE

DEBUG.OBJ:      DEBUG.ASM PAGE.INC OPTIONS.INC MOSTCB.INC MOSTCB.PUB \
                VERSION.INC

DEBUGMAN.OBJ:   DEBUGMAN.ASM PAGE.INC DEBUGMAC.INC

DEBUGCON.OBJ:   DEBUGCON.ASM PAGE.INC

DEBUGEXT.OBJ:   DEBUGEXT.ASM PAGE.INC

DEBUGTRA.OBJ:   DEBUGTRA.ASM PAGE.INC DEBUGMAC.INC

DEBUGSUP.OBJ:   DEBUGSUP.ASM PAGE.INC

DEBUGEND.OBJ:   DEBUGEND.ASM PAGE.INC

#******************************************************************************

DIRMAP.COM:     DIRMAP.ASM VERSION.INC PAGE.INC OPTIONS.INC

DISKCOPY.COM:   DISKCOPY.ASM PAGE.INC COPYRIT.INC VERSCHK.INC

DISKID.COM:     DISKID.ASM PAGE.INC VERSCHK.INC

FILEMODE.COM:   FILEMODE.ASM PAGE.INC VERSION.INC

FILTER.COM:     FILTER.ASM PAGE.INC

FORMAT.COM:     FORMAT.ASM PAGE.INC OPTIONS.INC MBOOT.PUB DSKSTRUC.INC \
                MBOOT.INC MACROS.INC FMCOMMON.INC

;HDSETUP.COM:    HDSETUP.ASM PAGE.INC MBRDEF.INC MBR.INC

KEYMAP.COM:     KEYMAP.ASM PAGE.INC

MINBRDPC.SYS:   MINBRDPC.ASM PAGE.INC

MISPEED.COM:    MISPEED.ASM PAGE.INC

MONITOR.COM:    MONITOR.ASM PAGE.INC OPTIONS.INC MOSTFB.INC MOSSCBDF.INC \
                MOSTCB.INC VERSION.INC

MORE.COM:       MORE.ASM PAGE.INC VERSION.INC

MOS.COM:        MOS.ASM MOSTCB.INC MOSSCBDF.INC MOSTFB.INC OPTIONS.INC \
                GENMOUSE.INC VERSION.INC MOXMOS.INC MACROS.INC

MOSADM.COM:     MOSADM.ASM PAGE.INC MOSTCB.INC MOSSCBDF.INC MOSTFB.INC \
                OPTIONS.INC GENMOUSE.INC VERSION.INC MOXMOS.INC

MOSDD7F.SYS:    MOSDD7F.ASM OPTIONS.INC

MOXCPTSK.COM:   MOXCPTSK.ASM PAGE.INC MOSSCBDF.INC

MSYS.COM:       MSYS.ASM PAGE.INC MBOOT.INC DSKSTRUC.INC MACROS.INC FMCOMMON.INC

NETNAME.COM:    NETNAME.ASM PAGE.INC VERSION.INC

PATCHID.COM:    PATCHID.ASM PAGE.INC MACROS.INC

PRINT.COM:      PRINT.ASM PAGE.INC OPTIONS.INC COPYRIT.INC
	public print
	copy ISMOS.DEF _OSMOS.DEF
	masm print;
	del PRINT.PUB
	link print;
	del PRINT.OBJ
	exe2bin print PRINT.COM
	del PRINT.EXE
	del _OSMOS.DEF

REMDEV.COM:     REMDEV.ASM PAGE.INC OPTIONS.INC

REMTASK.COM:    REMTASK.ASM PAGE.INC MOSTCB.INC MOSSCBDF.INC MOXUTL.INC \
                MOXUTIL.OBJ VERSION.INC
        public remtask
        masm remtask;
        del REMTASK.PUB
        link remtask+moxutil;
        del REMTASK.OBJ
        exe2bin remtask REMTASK.COM
        del REMTASK.EXE

SEARCH.COM:     SEARCH.ASM PAGE.INC VERSION.INC

SERINFO.COM:    SERINFO.ASM

SETMOUSE.COM:   SETMOUSE.ASM PAGE.INC

SPOOL.COM:      SPOOL.ASM PAGE.INC OPTIONS.INC MOSTCB.INC COPYRIT.INC \
                VERSCHK.INC
                        masm spool;
                        link spool;
                        exe2bin spool SPOOL.COM
                        del SPOOL.EXE

VERIFY.EXE:     VERIFY.ASM PAGE.INC OPTIONS.INC MACROS.INC DSKSTRUC.INC

_286N.SYS:      _286N.ASM PAGE.INC

_386.SYS:       _386.ASM PAGE.INC 

_ALL.SYS:       _ALL.ASM PAGE.INC MOXMEM.INC

_CHARGE.SYS:    _CHARGE.ASM PAGE.INC MOXMEM.INC

_DPMI.SYS:      _DPMI.ASM PAGE.INC _DPMI.INC MOSSCBDF.INC DPMISEG.INC MOSTCB.INC

_EMS.SYS:       _EMS.ASM PAGE.INC

_XMS.SYS:       _XMS.ASM PAGE.INC

_GIZMO.SYS:     _GIZMO.ASM PAGE.INC MOXMEM.INC


_KBBE.SYS:      MOSKBBE.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbbe,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBCF.SYS:      MOSKBCF.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbcf,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBDK.SYS:      MOSKBDK.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbdk,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBFR.SYS:      MOSKBFR.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbfr,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBGR.SYS:      MOSKBGR.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbgr,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBIT.SYS:      MOSKBIT.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbit,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBLA.SYS:      MOSKBLA.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbla,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBNL.SYS:      MOSKBNL.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbnl,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBNO.SYS:      MOSKBNO.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbno,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBPO.SYS:      MOSKBPO.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbpo,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBSF.SYS:      MOSKBSF.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbsf,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBSG.SYS:      MOSKBSG.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbsg,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBSP.SYS:      MOSKBSP.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbsp,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBSV.SYS:      MOSKBSV.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbsv,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe

_KBUK.SYS:      MOSKBUK.ASM PAGE.INC MOSKBFOR.INC MOSKBINZ.INC
        masm moskbuk,$*;
        link $*;
        exe2bin $* $*.sys
        del $*.obj
        del $*.exe


_MOUSE.SYS:     _MOUSE.ASM PAGE.INC OPTIONS.INC MOSREGS.INC XIFMACS.INC \
                MOSTCB.INC MOSSCBDF.INC GENMOUSE.INC

_NETBIOS.SYS:   _NETBIOS.ASM PAGE.INC OPTIONS.INC MOSTCB.INC MOSSCBDF.INC

_PIPE.SYS:      _PIPE.ASM PAGE.INC MOSSCBDF.INC OPTIONS.INC DEVREQH.INC

_RAMDISK.SYS:   _RAMDISK.ASM PAGE.INC

_SERIAL.SYS:    _SERIAL.ASM PAGE.INC OPTIONS.INC SERIAL.DEF JMPMACRO.INC \
                SERIOMAC.INC INT14.INC ISRSUB.INC PILDS.INC LLREC.INC
        copy SERIAL.DEF _SERIAL.DEF
        public _SERIAL.ASM
        masm _serial;
        del _SERIAL.PUB
        link _serial;
        exe2bin _serial _SERIAL.SYS
        del _SERIAL.OBJ
        del _SERIAL.EXE
        del _SERIAL.DEF


_ARNET.SYS:    _ARNET.ASM PAGE.INC OPTIONS.INC JMPMACRO.INC 
        public _ARNET.ASM
        masm _arnet;
        del _ARNET.PUB
        link _arnet;
        exe2bin _arnet _ARNET.SYS
        del _ARNET.OBJ
        del _ARNET.EXE

INIT.COM:       INIT.ASM

VIDPATCH.COM:   VIDPATCH.ASM

#******************************************************************************
#       MOS Command processor - $$SHELL.SYS
#******************************************************************************


__SHELL.SYS : MOXCPCOR.OBJ MOXCPINT.OBJ MOXCPPLS.OBJ MOXCPSUB.OBJ
        link moxcpcor+moxcpint+moxcppls+moxcpsub;
        exe2bin moxcpcor __SHELL.SYS
        del MOXCPCOR.EXE

MOXCPCOR.OBJ : MOXCPCOR.ASM OPTIONS.INC MOXCPDAT.INC MOSTCB.INC \
               MOXCPSXT.INC MOSSCBEX.INC VERSION.INC
        public moxcpcor
        public MOXCPDAT.INC
        type MOXCPDAT.PUB >> MOXCPCOR.PUB
        masm moxcpcor;
        del MOXCPCOR.PUB
        del MOXCPDAT.PUB

MOXCPSUB.OBJ :  MOXCPSUB.ASM  PAGE.INC  MOXCPDAT.INC  MOSSCBEX.INC \
                MOSTCB.INC
        public moxcpsub
        masm moxcpsub;
        del MOXCPSUB.PUB

MOXCPINT.OBJ :  MOXCPINT.ASM MOXCPDAT.INC MOXCPSXT.INC
        public moxcpint
        masm moxcpint;
        del MOXCPINT.PUB

MOXCPPLS.OBJ :  MOXCPPLS.ASM  PAGE.INC  MOXCPDAT.INC  MOSSCBDF.INC \
                MOXCPSXT.INC
        public moxcppls
        masm moxcppls;
        del MOXCPPLS.PUB
#
#  Utility programs written in C.  (And Pascal, temporarily)
#
COMPFILE.EXE: compfile.c
        loadfix cl -c compfile.c
        link compfile/e,,,rsasmall

HELPGEN.EXE: helpgen.c
        loadfix cl -c helpgen.c
        link helpgen/e,,,rsasmall

ED.EXE: ed.c
	loadfix cl -c -AL ed.c
	link ed,,,rsalarge

HELP.EXE: HELP.PAS HELP.INC
        tpc help
