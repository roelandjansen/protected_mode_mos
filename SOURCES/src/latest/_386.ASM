	include page.inc
	.286c

comment ^============================================================

$$memdev driver for the the 80386, 386SX, 386SL, 486, 486SX & 586??
copyright 1985-1992 The Software Link, Incorporated

*********** Special Notice - Please Read before modifing ************

NOTE:  Updated: 11/11/92 Stewart Hyde.  Special Notice concerning
IBM's 386SLC and 486SLC2 Microprocessors. These modified Intel 386SX
CPU's have a bug concerning 66h opcode that relateds to 5.01 work
around inside $386.SYS.  When calling 16 bit procedure from USE32
code the procedure that you call must be a forward reference or memdev 
will fail on 2.8 version of 386SLC and 486SLC2's from IBM.  IBM has stated
that they will fix the problem in 486SLC2 but not in 386SLC.  Early version
of 386SLC (version 2.7 and lower, 1st 6 months of production) will not
function with $386.SYS evenn with the 5.01 workaround.

The following is a IBM description of Bimini 2-SX "PC-MOS" errata

"Description: When executing a CALL or JMP instruction with a  negative
	      displacement within a 32-bit code segment and an operand 
	      prefix override is used (i.e., to limit the target address
              to 16 bits), the resulting target address is computed
	      incorrectly.

Conditions:   The current code segment must be 32-bit, a CALL or JMP 
              near instruction must be executed with an operand prefix
	      overide (X'66' byte).  The displacement field of the
	      CALL or JMP instruction must be negative for a control
	      tranfer to a previous instruction.  The of offset of the
	      CALL or JMP and its target must be within 32768 bytes
	      of each other.  In addition, the instructions must lie
	      within the first 64k bytes of the code segment."

********************************************************************

note: emulex version accomodates the fact that this hard disk
uses dma and requires a full 64k staging buffer. also beware
that it requires a hardware interrupt line (irq5 recommended).

ps/2 also requires hard disk dma staging.

====================================================================

rbr 05/06/87	added parmiop, for efficiency.

rbr 05/06/87	stage format operations to disk drives using dma.

rbr 05/07/87	always stage format and verify operations,
		regardless of buffer addresses. this was done
		because the pc/xt bios can generate dma overrun
		errors without just cause.

rbr 06/13/87	made 1st 2k read-only.  fixed garbage in idt
		added support for all's Charge Card; fixed crash
		on irq8-irqf while running in native mode.

rbr 06/28/87	added doinaxd, dooutaxd to handle in/out on ax
		increased iopbm for i/o addresses up to 37ff
		these were needed for the ps/2 model 80.
		also added /p, /x, /e options for ps/2, xt, and
		emulex hard disks, respectively.

rbr 06/30/87	implement request handler function 0 to reboot.
		relocate data area used by esdi fixed disk bios.

rbr 07/05/87	revised testing for extended memory to avoid
		crashing the wyse 386 (which seems to not like
		16-bit reads/writes to nonexistent ram).

rbr 07/19/87	modifications to support int 38h. also changed
		int 38h function 11h (allocate) to return an
 		error condition if there is not enough memory.

rbr 07/27/87	fix mmadrtab value for charge card.

sah 08/06/87	added conditional assembly of code which allows
		tracing of memory managements request header
		this code is include by making rhtrace true

rbr 08/08/87	added logic to preserve the original "et" bit in
		cr0, so that the 80387, if present, will be
		correctly supported.

sah 08/19/87	after testing for memory, made sure that memory
		was zero-out. this was a problem with turbo-c
		because it assume that the memory was clear. yes
		it is hard to believe but it is true.

rbr 08/21/87	corrections for new all card.

rbr 09/10/87	fix "alias" function (int 38h function 13h)

rbr 09/14/87	establish idt entry for all interrupts.
  
sah 09/30/87	allow for /t option with /p, /x or /e options
		this requires that /t be before /p....

sah/jrb 11/12/87 allow for port outs and in to return to mos
		int 06 handler, mos never got it because 386
		driver iret back to where it ok its exception

mjs 11/16/87	added new feature bit (10h) to control type of
		context switching done because of a
		conflict with ps/2's and I/O addressing

rbr 01/17/88	added "/maaaa,nnnn" option to declare a disjoint
		section of pre-initialized extended memory  ; this
		is used if you need to be able to boot up without
		trashing data saved on a nonvolatile ramdisk in
		extended memory.

rbr 01/17/88	memdev driver load address changed from 00800
		to 00700.  this is because $286.sys needs to be
		loaded there, and we want to be consistent.
		modified mosinit is now requried.

sah 01/22/88	check if cpu is 386 for 386 version of driver

rbr 03/07/88	don't croak on HLT.  Some BIOSes use it.

rbr 03/13/88	corrections to hlt stuff; dma fix.

rbr 04/22/88	minor addition to support the all chargecard ii.

rbr 06/21/88	added ivtable and supporting logic for $386.sys.

rbr 06/30/88	added parmpfa as a scratch area pointer for mos.

sah 07/12/88	added upper 60k support bit

rbr 07/13/88	added help for maxspeed driver in phymap

rbr 07/25/88	added ivtable support for chargecard & gizmo

rbr 07/28/88	modify usage of 386 page table for upper 60k use

rbr 08/03/88	added /i and /c options ; removed /m option; also
		do automatic /c if no extended memory.

sah 08/21/88	turn off nmi during 386 memory check

rbr 09/21/88	fix quattro putting itself into native mode.

sah 10/26/88	fix lockups if machines don't have extended memory
		for the non-386 machines.

sah 11/01/88	correction to 08/21/88 fix for non-386's

sah 11/01/88	added /m option for 32k dma buffer

rbr 12/02/88	preserve es during non-386 physical remaps.

rbr 12/12/88	fix native mode memory management to account for
		new relationship between "handle" and address
		also fixed ivtable usage in native mode apps.

mjs 12/29/88	added pushf/cli...popf protection to the phymap proc
		for the gizmo and allcard.  not having this in the gizmo
		case was causing a crash with maxspeed.  in the allcard
  		case, i just noticed this protection was missing.

sah 02/02/89	made hex-dec conversion use 5 digits and move messages
		to end of source. this is needed for machine with more
		than 15meg.

mjs 03/21/89	added list base mapping call and a block move call
		which takes advantage of the 386's 32 bit move string
		capability.  access to this block move routine will be
		made through a far pointer int the scb.
 ***** note:	any changes made to the vremap, vunmap or vphymap
		routines should be echoed into the appropriate sections
		of the vlistmap procedure as well.
		added calls to allow the 386's debug registers to be
		read and written.

mjs 06/06/89	modified response to int38 calls for native mode
		services to also responsd to intd4.  all points are
		tagged with the string "extsv".
		added /s option to gizmo and charge drivers to force
		the context remapping feature bit on.  this should allow
		some irq handling improvements on non-ps2 286 machines.

sah 06/21/89	added code into 386.sys int 13 routine to disable io
		protection to timer ports 40,42, and 43 when original
		bios is being called.  this was causing our disk io to
		be about 3 times slower than with this fix on writes

mjs 06/29/89	modify vreboot to make a warm boot by default

rbr 07/13/89	support upper-60k for gizmo & chargecard

rbr 07/17/89	oops, make that just chargecard - gizmo wraps at 1mb

sah 09/08/89	corrections for compaq 386s, allocated esdi buffer if
		needed before dma buffer.

mjs 09/12/89	corrected an instruction within makegdte.  this was
		causing data to be corrupted when an app used int38
		function 1001 to switch to native mode.
		the instruction: and cx,0ffffh	dw 00ffh  was used with
		the intention of producing:  and ecx,00ffffffh.
		when masm saw the and cx,0ffffh, it produced 83 e1 ff
		which is for a sign extended operand.  this left the
		dw 00ffh sitting in the code as whatever instruction
		that happens to be.  fixed by explicitly encoding:
		db 81h,0e1h  dw 0ffffh,00ffh..

bwr 11/30/89	marked messages for foreign language translation.

mjs 02/01/90	reworked the 386 initialization logic to build the
		page directory and page table within extended memory.
		established two use16 and two use32 segments to make
		it possible to use 386 mnemonics.
		reworked all logic which needed to access the page
		table to run in native mode.

SAH 02/28/90	Corrections for IBM Model 70 486, made sure that IRQ 1
		is mask out during INIT, It appears that Model 70 486
		Keyboard control is sensitive to turning Address 20 line
		On so that we can access above 1 meg.

mjs 03/27/90	removed sah's modification for timer port trapping
		(06/21/89).   due to the recursion of int13's caused
		by mosint13, this logic wasn't actually effective.  when
		a recursive call occured the timer trapping bits would
		get cleared and stay that way.	implemented a new version
		of this logic within mosint13

SAH 04/09/90	Corrections to oversight of MJS 02/01/90 Modications with
		code logic to copy ESDI bios area into low memory. This
		cause Charge.sys driver to lock up because its init code
		was being rewritten with ESDI Bios data

SAH 04/30/90	Removing setting value at 80c00000, now handle by
		MOSINIT2 via INT 15 call so it will work 386sx machines

mjs 05/04/90	corrected native mode initialization where the int2 vector
		is saved, changed and restored.  a mistake here was
		preventing the new 386 memdev from running with the
		intel inboard on a pc.

mjs 06/18/90	changed function number of the list based remapping
		call from 0a to 0d.  this is to prevent a conflict
		with function 0a, 0b and 0c within 286.sys.

mjs 06/25/90	corrected problems with list based remapping call.

mjs 12/11/90	corrected problem with $386.sys on 20 mhz compaqs with
		series 1 maxspeed boards.

mjs 12/13/90	converted dma staging logic to use a smaller buffer and
		break up the read or write so it will fit in the buffer.
		added the /d=nn parameter to allow buffer sizing.  can
		still use /p, /m, /e, etc. 

		added logic to support a native mode nmi handler.  this
		was done for display automation.

mjs 01/03/91	added api function 10h to support the restoration of
		the previous nmi handler.  display automation needs
		this so they can abort the loading of their driver
		when they detect equipment problems.

mjs 01/07/91	added version number and release date to boot messages

mjs 03/19/91	added api function 11h, netbios block copy.
		also, changed gdtzero to g=1 (granularity bit = 1).

mjs 04/22/91	added cs: overrides so the charge, gizmo and all versions
		would assemble.
		added vblkcpy support to the charge and gizmo drivers.

mjs 06/05/91	modified the code that determines when a disk operation
		should be staged.  instead of checking only the starting
		page of the buffer, must check the ending page.  
		otherwise, buffers which include the 640k boundary
		can cause problems in the foreground when the 'f'
		option of vtype is used.

SAH 06/05/91	Added /L option to disable checking of memory at upper 15 Meg
		for Compaq machines. This was causing a lock up on Club Hawk
		386.

mjs 07/01/91	version 4.14, reset idt after loadall.  was causing
		llpro to lock up on 286 machines.

SAH 01/02/92	Remove  Gizmo,Charge, and All Card from this source
		Up version # to 4.15 for this change

SAH 01/08/92	Change some of the code to support 386 instructions
		but unfortunately because of designed of this driver
		we can't completely change the entire driver
		Move bintodec to init section. Added /b option to 
		to keep  forground size what it is orginally and
		not to change 40:13
		Up version # to 4.16 for this change

SAH 01/15/92	Added get0phy, GetCR0, LoadDebug, and SaveDebug
		for VCPI/DPMI support.  Also change /b (PER RBR)
		to force memory to fill area so that machines that have
		extended bios will not lock the machine		
		Up version # to 4.17 for this change

SAH  03/03/92	Modified get0phy to detected for error, convert page 0
		addresss to linear address. Also added logic to detect
		for 486 and display on bootup.
		Up version # to 4.18 for this change

mjs 07/02/92	when an extended bios data area is being moved from
		9fc0 (the 639th K) to a lower area, we must not only
		update 40:e but also check the segment of the int41
		vector.  this problem was noticed on the decstation
		320+ (comcotec/brooks).
		version # 4.19

SAH 09/04/92    Add regdisp to dump additional debuging information. 
		normally this equate is off...set regdisp to true to
                include it.  Also added /6 to disable IO protection


SAH 11/11/92	Corrections for Bug I found in IBM 386SLC (and 486SLC2)
		where it did not like calling 16 bit code lower in 
		memory from a 32bit code.  This gave the chip headaches
		with neqative offset.  This is a work around the bug which
		IBM plans to make a update.  Currently this code works
		on the IBM 486SLC2 but does not work on the IBM 386SLC
		Up version to 5.01 (Not for global release yet)
=======================================================================^

include xifmacs.inc


TRUE	equ	1
FALSE	equ	0


; use these guys to simplify register saving and restoring

pushset macro	p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14
	irp	@@push,<p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14>
	ifnb	<@@push>
	push	@@push
	endif
	endm
	endm

; couldn't get irp to work for this one

popset	macro	p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14
	ifnb	<p14>
	pop	p14
	endif
	ifnb	<p13>
	pop	p13
	endif
	ifnb	<p12>
	pop	p12
	endif
	ifnb	<p11>
	pop	p11
	endif
	ifnb	<p10>
	pop	p10
	endif
	ifnb	<p9>
	pop	p9
	endif
	ifnb	<p8>
	pop	p8
	endif
	ifnb	<p7>
	pop	p7
	endif
	ifnb	<p6>
	pop	p6
	endif
	ifnb	<p5>
	pop	p5
	endif
	ifnb	<p4>
	pop	p4
	endif
	ifnb	<p3>
	pop	p3
	endif
	ifnb	<p2>
	pop	p2
	endif
	ifnb	<p1>
	pop	p1
	endif
	endm


; other assembly-time options

int6	equ	TRUE			; if int 6's to be generated
rhtrace equ	false			; if request header tracing
trace	equ	false			; if int1 trace code is to be included
dbgemu	equ	false			; if want debug reg access emulation
regdisp equ     false			; if display registers at boot.

; mos-dependent equates

scbtcbpc equ   19			; scb offset to current tcb address
tcbid	equ   16			; tcb offset to task id
tcbncadr equ   18			; tcb offset to nca address
tcbpsp	equ   2deh			; tcb offset to the current PSP (UPDATE 67)

	page
;--------------------------------------------------------------------
;		      native context area
;--------------------------------------------------------------------

nca	segment at 386h 		; we lie, so what?
ncastack label word			; v86 stack, must immediately precede ncairegs
ncairegs label word			; v86 flags,di,si,dx,ax,bx,cx,es,ds,bp
ncavflag dw    0,0
ncavdi	dw    0,0
ncavsi	dw    0,0
ncavdx	dw    0,0
ncavax	dw    0,0
ncavbx	dw    0,0
ncavcx	dw    0,0
ncaves	dw    0,0
ncavds	dw    0,0
ncavbp	dw    0,0
ncap0stk label word			; native es,ds,fs,gs,eip,cs,flags,esp,ss
ncanes	dw    0,0			;   must immediately follow ncairegs
ncands	dw    0,0
ncanfs	dw    0,0
ncangs	dw    0,0
ncanip	dw    0,0
ncancs	dw    0,0
ncanflag dw    0,0
ncansp	dw    0,0
ncanss	dw    0,0
ncauregs dw    4 dup(0,0)		; scratch area for staging & such
ncaretad dw    0			; return address from dovmint
ncarwseg dw    0			; user'S I/O
ncarwoff dw    0,0			;   address
ncarwlen dw    0,0			; remaining length to read or write
ncarwlsv dw    0,0			; original i/o length requested
ncabufsz dw    0,0			; length of ncabufer
ncabufer label word			; staging buffer
ncalen	equ   $-nca
nca	ends


; use to call native mode procedures from within a use16 segment

call32 macro lbl
local xyz
	db	68h			;; this code runs in native mode
	dw	mmgrp:xyz,0		;; push on return address
	db	68h
	dw	mmgrp:lbl,0		;; push on destination address
	ret				;; enter use32 segment
xyz:
	endm

; use to call native code still in use16 from use32.  the routine being
; called must use a db66 in front of its ret (e.g. eicommon)

calls32 macro lbl
local xyz
	db	66h,68h 		;; push 16 bit immeadiate (native)
	dw	mmgrp:xyz		;; push on return address
	db	66h,68h
	dw	mmgrp:lbl		;; push on destination address
	db	66h,0c3h		;; 16 bit ret
xyz:
	endm

; use to jmp from use32 to protected mode code within a use16

jmps32	macro	lbl
	db	66h,68h 		;; 16 bit push immeadiate
	dw	mmgrp:lbl		;; 16 bit offset to push
	db	66h,0c3h		;; 16 bit ret
	endm

	page
;--------------------------------------------------------------------
;			  main segment
;--------------------------------------------------------------------

mmgrp	group	res16,res32,init16,init32


;======================== 16 bit resident code =========================

res16  segment para public 'CODE'
	assume cs:mmgrp,ds:mmgrp

begin label near

	public mmbeg
mmbeg:

; device header

devheadr:
	 dd    -1			; pointer to next driver
	 dw	8000h			; attribute: indicate character device
stratvec dw    strategy 		; ptr to strategy routine
intervec dw    interupt 		; ptr to interrupt routine
devname  db    '$$MEMDEV'		; device name
endhead:

; transfer to relocated driver

tostrat db	0eah			; far jump opcode
	dw	strategy,0
tointer db	0eah
	dw	interupt,0
relomin equ	$-begin 		; minimum relocation in bytes

; miscellaneous constants

foption db	0			; flag for /f option
zero	 dw    0
wordten  dw    10

	page
;--------------------------------------------------------------------
;		      device function vectors
;--------------------------------------------------------------------
	even
funtab	label word
	dw	mmgrp:init
	dw	mediachk
	dw	buildbpb
	dw	ioctlin
	dw	input
	dw	ndinput
	dw	instatus
	dw	inflush
	dw	output
	dw	outputv
	dw	oustatus
	dw	ouflush
	dw	ioctlout

	org	 0100h			; skip to location 00800

;======================================================================
;,fs
; strategy
;
; in:	es:bx -> request header
;
; out:	none
;
;,fe
;=====================================================================
strategy:
	mov	cs:[rhseg],es
	mov	cs:[rhoff],bx
	retf

;======================================================================
;,fs
; interupt
;
; in:	request header pointer in [rhseg]:[rhoff]
;
; out:	request header updated
;
;,fe
;=====================================================================
interupt:
	push	bp
	push	es
	push	ds
	push	di
	push	si
	push	dx
	push	cx
	push	bx
	push	ax
	push	cs			; init ds register
	pop	ds
	les	bx,dword ptr [rhoff]	; load rh pointer
	mov	al,es:[bx+2]		; get command code byte
	xor	ah,ah
	shl	ax,1
	mov	di,ax
	jmp	[di+funtab]
donestat:
	les	bx,dword ptr [rhoff]
	or	word ptr es:[bx+03],0100h  ; "done" status
exit:
	clc
	pop	ax
	pop	bx
	pop	cx
	pop	dx
	pop	si
	pop	di
	pop	ds
	pop	es
	pop	bp
	retf
ddabort:
	mov	word ptr [devname],'\\'
	les	bx,dword ptr [rhoff]
	mov	word ptr es:[bx+14],offset mmgrp:endhead
	mov	word ptr es:[bx+16],cs
	or	word ptr es:[bx+3],8001h; error unknow unit
	jmp	exit

	page
;--------------------------------------------------------------------
;			device functions
;--------------------------------------------------------------------
input:
	les	bx,dword ptr es:[bx+14] ; address the buffer
	mov	word ptr es:[bx],offset mmgrp:parms
	mov	es:[bx+2],cs
	les	bx,dword ptr [rhoff]
	mov	word ptr es:[bx+18],4	; 4 bytes transferred
	jmp	donestat
output:
outputv:
ioctlin:
ioctlout:
	mov	word ptr es:[bx+18],0	; no data transferred
ndinput:
instatus:
inflush:
oustatus:
ouflush:
mediachk:
buildbpb:
	or	word ptr es:[bx+03],8102h  ; indicate device not ready
	jmp	donestat

	page

;==== int 13 vector table

	even
int13tab label word
	dw	i13pass 	; 00  reset disk
	dw	i13pass 	; 01  get status
	dw	i13nread	; 02  read sectors
	dw	i13nwrit	; 03  write sectors
	dw	i13verfy	; 04  verify sectors
	dw	i13fmt		; 05  format track
	dw	i13fmt		; 06  format track with bad sector flags
	dw	i13pass 	; 07  format drive
	dw	i13pass 	; 08  get drive parameters
	dw	i13pass 	; 09  init drive pair characteristics
	dw	i13lread	; 0a  read long  (516 bytes per sector)
	dw	i13lwrit	; 0b  write long (516 bytes per sector)
	dw	i13pass 	; 0c  seek
	dw	i13pass 	; 0d  alternate disk reset
	dw	i13sread	; 0e  read sector buffer  (only 1 sector)
	dw	i13swrit	; 0f  write sector buffer (only 1 sector)
	dw	i13pass 	; 10  test drive ready
	dw	i13pass 	; 11  recalibrate
	dw	i13pass 	; 12  controller ram diagnostic
	dw	i13pass 	; 13  drive diagnostic
	dw	i13pass 	; 14  controller internal diagnostic
	dw	i13pass 	; 15  read dasd type
	dw	i13pass 	; 16  get change line status
	dw	i13pass 	; 17  set dasd type for format
	dw	i13pass 	; 18  reset disk    \
	dw	i13pass 	; 19  get status     \	emulex hard disk
	dw	i13nread	; 1a  read sectors   /
	dw	i13nwrit	; 1b  write sectors /


	subttl entinr13 - int13 intercept entry for dma staging
	page
;======================================================================
;,fs
; entinr13 - int13 intercept entry for dma staging
;
; this logic is always used for floppy disks.  it is used for hard
; disks when certain switch options are specified.
;
; in:	int13 entry registers
;
; out:	int13 exit registers
;
;=====================================================================
; i6fstub - real-mode/v-86 int 6fh entry point.
;
; Hooked into IVT[6Fh] at init. At IOPL=3 an INT n in v-86 mode is not
; trapped, so int 6fh from a v-86 caller lands here instead of at
; entint6f. "out 0e0h,al" IS trapped, by the TSS i/o permission bitmap
; (bit force-set alongside 04h/81h), landing in doi6fgate, which hands
; over to the normal int 6fh dispatcher.
;
; out imm8,al only READS al, so the caller's ax -- the int 6fh
; function number -- reaches the dispatcher untouched. Values the
; handler returns in ax/bx/cx survive; only bp and the flags are
; touched here.
;
; CF carries success/failure. The handler sets it in s0flags, which
; cgrm7's iretd restores into the live flags -- but a plain iret would
; then pop the caller's own flags image off the v-86 stack and discard
; that result, so propagate CF into the saved image first. "retf 2"
; would also preserve CF, but would leave IF as int 6fh cleared it.
;=====================================================================

i6fstub:
	out	0e0h,al 		; traps -> doi6fgate -> e6fa
	push	bp
	mov	bp,sp			; caller's flags image at [bp+6]
	jc	i6fstub1
	and	word ptr [bp+6],0fffeh	; cf clear = success
	jmp	short i6fstub2
i6fstub1:
	or	word ptr [bp+6],0001h	; cf set = failure
i6fstub2:
	pop	bp
	iret

dooutali9:
	cmp	ch,0e0h
	je	doi6fgate
	db	66h
	jmp	doinout

; int 6fh gateway.
;
; The v-86 task runs at IOPL=3 (uioplb), so INT n is NOT trapped -- it
; dispatches through the real-mode IVT and never reaches entint6f.
; That severs valloc, which runs in virtual mode by design and
; re-enters native mode via int 6fh. I/O, however, still traps at
; IOPL=3 through the TSS permission bitmap, so an I/O instruction is a
; usable doorway.
;
; i6fstub (hooked into IVT[6Fh] at init) executes "out 0e0h,al", whose
; bit is force-set in t2iopbm alongside 04h/81h. That faults here with
; the caller's ax untouched -- out imm8,al only reads al -- so we can
; hand straight to the normal int 6fh dispatcher.
;
; Advance s0ip past both bytes of the 2-byte "out imm8,al" first,
; exactly as doout04i + dooutbye do between them, or the iretd out of
; cgrm7 would re-execute the faulting instruction forever.
;
; Safe to jump into e6fa: both paths come through one eicommon and
; share one frame (measured -- all five pushes are 4 bytes, because
; gdtcode has d=1 and res16 executes 32-bit despite assembling USE16).
; bp is p0stack-40 here, below p0stack-28, which is the v-86 case e6fa
; expects. See addendum.
;
doi6fgate:
	db	67h
	inc	word ptr ss:[s0ip]	; past the e6 opcode
	db	67h
	inc	word ptr ss:[s0ip]	; past the imm8 port byte
	mov	ch,6fh
	db	67h
	mov	ss:[debugint],ch
	db	67h
	mov	ss:[iveccode],ch
	jmps32	e6fa

;,fe
;=====================================================================
entinr13:
	sti
	pushf
	cmp	ah,42h			; extended read/write (UPDATE 103)
	je	x13ext0
	cmp	ah,43h
	jne	x13ext1
x13ext0:
	jmp	x13ext
x13ext1:
	cmp	dl,80h			; ***** exit if dma not used *****
dmajump label word			; this is nop'ed out if hard disk uses dma
	jae	fastex13
	cmp	ah,1bh			; boundary check
	ja	fastex13
	mov	cs:[usercx],cx
	mov	cs:[userdx],dx
	cmp	ah,6			; formats are very dma boundary sensitive
	ja	i13not46
	cmp	ah,4			; stupidly enough, so are verifies!
	jae	stage
i13not46:
	mov	dx,bx			; compute starting seg address
	shr	dx,4
	mov	cx,es
	add	dx,cx


; for function 2 and 3, form sectors to be written in ax
; (ax << 9) would convert sectors into total bytes
; (ax >> 4) would convert total bytes into paragraphs
; therefore, using (ax << 5) which will produce the same results unless
; the entry al value was > 7f.
; adding the number of paragraphs for the write to the current value in
; dx.  the current dx value comes from  ((ofs>>4) + segment)
; this should produce a number which represents the highest end of the 
; memory involved in the transfer.

	cmp	ah,2
	je	i13xx1
	cmp	ah,3
	jne	i13xx2
i13xx1:
	push	ax
	xor	ah,ah
	shl	ax,5
	add	dx,ax
	pop	ax
i13xx2:


	cmp	dh,cs:[dmabank] 	; below switched partitions?
	jae	stage			; no, go do staging
	mov	cx,cs:[usercx]		; yes, resume normally
	mov	dx,cs:[userdx]
fastex13:
	popf
	call	call13
	jmp	farret13
stage:
	pop	cs:[userflag]
	push	di
	push	si
	push	ds
	mov	si,cs
	mov	ds,si
	mov	[userax],ax
	mov	[origcmd],ah
	mov	[userbx],bx
	mov	[useres],es
	xor	bh,bh
	mov	bl,ah
	shl	bx,1
	jmp	word ptr [int13tab+bx]

i13pass:
	mov	ax,[userax]
	mov	bx,[userbx]
	mov	cx,[usercx]
	mov	dx,[userdx]
	mov	es,[useres]
	push	[userflag]
	popf
	pop	ds
	pop	si
	pop	di
	jmp	dword ptr cs:[oldint13]


	subttl x13ext - stage int 13h 42h/43h (extended read/write)
	page
;======================================================================
;,fs
; x13ext - stage int 13h 42h/43h (extended read/write)
;
; the kernel reads and writes hard disks with the int 13h extensions
; when the bios has them (UPDATE 93).  a bios that transfers with
; bus-master dma (vmware, many real machines) writes to physical
; addresses, but a buffer in remapped (paged) memory is somewhere
; else physically: reads land in the wrong place, writes take the
; wrong data.  so, as for the other disk calls, a transfer whose
; buffer reaches into remapped memory (dmabank and up) goes through
; the staging buffer, in pieces of at most buffsize.  a buffer below
; dmabank is passed straight through.  (UPDATE 103)
;
; in:	int 13h 42h/43h registers: ds:si -> disk address packet
;	(size, 0, count, buffer offset, buffer segment, 64-bit lba)
;	stack: flags pushed by entinr13
;
; out:	as int 13h: cy and ah = error code if error; on an error the
;	packet's count is set to the sectors transferred
;
;,fe
;======================================================================
x13ext:
	pop	cs:[userflag]
	push	di
	push	si
	push	ds
	mov	cs:[userax],ax
	mov	cs:[userbx],bx
	mov	cs:[usercx],cx
	mov	cs:[userdx],dx
	mov	cs:[useres],es
	mov	cs:[origcmd],ah
	mov	cs:[xdapofs],si
	mov	cs:[xdapseg],ds

; last paragraph of the caller's buffer: segment + offset/16 + count*32

	mov	bx,[si+4]
	shr	bx,4
	add	bx,[si+6]
	jc	x13stg
	mov	ax,[si+2]
	cmp	ax,800h			; count*32 would overflow
	jae	x13stg
	shl	ax,5
	add	ax,bx
	jc	x13stg
	cmp	ah,cs:[dmabank]		; below remapped memory?
	jae	x13stg
	push	cs			; i13pass expects ds = cs
	pop	ds
	jmp	i13pass			; no staging needed

x13stg:
	mov	ax,cs
	mov	ds,ax
	mov	ax,[buffsize]
	xor	dx,dx
	mov	bx,512
	div	bx
	mov	[buffsects],ax
	les	si,dword ptr [xdapofs]	; es:si -> caller's packet
	mov	ax,es:[si+2]
	mov	[xleft],ax
	mov	ax,es:[si+4]
	mov	[xuofs],ax
	mov	ax,es:[si+6]
	mov	[xuseg],ax
	mov	ax,es:[si+8]
	mov	word ptr [xdap+8],ax
	mov	ax,es:[si+10]
	mov	word ptr [xdap+10],ax
	mov	ax,es:[si+12]
	mov	word ptr [xdap+12],ax
	mov	ax,es:[si+14]
	mov	word ptr [xdap+14],ax
	mov	[xdone],0
	mov	byte ptr [xdap],16
	mov	byte ptr [xdap+1],0
	mov	word ptr [xdap+4],0
	mov	ax,[buffaddr]
	mov	word ptr [xdap+6],ax

x13lp:
	mov	ax,[xleft]
	or	ax,ax
	jz	x13ok
	cmp	ax,[buffsects]
	jbe	x13l1
	mov	ax,[buffsects]
x13l1:
	mov	[xnow],ax
	mov	word ptr [xdap+2],ax
	cmp	[origcmd],43h		; write: caller's data to the buffer
	jne	x13l2
	call	x13cpy
x13l2:
	mov	ah,[origcmd]
	mov	al,byte ptr [userax]
	mov	dx,[userdx]
	mov	si,offset xdap		; ds = cs
	call	call13u
	pushf
	pop	[userflag]
	mov	[userax],ax
	jc	x13er
	cmp	[origcmd],42h		; read: buffer to the caller's data
	jne	x13l3
	call	x13cpy
x13l3:
	mov	ax,[xnow]
	add	[xdone],ax
	sub	[xleft],ax
	add	word ptr [xdap+8],ax	; lba += pieces
	adc	word ptr [xdap+10],0
	adc	word ptr [xdap+12],0
	adc	word ptr [xdap+14],0
	shl	ax,5			; caller's buffer += xnow*512 bytes
	add	[xuseg],ax
	jmp	x13lp

x13er:
	les	si,dword ptr [xdapofs]	; report sectors done
	mov	ax,[xdone]
	mov	es:[si+2],ax
	jmp	i13exit

x13ok:
	mov	byte ptr [userax+1],0	; ah = 0, carry clear
	and	byte ptr [userflag],0feh
	jmp	i13exit

;==== copy xnow sectors between the caller's buffer and the staging
;==== buffer: to the buffer for 43h, from it for 42h.  ds = cs.

x13cpy:
	pushset ax,cx,si,di,ds,es
	mov	cx,[xnow]
	xchg	ch,cl			; cx = xnow*256 words
	cld
	cmp	[origcmd],43h
	jne	x13c1
	mov	es,[buffaddr]
	xor	di,di
	mov	si,[xuofs]
	mov	ds,[xuseg]
	jmp	short x13c2
x13c1:
	mov	es,[xuseg]
	mov	di,[xuofs]
	mov	ds,[buffaddr]
	xor	si,si
x13c2:
	rep	movsw
	popset ax,cx,si,di,ds,es
	ret


	subttl advance_sect - calc new cyl, head, sect for +sect
	page
;======================================================================
;,fs
; advance_sect - calc new cyl, head, sect for +sect
;
; accepts cylinder, head and sector information in int13 call format
; and derives the new cylinder, head and sector values for advancing
; a certain number of sectors.
; 
;             �� 			             Ŀ
;  	      �  q1/r1 = (cur_sect + add_sect) / spt  � 
; cur_cyl  -> �  �� if(r1 == 0)		              � -> new_cyl
; cur_head -> �  � r1 = spt			      � -> new_head
; cur_sect -> �  � q1--			              � -> new_sect
; add_sect -> �  �� 				      � 
; heads	   -> �  cur_sect = r1			      � 
; spt	   -> �  q2/r2 = (cur_head + q1) / heads      � 
; 	      �  cur_head = r2			      � 
; 	      �  cur_cyl += q2			      � 
; 	      ��				     ��
; 
; in:	al = # of sectors to advance (add_sect)
;	ch = cylinder # (high 2 bits in cl) (cur_cyl)
;	cl = sector # (plus high bits of cylinder #) (cur_sect)
;	dh = head # (cur_head)
;	bh = total # of heads (heads)
;	bl = sectors per track (spt)
;
; out:	ch = cylinder # (high 2 bits in cl) (new_cyl)
;	cl = sector # (plus high bits of cylinder #) (new_sect)
;	dh = head # (new_head)
;	
;,fe
;=====================================================================
advance_sect:
	pushset ax,bx,si,di
	xor	ah,ah			; ax = add_sect
	mov	si,cx
	and	si,3fh			; si = cur_sect 
	rol	cl,2
	and	cl,3
	xchg	ch,cl			; cx = cur_cyl
	add	ax,si			; ax = (cur_sect + add_sect)
	mov	si,bx
	and	si,0ffh			; si = spt
	mov	di,dx
	xor	dx,dx
	div	si
	or	dx,dx
	jnz	ads1			; if (rem == 0)
	mov	dx,si			; r1 = spt
	dec	ax			; q1--
ads1:
	xchg	di,dx			; di = cur_sect
	xchg	dh,dl
	mov	si,dx
	xchg	dh,dl
	and	si,0ffh			; si = cur_head
	add	ax,si			; ax = (cur_head + q1)
	mov	bl,bh
	xor	bh,bh			; bx = heads
	mov	si,dx
	xor	dx,dx
	div	bx
	mov	bl,dl			; new_head = r2
	mov	dx,si
	mov	dh,bl			; dh = new_head, dl preserved
	add	cx,ax			; cx = new_cyl = cur_cyl + q2
	xchg	ch,cl
	ror	cl,2			; hi 2 bits of cyl # to cl hi bits
	mov	ax,di
	or	cl,al			; cl (b0 - b5) = new_sect
	popset ax,bx,si,di
	ret


	subttl rw_piece - read into staging buffer & copy to caller's buffer
	page
;======================================================================
;,fs
; rw_piece - read into staging buffer & copy to caller's buffer
; 
; in:	al = entry al for int13 call
;	[origcmd] = orig ah value
;	di = offset for data within caller's buffer
;	[usercx] = entry cx for int13 call
;	[userdx] = entry dx for int13 call
;	[useres] = entry es for int13 call
;	[buffaddr] = segment for read
;	[bps] = bytes per sector
;
; out:	[userax] = exit ax from int13 call
;	[userflag] = exit flags from int13 call
;	di = next offset in caller's buffer (invalid if int13 error)
;	crashes ax,bx,cx,dx,si,es
;
;,fe
;=====================================================================
rw_piece:
	mov	ah,[origcmd]
	cmp	ah,2			; doing a read?
	je	r_piece
	cmp	ah,0ah
	je	r_piece
	cmp	ah,0eh
	je	r_piece
	cmp	ah,1ah
	je	r_piece
	jmp	w_piece			; must be write

;==== read piece

r_piece:
	push	ax
	mov	es,[buffaddr]
	xor	bx,bx
	mov	cx,[usercx]
	mov	dx,[userdx]
	push	di
	call	call13u 		; call original int 13 bios
	pop	di
	pushf
	pop	[userflag]		; save returned flags and ax
	mov	[userax],ax
	test	ah,80h			; time out?
	pop	ax			; recover entry al
	jnz	i13rskp2		; yes, not safe to move data
	xor	ah,ah			; calc # of bytes to move
	mov	cx,[bps]
	mul	cx			; presuming dx must be 0
	mov	cx,ax
	mov	es,[useres]		; move data to user area
	xor	si,si
	push	ds
	mov	ds,[buffaddr]
	cld

	.386
	shr	cx,2			; if 386, use 32-bit word moves
	rep	movsd
	.286
	nop	 			; accomodate alleged 386 bug

	pop	ds
i13rskp2:
	ret

;==== write piece

w_piece:
	push	ax
	xor	ah,ah			; calc # of bytes to move
	mov	cx,[bps]
	mul	cx			; presuming dx must be 0
	mov	cx,ax
	pop	ax
	mov	es,[buffaddr]
	push	ds
	mov	ds,[useres]		; move data to user area
	mov	si,di
	xor	di,di
	cld

	.386
	shr	cx,2			; if 386, use 32-bit word moves
	rep	movsd
	nop 				; accomodate alleged 386 bug
	.286

	mov	di,si
	pop	ds
	xor	bx,bx
	mov	cx,[usercx]
	mov	dx,[userdx]
	push	di
	call	call13u 		; call original int 13 bios
	pop	di
	pushf
	pop	[userflag]		; save returned flags and ax
	mov	[userax],ax
	ret


	subttl fixbps - fetch bps from diskette parms table for floppy operations
	page
;======================================================================
;,fs
; fixbps - fetch bps from diskette parms table for floppy operations
; 
; in:	[userdx] (dl) = drive number
;
; out:	bx = bps (read from diskette parm table for dl < 80)
;
;,fe
;======================================================================
fixfbps:
	cmp	byte ptr [userdx],80h	; hard disk?
	jae	fxf1			; yes, skip
	pushset	cx,si,es
	mov	es,[zero]
	les	si,dword ptr es:[0078h] ; address diskette parm table
	mov	cl,es:[si+3]		; load bytes/sector indicator
	mov	bx,128
	shl	bx,cl			; bx is now correct bytes/sector
	popset	cx,si,es
fxf1:
	ret


	subttl call13u, call13 - call the rom bios int13 handler
	page
;======================================================================
;,fs
; call13u, call13 - call the rom bios int13 handler
;
; in:	int13 entry registers
;	 (if call call13u, [userflag] is put into flags register)
;
; out:	int13 exit registers
;
;,fe
;======================================================================
call13u proc	near
	push	word ptr [userflag]
	popf
call13:
	cli
	pushf
	call	dword ptr cs:[oldint13]
	ret
call13u endp


	subttl 
	page
;======================================================================
;,fs
; i13nread, i13lread, i13sread, i13nwrit, i13lwrit, i13swrit
; 
; process dma read and write requests
;
; in:	al = # of sectors to read
;	[userax], [userbx], [usercx], [userdx], [useres],
;	[userflag] and [origcmd] set from int13 entry values
;
; out:	[userax], [userbx], [usercx], [userdx], [useres] and
;	[userflag] set for int13 exit values
;
;,fe
;======================================================================
i13nread:
i13nwrit:
	mov	bx,512
	jmp	short i13read
i13lread:
i13lwrit:
	mov	bx,516
	jmp	short i13read
i13sread:
i13swrit:
	mov	al,1
	mov	bx,512
i13read:
i13write:

; al is now the number of sectors requested
; bx is bps

	mov	[origsects],al
	call	fixfbps			; fix bps for floppys
	mov	[bps],bx
	mov	ax,[buffsize]
	xor	dx,dx
	div	bx
	mov	[buffsects],ax		; using word for 64k/128 case
	mov	di,[userbx]
	mov	byte ptr [heads],0
	mov	al,[origsects]

; al is now the number of sectors requested
; [buffsects] is the max number of sectors which can fit within buffsize
; di is the starting offset within the caller's buffer

read_loop:
	xor	ah,ah
	cmp	ax,[buffsects]		; if request > available
	ja	mult_pieces		; must do in multiple pieces
	call	rw_piece		; do in one piece
	jmp	i13rexit
mult_pieces:
	mov	dx,[userdx]

; since int13fun08 is not supported for diskettes on all machines
; (e.g. Compaq 16Mhz 386) we cannot easily know the spt and heads
; values.  rather than try to determine the media, the following
; logic simply presumes that no update of the head or cylinder
; will be required.

	cmp	dl,80h			; skip int13fun08 call for diskette
	jb	mp1
	cmp	byte ptr [heads],0	; already made the call? 
	jne	mp1
	mov	ah,8
	push	di
	call	call13	 		; call original int 13 bios
	pop	di
	inc	dh
	mov	[heads],dh		; advance_sect needs these
	and	cl,3fh
	mov	[spt],cl
mp1:
	mov	ax,[userax]
	mov	cl,byte ptr [buffsects]  ; hi word must be 0 anyway
	sub	al,cl
	mov	[remainsects],al
	mov	al,cl
	push	ax
	call	rw_piece		; read a buffer full
	pop	ax
	push	[userflag]		; if error, get out now
	popf
	jc	i13rexit
	mov	cx,[usercx]
	mov	dx,[userdx]
	cmp	dl,80h			; use simple/dumb method for diskette
	jb	mp2
	mov	bh,[heads]
	mov	bl,[spt]		; adjust cx and dx for next piece
	call	advance_sect
	mov	[userdx],dx
	jmp	short mp3
mp2:
	mov	bl,cl			; simple/dump sector advance (diskette)
	and	bl,0c0h
	and	cl,3fh
	add	cl,al
	or	cl,bl
mp3:
	mov	[usercx],cx
	mov	al,[remainsects]	; update accounting
	mov	byte ptr [userax],al
	or	al,al
	jz	i13rexit		; any more?
	jmp	read_loop
i13rexit:
	mov	al,[origsects]
	mov	byte ptr [userax],al
	jmp	i13exit


	subttl 
	page
;======================================================================
;,fs
; i13fmt, i13verfy
; 
; process format and verify operations
;
; in:	[userax], [userbx], [usercx], [userdx], [useres],
;	[userflag] and [origcmd] set from int13 entry values
;
; out:	[userax], [userbx], [usercx], [userdx], [useres] and
;	[userflag] set for int13 exit values
;
;,fe
;======================================================================
i13fmt:
	mov	al,1
	mov	bx,512
	cmp	byte ptr [userdx],80h	; hard disk?
	jae	skipflop		; yes, skip
	mov	es,[zero]
	les	si,dword ptr es:[0078h]	; address diskette parm table
	mov	cl,es:[si+3]		; load bytes/sector indicator
	mov	bx,128
	shl	bx,cl			; bx is now correct bytes/sector
skipflop:
	xor	ah,ah
	mul	bx
	jc	i13error
	cmp	ax,[buffsize]		; check if too big for buffer
	ja	i13error
	push	ds
	mov	cx,ax
	mov	es,[buffaddr]		; move data from user buffer
	xor	di,di
	mov	si,[userbx]
	mov	ds,[useres]
	cld

	.386
	shr	cx,2			; if 386, use 32-bit word moves
	rep	movsd
	nop	 			; accomodate alleged 386 bug
	.286

	pop	ds

;==== entry point for verify

i13verfy:
	mov	es,[buffaddr]
	xor	bx,bx
	mov	ax,[userax]		; setup int 13
	mov	cx,[usercx]
	mov	dx,[userdx]
	call	call13u 		; call original int 13 bios
	pushf
	pop	[userflag]		; save returned flags and ax
	mov	[userax],ax

;==== common exit handler

i13exit:
	mov	ax,[userax]
	mov	bx,[userbx]
	mov	cx,[usercx]
	mov	dx,[userdx]
	mov	es,[useres]
	push	[userflag]
	popf
	pop	ds
	pop	si
	pop	di
farret13:
	retf	2

;==== common error handler for buffer overflow

i13error:
	or	byte ptr [userflag],01h	; set carry for failed operation
	mov	word ptr [userax],0bb00h ; indicate undefined error in ah
	jmp	i13exit


;======================================================================
;,fs
; rhentry
;
; this function must be reentrant and must not change the
; state of the interrupt enable flag.
;
; all entry registers except bp must be passed through to the 
; subfunction.  all subfunction exit registers except bp must be 
; passed back to the caller.
;
; in:	ah = sub-function #
;	other registers depend on function being called
;
; out:	depends on function being called
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
rhentry:


IF RHTRACE
	call	rhdebug 		; display request handler debugging
ENDIF

	cmp	ah,rhtablen/2		; invalid function codes are ignored
	jae	rhe1
	push	bx
	push	bp
	mov	bp,sp
	mov	bx,offset mmgrp:rhe2
	push	bx
	mov	bl,ah
	xor	bh,bh
	shl	bx,1
	push	cs:[rhtable+bx]
	mov	bx,[bp+2]
	mov	bp,[bp]
	ret
rhe2:
	pop	cs:[pop_junk]		; balance the stack without changing
	pop	cs:[pop_junk]		; any registers, including flags
rhe1:
	retf

pop_junk dw	?

	even
rhtable label	word
	dw	vreboot 		; ah=0
	dw	valloc			; ah=1
	dw	vrelease		; ah=2
	dw	vremap			; ah=3
	dw	vunmap			; ah=4
	dw	vphymap 		; ah=5
	dw	vprotect		; ah=6
	dw	vunprot 		; ah=7
	dw	vsetiop 		; ah=8
	dw	vclriop 		; ah=9
	dw	3 dup(?)		; 0a,0b,0c - reserved for _286.asm
	dw	vlistmap		; ah=0d
	dw	vdrvstat		; ah=0e
	dw	vsetnmi 		; ah=0f
	dw	vclrnmi 		; ah=10
	dw	vblkcpy 		; ah=11
;
; VCPI/DPMI Functions
;
	dw	vget0phy		; ah=12
	dw	vreadcr0		; ah=13
	dw	vreaddebug		; ah=14
	dw	vloaddebug		; ah=15

rhtablen equ	$-rhtable

IF RHTRACE+REGDISP
;======================================================================
;,fs
; rhdebug
;
; request handler debugging (if rhtrace is true)
;
; in:	
;
; out:	
;
;,fe
;=====================================================================
rhmsg	db	'MEMDEV Request '	;@@xlat
rhax	db	'    H  BX= '
rhbx	db	'    H  CX= '
rhcx	db	'    H  ES= '
rhes	db	'    H',13,10,'$'
hextab	db	'0123456789ABCDEF'
rhpause db	0

rhdebug proc	near
	push	ax
	push	bx
	push	cx
	push	dx
	push	ds
	push	si
	push	cs
	pop	ds
	push	cx
	push	bx
	mov	bx,offset mmgrp:rhax+3	; convert ax to hex
	call	bin2hex
	pop	ax			; pushed as bx
	mov	bx,offset mmgrp:rhbx+3	; convert bx to hex
	call	bin2hex
	pop	ax			; pushed as cx
	mov	bx,offset mmgrp:rhcx+3	; convert cx to hex
	call	bin2hex
	mov	ax,es
	mov	bx,offset mmgrp:rhes+3	; convert es to hex
	call	bin2hex
	mov	dx,cs:[portaddr]
	mov	si,offset mmgrp:rhmsg	; point to message
rhdblp:
	lodsb
	cmp	al,'$'			; are we at the end
	je	rhdbend
	mov	ah,al
rhdbout:
	add	dl,5
	in	al,dx
	sub	dl,5
	test	al,20h
	jz	rhdbout
	jmp	$+2
	mov	al,ah
	out	dx,al
	jmp	rhdblp
rhdbend:
	mov	dx,mmgrp:[portaddr]
	add	dl,5
	in	al,dx
	sub	dl,5
	test	al,01h
	jz	rhdbskip
	xor	mmgrp:[rhpause],1
	in	al,dx
rhdbskip:
	cmp	mmgrp:[rhpause],1
	je	rhdbend
	pop	si
	pop	ds
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
rhdebug endp

;======================================================================
;,fs
; bin2hex
;
; in:	ds:bx -> end of destination buffer
;	ax = word to convert
;
; out:	none
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
bin2hex proc	near
	push	ax
	push	bx
	push	cx
	push	si
	mov	dl,4
b2hexl1:
	mov	si,ax
	and	si,000fh
	mov	cl,mmgrp:[hextable+si]
	mov	[bx],cl
	shr	ax,4
	dec	bx
	dec	dl
	jg	b2hexl1
	pop	si
	pop	cx
	pop	bx
	pop	ax
	ret
bin2hex endp

ENDIF


;======================================================================
;,fs
; vreboot - memdev api function 00h
;
; in:	none
;
; out:	none
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vreboot:
	push	cs
	pop	ds
	assume	ds:mmgrp
	cli
	mov	ss,mmgrp:[buffaddr]	; use staging buffer for our stack
	mov	sp,256
	mov	ax,7700h		; use int 6f to enter real mode
	int	6fh
	cmp	mmgrp:[foption],0
	jne	fullboot
	mov	ax,40h
	mov	es,ax
	mov	word ptr es:[72h],1234h
fullboot:

	db	0eah			; direct intersegment jump
	dw	0fff0h,0f000h		;   into bios reset code


;======================================================================
;,fs
; valloc - memdev api function 01h
;
; if the allocation request cannot be satisfied, the largest
; available block is returned. the variable parmused is dynami-
; cally maintained to indicate how much extended memory is used.
;
; in:	cx = number of banks desired
;
; out:	ax = 0 if successful, 1 if less allocated than requested
;	bx = starting bank number
;	cx = actual number of banks allocated
;	other registers are preserved
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
valloc  proc	near
	mov	word ptr mmgrp:[ntrash1],cx
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	ax,7705h		; the native mode valloc proc
	int	6fh			; will have to modify the page table
	mov	ax,word ptr mmgrp:[ntrash1]
	mov	bx,word ptr mmgrp:[ntrash2]
	mov	cx,word ptr mmgrp:[ntrash3]
	ret
valloc	endp

;======================================================================
;,fs
; vrelease - memdev api function 02h
;
; parmused is maintained.
;
; in:	bx = starting bank number to release
;	cx = number of banks
;
; out:	ax = 0 if no errors
;	     1 if releasing unallocated blocks, or if cx=0
;	bx,cx destroyed
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vrelease proc	near
	mov	word ptr mmgrp:[ntrash1],bx
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	word ptr mmgrp:[ntrash2],cx
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	ax,7706h		; the native mode vrelease proc
	int	6fh			; will have to modify the page table
	mov	ax,word ptr mmgrp:[ntrash1]
	ret
vrelease endp

;======================================================================
;,fs
; maint_dmabank
;
; in:	
;
; out:	
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
maint_dmabank:
	cmp	bl,mmgrp:[dmabank]	; maintain lowest remapped bank
	jae	vremcont
	or	bl,bl
	jz	vremcont
	mov	mmgrp:[dmabank],bl
vremcont:
	ret


;======================================================================
;,fs
; vremap - memdev api function 03h
;
; !! any changes made to this routine should be echoed into vlistmap
;
; in:	bx = starting handle # to map into meg0
;	cx = number of banks
;	es = segment address (must be multiple of granule size)
;
; out:	ax = 0
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vremap	proc  near
	push	bx
	push	cx
	pushf				; save interrupt flag state
	cli				; insure no irq's
	mov	ax,bx
	mov	bx,es
	mov	bl,bh
	xor	bh,bh
	call	maint_dmabank

; at this point:  ax = page # relative to parspace (handle)
;		  bx = page frame # within 1st meg
;		  cx = # of pages to remap

	call	remap
	xor	ax,ax
	popf				; restore interrupt flag state
	pop	cx
	pop	bx
	ret
vremap	endp


;======================================================================
;,fs
; vunmap - memdev api function 04h
;
; !! any changes made to this routine should be echoed into vlistmap
;
; in:	cx = number of banks
;	es = segment address (must be multiple of granule size)
;
; out:	ax = 0
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vunmap	proc  near
	push	es
	push	bx
	push	cx
	pushf				; save interrupt flag state
	cli				; insure no irq's
	mov	ax,es
	mov	al,ah
	xor	ah,ah

; at this point:  ax = starting page frame # to be unmapped
;		  cx = number of frames to identity map

	call	selfmap
	xor	ax,ax
	popf				; restore interrupt flag state
	pop	cx
	pop	bx
	pop	es
	ret
vunmap	endp


;======================================================================
;,fs
; vphymap - memdev api function 05h
;
; !! any changes made to this routine should be echoed into vlistmap
;
; in:	bx = starting physical bank number to map into meg0
;	cx = number of banks
;	es = segment address (must be multiple of granule size)
;
; out:	ax = 0
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vphymap	proc  near
	pushf				; save interrupt flag state
	cli				; insure no irq's
	push	bx
	push	cx
	mov	ax,bx
	mov	bx,es
	mov	bl,bh
	xor	bh,bh

; at this point:  ax = page # to be remapped
;		  bx = page frame # to remap into
;		  cx = number of pages

	call	phymap
	pop	cx
	pop	bx
	popf				; restore interrupt flag state
	xor	ax,ax
	ret
vphymap  endp


;======================================================================
;,fs
; vprotect - memdev api function 06h
;
; if an attempt is made to write on protected memory, an int 6 is
; generated, with the cs and ip values saved on the stack pointing
; to the offending instruction. in addition, parm6ec is set to 0,
; and the doubleword at parm6adr is set to the 32-bit address to
; which the write was attempted.
;
; in:	bx = starting physical bank number, 
;		or else starting handle + 0110h
;	cx = number of banks
;
; out:	ax = 0 if no errors
;	bx,cx destroyed
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vprotect proc	near
	mov	word ptr mmgrp:[ntrash1],bx
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	word ptr mmgrp:[ntrash2],cx
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	ax,7707h		; the native mode nprotect proc
	int	6fh			; will have to modify the page table
	mov	ax,word ptr mmgrp:[ntrash1]
	ret
vprotect endp

;======================================================================
;,fs
; vunprot - memdev api function 07h
;
; in:	bx = starting physical bank number,
;		or else starting handle + 0110h
;	cx = number of banks
;
; out:	ax = 0 if no errors
;	bx,cx destroyed
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vunprot proc	near
	mov	word ptr mmgrp:[ntrash1],bx
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	word ptr mmgrp:[ntrash2],cx
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	ax,7708h		; the native mode nunprot proc
	int	6fh			; will have to modify the page table
	mov	ax,word ptr mmgrp:[ntrash1]
	ret
vunprot endp

;======================================================================
;,fs
; vsetiop - memdev api function 08h
;
;  byte 0, bit 0 of the 128-byte bit map corresponds to i/o address
;  000; byte 127, bit 7 corresponds to 3ff. a zero bit allows i/o
;  to its port address; a 1 bit causes an int 6 to be generated if
;  i/o is attempted.  when the int 6 occurs, the cs and ip values
;  saved on the stack point to the offending instruction.  parm6ec
;  indicates the type of instruction, as follows:
;      3 - in al,xx
;      4 - in ax,xx
;      5 - out xx,al
;      6 - out xx,ax
;      7 - in al,dx
;      8 - in ax,dx
;      9 - out dx,al
;     10 - out dx,ax
;  in addition, the word at parm6adr is set to the 4 bytes of code
;  starting at cs:ip.
;
; in:	es:bx = pointer to 128-byte bit map (i/o addr 0-3ff)
;
; out:	ax = 0
;	bx,cx destroyed
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vsetiop  proc  near
	push	di
	push	ds
	push	es
	mov	si,bx
	mov	di,offset mmgrp:t2iopbm
	mov	bx,es
	mov	ds,bx
	mov	bx,cs
	mov	es,bx
	mov	cx,128/4
	cld
	.386
	rep	movsd
	.286
	nop
	pop	es
	pop	ds
	pop	di
	or	byte ptr mmgrp:[t2iopbm],10h	; protect port 04h
	or	byte ptr mmgrp:[t2iopbm+10h],02h  ; and port 81h
	or	byte ptr mmgrp:[t2iopbm+1ch],01h  ; and port 0e0h (int 6fh gateway)
	xor	ax,ax
	ret
vsetiop  endp


;======================================================================
;,fs
; vclriop - memdev api function 09h
;
; this is a shortcut method of clearing the entire permission map.
;
; in:	none
;
; out:	ax = 0
;	bx,cx destroyed
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vclriop  proc  near
	push	di
	push	es
	mov	di,offset mmgrp:t2iopbm
	mov	bx,cs
	mov	es,bx
	.386	
	xor	eax,eax
	mov	cx,128/4
	cld
	rep	stosd
	.286
	nop
	pop	es
	pop	di
	or	byte ptr mmgrp:[t2iopbm],10h	; protect port 04h
	or	byte ptr mmgrp:[t2iopbm+10h],02h  ; and port 81h
	or	byte ptr mmgrp:[t2iopbm+1ch],01h  ; and port 0e0h (int 6fh gateway)
	ret
vclriop  endp


;======================================================================
;,fs
; vlistmap - memdev api function 0Dh
;
; list record format:
;
;  +0	action code	word	0 skip, 3 remap, 4 unmap, 5 phymap
;  +2	segment 	word
;  +4	1st bank #	word	(n/a for unmap)
;  +6	1st page count	word
;  +8	2nd bank #	word	** these 2nd bank # and page count
;  +10	2nd page count	word	** fields are only for the remap case.
;
; in:	es:di -> list of mapping instructions and data
;	cx = number of records in list
;
; out:	none
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vlistmap proc	near
	pushf				; save current interrupt flag state
	cli				; insure no irq's

; do an initial scan of the list for remap entries and let
; maint_dmabank see each of the meg0 page numbers (high byte of segment)

	push	cx
	push	di
vlm1:
	cmp	word ptr es:[di],3
	jne	vlm3
	mov	bl,es:[di+3]		; get high byte of segment
	call	maint_dmabank
vlm3:
	add	di,12			; advance to next list entry
	loop	vlm1
	pop	di
	pop	cx

; form zero based linear address of list in ntrash1

	push	ax
	push	cx
	push	dx
	xor	dx,dx
	mov	ax,es
	shl	ax,1			; convert the segment to
	rcl	dx,1			; a linear address
	shl	ax,1			; convert the segment to
	rcl	dx,1			; a linear address
	shl	ax,1			; convert the segment to
	rcl	dx,1			; a linear address
	shl	ax,1			; convert the segment to
	rcl	dx,1			; a linear address
	add	ax,di			; add in the offset
	adc	dx,0
	mov	word ptr mmgrp:[ntrash1],ax  ; put where nlistmap can get it
	mov	word ptr mmgrp:[ntrash1+2],dx
	mov	word ptr mmgrp:[ntrash2],cx  ; setup count
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	ax,7701h		; nlistmap must access the page
	int	6fh			; table in native mode
	pop	dx
	pop	cx
	pop	ax
	popf				; restore interrupt flag state
	ret
vlistmap endp

	subttl vdrvstat - return driver status information
	page
;======================================================================
;,fs
; vdrvstat - memdev api function 0Eh
;
; return driver status information
;
; in:	bx == 0  (so signature is meaningful)
;
; out:	ax = highest function number supported
;	bx = fa05 (signature)
;	cx = feature bits
;	      b0  - 1 means the memdev is $386.sys - 386 cpu or above
;	      b1  - 1 means protected mode nmi support is active (/n)
;	      b2  - 1 means
;	      b3  - 1 means
;	      b4  - 1 means
;	      b5  - 1 means
;	      b6  - 1 means
;	      b7  - 1 means
;	      b8  - 1 means
;	      b9  - 1 means
;	      b10 - 1 means
;	      b11 - 1 means
;	      b12 - 1 means
;	      b13 - 1 means
;	      b14 - 1 means
;	      b15 - 1 means
;
;	dx = feature bits
;	      b0  - 1 means
;	      b1  - 1 means
;	      b2  - 1 means
;	      b3  - 1 means
;	      b4  - 1 means
;	      b5  - 1 means
;	      b6  - 1 means
;	      b7  - 1 means
;	      b8  - 1 means
;	      b9  - 1 means
;	      b10 - 1 means
;	      b11 - 1 means
;	      b12 - 1 means
;	      b13 - 1 means
;	      b14 - 1 means
;	      b15 - 1 means
;
;,fe
;=====================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vdrvstat proc	near
	mov	bx,0fa05h		; signature
	mov	ax,rhtablen/2-1 	; return highest function supported
	mov	cx,mmgrp:[dvstat1]
	mov	dx,mmgrp:[dvstat2]
	ret
vdrvstat endp

	subttl vsetnmi - establish a new protected mode nmi handler
	page
;======================================================================
;,fs
; vsetnmi - memdev api function 0Fh
;
; establish a new protected mode nmi handler
;
; in:	bx:cx = cs:ip of new nmi handler (16 bit seg:ofs format)
;
; out:	ax = 0 if successful
;	 bx:cx = 32 bit offset of previous handler
;	 dx = code selector of previous handler
;	 di = data selector of previous handler
;	ax == 1 if failed due to insufficient memory in gdt table
;	 bx, cx, dx and di undefined
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vsetnmi proc	near
	mov	word ptr mmgrp:[ntrash1],bx
	mov	word ptr mmgrp:[ntrash2],cx
	mov	ax,7709h
	int	6fh
	mov	ax,word ptr mmgrp:[ntrash3]
	mov	bx,word ptr mmgrp:[ntrash1+2]
	mov	cx,word ptr mmgrp:[ntrash1]
	mov	dx,word ptr mmgrp:[ntrash2+2]
	mov	di,word ptr mmgrp:[ntrash2]
	ret
vsetnmi endp

	subttl vclrnmi - restore previous protected mode nmi handler
	page
;======================================================================
;,fs
; vclrnmi - memdev api function 10h
;
; restore previous protected mode nmi handler
;
; in:	bx:cx = 32 bit offset of previous handler
;	dx = code selector of previous handler
;	di = data selector of previous handler
;
; out:	none
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing
vclrnmi proc	near
	mov	word ptr mmgrp:[ntrash1+2],bx
	mov	word ptr mmgrp:[ntrash1],cx
	mov	word ptr mmgrp:[ntrash2],dx
	mov	word ptr mmgrp:[ntrash3],di
	mov	ax,770ah
	int	6fh
	ret
vclrnmi endp

;======================================================================
;==== support logic for vblkcpy
;======================================================================

;==== local storage macros

; invoke the definit macro at the start of a block of defbyte,
; defword and defdword macros 

definit	macro
bpofs = 0
	endm


; define a byte of local storage

defb1	macro	bname,ofs
bname	equ	byte ptr [bp+ofs]
	endm

defbyte macro	bname
defb1	bname,%bpofs
bpofs = bpofs + 1
	endm


; define a word of local storage

defw1	macro	wname,ofs
wname	equ	word ptr [bp+ofs]
	endm

defword macro	wname
defw1	wname,%bpofs
bpofs = bpofs + 2
	endm


; define a doubleword of local storage

defd1	macro	dname,ofs
dname	equ	dword ptr [bp+ofs]
	endm

defdword macro	dname
defd1	dname,%bpofs
bpofs = bpofs + 4
	endm


; define a buffer of local storage

defbf1	macro	bname,ofs
bname	equ	byte ptr [bp+ofs]
	endm

defbuf	macro	bname,blen
defbf1	bname,%bpofs
bpofs = bpofs + blen
	endm


; invoke loc_start at the beginning of the function to establish 
; the stack frame.

loc_start macro
	push	bp
	sub	sp,bpofs+2
	mov	bp,sp
defw1	caller_bp,%(bpofs+2)
	endm


; invoke loc_end at the end of the function to delete the stack
; frame and preserve the exit flags.

loc_end	macro 
	pushf
	pop	[bp+bpofs]
	add	sp,bpofs
	popf
	pop	bp
	endm

;==== macros bytes to pages and pages to bytes calculations

;==== NOTE: this section is specific to 4096 bytes per page !!!

pg_size	equ	4096	; # of bytes in one page 

; convert a byte count to a number of pages, truncating any partial amounts
; shifts right by 12 for a 4k bytes/page system
; don't waste time shifting 0 
; expects the phyaddr in dx:ax

b2pt	macro
	local	skip
	push	ax
	or	ax,dx
	pop	ax
	jz	skip
	mov	al,ah			; byte swap to shift by 8
	mov	ah,dl			; quickly
	mov	dl,dh
	xor	dh,dh
	shr	dx,1			; four double word shifts
	rcr	ax,1			; witout looping overhead
	shr	dx,1			; for a fast shift by 4
	rcr	ax,1
	shr	dx,1
	rcr	ax,1
	shr	dx,1
	rcr	ax,1
skip:
	endm


; convert a page count to a number of bytes
; shifts left by 12 for a 4k bytes/page system
; don't waste time shifting 0 
; expects the phyaddr in dx:ax

p2b	macro
	local	skip
	push	ax
	or	ax,dx
	pop	ax
	jz	skip
	mov	dh,dl			; byte swap to shift by 8
	mov	dl,ah			; quickly
	mov	ah,al
	xor	al,al
	shl	ax,1			; four double word shifts			
	rcl	dx,1			; witout looping overhead
	shl	ax,1			; for a fast shift by 4
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
skip:
	endm


; truncate a phyaddr to the next lowest page boundary
; does a logical and with ~fff for a 4k bytes/page system 
; expects the phyaddr in dx:ax

tphy	macro
	and	ax,not 0fffh
	endm


; convert a meg0 phyaddr to a page frame number and an offset within
; the page

; in:	dx:si = phyaddr within meg0
;
; out:	dx = page frame number
;	si = offset within the page

phy2pgo	macro
	push	ax
	mov	ax,si
	and	ax,0fffh		; make ax be offset within page
	shl	si,1
	rcl	dx,1
	shl	si,1
	rcl	dx,1
	shl	si,1
	rcl	dx,1
	shl	si,1
	rcl	dx,1			; dx now holds the page number
	mov	si,ax			; si now holds the offset 
	pop	ax
	endm

;==== end of section which is specific to 4096 bytes per page !!!

max_sc	dw	1000h	; max sub-chunk size 
			;  (max # of bytes to xfer with interrupts off) 


;======================================================================
;,fs
; mso2abs - convert a seg/sel:ofs address to a phyaddr
;
; in:	dx:ax = the seg/sel:ofs type address to convert
;
; out:	dx:ax = the corresponding physical address
;
;,fe
;=====================================================================
	assume ds:nothing,es:nothing,ss:nothing
mso2abs proc	near

;$$$$ if(protected mode) call internal memdev function

soa1:					; non-protected mode logic
	push	bx
	mov	bx,ax
	mov	ax,dx
	xor	dx,dx
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	shl	ax,1
	rcl	dx,1
	add	ax,bx
	adc	dx,0
	pop	bx
	ret
mso2abs endp

;======================================================================
;,fs
; copygt_low
;
; in:	si = task hdl
; 	bx = ofs within task page
;	dx:di = phyaddr of global buffer
;	cx = bytes to copy
;	ax = direction flag (0 for g->t, 1 for t->g)
;
; out:	ax != 0 if error
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing
copygt_low proc	near
	mov	word ptr mmgrp:[ntrash1],si
	mov	word ptr mmgrp:[ntrash1+2],bx
	mov	word ptr mmgrp:[ntrash2],di
	mov	word ptr mmgrp:[ntrash2+2],dx
	mov	word ptr mmgrp:[ntrash3],cx
	mov	word ptr mmgrp:[ntrash3+2],ax
	mov	ax,770bh
	int	6fh
	mov	ax,word ptr mmgrp:[ntrash2]
	ret
copygt_low endp

; this org must remain to insure that no dynamic data is located within
; the first page of meg0.  on 386 systems, the first page is remapped.
; some gizmo and charge systems will also do this.

; !!!!!!!!!! only needed if vblkcpy is not eating up code space

;	org	900h			; 70:900 = 1000


	subttl vblkcpy - protected mode block copy
	page
;======================================================================
;,fs
; vblkcpy - memdev api function 11h
;
; protected mode block copy 
; always does an upwards copy
;
; in:	bx:bp = address of start of handle/page count array	(hp_base)
;	al = (b0 - b6) # of hp array entries			(hp_ele)
;	     (b7) copy direction flag				(dir_flag)
;	      0xxxxxxx - move from global to task buffer
;	      1xxxxxxx - move from task to global buffer   
;	dx = seg/sel corresponding to first task page 		(beg_ad)
;	ds:si == seg/sel:ofs of task buffer 			(task_ptr)
;	es:di = seg/sel:ofs of global buffer 			(glob_ptr)
;	cx = total bytes to copy 				(xfer_bytes)
;
; out:	ax == 0 if no error
;	ax = 1 when entry cx == 0
;	ax = 2 when total pages in array < pgs1
;	ax = 3 for array bounds error
;	ax = 4 for invalid handle
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing

;==== stack variables for copygt

definit
defdword hp_base;	; address of start of handle/page count array
defword  hp_ele;	; # of hp array entries (currently 4)
defword  dir_flag;	; operation code, 0 for g->t, 1 for t->g
defword  xfer_cnt;	; total # of bytes to copy
defdword phy_b		; phyaddr of tcbbegad
defdword phy_t		; phyaddr of task_ptr
defdword phy_g		; phyaddr of glob_ptr
defword  pgs1		; # of pages from pb to pd (inclusive) 
defword  pgs2		; # of pages remaining within current section     
defword  task_hdl	; handle of page containing copy point      
defword  task_hofs	; offset into page for copy point
defword  hp_base2	; offset of page # portion of hp array 
defword  ndx		; index into hp_array

;==== end of stack variables

vblkcpy proc near
	loc_start
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	cmp	cx,0
	jne	cgt1
	mov	ax,1
	jmp 	cgt2
cgt1:
	push	ds
	push	cs
	pop	ds
	assume	ds:mmgrp

; record entry paramters in stack based vars

	mov	[xfer_cnt],cx
	xor	ah,ah
	push	ax
	and	al,7fh
	mov	[hp_ele],ax
	pop	ax
	and	al,80h
	rol	al,1
	mov	[dir_flag],ax
	mov	ax,[caller_bp]
	mov	word ptr [hp_base],ax
	mov	word ptr [hp_base+2],bx

; dx = [tcbbegad], convert to phyaddr and record in pb

	xor	ax,ax
	call	mso2abs
	mov	word ptr [phy_b],ax
	mov	word ptr [phy_b+2],dx

; es:di -> global buffer, convert to phyaddr and record in pgb

	mov	dx,es
	mov	ax,di
	call	mso2abs
	mov	word ptr [phy_g],ax
	mov	word ptr [phy_g+2],dx

; ds:si -> task buffer, convert to phyaddr in dx:ax
; calc pages to traverse,         pgs1 = b2pt(phy_t - phy_b)
; calc offset within task page,   task_hofs = phy_t - tphy(phy_t)

	pop	dx			; pushed as ds
	mov	ax,si
	call	mso2abs
	mov	si,ax
	sub	ax,word ptr [phy_b]
	sbb	dx,word ptr [phy_b+2]
	b2pt
	mov	[pgs1],ax
	mov	ax,si
	tphy
	sub	si,ax
	mov	[task_hofs],si

; derive ptr to page count entries 

	mov	ax,[hp_ele]
	shl	ax,1
	add	ax,word ptr [hp_base]
	mov	[hp_base2],ax

; tally # of pages to pass

	mov	bx,ax			; make es:bx -> page count entries
	mov	es,word ptr [hp_base+2]
	xor	si,si			;ndx
	xor	ax,ax			;w2
	xor	di,di			;w3
	xor	dx,dx			;w1
cgt3:
	mov	di,ax
	add	ax,es:[bx+si]
	cmp	ax,[pgs1]
	ja	cgt4			; done when satisfy pgs1
	add	si,2
	inc	dx
	cmp	dx,[hp_ele]
	jb	cgt3
	mov	ax,2
	jmp 	cgt2
cgt4:
	mov	[ndx],si

; at this point, di is a tally of the pages in all sections
; previous to the current one (the one addressed by ndx).

	mov	ax,[pgs1]
	sub	ax,di			; calc # of pages into section
	mov	dx,es:[bx+si]		; calc # of pages remaining in section
	sub	dx,ax
	dec	dx
	mov	[pgs2],dx
	mov	bx,word ptr [hp_base]	; derive first task handle */
	add	ax,es:[bx+si]
	mov	[task_hdl],ax
cgt5:
	mov	cx,[xfer_cnt]
	cmp	cx,[max_sc]		
	jna	cgt7			; derive amount to transfer
	mov	cx,[max_sc]		; in this cycle
cgt7:
	mov	di,pg_size
	sub	di,[task_hofs]		; calc bytes remaining in task page
	mov	ax,[pgs2]
	xor	dx,dx
	p2b
	add	ax,di			; calc total bytes remaining in section
	adc	dx,0
	or	dx,dx			; limit to remainder in section
	jnz	cgt8
	or	ax,ax
	jz	cgt8
	cmp	ax,cx
	jnb	cgt8
	mov	cx,ax
cgt8:
	push	di			; save # of bytes remaining in task page
	mov	ax,[dir_flag]
	mov	di,word ptr [phy_g]
	mov	dx,word ptr [phy_g+2]
	mov	bx,[task_hofs]
	mov	si,[task_hdl]
	call	copygt_low
	pop	di
	or	ax,ax
	jz	cgt10
	mov	ax,4
	jmp 	cgt2
cgt10:
	sub	[xfer_cnt],cx		; update accounting
	jnz	cgt11			; done yet?
	xor	ax,ax
	jmp 	cgt2
cgt11:
	cmp	cx,di
	jnae	cgt12			; if just xferred more than remainder in page
	mov	ax,cx			; calc how much more
	sub	ax,di
	mov	di,ax
	xor	dx,dx
	b2pt				; calc pages to advance
	inc	ax
	cmp	ax,[pgs2]
	jna	cgt13			; if not enough pages remaining in section
	add	[ndx],2			; advance to next section
	mov	si,[ndx]
	mov	ax,[hp_ele]
	shl	ax,1
	cmp	si,ax
	jne	cgt14
	mov	ax,2
	jmp 	cgt2
cgt14:
	mov	bx,word ptr [hp_base]	; es still set
	mov	ax,es:[bx+si]
	mov	[task_hdl],ax
	mov	bx,[hp_base2]
	mov	ax,es:[bx+si]
	dec	ax
	mov	[pgs2],ax
	mov	[task_hofs],0
	jmp	short cgt15
cgt13:
	add	[task_hdl],ax		; advance within current section
	sub	[pgs2],ax
	mov	ax,di
	tphy
	sub	di,ax
	mov	[task_hofs],di
cgt15:
	jmp	short cgt17
cgt12:
	add	[task_hofs],cx		; advance within current page
cgt17:
	add	word ptr [phy_g],cx
	adc	word ptr [phy_g+2],0	; update global pointer 	
	jmp 	cgt5
cgt2:
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	loc_end
	ret
vblkcpy endp 


	subttl vget0phy - Get Page 0 Physical address
	page
;======================================================================
;,fs
; vget0phy - memdev api function 12h
;
; translate page 0 address into physical address
;
; IN:
;	CX= Linear Page 0 address (0000 - 00FF)
;
; OUT:
;	EDX= Physical address of 4K Page
;	AX=0 if Successfull 
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing

vget0phy proc	near
	or	ch,ch					; this must be 0
	jz	vget0phy1
	mov	ax,1					; indicated  error
	ret
vget0phy1:
	mov	word ptr mmgrp:[ntrash1],cx
	mov	word ptr mmgrp:[ntrash3],0	     	; indicate no error
	mov	ax,770ch		
	int	6fh
	.386
	mov	edx,dword ptr mmgrp:[ntrash1]
	.286
	mov	ax,word ptr mmgrp:[ntrash3]
	ret
vget0phy endp

	subttl vreadcr0 - Read CR0
	page
;======================================================================
;,fs
; vreadcr0 - memdev api function 13h
;
;
; IN:
;
; OUT:
;	EBX	contains CR0 value
;	AX=0 if Successfull 
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing

vreadcr0 proc	near
	mov	ax,770dh
	int	6fh
	.386
	mov	ebx,dword ptr mmgrp:[ntrash2]
	.286
	mov	ax,word ptr mmgrp:[ntrash3]		; get return code
	ret
vreadcr0 endp

	subttl vreaddebug - Read DEBUG register
	page
;======================================================================
;,fs
; vreaddebug - memdev api function 14h
;
;
; IN:
;       ES:DI -> Pointer to array of 8 DWORDS, DR0 first in array
;        	 DR4 and DR5 not used.
;
; OUT:
;	AX=0 if Successfull 
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing

vreaddebug proc	near
	pushf
	cli
	mov	ax,770eh		; Read Debug Registers
	int	6fh
	push	cx
	push	si
	push	di
	push	ds
	
	mov	ax,cs
	mov	ds,ax
	mov	cx,8
	mov	si,offset [debugregs]
	.386
	rep	movsd
	.286

	pop	ds
	pop	di
	pop	si
	pop	cx
	mov	ax,word ptr mmgrp:[ntrash1]		; return error code
	popf
	ret
vreaddebug endp

	subttl vloaddebug - Load Debug registers
	page
;======================================================================
;,fs
; vloaddebug - memdev api function 15h
;
;
; IN:
;       ES:DI -> Pointer to array of 8 DWORDS, DR0 first in array
;        	 DR4 and DR5 not used.
;
; OUT:
;	AX=0 if Successfull 
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing

vloaddebug proc	near
	pushf
	cli
	push	cx
	push	si
	push	di
	push	ds
	
	mov	si,di
	mov	ax,ds
	mov	es,ax
	mov	ax,cs
	mov	es,ax
	mov	cx,8
	mov	di,offset [debugregs]
	.386
	rep	movsd
	.286

	pop	ds
	pop	di
	pop	si
	pop	cx

	mov	ax,770fh		; Load Debug Registers
	int	6fh
	mov	ax,word ptr mmgrp:[ntrash1] 	; return error code
	popf
	ret
vloaddebug endp


;====================== low level mapping routines ==================

	assume	ds:nothing,es:nothing,ss:nothing

;--------------------------------------------------------------------
;	remapping routine.  bx is starting logical page number,
;	ax is starting physical page (ah is megabytes), cx is
;	number of pages to be mapped.	remember that a page is
;	4k bytes (1000 hex) in length.
;--------------------------------------------------------------------

;======================================================================
;,fs
; remap
;
; setup parms and call the native mode remap procedure
;
; in:	ax = page # relative to parspace (handle)
;	bx = page frame # within 1st meg
;	cx = # of pages to remap
;
; out:	none
;
;,fe
;======================================================================
remap   proc	near
	mov	word ptr mmgrp:[ntrash1],ax
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	word ptr mmgrp:[ntrash2],bx
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	word ptr mmgrp:[ntrash3],cx
	mov	word ptr mmgrp:[ntrash3+2],0
	mov	ax,7703h		; the native mode vremap proc
	int	6fh			; will have to modify the page table
	ret
remap   endp

;======================================================================
;,fs
; selfmap
;
; setup parms and call the native mode phymap procedure
;
; in:	ax = starting page frame # to be unmapped
;	cx = number of frames to identity map
;
; out:	none
;
;,fe
;======================================================================
selfmap proc	near
	mov	ah,0
	mov	word ptr mmgrp:[ntrash1],ax
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	word ptr mmgrp:[ntrash2],ax
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	word ptr mmgrp:[ntrash3],cx
	mov	word ptr mmgrp:[ntrash3+2],0
	mov	ax,7704h		; the native mode nphymap proc
	int	6fh			; will have to modify the page table
	ret
selfmap endp

;======================================================================
;,fs
; phymap
; 
; setup parms and call the native mode phymap procedure
;
; in:	ax = page # to be remapped
;	bx = page frame # to remap into
;	cx = number of pages
;
; out:	none
;
;,fe
;======================================================================
phymap  proc	near
	mov	word ptr mmgrp:[ntrash1],ax
	mov	word ptr mmgrp:[ntrash1+2],0
	mov	word ptr mmgrp:[ntrash2],bx
	mov	word ptr mmgrp:[ntrash2+2],0
	mov	word ptr mmgrp:[ntrash3],cx
	mov	word ptr mmgrp:[ntrash3+2],0
	mov	ax,7704h		; the native mode nphymap proc
	int	6fh			; will have to modify the page table
	ret
phymap  endp



	page
;--------------------------------------------------------------------
;		    turn on address bit 20 gate
;--------------------------------------------------------------------
bit20on  proc  near
	push	ax
	cli
	call	clr8042
	mov	al,0d1h
	out	64h,al
	call	clr8042
	mov	al,0dfh
	out	60h,al
	call	clr8042
	pop	ax
	ret
bit20on  endp

clr8042  proc  near
clr8042l:
	in	al,064h 		; read status port
	and	al,02h			; loop until buffer empty
	jnz	clr8042l
	ret
clr8042  endp



	page

; 80386 debugging/tracing stuff

	even
portaddr dw    03f8h			; serial port address
hextable db    '0123456789ABCDEF'

;cs- ---ip--- -ss- ---sp--- -ds- -es- ---ax--- ---bx--- ---cx--- ---dx---

regtabnm label word
	db	40			; cs
	db	36+80h			; ip
	db	52			; ss
	db	48+80h			; sp
	db	28			; ds
	db	24			; es
	db	12+80h			; ax
	db	16+80h			; bx
	db	20+80h			; cx
	db	08+80h			; dx
	db	255

regtabvm label word
	db	40			; cs
	db	36			; ip
	db	52			; ss
	db	48			; sp
	db	60			; ds
	db	56			; es
	db	12			; ax
	db	16			; bx
	db	20			; cx
	db	08			; dx
	db	04			; si
	db	00			; di
	db	32			; bp
	db	255

	even
exmtable label byte
	db	'Divide$         '	; 00 ;@@xlat
	db	'Single step$    '	; 01 ;@@xlat
	db	'NMI interrupt$  '	; 02 ;@@xlat
	db	'Breakpoint$     '	; 03 ;@@xlat
	db	'INTO overflow$  '	; 04 ;@@xlat
	db	'BOUND range$    '	; 05 ;@@xlat
	db	'Invalid opcode$ '	; 06 ;@@xlat
	db	'80x87 absent$   '	; 07 ;@@xlat
	db	'Double fault$   '	; 08 ;@@xlat
	db	'80x87 overrun$  '	; 09 ;@@xlat
	db	'Invalid TSS$    '	; 0a ;@@xlat
	db	'Seg not present$'	; 0b ;@@xlat
	db	'Stack segment$  '	; 0c ;@@xlat
	db	'Protection$     '	; 0d ;@@xlat
	db	'Page fault$     '	; 0e ;@@xlat

;--------------------------------------------------------------------
;	   interrupt vector table for kernel preprocessing
;--------------------------------------------------------------------
ivtable dw	128 dup(0,0)		; allows for interrupts 00-7f

	page
;--------------------------------------------------------------------
;		   parameters available to user
;--------------------------------------------------------------------

;=========== note: the following variables must stay in order =========

	even
parms	label word
parmrhad dw    2 dup(0) 		; address of request handler
parmfeat label word			; special features:
					;   8000h = all memory is managed
					;   4000h = i/o trapping supported
					;   2000h = write protection supported
					;   1000h = use memory mapping for cxt switch
					;   0800h = "declare" supported ($286.sys only)
					;   0400h = ivtable support
					;   0200h = upper 60k supported (fff8:1080)

IF INT6
	dw	0f600h
ELSE
	dw	0b600h
ENDIF

parmgran dw    4096,0			; granularity is 4k per page
parmtot  dw    0,0			; total extended memory (pages)
parmused dw    0,0			; used	extended memory (pages)
parm6ec  dw    0			; error code for int 6
;		0 - writing to protected memory
;		1 - operation exception
;		2 - protection exception (not due to i/o or write protection)
;		3 - in al,xx
;		4 - in ax,xx
;		5 - out xx,al
;		6 - out xx,ax
;		7 - in al,dx
;		8 - in ax,dx
;		9 - out dx,al
;		10 - out dx,ax

parm6adr dw    0,0			; address or i/o instruction for int 6
parmscb  dw    01fch,0			; scb address - filled in by mos
parmiop dw    offset mmgrp:t2iopbm,0	; address of i/o permission bit map
parmaiv dw	offset mmgrp:ivtable
parmpfa dw	0			; address of 4k page frame in staging buffer

;========================= end of fixed area =========================

	page

; dma staging buffer parameters

	even
oldint6f	dd	0		; original real-mode int 6fh vector
oldint13	dd	0		; original int13 vector
buffaddr	dw	0		; disk staging buffer seg address
buffsize	dw	18*512		; disk staging buffer size
origsects	db	0		; initial request sectors
remainsects	db	0		; remaining sectors to process
buffsects	dw	0		; # of sectors which can fit in buffer
origcmd		db	0		; int13 command being processed
heads		db	0		; total heads for drive
spt		db	0		; sectors per track
bps		dw	0		; bytes per sector
userax		dw	0		; entry/exit ax
userbx		dw	0		; entry/exit bx
usercx		dw	0		; entry/exit cx
userdx		dw	0		; entry/exit dx
useres		dw	0		; entry/exit es
userflag	dw	0		; entry/exit flags
xdapofs		dw	0		; caller's disk address packet (42h/43h)
xdapseg		dw	0		; this must immediately follow xdapofs!
xuofs		dw	0		; caller's buffer, advanced per piece
xuseg		dw	0
xleft		dw	0		; sectors still to transfer
xdone		dw	0		; sectors transferred
xnow		dw	0		; sectors in this piece
xdap		db	16 dup (0)	; packet for the staged pieces

; assorted data

rhoff		dw	0		; request header pointer
rhseg		dw	0		; this must immediately follow rhoff!
meg0old 	dw	0080h		; original nbr meg0 banks
meg0new 	dw	0080h		; final number meg0 banks
dmabank 	db	0ffh,0		; bank above which disk staging needed
mysegadr	dw	0		; segment address of this driver
videoadr	dw	0b000h		; seg address of video ram
trash1		dw	-1		; scratch areas
dvstat1 	dw	0		; used by function 14
dvstat2 	dw	0		; used by function 14

	page
;--------------------------------------------------------------------
;		    80386-specific data areas
;--------------------------------------------------------------------
	even
zero1631	dw	0ffffh,0	; constant
loadaddr	dw	0		; initial psp address
parsize 	dd	0		; length of parspace
wsgdtr		dw	gdtlen-1,offset mmgrp:gdt,0  ; to initialize gdt
wsvmidtr	dw	idtlen-1,offset mmgrp:idt,0  ;	   and idt
wsrmidtr	dw	3ffh,0,0	; idtr for real mode
wscr0		dw	0001h,8000h	; to initialize cr0
wshalt		db	0,0		;031388  1 if hlt is pending
;
; TEST (int 6fh reachability from v-86): user IOPL forced to 0.
;
; Was 00110000b = IOPL 3, OR'd into t2eflags+1 during init (see "mov
; al,[uioplb]" further down), which is what fills in the "iopl=??" in
; the t2eflags comment.
;
; At IOPL=3 the INT n instruction is NOT trapped in v-86 mode -- it
; dispatches through the real-mode IVT. IVT[6Fh] was measured as
; F000:1060, the untouched BIOS default stub (identical to the unused
; IVT[6Eh]), so int 6fh issued from a v-86 task never reaches
; entint6f. That severs valloc, which runs in virtual mode BY DESIGN
; ("call allocation routine in virtual mode", the dovmrh/rhentry
; dispatch) and re-enters native mode via int 6fh AX=7705h.
;
; I/O still traps at IOPL=3 through the TSS permission bitmap
; (t2iopbm), which is why the IN/OUT trap path works; INT n has no
; equivalent backstop. t2eflags itself starts the task at IOPL=0,
; which is what the whole dovmint/ivtable reflection path assumes.
;
; Caveat: IOPL=0 also traps CLI/STI/PUSHF/POPF/IRET, so each becomes
; a monitor round-trip. Expect it to be slower, and expect any latent
; bug in those emulation paths to surface immediately.
;
uioplb		db	00110000b	; user i/o privilege level * 16  (TEST of 0 = IOPL 0 reverted; see comment above)
realsw		db	'N'		; if entering real mode on purpose
iveccode	db	0		; saves interrupt number
dmaindex	db	0
dmastuff	db	4 dup(0)
trapflag	db	0		; 01h if tracing is active
trapsave	db	0		; 01h if tracing is active
tprintsw	db	000h		; ff to bypass trace display
spmonsw 	db	'N'		; if monitoring sp high bits
spmondat	db	0
debugint	db	0
ssmondat	dw	0
dblastip	dw	0,0		; eip at previous debug trap
msgadr		dw	0
msgexcp 	db	' exception - processing halted!   ',13,10,'$'	;@@xlat
msgreg		db	'??=0000 $'
msgcrlf 	db	13,10,'$'
msgtrace	db	79 dup(' ')	; cs,ip,ss,sp,ds,es,ax,bx,cx,dx,si,di,bp
		db	13,10

pd_addr dd	?			; ptr to base of page directory
pt_addr dd	?			; ptr to base of page table
ext_pages dd	?			; total number of extmem pages
pt_pages dd	?			; number of pages used for page table
pt_recs dd	?			; number of entries needed in page table
nparspace	equ	440h		; offset within page table of allocation list
ntrash1 dd	0			; used with int6f
ntrash2 dd	0			; used with int6f
ntrash3 dd	0			; used with int6f
nhint	dd	0			; UPDATE 70: nalloc starts here -- every
					;  parspace entry below it is in use
nfirst	dd	0			; UPDATE 70: first free entry nalloc saw
m17wrap db	'N'			; set to 'Y' if 1000000 wraps to 0
nmi_slctr	dw	?		; data selector for nmi handler
nmi_vector	dd	?		; fword pointer to nmi handler
		dw	?		; selector portion of nmi fword handler

debugregs dd	8 dup (0)	; used with INT 6f for tranfer of debug regs

	page
;--------------------------------------------------------------------
;	     stack for privilege change to level zero
;--------------------------------------------------------------------
	align 16			; align to paragraph boundary

	dw	108 dup(-1)
s0error dw	0,0			; error code for int 0a-0d
s0ip	dw	0,0
s0cs	dw	0,0
s0flags dw	0,0
s0sp	dw	0,0
s0ss	dw	0,0
s0es	dw	0,0
s0ds	dw	0,0
s0fs	dw	0,0
s0gs	dw	0,0
p0stack  label word
	db	'**P0STACK END***'

	page
;--------------------------------------------------------------------
;	task state segment #2 - sets/saves virtual 8086 mode
;--------------------------------------------------------------------
	align 16			; align to paragraph boundary

	db	'******TSS2******'
tss2	label word
	dw	0,0			; link to previous tss
	dw	offset mmgrp:p0stack,0	; esp/ss for level 0 stack switch
	dw	gdtdata-gdt,0
	dw	0,0,0,0 		; esp/ss for level 1 stack switch
	dw	0,0,0,0 		; esp/ss for level 2 stack switch
t2cr3	dd	0			; page directory table address
t2eip	dw	offset mmgrp:vmstart,0	; initial instruction pointer
t2eflags label word
	db	00000010b		; sf=0,zf=0,0,af=0,0,pf=0,1,cf=0
	db	00000000b		; 0,nt=0,iopl=??,of=0,df=0,if=0,tf=0
	db	00000010b		; 000000,vm=1,rf=0
	db	00000000b		; reserved flag bits
	dw	0,0			; eax
	dw	0,0			; ecx
	dw	0,0			; edx
	dw	0,0			; ebx
t2sp	dw	0,0			; esp
	dw	0,0			; ebp
	dw	0,0			; esi
	dw	0,0			; edi
t2es	dw	0,0			; segment regs
t2cs	dw	0,0
t2ss	dw	0,0
t2ds	dw	0,0
t2fs	dw	0,0
t2gs	dw	0,0
	dw	0,0			; task ldt selector
	dw	0			; bit 0 is 'T' bit
	dw	0068h			; offset to i/o permission bit map
t2iopbm db	1792 dup(0)		; i/o addresses 0000-37ff
	db	-1			; must follow the map
tss2len equ	$-tss2

	page
;--------------------------------------------------------------------
;		     descriptor task id table
;--------------------------------------------------------------------
dtitable label byte
	db	250 dup(-1)		; user selectors (UPDATE 64: was 30, shared
					;  by every task incl. the host's own client
					;  selectors; one DOS/4GW client asks for 47)
dtilen	equ	$-dtitable

;--------------------------------------------------------------------
;		     global descriptor table
;--------------------------------------------------------------------

	align 16			; align to paragraph boundary

	db	'******GDT*******'
gdt	label	word
gdtnull label	byte			; null selector
	dw	4 dup(0)
gdttss1  label byte			; task state segment #1
	dw	tss1len,offset mmgrp:tss1  ; limit, base
	db	0			; base bits 16-23
	db	10001001b		; p=1,dpl=0,s=0,type=9
	db	00000000b		; g=0,000,limit bits 16-19
	db	0			; base bits 24-31
gdttss2  label byte			; task state segment #2
	dw	tss2len,offset mmgrp:tss2  ; limit, base
	db	0			; base bits 16-23
	db	10001001b		; p=1,dpl=0,s=0,type=9
	db	00000000b		; g=0,000,limit bits 16-19
	db	0			; base bits 24-31
gdtcode  label byte			; this driver's code segment
	dw	0ffffh,0		; limit, base
	db	0			; base bits 16-23
	db	10011010b		; p=1,dpl=0,s=1,e=1,c=0,r=1,a=0
	db	01001111b		; g=0,d=1,00,limit bits 16-19
	db	0			; base bits 24-31
gdtdata  label byte			; this driver's data segment
	dw	0ffffh,0		; limit, base
	db	0			; base bits 16-23
	db	10010010b		; p=1,dpl=0,s=1,e=0,ed=0,w=1,a=0
	db	01001111b		; g=0,d=1,00,limit bits 16-19
	db	0			; base bits 24-31
gdtcod16 label byte			; this driver's code segment
	dw	0ffffh,0		; limit, base
	db	0			; base bits 16-23
	db	10011010b		; p=1,dpl=0,s=1,e=1,c=0,r=1,a=0
	db	00001111b		; g=0,d=0,00,limit bits 16-19
	db	0			; base bits 24-31
gdtdat16 label byte			; this driver's data segment
	dw	0ffffh,0		; limit, base
	db	0			; base bits 16-23
	db	10010010b		; p=1,dpl=0,s=1,e=0,ed=0,w=1,a=0
	db	00001111b		; g=0,d=0,00,limit bits 16-19
	db	0			; base bits 24-31
gdtzero  label byte			; segment at absolute zero
	dw	0ffffh,0		; limit, base
	db	0			; base bits 16-23
	db	10010010b		; p=1,dpl=0,s=1,e=0,ed=0,w=1,a=0
	db	11001111b		; g=1,d=1,00,limit bits 16-19
	db	0			; base bits 24-31
gdtzero3 label byte			; UPDATE 79: selector 0040h = BIOS data area
	dw	0ffffh,0400h		; limit, base 400h: DOS/4GW (and DPMI
					;  convention) reads the tick count at
					;  0040h:006Ch for int 21h 2Ch
	db	0			; base bits 16-23
	db	11110010b		; p=1,dpl=3,s=1,e=0,ed=0,w=1,a=0
	db	01001111b		; g=0,d=1,00,limit bits 16-19
	db	0			; base bits 24-31
gdtvideo label byte			; 0040 = segment at b8000
	dw	0ffffh,8000h		; limit, base
	db	0bh			; base bits 16-23
	db	11110010b		; p=1,dpl=3,s=1,e=0,ed=0,w=1,a=0
	db	01001111b		; g=0,d=1,00,limit bits 16-19
	db	0			; base bits 24-31

; this gdt is initially used for full access to extended memory - for the
; memory test done to setup the page table.  once the tables are setup,
; the base of this gdt will be changed for simple access to the page table.

gdtpage  label byte
	dw	0ffffh,0		; limit, base
	db	0			; base bits 16-23
	db	10010010b		; p=1,dpl=0,s=1,e=0,ed=0,w=1,a=0
	db	11001111b		; g=1,d=1,00,limit bits 16-19
	db	0			; base bits 24-31


phooktab equ	0			; UPDATE 73: offset 0 in gdthook (gs) --
					;  defined before any use: no phase error
gdthook  label byte			; UPDATE 73: the pm hook table (phooktab),
	dw	DPHKN*12+2000h-1,0	;  12 KB + the 4 KB hook bitmap (UPDATE 74)
					;  + the DTA page (UPDATE 80);
	db	0			;  hookinit at the first session start
	db	10010010b		; p=1,dpl=0,s=1,e=0,ed=0,w=1,a=0
	db	0			; g=0,d=0
	db	0			; base bits 24-31

gdtspace label byte
	dw	dtilen dup(0,0,0,0)	; space for user selectors
gdtlen	equ	$-gdt

	page
;--------------------------------------------------------------------
;		  interrupt descriptor table
;--------------------------------------------------------------------
	align 16			; align to paragraph boundary

	db	'******IDT*******'
idt	label	word
;	dw	offset mmgrp:entint??	; offset
;	dw	gdtcode-gdt		; selector
;	db	0			; 000, word count
;	db	11101110b		; p=1,dpl=3,s=0,type=e
;	dw	0			; offset bits 16-31

	dw	mmgrp:etb+000h,gdtcode-gdt,0ee00h,0  ; 00
	dw	mmgrp:entint01,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+008h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+00ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+010h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+014h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint06,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint07,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint08,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+024h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint0a,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint0b,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+030h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint0d,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint0e,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+03ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+040h,gdtcode-gdt,0ee00h,0  ; 10
	dw	mmgrp:etb+044h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+048h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+04ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+050h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+054h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+058h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+05ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+060h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+064h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+068h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+06ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint1c,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+074h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+078h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+07ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+080h,gdtcode-gdt,0ee00h,0  ; 20
	dw	mmgrp:etb+084h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+088h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+08ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+090h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+094h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+098h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+09ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0a0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0a4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0a8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0ach,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0b0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0b4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0b8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0bch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0c0h,gdtcode-gdt,0ee00h,0  ; 30
	dw	mmgrp:etb+0c4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0c8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0cch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0d0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0d4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0d8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0dch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint38,gdtcode-gdt,0ee00h,0  ; extsv
	dw	mmgrp:etb+0e4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0e8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0ech,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0f0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0f4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0f8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+0fch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+100h,gdtcode-gdt,0ee00h,0  ; 40
	dw	mmgrp:etb+104h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+108h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+10ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+110h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+114h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+118h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+11ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+120h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+124h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+128h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+12ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+130h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+134h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+138h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+13ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+140h,gdtcode-gdt,0ee00h,0  ; 50
	dw	mmgrp:etb+144h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+148h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+14ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+150h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+154h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+158h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+15ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+160h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+164h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+168h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+16ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+170h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+174h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+178h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+17ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+180h,gdtcode-gdt,0ee00h,0  ; 60
	dw	mmgrp:etb+184h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+188h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+18ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+190h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+194h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+198h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+19ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1a0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1a4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1a8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1ach,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1b0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1b4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1b8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entint6f,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1c0h,gdtcode-gdt,0ee00h,0  ; 70
	dw	mmgrp:etb+1c4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1c8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1cch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1d0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1d4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1d8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1dch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1e0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1e4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1e8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1ech,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1f0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1f4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1f8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+1fch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+200h,gdtcode-gdt,0ee00h,0  ; 80
	dw	mmgrp:etb+204h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+208h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+20ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+210h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+214h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+218h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+21ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+220h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+224h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+228h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+22ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+230h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+234h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+238h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+23ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+240h,gdtcode-gdt,0ee00h,0  ; 90
	dw	mmgrp:etb+244h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+248h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+24ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+250h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+254h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+258h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+25ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+260h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+264h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+268h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+26ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+270h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+274h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+278h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+27ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+280h,gdtcode-gdt,0ee00h,0  ; a0
	dw	mmgrp:etb+284h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+288h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+28ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+290h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+294h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+298h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+29ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2a0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2a4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2a8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2ach,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2b0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2b4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2b8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2bch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2c0h,gdtcode-gdt,0ee00h,0  ; b0
	dw	mmgrp:etb+2c4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2c8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2cch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2d0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2d4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2d8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2dch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2e0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2e4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2e8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2ech,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2f0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2f4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2f8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+2fch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+300h,gdtcode-gdt,0ee00h,0  ; c0
	dw	mmgrp:etb+304h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+308h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+30ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+310h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+314h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+318h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+31ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+320h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+324h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+328h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+32ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+330h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+334h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+338h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+33ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+340h,gdtcode-gdt,0ee00h,0  ; d0
	dw	mmgrp:etb+344h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+348h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+34ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:entintd4,gdtcode-gdt,0ee00h,0  ; extsv
	dw	mmgrp:etb+354h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+358h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+35ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+360h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+364h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+368h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+36ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+370h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+374h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+378h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+37ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+380h,gdtcode-gdt,0ee00h,0  ; e0
	dw	mmgrp:etb+384h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+388h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+38ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+390h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+394h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+398h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+39ch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3a0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3a4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3a8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3ach,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3b0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3b4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3b8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3bch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3c0h,gdtcode-gdt,0ee00h,0  ; f0
	dw	mmgrp:etb+3c4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3c8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3cch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3d0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3d4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3d8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3dch,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3e0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3e4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3e8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3ech,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3f0h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3f4h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3f8h,gdtcode-gdt,0ee00h,0
	dw	mmgrp:etb+3fch,gdtcode-gdt,0ee00h,0
idtlen	equ   $-idt

page
;--------------------------------------------------------------------
;		 interrupt 1 handler (single step)
;--------------------------------------------------------------------
entint01:
	db	66h
	call	eicommon		; common entry logic

IF TRACE
	db	67h			; 16-bit address
	cmp	ss:[trapsave],0 	; are we doing the trapping?
	jne	i01begin		; yes, jump
ENDIF

	mov	cl,1
	db	66h			; *16-bit displacement*
	jmp	entirq

IF TRACE
;------------ single stepping was initiated by this driver ----------

comment |

use memdev=$386.sys /t and have a 19.2k baud terminal on 03f8.
press space bar to turn off display of tracing (to speed up during boot)
the return key toggles start/stop execution
while stopped, can enter 4 hex digits for a dump
display order:	cs ip ss sp ds es ax bx cx dx si di bp

|

i01begin:
	push	ax			; save remaining registers
	push	dx
	push	si
	push	di

;------------------- fix single-step bug with esc -------------------

	db	67h
	mov	ax,[bp+4]		; get eip
	db	67h
	cmp	ss:[dblastip],ax	; same as last eip?
	db	67h
	mov	ss:[dblastip],ax
	jne	i01escok		; no, skip this garbage
	db	66h
	call	calcinad		; compute instruction address in ebx
	db	8bh,00001011b		; mov ecx,[ebx]
					;	  00...011		; disp=none,base=ebx
	and	cl,11111000b		; extract high 5 bits of opcode
	cmp	cl,11011000b		; is it an escape instruction?
	jne	i01escok		; no, skip this garbage
	xor	bx,bx
	and	ch,11000111b		; extract "mod" and "r/m" bits
	cmp	ch,00000110b		; direct address is length 4
	je	i01escl4
	mov	bl,2
	cmp	ch,00000111b		; otherwise mod=00 means length 2
	jbe	i01escad
	cmp	ch,11000000b		; mod=11 means length 2
	jae	i01escad
	inc	bl
	cmp	ch,01000111b		; mod=01 means length 3
	jbe	i01escad
i01escl4:
	mov	bl,4			; mod=10 means length 4
i01escad:
	db	67h			; 16-bit address
	add	[bp+4],bx		; add instruction length to eip
i01escok:

;  "." command at debug terminal requests auto-stop upon any radical
;  changes to ss or sp; the following code monitors for such changes:

	db	67h			; 16-bit address
	mov	al,byte ptr [bp+16+1]	; al = high 6 bits of user'S SP
	and	al,0fch
	db	66h
	db	67h
	mov	bx,[bp+20]		; bx = user'S SS
	db	66h
	db	67h
	cmp	byte ptr [bp+16],8	; if sp less than 8, stop
	jb	i01spch
	db	67h
	cmp	al,ss:[spmondat]	; sp bits 8-15 changed?
	jne	i01spch
	db	66h
	db	67h
	cmp	bx,ss:[ssmondat]	; ss changed?
	je	i01nosp
i01spch:

; ss:sp has changed enough to stop the trace

	db	67h
	mov	ss:[spmondat],al
	db	66h
	db	67h
	mov	ss:[ssmondat],bx
	db	67h
	cmp	ss:[spmonsw],'Y'	; sp monitoring active?
	jne	i01nosp
	db	67h
	mov	ss:[tprintsw],0 	; yes, turn trace back on
	db	67h
	mov	ss:[spmonsw],'H'	; and halt after reg display

; check if registers are to be displayed for this instruction

i01nosp:
	db	67h
	cmp	ss:[debugint],1ch	; always trace if interrupt
	je	i01sk1c
	db	67h
	cmp	ss:[debugint],00h	; always trace if interrupt
	jne	i01disp
i01sk1c:
	db	67h			; 16-bit address
	cmp	ss:[tprintsw],0 	; bypass display?
	je	$+6
	db	66h			; 16-bit data
	jmp	i01tstin		; yes, jump

; convert all registers to hex display format

i01disp:
	db	66h			; 16-bit data
	mov	di,offset mmgrp:msgtrace
	db	66h
	mov	si,offset mmgrp:regtabnm; register table for native mode
	db	66h
	cmp	bp,offset mmgrp:p0stack-28  ; native mode?
	jae	i01skip1		; yes, skip
	db	66h
	mov	si,offset mmgrp:regtabvm; no, use table for v-86 mode
i01skip1:
	xor	bx,bx
	mov	cl,4
i01loop1:
	xor	bx,bx
	db	67h			; 16-bit address
	mov	bl,ss:[si]		; load offset to register contents
	cmp	bl,255			; test for end
	je	i01dsdon
	mov	ch,4
	test	bl,80h			; set count for 4 or 8 hex digits
	jz	i01skip8
	mov	ch,8
	and	bl,7fh
i01skip8:
	xor	dx,dx
	mov	dl,ch
	add	bx,sp
	db	67h			; 16-bit address
	mov	ax,ss:[bx]		; load register contents to eax
	add	di,dx
	xor	bx,bx
i01loop2:
	dec	di
	mov	bl,al
	and	bl,0fh
	db	67h			; 16-bit address
	mov	bl,byte ptr ss:[bx+hextable]
	db	67h			; 16-bit address
	mov	byte ptr ss:[di],bl
	shr	ax,cl
	dec	ch
	jnz	i01loop2
	add	di,dx
	db	67h
	mov	byte ptr ss:[di],20h	; be sure blanks separate the fields
	inc	di
	inc	si
	jmp	short i01loop1

; the following added 870424

i01dsdon:
	mov	al,0
	db	67h
	xchg	al,ss:[debugint]
	or	al,al			; any interrupt occurred?
	jz	i01okprt		; no, skip
	inc	di
	xor	bx,bx
	mov	bl,al
	and	bl,0fh
	db	67h			; 16-bit address
	mov	bl,byte ptr ss:[bx+hextable]
	db	67h			; 16-bit address
	mov	byte ptr ss:[di],bl
	shr	al,cl
	dec	di
	mov	bl,al
	db	67h			; 16-bit address
	mov	bl,byte ptr ss:[bx+hextable]
	db	67h			; 16-bit address
	mov	byte ptr ss:[di],bl
	add	di,2

; write display to serial port

i01okprt:
	db	66h
	db	67h
	mov	word ptr ss:[di],0a0dh	; terminate with cr,lf
	db	66h			; 16-bit data
	mov	bx,offset mmgrp:msgtrace
i01loop3:
	db	67h			; 16-bit address
	mov	al,ss:[bx]
	db	66h			; 16-bit data
	call	writchar
	inc	bx
	cmp	al,0ah			; check for last character
	jne	i01loop3

; check for input from the serial port

i01tstin:
i01tibak:
	db	67h			; 16-bit address
	cmp	ss:[spmonsw],'H'	; check if sp monitoring is quiescing
	je	i01sphlt
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	dx,ss:[portaddr]	; address com1
	add	dl,5
	in	al,dx
	sub	dl,5
	test	al,01h			; is any input there?
	jnz	i01input		; yes, jump
	db	67h
	mov	al,ss:[trapflag]	; make sure trap flag is right
	db	67h
	and	byte ptr [bp+12+1],0feh
	db	67h
	or	[bp+12+1],al
	pop	di
	pop	si
	pop	dx
	pop	ax
	pop	bx
	pop	cx
	pop	es
	pop	ds
	pop	bp
	iret				; int 1 gives no error code

; get the character from the serial port

i01input:
	db	66h
	call	readchar		; read the character
	cmp	al,20h			; space bar toggles register display
	je	i01space
	cmp	al,0dh			; c/r to dump memory
	je	i01dump
	cmp	al,'.'			; period to monitor ss:sp for
	je	i01spmon		;   drastic changes
	jmp	short i01tstin

; space bar pressed

i01space:
	db	67h			; 16-bit address
	xor	ss:[tprintsw],0ffh	; toggle print switch
	jmp	short i01tstin

; period keyed to request ss:sp monitoring

i01spmon:
	db	67h
	mov	ss:[spmonsw],'Y'	; sp monitoring on
	db	67h
	mov	ss:[tprintsw],0ffh	; automatically turn off trace display
	jmp	short i01tstin

; turn off ss:sp monitoring

i01sphlt:
	db	67h
	mov	ss:[spmonsw],'N'

; read address for memory dump

i01dump:
	xor	bx,bx			; bx accumulates dump address
	mov	ch,4			; 4 characters are required
i01dloop:
	db	66h
	call	readchar		; read next character from terminal
	cmp	al,0dh			; another c/r aborts this mode
	je	i01tibak
	cmp	al,'.'			; period is also permitted here
	je	i01spmon
	cmp	al,'A'
	jb	i01dchar
	sub	al,'A'-10
i01dchar:
	and	al,0fh
	or	bl,al
	shl	bx,4
	dec	ch
	jnz	i01dloop		; do 4 times

; got dump address - start dumping

	mov	al,0ah			; write an extra line feed
	db	66h
	call	writchar
	db	66h
	mov	ax,gdtzero-gdt		; address absolute memory
	mov	ds,ax
	mov	ch,16			; number of lines to dump
i01dlop2:
	xor	ax,ax
	db	8ah,00000011b		; mov al,[ebx]
	;	    00...011		; disp=none,base=ebx
	mov	di,ax			; save it
	shr	al,4			; write first nybble
	mov	si,ax
	db	67h
	mov	al,ss:[si+hextable]
	db	66h
	call	writchar
	mov	ax,di			; write 2nd nybble of byte
	and	al,0fh
	mov	si,ax
	db	67h
	mov	al,ss:[si+hextable]
	db	66h
	call	writchar
	inc	bx
	test	bl,0fh
	jz	i01delin
	mov	al,'.'
	test	bl,07h
	jz	i01dwfil
	mov	al,' '
i01dwfil:
	db	66h
	call	writchar
	jmp	short i01dlop2
i01delin:
	mov	al,0dh			; write cr/lf
	db	66h
	call	writchar
	mov	al,0ah
	db	66h
	call	writchar
	dec	ch
	jnz	i01dlop2
	db	66h
	jmp	i01dump

; serial i/o subroutines

readchar proc  near
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	dx,ss:[portaddr]	; address com1
	add	dl,5
	in	al,dx
	sub	dl,5
	test	al,01h			; is any input there?
	jz	readchar		; no, jump
	in	al,dx			; read the character
	db	66h			; 16-bit data
	ret
readchar endp
ENDIF


IF TRACE
writchar proc  near
	mov	ah,al
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	dx,cs:[portaddr]	; address com1
wchloop:
	add	dl,5
	in	al,dx
	sub	dl,5
	test	al,20h
	jz	wchloop
	jmp	$+2
	mov	al,ah
	out	dx,al
	db	66h
	ret
writchar endp
ENDIF

	page
;--------------------------------------------------------------------
;	      interrupt 6 handler (invalid instruction)
;--------------------------------------------------------------------
entint06:
	db	66h
	call	eicommon

IF INT6
	db	66h
	db	67h
	mov	ss:[parm6ec],1		; error code 1 = operation exception
	mov	cl,06h			; invalid-instruction interrupt
	db	66h
	jmp	entirq
ELSE
	mov	cl,6
	db	66h
	jmp	realhalt
ENDIF

	page
;--------------------------------------------------------------------
;	interrupt 7 handler (wait or esc without coprocessor)
;	this should only happen if the 80x87 is not present
;	to emulate the 8086, we must ignore this instruction
;	therefore we must compute its length to bypass it.
;--------------------------------------------------------------------
;    actually, now that we have implemented the clts instruction,
;    this routine should never receive control! 	  --rod
;--------------------------------------------------------------------
entint07:
	db	66h
	call	eicommon
	db	67h
	mov	ss:[debugint],07h
	db	66h
	call	calcinad		; compute instruction address in ebx
	db	8bh,00001011b		; mov ecx,[ebx]
	;	  00...011		; disp=none,base=ebx
	xor	bx,bx
	and	ch,11000111b		; extract "mod" and "r/m" bits
	cmp	ch,00000110b		; direct address is length 4
	je	ei07l4
	mov	bl,2
	cmp	ch,00000111b		; otherwise mod=00 means length 2
	jbe	ei07bump
	cmp	ch,11000000b		; mod=11 means length 2
	jae	ei07bump
	inc	bl
	cmp	ch,01000111b		; mod=01 means length 3
	jbe	ei07bump
ei07l4:
	mov	bl,4			; mod=10 means length 4
ei07bump:
	db	67h			; 16-bit address
	add	[bp+4],bx		; add instruction length to eip
	pop	bx
	pop	cx
	pop	es
	pop	ds
	pop	bp
	iret				; int 7 gives no error code

;--------------------------------------------------------------------
;	     interrupt 0a handler (invalid tss or irq2)
;--------------------------------------------------------------------
entint0a:
	db	66h
	call	eicommon
	mov	cl,0ah
	db	67h
	mov	ss:[debugint],cl
;#####	db	66h
	jmp	short extonly



;--------------------------------------------------------------------
;	 interrupt 0b handler (segment not present or irq3)
;--------------------------------------------------------------------
entint0b:
	db	66h
	call	eicommon
	mov	cl,0bh
	db	67h
	mov	ss:[debugint],cl
;#####	db	66h
	jmp	short extonly

;--------------------------------------------------------------------
;	     interrupt 0c handler (stack fault or irq4)
;--------------------------------------------------------------------
entint0c:
	db	66h
	call	eicommon
	mov	cl,0ch
	db	67h
	mov	ss:[debugint],cl
;#####	db	66h
	jmp	short extonly


	page
;--------------------------------------------------------------------
;	      interrupt 8 handler (double fault or irq0)
;--------------------------------------------------------------------
entint08:
	db	66h
	call	eicommon
	mov	cl,8
extonly:
	db	66h
	cmp	bp,offset mmgrp:p0stack-44  ; v-86 mode with error code?
	je	extoec			; yes, jump
	db	66h
	cmp	bp,offset mmgrp:p0stack-28  ; native mode with error code?
	jne	extojei 		; no, jump
extoec:
	db	67h
	test	byte ptr [bp+4],1	; external event caused interrupt?
	jz	realhec			; no, halt the machine
extojei:
	db	66h
	jmp	entirqnt


	page
;--------------------------------------------------------------------
;			 enter real mode
;--------------------------------------------------------------------
realhalt:				; enter here if no error code
	mov	di,bp
	jmp	short realhent
realhec:				; enter here if error code
	mov	di,bp
	add	di,4

;  i don't know why, but I was not able to get to real mode
;  without first going to 16-bit protected mode. someday we will
;  look into this further, but the following works.   --rod

realhent:
	db	0eah			; direct intersegment jump
	dw	offset mmgrp:$+6	; loads 16-bit code selector
	dw	0
	dw	gdtcod16-gdt
	mov	ax,gdtdat16-gdt 	; change data selectors also
	mov	ds,ax
	mov	es,ax
	mov	ss,ax
	cli

	.386p
	xor	eax,eax
	mov	cr0,eax
	.286

; now in real mode

	db	0eah			; direct intersegment jump
	dw	offset mmgrp:realcs+2
realcs	dw	0
	mov	ax,cs			; make a valid real-mode stack
	mov	ss,ax
	mov	ds,ax
	mov	es,ax

	db	0fh,01h,00011110b	; lidt with real-mode version
	dw	offset mmgrp:wsrmidtr

	sti
	cmp	[realsw],'Y'		; are we here on purpose?
	jne	abort			; no, jump
	jmp	realret 		; yes

; tell the user why we aborted

abort:
	mov	dx,offset mmgrp:msgcrlf
	call	wrstring
	xor	dx,dx			; write exception type to console
	mov	dl,cl
	shl	dx,4
	add	dx,offset mmgrp:exmtable
	call	wrstring
	mov	dx,offset mmgrp:msgexcp
	call	wrstring
	mov	word ptr [msgreg],'SC'
	mov	ax,[di+8]
	call	wrreg
	mov	word ptr [msgreg],'PI'
	mov	ax,[di+4]
	call	wrreg
	mov	word ptr [msgreg],'SS'
	mov	ax,[di+20]
	call	wrreg
	mov	word ptr [msgreg],'PS'
	mov	ax,[di+16]
	call	wrreg
	mov	word ptr [msgreg],'SD'
	mov	ax,[bp-4]
	call	wrreg
	mov	word ptr [msgreg],'SE'
	mov	ax,[bp-8]
	call	wrreg
	cmp	di,bp
	je	realhsk1
	mov	word ptr [msgreg],'CE'
	mov	ax,[bp]
	call	wrreg
realhsk1:
	mov	word ptr [msgreg],'PO'
	mov	es,[di+8]
	mov	bx,[di+4]
	mov	ax,es:[bx]
	xchg	al,ah
	call	wrreg
	sti
	jmp	$

wrreg	proc  near			; display a register
	mov	cl,4
	mov	si,offset mmgrp:msgreg+6
	xor	bx,bx
wrreglop:
	mov	bl,al
	and	bl,0fh
	mov	bl,byte ptr [bx+hextable]
	mov	byte ptr [si],bl
	shr	ax,cl
	dec	si
	cmp	si,offset mmgrp:msgreg+2
	ja	wrreglop
	mov	dx,offset mmgrp:msgreg
	call	wrstring
	ret
wrreg	endp

wrstring proc  near
	push	si
	push	di
	push	es
	mov	si,dx
	mov	di,[msgadr]
	mov	es,[videoadr]
	cld
wrstloop:
	lodsb
	cmp	al,'$'
	je	wrstret
	stosb
	mov	al,07h
	stosb
	jmp	short wrstloop
wrstret:
	mov	[msgadr],di
	pop	es
	pop	di
	pop	si
	ret
wrstring endp


;--------------------------------------------------------------------
;	     interrupt 0e handler (page fault or irq6)
;--------------------------------------------------------------------
entint0e:
	db	66h
	call	eicommon
	db	66h
	cmp	bp,offset mmgrp:p0stack-44  ; v-86 mode with error code?
	je	ei0eec			; yes, jump
	db	66h
	cmp	bp,offset mmgrp:p0stack-28  ; native mode with error code?
	je	ei0eec			; yes, jump
	mov	cl,0eh			; no, must be hardware irq6
	db	66h
	jmp	entirq
ei0eec:

IF INT6
	db	66h
	db	67h
	mov	ss:[parm6ec],0		; error code
	db	0fh,20h,11010001b	; mov cx,cr2 - get page fault address
	db	67h
	mov	ss:[parm6adr],cx	; 32-bit move
	mov	cl,06h			; invalid-instruction interrupt
	db	66h
	jmp	entirq
ELSE
	mov	cl,0eh
	db	66h
	jmp	realhec
ENDIF

	page
;--------------------------------------------------------------------
;		 other intel reserved interrupts
;--------------------------------------------------------------------
entint1c:
	db	66h
	call	eicommon
	mov	cl,1ch
	db	66h
	jmp	entirqnt

etb	equ	$
	db	66h
	call	eicalled		; 00
	db	66h
	call	eicalled		; 01 (dummy)
	db	66h
	call	eicalled		; 02
	db	66h
	call	eicalled		; 03
	db	66h
	call	eicalled		; 04
	db	66h
	call	eicalled		; 05
	db	66h
	call	eicalled		; 06 (dummy)
	db	66h
	call	eicalled		; 07 (dummy)
	db	66h
	call	eicalled		; 08 (dummy)
	db	66h
	call	eicalled		; 09
	db	66h
	call	eicalled		; 0a (dummy)
	db	66h
	call	eicalled		; 0b (dummy)
	db	66h
	call	eicalled		; 0c
	db	66h
	call	eicalled		; 0d (dummy)
	db	66h
	call	eicalled		; 0e (dummy)
	db	66h
	call	eicalled		; 0f (dummy)
	db	66h
	call	eicalled		; 10
	db	66h
	call	eicalled		; 11
	db	66h
	call	eicalled		; 12
	db	66h
	call	eicalled		; 13
	db	66h
	call	eicalled		; 14
	db	66h
	call	eicalled		; 15
	db	66h
	call	eicalled		; 16
	db	66h
	call	eicalled		; 17
	db	66h
	call	eicalled		; 18
	db	66h
	call	eicalled		; 19
	db	66h
	call	eicalled		; 1a
	db	66h
	call	eicalled		; 1b
	db	66h
	call	eicalled		; 1c (dummy)
	db	66h
	call	eicalled		; 1d
	db	66h
	call	eicalled		; 1e
	db	66h
	call	eicalled		; 1f
	db	66h
	call	eicalled		; 20
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 30
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 40
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 50
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 60
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 70
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 80
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; 90
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; a0
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; b0
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; c0
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; d0
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; e0
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled		; f0
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled
	db	66h
	call	eicalled

	page
;--------------------------------------------------------------------
;  general-purpose interrupt entry. this routine is entered from the
;  call statements in etb, which in turn is referenced by the
;  interrupt descriptor table. for better performance, the first
;  part of this routine duplicates code in eicommon.
;--------------------------------------------------------------------
eicalled:
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	pop	ss:[trash1]		; address from the call
	push	bp
	mov	bp,sp			; bp is at [bp]
	push	ds			; ds is at [bp-4]
	push	es			; es is at [bp-8]
	push	cx			; cx is at [bp-12]
	push	bx			; bx is at [bp-16]
	db	66h
	mov	bx,gdtzero-gdt		; load segment selectors
	mov	ds,bx
	mov	bx,ss
	mov	es,bx
	xor	cx,cx			; compute interrupt number in cl
	db	66h
	db	67h
	mov	cx,ss:[trash1]
	db	66h
	sub	cx,offset mmgrp:etb+4
	shr	cx,2
	db	66h
	jmp	entirq

	page
;--------------------------------------------------------------------
;			interrupt d4 and 38 handler
;--------------------------------------------------------------------
entintd4:				; extsv
	db	66h
	call	eicommon
	mov	ch,0d4h
	db	67h
	mov	ss:[debugint],ch
	db	67h
	mov	ss:[iveccode],ch
	db	66h
	cmp	bp,offset mmgrp:p0stack-28
	jae	ei38nat 		; jump if user is in native mode
	cmp	ah,10h
	jne	ei38cont
	db	66h			; this test is an attempt to
	db	67h			;   determine if the application
	mov	bx,ds:[0d4h*4+2]	;   has its own int d4 handler
	db	66h			;   if it does, then we assume that
	db	67h			;   it's NOT trying to switch into
	cmp	bx,ds:[06h*4+2] 	;   native mode!  note the dependency
	jne	ei38cont		;   on the int 6 vector.
	db	66h
	jmp	nmswitch		; execute switch to native mode

entint38:				; extsv
	db	66h
	call	eicommon
	mov	ch,38h
	db	67h
	mov	ss:[debugint],ch
	db	67h
	mov	ss:[iveccode],ch
	db	66h
	cmp	bp,offset mmgrp:p0stack-28
	jae	ei38nat 		; jump if user is in native mode
	cmp	ah,10h
	jne	ei38cont
	db	66h			; this test is an attempt to
	db	67h			;   determine if the application
	mov	bx,ds:[38h*4+2] 	;   has its own int 38 handler
	db	66h			;   if it does, then we assume that
	db	67h			;   it's NOT trying to switch into
	cmp	bx,ds:[06h*4+2] 	;   native mode!  note the dependency
	jne	ei38cont		;   on the int 6 vector.
	db	66h
 	jmp	nmswitch		; execute switch to native mode
ei38nat:
	db	66h
	jmp	einative		; handle native-mode interrupt
ei38cont:
	db	66h
	jmp	contirq

	page
;--------------------------------------------------------------------
;	interrupt 0d handler (general protection or irq5)
;--------------------------------------------------------------------


entint0d:
	db	66h
	call	eicommon
	mov	cl,0dh
	db	66h
	cmp	bp,offset mmgrp:p0stack-44  ; v-86 mode with error code?
	je	ei0dec			; yes, jump
	db	66h
	cmp	bp,offset mmgrp:p0stack-28  ; native mode with error code?
	jne	jentirq2		; no, go treat as irq5
ei0dec:
	db	67h			; 16-bit address
	test	byte ptr [bp+4],1	; external event caused interrupt?
	jnz	dobad			;091587

; protection exception was caused by an instruction

	db	66h
	call	calcinad		; compute instruction address in ebx
	db	8bh,00001011b		; mov ecx,[ebx]
	;	  00...011		; disp=none,base=ebx
	db	67h
	mov	ss:[parm6adr],cx	; save 4 instruction bytes for mos
	xor	bx,bx
	mov	bl,cl			; save 2nd byte in ch

; check for an exception due to a debug register access attempt

IF DBGEMU

	cmp	bl,0fh
	je	dbgchk
ENDIF

; this next test presumes that all exception op codes are greater than 127
; if anyone ever uses ins or outs to a trapped port, will need to modify

	test	bl,80h
	jz	dobad
	db	67h			; 16-bit address
	mov	bl,ss:[bx+intable1-128]
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	jmp	ss:[bx+intable2]

; interrupt 0d caused by an external event

jentirq2:				; enter here if no error code (irq5)
	db	66h			; 16-bit data
;>>>>>>>> change this one
	jmp	entirq
;>>>>>>>> change this one

; terminate due to invalid instruction

dobad:

IF INT6
	db	66h
	db	67h
	mov	ss:[parm6ec],2		; error code 2 = protection exception
	mov	cl,06h			; invalid-instruction interrupt
;>>>>>>>> change this one
	db	66h
	jmp	entirq
;>>>>>>>> change this one
ELSE
	mov	cl,0dh			; indicate protection exception
	db	66h			; 16-bit data
	jmp	realhec 		; halt with error code
ENDIF

IF DBGEMU

; note - this code is not in use16 format.  to use this new debugging code,
; will either need to convert it to use16 or convert the rest of the
; driver to use32.  the use32 conversion is eventual - depends on timing.

; handle access to debug registers


dbgchk:
	push	eax
	push	edx
	push	esi
	push	edi

; stack frame access at this point:
;
;	ebp	[ebp-0]
;	ecx	[ebp-12]
;	ebx	[ebp-16]
;	eax	[ebp-20]
;	edx	[ebp-24]
;	esi	[ebp-28]
;	edi	[ebp-32]

	mov	al,cl			; get op1
	mov	bh,ch			; get op2
	shr	ecx,8
	mov	bl,ch			; get op3

; op1 in al, op2 in bh, op3 in bl

	cmp	al,0fh			; verify op1
	jne	short dbgbad
	mov	esi,offset mmgrp:dr2reg
	cmp	bh,21h			; verify op2
	je	short a1
	mov	esi,offset mmgrp:reg2dr
	cmp	bh,23h
	je	short dbg1
dbgbad:
	pop	edi
	pop	esi
	pop	edx
	pop	eax
	jmp	short dobad
dbg1:
	mov	al,bl
	and	al,11000000b		; verify op3
	cmp	al,11000000b
	jne	short dbgbad
	mov	al,bl
	and	al,00111000b
	cmp	al,00100000b		; access to dr4 not allowed
	je	short dbgbad
	cmp	al,00101000b		; access to dr5 not allowed
	je	short dbgbad
	mov	al,bl
	and	al,00000111b		; use of sp as the target register
	cmp	al,00000100b		; too messy and not likely
	je	short dbgbad
	mov	edx,ebx 		; save original - will need again
	cmp	bh,23h			; if reg2dr format, need to
	jne	short dbg2		; get the reg into eax
	and	ebx,7			; use the reg bits to derive an
	shl	ebx,1			; index into dbgregtbl
	movzx	ebx,word ptr [dbgregtbl+ebx]
	neg	ebx
	mov	eax,[ebp+ebx]		; get the debug register data
	mov	ebx,edx 		; restore ebx
dbg2:
	shr	ebx,3			; derive an index based on
	and	ebx,7			; the eee bits
	cmp	bl,6
	jb	short dbg3		; convert 6 to 4 and 7 to 5 to
	sub	bl,2			; keep from needing two
dbg3:					; dead spots in the table
	mov	ecx,ebx
	shl	ebx,2			; ebx * 4 + orig ebx  (ebx *= 5)
	add	ebx,ecx 		; 5 bytes per table entry
	add	ebx,esi 		; si selects the dr2reg or
	jmp	ebx			; the reg2dr table
dr2reg:
	mov	eax,dr0
	jmp	short d2rcommon
	mov	eax,dr1
	jmp	short d2rcommon
	mov	eax,dr2
	jmp	short d2rcommon
	mov	eax,dr3
	jmp	short d2rcommon
	mov	eax,dr6
	jmp	short d2rcommon
	mov	eax,dr7
d2rcommon:
	mov	ebx,edx 		; when using the dr2reg format
	and	ebx,7			; need to derive an index into
	shl	ebx,1			; dbgregtbl to save the data
	movzx	ebx,word ptr [dbgregtbl+ebx]
	neg	ebx
	mov	[ebp+ebx],eax
	jmp	short r2dcommon
reg2dr:
	mov	dr0,eax
	jmp	short r2dcommon
	mov	dr1,eax
	jmp	short r2dcommon
	mov	dr2,eax
	jmp	short r2dcommon
	mov	dr3,eax
	jmp	short r2dcommon
	mov	dr6,eax
	jmp	short r2dcommon
	mov	dr7,eax
r2dcommon:
	pop	edi
	pop	esi
	pop	edx
	pop	eax

; future!!! - handle trapped debug access from native mode
; (e.g. if native mode code ever runs at a restricted privledge level)
; would want to modify eip.

	add	word ptr ss:[s0ip],3	; bump ip past the instruction

	pop	ebx
	pop	ecx
	pop	es
	pop	ds
	pop	ebp
	mov	esp,offset mmgrp:s0ip
	iret
ENDIF

; compute 32-bit instruction address in ebx

calcinad proc  near
	db	66h
	cmp	bp,offset mmgrp:p0stack-28
	jae	cinative		; jump if user is in native mode
	xor	bx,bx			; compute instruction address in ebx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	bx,ss:[s0cs]		; get cs
	shl	bx,4
	xor	cx,cx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	cx,ss:[s0ip]		; get ip
	add	bx,cx
	db	66h
	ret
cinative:
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	bx,ss:[p0stack-16]	; load user'S CS SELECTOR
	and	bl,11111000b		; turn off trash bits
	db	67h			; 16-bit address
	mov	bx,ss:[bx+gdt+2]	; load base bits 0-23
; and ebx,00FFFFFFh, spelled out: TSL wrote "and bx,0ffffh" + "dw 00ffh",
; relying on MASM's imm16 form (81 E3 FFFF). MASM chose 83 E3 FF (-1,
; sign-extended), so the dw ran as FF 00 = inc dword ptr [eax]: every
; native-mode #GP corrupted a dword and then page-faulted here with the
; access byte left in ebx (UPDATE 55).
	db	81h,0e3h		; and ebx,00FFFFFFh: clear bits 24-31
	dw	0ffffh,00ffh
	db	67h			; 16-bit address
	add	bx,ss:[p0stack-20]	; add ip to get instruction address
	db	66h
	ret
calcinad endp

	page
;--------------------------------------------------------------------
;		      opcode vector tables
;--------------------------------------------------------------------
	even
intable2 label	word
t2bad	 dw	offset mmgrp:dobad
t2inalp  dw	offset mmgrp:doinali
t2inaxp  dw	offset mmgrp:doinout
t2outalp dw	offset mmgrp:dooutali
t2outaxp dw	offset mmgrp:doinout
t2inald  dw	offset mmgrp:doinald
t2inaxd  dw	offset mmgrp:doinaxd
t2outald dw	offset mmgrp:dooutald
t2outaxd dw	offset mmgrp:dooutaxd
t2hlt	 dw	offset mmgrp:dohlt
intable1 label byte
	 db	16 dup(0)		; 80-8f
	 db	12 dup(0)		; 90-9b
	 db	0			; 9c
	 db	0			; 9d
	 db	2 dup(0)		; 9e-9f
	 db	16 dup(0)		; a0-af
	 db	16 dup(0)		; b0-bf
	 db	12 dup(0)		; c0-cb
	 db	0,0
	 db	0			; ce	  0
	 db	0			; cf	 iret
	 db	16 dup(0)		; d0-df
	 db	4 dup(0)		; e0-e3
	 db	t2inalp-intable2	; e4
	 db	t2inaxp-intable2	; e5
	 db	t2outalp-intable2	; e6
	 db	t2outaxp-intable2	; e7
	 db	4 dup(0)		; e8-eb
	 db	t2inald-intable2	; ec
	 db	t2inaxd-intable2	; ed
	 db	t2outald-intable2	; ee
	 db	t2outaxd-intable2	; ef
	 db	0			; f0	  lock
	 db	3 dup(0)
	 db	t2hlt-intable2		; hlt
	 db	5 dup(0)
	 db	0			; fa	  cli
	 db	0			; fb	  sti
	 db	2 dup(0)		; fe-ff

	page
;--------------------------------------------------------------------
;		 i/o trapped for virtual 8086 task
;--------------------------------------------------------------------
doinali:				; in al,imm enters here
	push	dx
	xor	dx,dx
	mov	dl,ch
	jmp	short doinal1
doinald:				; in al,dx enters here
	push	dx
	db	66h
	cmp	dh,0fh			; allow i/o above address 0fff
	ja	doinal2
doinal1:
	db	66h
	cmp	dx,0004h		; allow reads from dma ports
	je	doinal2
	db	66h
	cmp	dx,0081h
	je	doinal2
	pop	dx
	db	66h
	jmp	doinout
doinal2:
	in	al,dx
	pop	dx
	jmp	short dooutbye
doinaxd:				; in ax,dx enters here
	jmp	short doinald		; sah\jrb let mos handle it
dooutaxd:				; out dx,ax enters here
	jmp	short dooutald		; sah\jrb let mos handle it
dooutali:				; out imm,al enters here
	cmp	ch,04h
	je	doout04i
	cmp	ch,81h
	je	doout81i
	db	66h
	jmp	dooutali9		; 0e0h test lives out of line: anything
					;  inserted here pushes the two short
					;  jumps above out of range
;
doout04i:
	db	67h
	inc	word ptr ss:[s0ip]
doout04:
	db	67h
	mov	bl,ss:[dmaindex]
	db	67h
	mov	ss:[bx+dmastuff],al
	db	67h
	xor	ss:[dmaindex],1
	jz	dooutdma
dooutbye:
	db	67h
	inc	word ptr ss:[s0ip]
dohexit:
	pop	bx
	pop	cx
	pop	es
	pop	ds
	pop	bp
	db	66h
	mov	sp,offset mmgrp:s0ip
	iret
dohlt:
	db	67h
	mov	byte ptr ss:[wshalt],1
	jmp	short dohexit
dooutald:				; out dx,al enters here
	db	66h
	cmp	dh,0fh			; allow i/o above address 0fff
	ja	dooutalo
	db	66h
	cmp	dx,0004h
	je	doout04
	db	66h
	cmp	dx,0081h
	je	doout81
	jmp	short doinout
dooutalo:
	out	dx,al
jdooutbye:
	jmp	short dooutbye
doout81i:
	db	67h
	inc	word ptr ss:[s0ip]	; bump ip an extra byte
doout81:
	db	67h
	mov	ss:[dmastuff+2],al	; save high byte for debugging
dooutdma:
	push	ax
	xor	cx,cx
	db	67h
	mov	ss:[dmaindex],cl
	db	67h
	mov	ch,ss:[dmastuff+2]
	db	67h
	mov	cl,ss:[dmastuff+1]	; bits 8-23 are now in cx
	mov	bx,cx
	and	bl,0f0h 		; keep bits 12-23
	shr	bx,2			; plus 2 zero bits to index patable

;============== my new code

	push	ax			; push eax
	push	es
	db	66h
	mov	ax,gdtpage-gdt		; this gdt's base points to the
	db	66h			; page table
	mov	es,ax
	db	66h
	inc	bx
	db	66h
	db	67h
	mov	bx,es:[bx]		; get new address bits 12-23
	pop	es
	pop	ax			; pop eax

;============== the original code

;	db	66h
;	db	67h
;	mov	bx,ss:[bx+patkable+1]	; get new address bits 12-23


	and	bl,0f0h 		; clear irrelevant bits
	and	cl,0fh			; merge to get bits 8-23 in bx
	or	bl,cl
	db	67h
	mov	al,ss:[dmastuff]
	out	04h,al
	jmp	$+2
	jmp	$+2
	jmp	$+2
	mov	al,bl
	out	04h,al
	jmp	$+2
	jmp	$+2
	jmp	$+2
	mov	al,bh
	out	81h,al
	pop	ax			; restore original al
;#####	db	66h
;>>>>>>>> change this 
;#####	jmp	dooutbye
	jmp	short jdooutbye
;>>>>>>>> change this
doinout:

IF INT6
	db	67h
	mov	ss:[parm6adr],cx	; save 4 instruction bytes for mos
	db	66h
	sub	bx,t2inalp-intable2	; compute error code for mos
	db	66h
	shr	bx,1
	db	66h
	add	bx,3
	db	66h
	db	67h
	mov	ss:[parm6ec],bx
	mov	cl,06h
;#####	db	66h
;>>>>>> change this one
	jmp	short entirq			; enter mos error handler
;>>>>>> change this one
ELSE
	mov	cl,0dh			; indicate protection exception
	db	66h			; 16-bit data
	jmp	realhec 		; halt with error code
ENDIF

realret:
	db	66h
	pop	ax
	db	66h			; bx & cx were pushed as dwords
	pop	bx
	db	66h
	pop	cx
	add	sp,8
	db	66h
	pop	bp
	mov	ds,cs:[s0ds]
	mov	es,cs:[s0es]
	mov	ss,cs:[s0ss]
	mov	sp,cs:[s0sp]
	pushf
	push	cs:[s0cs]
	push	cs:[s0ip]
	iret



	page
;--------------------------------------------------------------------
;		 common hardware interrupt handler
;--------------------------------------------------------------------
entirq:
	db	67h
	mov	ss:[debugint],cl
entirqnt:
	db	67h			; 16-bit address
	mov	ss:[iveccode],cl	; save interrupt number
	db	66h
	cmp	bp,offset mmgrp:p0stack-28  ; is user in native mode?
	jae	jeinat			; yes, jump
;#####	db	66h
	jmp	short contirq 		; otherwise go to v-86 handler
jeinat:
	db	66h			; 16-bit data
	jmp	einative


	page
;--------------------------------------------------------------------
;	   common interrupt logic for virtual-8086 tasks
;--------------------------------------------------------------------
contirq:

; TEST v2 (guard removed): the nmswitch guard that used to sit here
; is neutralized -- contirq now falls straight through to cirqhndl,
; i.e. the ORIGINAL real-mode-IVT reflection, unconditionally, for
; every vector including those with ivtable[N]==0.
;
; Rationale: the guard was added on the diagnosis that an
; ivtable[N]==0 reflection loaded a garbage vector and crashed. That
; diagnosis is in doubt -- 0x76cd is the valid MOS kernel segment for
; both IVT[6] and IVT[8], so reflecting via the real-mode IVT was
; arguably always correct, and the guard instead broke the timer
; (int 8) by forcing it native. The vmstart V/W markers now in the
; tree make the outcome of this test unambiguous. See addendum.
cirqhndl:
	push	dx

; flags to stack

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	sub	ss:[s0sp],2		; decrement user'S SP
	xor	bx,bx			; compute stack address in ebx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	bx,ss:[s0ss]
	shl	bx,4
	mov	dx,bx			; dx saves shifted ss
	xor	cx,cx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	cx,ss:[s0sp]
	add	bx,cx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	cx,ss:[s0flags] 	; load user flags to cx
	and	ch,10001111b		; make sure nt and iopl are clear
	db	66h			; 16-bit data
	db	89h,00001011b		; mov [ebx],cx
	;	  00...011		; disp=none,base=ebx

; cs to stack

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	sub	ss:[s0sp],2		; decrement user'S SP
	xor	bx,bx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	bx,ss:[s0sp]
	add	bx,dx			; add in shifted ss
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	cx,ss:[s0cs]		; load user cs reg to cx
	db	66h			; 16-bit data
	db	89h,00001011b		; mov [ebx],cx
	;	  00...011		; disp=none,base=ebx

; ip to stack

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	sub	ss:[s0sp],2		; decrement user'S SP
	xor	bx,bx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	bx,ss:[s0sp]
	add	bx,dx			; add in shifted ss
	xor	cx,cx			; if hlt instruction was
	db	67h			;   interrupted, we must bump
	xchg	cl,ss:[wshalt]		;   the return address by 1
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	add	cx,ss:[s0ip]
	db	66h			; 16-bit data
	db	89h,00001011b		; mov [ebx],cx
	;	  00...011		; disp=none,base=ebx

; interrupt vector to cs:ip

	xor	bx,bx			; 32-bit clear
	db	67h			; 16-bit address
	mov	bl,ss:[iveccode]
	shl	bx,2
	cmp	bh,02h			; skip if int 80-ff
	jae	cirq1
	db	67h			; 16-bit address
	mov	cx,ss:[bx+ivtable]	; get 32-bit vector from ivtable
	or	cx,cx			; is one there?
	jnz	cirq2			; yes, jump
cirq1:
	db	8bh,00001011b		; mov ecx,[ebx]
	;	   00...011		; disp=none,base=ebx
cirq2:
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	ss:[s0ip],cx
	shr	cx,16			; this is only 3 clocks on the 386
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	ss:[s0cs],cx

; special handling for trap flag

	db	67h
	mov	bl,ss:[iveccode]
	cmp	bl,8			; timer interrupt?
	je	contirq1		; yes, clear trap flag
	cmp	bl,1ch			; timer interrupt?
	je	contirq1		; yes, clear trap flag
	cmp	bl,1			; single step interrupt?
	je	contirq1		; yes, clear trap flag
	db	67h
	mov	bl,ss:[trapflag]	; set trap flag if we'RE TRACING
	db	67h
	or	byte ptr ss:[s0flags+1],bl

; clear interrupt flag

contirq2:
	db	67h
	and	byte ptr ss:[s0flags+1],11111101b

; return

	pop	dx
	pop	bx
	pop	cx
	add	sp,8			; skip es,ds
	pop	bp
	db	66h			; 16-bit data
	mov	sp,offset mmgrp:s0ip	; remove error code from stack
	iret

; clear trap flag

contirq1:
	db	67h			; 16-bit address
	and	byte ptr ss:[s0flags+1],11111110b
	jmp	short contirq2


	page
;--------------------------------------------------------------------
;		09 - display $-terminated string
;--------------------------------------------------------------------
;
; Stages the client's string at ds:(e)dx into ncabufer, up to and
; including the '$' (capped at ncabufsz, '$' forced at the cap), then
; reflects the call with v86 ds:dx pointing at the buffer.
;
; Runs in the 32-bit monitor cs: encoded by hand where operand size
; matters. A 16-bit client (D bit clear in its cs descriptor) may have
; junk in the high word of edx, so the offset is zero-extended.
;

; save edx to ncauregs

einfun09:
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+00],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; source offset, zero-extended for a 16-bit client

	mov	ax,ds			; es = absolute zero, like senddsdx
	mov	es,ax
	db	8bh,01110011b		; mov esi,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	66h
	call	c32eax		; eax bit 22 = 32-bit client (UPDATE 62)
	db	0a9h			; test eax,00400000h (D bit)
	dd	00400000h
	jnz	e09is32
	db	0fh,0b7h,11110110b	; movzx esi,si
e09is32:

; copy up to and including '$', at most ncabufsz-1 bytes

	db	8bh,01001011b		; mov ecx,[ebx+ncabufsz]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncabufsz
	or	cx,cx			; or ecx,ecx
	jnz	e09szok
	mov	cl,64			; no size recorded: stay small
e09szok:
	dec	cx			; dec ecx: room for a forced '$'

; cap the count at the client segment's own limit, so a string with no
; '$' before the limit cannot fault the monitor at ring 0. lsl gives
; the byte limit (granularity already applied); zf clear means the
; selector is not readable here, and the buffer size then stands.

	db	0fh,03h,01000011b	; lsl eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	jnz	e09nocap
	db	29h,11110000b		; sub eax,esi
	db	40h			; inc eax: bytes left from esi to limit
	js	e09none			; esi past the limit: copy nothing
	db	39h,11000001b		; cmp ecx,eax
	jbe	e09nocap
	db	89h,11000001b		; mov ecx,eax
	jmp	short e09nocap
e09none:
	xor	cx,cx			; xor ecx,ecx
e09nocap:
	mov	di,bx			; mov edi,ebx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	;	  11...111		; reg=edi
	db	offset nca:ncabufer
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	mov	ds,ax			; client's data selector
	cld
	db	0e3h			; jecxz e09cap: nothing may be copied
	db	e09cap-$-1
e09loop:
	lodsb
	stosb
	cmp	al,'$'
	je	e09done
	loop	e09loop			; ecx in a 32-bit cs
e09cap:
	mov	al,'$'			; cap reached: terminate
	stosb
e09done:
	mov	ax,es			; fix ds back to normal
	mov	ds,ax

; set v86 ds:dx to ncabufer (as senddsdx does)

	mov	ax,bx
	shr	ax,4			; segment portion
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncavds],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavds
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	dw	offset nca:ncabufer	; immediate data

; execute vm handler

	db	66h
	call	dovmint 		; edx contains vector number

; recover edx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00] (edx)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdx],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;		39 - send-stage file or directory name
;--------------------------------------------------------------------

; save edx to ncauregs

einfun39:
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; =byte,base=ebx
	db	offset nca:ncauregs+00

; move 64 bytes addressed by ds:edx to ncabufer

	xor	cx,cx
	mov	cl,64
	db	66h
	call	senddsdx

; execute vm handler

	db	66h
	call	dovmint 		; edx contains vector number

; recover edx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00] (edx)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	66h
	jmp	einback
	page
;--------------------------------------------------------------------
;			40 - write file data
;--------------------------------------------------------------------
einfun40:
	db	66h
	call	e3f40pre		; preparation logic

; compute length for this write

e40loop:
	db	8bh,01000011b		; mov eax,[ebx+ncabufsz]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncabufsz
	db	8bh,01010011b		; mov edx,[ebx+ncarwlen]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlen
	cmp	ax,dx
	jb	e40skip1
	mov	ax,dx			; write length is now in eax
e40skip1:
	db	89h,01000011b		; mov [ebx+ncavcx],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx

; move output data to ncabufer

	mov	dx,ds			; set es to address absolute zero
	mov	es,dx
	db	66h
	db	8bh,01010011b		; mov dx,[ebx+ncarwseg]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwseg
	db	8bh,01110011b		; mov esi,[ebx+ncarwoff]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwoff
	mov	di,bx			; compute target offset
	db	83h,11000111b		; add edi,offset nca:ncabufer
	;	  11...111		; reg=edi
	db	offset nca:ncabufer
	mov	ds,dx			; user's selector
	mov	cx,ax
	shr	cx,2
	cld
	rep	movsw
	mov	cl,al
	and	cl,03h
	rep	movsb
	mov	dx,es			; fix ds back
	mov	ds,dx

; execute vm handler

	xor	dx,dx			; edx is vector number
	mov	dl,21h
	db	0c6h,01000011b		; mov [ebx+ncavax+1],40h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	db	40h			; function code moved to ah
	db	66h
	call	dovmint
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
	jnz	e40end			; jump if carry was set

; get length written

	xor	ax,ax
	db	66h			; 16-bit operand
	db	8bh,01000011b		; mov ax,[ebx+ncavax]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax

; update target address and remaining length

	db	01h,01000011b		; add [ebx+ncarwoff],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwoff
	db	29h,01000011b		; sub [ebx+ncarwlen],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlen
	jz	e40wrap 		; exit if all bytes written
	db	3bh,01000011b		; cmp eax,[ebx+ncabufsz]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncabufsz
	je	e40loop 		; exit if not full staging buffer

; wrap up

e40wrap:
	db	66h
	jmp	e3fwrap
e40end:
	db	66h
	jmp	e3fend

	page
;--------------------------------------------------------------------
;		47 - get current directory with ds:esi
;--------------------------------------------------------------------

; save esi to ncauregs

einfun47:
	db	8bh,01000011b		; mov eax,[ebx+ncavsi]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavsi
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; move data area to ncabufer

	db	66h
	call	senddssi

; execute vm handler

	db	66h
	call	dovmint 		; edx contains vector number

; move modified area to user

	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	8bh,01111011b		; mov edi,[ebx+ncauregs+00] (esi)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	mov	es,ax
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	;	  11...110		; reg=esi
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,64/4
	cld
	rep	movsw

; recover esi from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavsi],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavsi
	db	66h
	jmp	einback

	page
	page
;--------------------------------------------------------------------
;	DTA functions, DOS conventions (UPDATE 80)
;--------------------------------------------------------------------
;
; TSL's native-mode API took the DTA in es:ebx at every 4Eh/4Fh and did
; not translate 1Ah/2Fh. Translating DPMI hosts (Windows, HDPMI) keep a
; protected-mode DTA set by 1Ah instead; this host now does the same.
; There are no native-mode programs left to keep the old API for.
;
; The DTA pointer is kept per client id in the hook segment (gs, page
; 5): gs:[4000h + id*8] = dd offset, dw selector, db set. cidstart
; clears an id's entry when it hands the id out. Without a 1Ah the DTA
; is DOS's default, PSP:80h, reached flat (linear PSP*16 + 80h).
;
; The real-mode side uses ncabufer as the DTA: 44 bytes (43 used),
; the ASCIIZ name for 4Eh at ncabufer+44. ncauregs: +00 destination
; offset, +04 destination selector, +08 the client's edx.
;
; entcid is read before the first dovmint only.
;

;---- 1a - set DTA: ds:(e)dx

einfun1a:
	xor	ax,ax			; xor eax,eax
	db	67h
	mov	al,ss:[entcid]
	mov	si,ax			; mov esi,eax
	shl	si,3			; shl esi,3: id*8
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	db	offset nca:ncavdx
	db	66h
	call	c32edc			; edx bit 22 = 32-bit client
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jnz	e1ais32
	db	0fh,0b7h,0c0h		; movzx eax,ax: 16-bit client
e1ais32:
	db	67h,65h			; gs:, 16-bit addressing
	mov	word ptr [si+4000h],ax	; mov [si+4000h],eax: offset
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncands]
	db	offset nca:ncands
	db	66h,67h,65h
	mov	word ptr [si+4004h],ax	; selector
	db	67h,65h
	mov	byte ptr [si+4006h],1	; set
	db	66h
	jmp	einback

;---- 2f - get DTA: es:ebx (reflected if the client never set one)

einfun2f:
	xor	ax,ax
	db	67h
	mov	al,ss:[entcid]
	mov	si,ax
	shl	si,3
	db	67h,65h
	cmp	byte ptr [si+4006h],0
	je	e2fpass
	db	67h,65h
	mov	ax,word ptr [si+4000h]	; mov eax,[si+4000h]
	db	89h,01000011b		; mov [ebx+ncavbx],eax
	db	offset nca:ncavbx
	db	66h,67h,65h
	mov	ax,word ptr [si+4004h]
	db	66h
	db	89h,01000011b		; mov [ebx+ncanes],ax: es on return
	db	offset nca:ncanes
	db	66h
	jmp	einback
e2fpass:
	db	66h
	jmp	einstand

;---- destination of the DTA copy into ncauregs+00/+04, edx into +08.
;     Near subroutine, no dovmint. Uses eax, esi, edi.

e4dst:
	xor	ax,ax
	db	67h
	mov	al,ss:[entcid]
	mov	si,ax
	shl	si,3
	db	67h,65h
	cmp	byte ptr [si+4006h],0
	je	e4dpsp
	db	67h,65h
	mov	ax,word ptr [si+4000h]	; offset
	db	89h,01000011b		; mov [ebx+ncauregs+00],eax
	db	offset nca:ncauregs+00
	db	66h,67h,65h
	mov	ax,word ptr [si+4004h]	; selector
	jmp	short e4dsel
e4dpsp:
	mov	di,si			; mov edi,esi
	shr	di,2			; id*2: cidpsp index
	xor	ax,ax
	db	66h,67h
	mov	ax,ss:[di+cidpsp]	; the client's PSP segment
	shl	ax,4			; shl eax,4
	db	05h			; add eax,80h
	dw	80h,0
	db	89h,01000011b		; mov [ebx+ncauregs+00],eax
	db	offset nca:ncauregs+00
	mov	ax,ds			; flat
e4dsel:
	db	66h
	db	89h,01000011b		; mov [ebx+ncauregs+04],ax
	db	offset nca:ncauregs+04
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+08],eax
	db	offset nca:ncauregs+08
	db	66h
	ret

;---- 4e - find first: name at ds:(e)dx, result to the DTA

einfun4e:
	db	66h
	call	e4dst

; move the ASCIIZ name to ncabufer+44

	cld
	mov	ax,ds
	mov	es,ax
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	db	offset nca:ncands
	db	8bh,01110011b		; mov esi,[ebx+ncavdx]
	db	offset nca:ncavdx
	mov	di,bx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	db	offset nca:ncabufer
	db	83h,11000111b		; add edi,44
	db	44
	mov	ds,ax
	xor	cx,cx
	mov	cl,64/4
	rep	movsw			; rep movsd
	mov	ax,es
	mov	ds,ax

; real-mode DTA = ncabufer

	mov	ax,bx
	shr	ax,4
	db	66h
	db	89h,01000011b		; mov [ebx+ncavds],ax
	db	offset nca:ncavds
	db	66h
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer
	db	offset nca:ncavdx
	dw	offset nca:ncabufer
	xor	dx,dx
	mov	dl,21h
	db	0c6h,01000011b		; mov [ebx+ncavax+1],1ah
	db	offset nca:ncavax+1
	db	1ah
	db	66h
	call	dovmint

; find first, name at ncabufer+44

	db	66h
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer+44
	db	offset nca:ncavdx
	dw	offset nca:ncabufer+44
	xor	dx,dx
	mov	dl,21h
	db	0c6h,01000011b		; mov [ebx+ncavax+1],4eh
	db	offset nca:ncavax+1
	db	4eh
	db	66h
	call	dovmint
	db	66h
	jmp	e4fback

;---- 4f - find next: search state from the DTA, result back to it

einfun4f:
	db	66h
	call	e4dst

; move the DTA (the search state) to ncabufer

	cld
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncauregs+04]
	db	offset nca:ncauregs+04
	db	8bh,01110011b		; mov esi,[ebx+ncauregs+00]
	db	offset nca:ncauregs+00
	mov	cx,ds
	mov	es,cx
	mov	di,bx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	db	offset nca:ncabufer
	mov	ds,ax
	xor	cx,cx
	mov	cl,44/4
	rep	movsw			; rep movsd
	mov	ax,es
	mov	ds,ax

; real-mode DTA = ncabufer, then find next

	mov	ax,bx
	shr	ax,4
	db	66h
	db	89h,01000011b		; mov [ebx+ncavds],ax
	db	offset nca:ncavds
	db	66h
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer
	db	offset nca:ncavdx
	dw	offset nca:ncabufer
	xor	dx,dx
	mov	dl,21h
	db	0c6h,01000011b		; mov [ebx+ncavax+1],1ah
	db	offset nca:ncavax+1
	db	1ah
	db	66h
	call	dovmint
	xor	dx,dx
	mov	dl,21h
	db	0c6h,01000011b		; mov [ebx+ncavax+1],4fh
	db	offset nca:ncavax+1
	db	4fh
	db	66h
	call	dovmint

; both: copy ncabufer back to the DTA, restore edx

e4fback:
	cld
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncauregs+04]
	db	offset nca:ncauregs+04
	db	8bh,01111011b		; mov edi,[ebx+ncauregs+00]
	db	offset nca:ncauregs+00
	mov	es,ax
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,44/4
	rep	movsw			; rep movsd
	mov	ax,ds
	mov	es,ax
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+08]
	db	offset nca:ncauregs+08
	db	89h,01000011b		; mov [ebx+ncavdx],eax
	db	offset nca:ncavdx
	db	66h
	jmp	einback


	page
;--------------------------------------------------------------------
;			56 - rename
;--------------------------------------------------------------------

; save edx to ncauregs

einfun56:
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; save edi to ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncavdi]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdi
	db	89h,01000011b		; mov [ebx+ncauregs+04],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04

; move 64 bytes addressed by ds:edx to ncabufer

	xor	cx,cx
	mov	cl,64
	db	66h
	call	senddsdx

; move 64 bytes addressed by es:edi to ncabufer+64

	db	66h
	call	sendesdi

; execute vm handler

	xor	dx,dx			; edx is vector number
	mov	dl,21h
	db	66h
	call	dovmint 		; edx contains vector number

; recover edx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00] (edx)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx

; recover edi from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+04]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04
	db	89h,01000011b		; mov [ebx+ncavdi],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdi
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;		     5a - create temporary file
;--------------------------------------------------------------------

; save edx to ncauregs

einfun5a:
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; move 64 bytes addressed by ds:edx to ncabufer

	xor	cx,cx
	mov	cl,64
	db	66h
	call	senddsdx

; execute vm handler

	xor	dx,dx			; edx is vector number
	mov	dl,21h
	db	66h
	call	dovmint 		; edx contains vector number

; move modified string to user

	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	8bh,01111011b		; mov edi,[ebx+ncauregs+00]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	mov	es,ax
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	;	  11...110		; reg=esi
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,44/4
	cld
	rep	movsw

; recover edx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00] (edx)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;			3f - read file data
;--------------------------------------------------------------------
einfun3f:
	db	66h
	call	e3f40pre		; preparation logic

; compute length for this read

e3floop:
	db	8bh,01000011b		; mov eax,[ebx+ncabufsz]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncabufsz
	db	8bh,01010011b		; mov edx,[ebx+ncarwlen]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlen
	cmp	ax,dx
	jb	e3fskip1
	mov	ax,dx			; read length is in ax
e3fskip1:
	db	89h,01000011b		; mov [ebx+ncavcx],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx

; execute vm handler

	xor	dx,dx			; edx is vector number
	mov	dl,21h
	db	0c6h,01000011b		; mov [ebx+ncavax+1],3fh
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	db	3fh			; function code moved to ah
	db	66h
	call	dovmint
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
	jnz	e3fend			; jump if carry was set

; get length read

	xor	ax,ax
	db	66h			; 16-bit operand
	db	8bh,01000011b		; mov ax,[ebx+ncavax]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax

; move input data to user'S BUFFER

	db	66h
	db	8bh,01111011b		; mov di,[ebx+ncarwseg]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwseg
	mov	es,di
	db	8bh,01111011b		; mov edi,[ebx+ncarwoff]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwoff
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	;	  11...110		; reg=esi
	db	offset nca:ncabufer
	mov	cx,ax
	shr	cx,2
	cld
	rep	movsw
	mov	cl,al
	and	cl,03h
	rep	movsb
	nop

; update target address and remaining length

	db	01h,01000011b		; add [ebx+ncarwoff],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwoff
	db	29h,01000011b		; sub [ebx+ncarwlen],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlen
	jz	e3fwrap 		; exit if all bytes read
	db	3bh,01000011b		; cmp eax,[ebx+ncabufsz]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncabufsz
	jne	e3fwrap 		; exit if not full staging buffer
;#####	db	66h
	jmp	short e3floop 		; repeat until everything read

; return actual length in eax

e3fwrap:
	db	8bh,01000011b		; mov eax,[ebx+ncarwlsv]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlsv
	db	2bh,01000011b		; sub eax,[ebx+ncarwlen]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlen
	db	89h,01000011b		; mov [ebx+ncavax],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax

; recover ecx,edx from ncauregs

e3fend:
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavcx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+04]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04
	db	89h,01000011b		; mov [ebx+ncavdx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	66h
	jmp	einback


	page
;--------------------------------------------------------------------
;		common prep code for reads and writes
;--------------------------------------------------------------------

; save ecx,edx to nca

e3f40pre proc  near
	db	8bh,01001011b		; mov ecx,[ebx+ncavcx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	89h,01001011b		; mov [ebx+ncauregs+00],cx
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+04],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04

; init address and length

	db	89h,01001011b		; mov [ebx+ncarwlen],ecx
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlen
	db	89h,01001011b		; mov [ebx+ncarwlsv],ecx
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwlsv
	db	89h,01000011b		; mov [ebx+ncarwoff],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwoff
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	66h
	db	89h,01000011b		; mov [ebx+ncarwseg],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncarwseg

; set v86 ds:dx

	mov	ax,bx
	shr	ax,4			; segment portion
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncavds],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavds
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	dw	offset nca:ncabufer	; immediate data
	cld
	db	66h
	ret
e3f40pre endp



	page
;--------------------------------------------------------------------
;		      82 - get scb address
;--------------------------------------------------------------------

; execute vm handler

einfun82:
;
; UPDATE 82: the kernel returns the SCB (02h) in es:bx and the TCB (04h)
; in es only -- bx is 04h's input, the task id. Was: the segment taken
; from ncavds (the caller's ds) and es*16 + bx for both. Now es; offset
; bx for 02h, 0 for 04h; registers as the kernel left them on an error.
;
	xor	ax,ax			; xor eax,eax
	db	8ah,01000011b		; mov al,[ebx+ncavax+1]: the function
	db	offset nca:ncavax+1
	db	89h,01000011b		; mov [ebx+ncauregs+00],eax
	db	offset nca:ncauregs+00
	db	66h
	call	dovmint 		; edx contains vector number
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	db	offset nca:ncavflag
	db	01h
	jnz	e82x			; error: nothing to translate

; translate es:bx (02h) or es:0 (04h) to es:ebx, es = 0043h

	xor	dx,dx			; xor edx,edx
	db	66h			; 16-bit data
	db	8bh,01010011b		; mov dx,[ebx+ncaves]
	db	offset nca:ncaves
	shl	dx,4			; shl edx,4: linear of the segment
	xor	ax,ax			; xor eax,eax: offset 0 for 04h
	db	80h,01111011b		; cmp byte ptr [ebx+ncauregs+00],04h
	db	offset nca:ncauregs+00
	db	04h
	je	e82t
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncavbx]
	db	offset nca:ncavbx
e82t:
	add	ax,dx			; add eax,edx
	db	2dh			; sub eax,400h (UPDATE 79): es = 0043h
	dw	0400h,0			;  has base 400h, see gdtzero3
	db	89h,01000011b		; mov [ebx+ncavbx],eax
	db	offset nca:ncavbx
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncanes],gdtzero3-gdt+3
	db	offset nca:ncanes
	dw	gdtzero3-gdt+3
e82x:
	db	66h
	jmp	einback


	page
;--------------------------------------------------------------------
;		83 - get/set extended directory info
;--------------------------------------------------------------------

; save edx,ebx to ncauregs

einfun83:
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	8bh,01000011b		; mov eax,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	89h,01000011b		; mov [ebx+ncauregs+04],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04

; move comm area to ncabufer

	mov	ax,ds
	mov	es,ax
	db	8bh,01000011b		; mov eax,[ebx+ncanes]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	8bh,01110011b		; mov esi,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	mov	ds,ax
	mov	di,bx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	;	  11...111		; reg=edi
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,10/2
	db	66h			; move 16-bit words
	rep	movsw
	nop
	mov	ax,es			; fix ds back to normal
	mov	ds,ax

; move asciiz string to ncabufer

	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	8bh,01110011b		; mov esi,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	mov	ds,ax
	xor	cx,cx
	mov	cl,64/4
	rep	movsw
	mov	ax,es			; fix ds back to normal
	mov	ds,ax

; set v86 bx,dx

	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavbx],offset nca:ncabufer
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	dw	offset nca:ncabufer	; immediate data
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer+10
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	dw	offset nca:ncabufer+10	; immediate data

; execute vm handler

	xor	dx,dx			; edx is vector number
	mov	dl,38h
	db	66h
	call	dovmint 		; edx contains vector number

; move modified area to user

	db	8bh,01000011b		; mov eax,[ebx+ncanes]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	8bh,01111011b		; mov edi,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	mov	es,ax
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	;	  11...110		; reg=esi
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,10/2
	cld
	db	66h
	rep	movsw
	nop

; recover edx,ebx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+04]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04
	db	89h,01000011b		; mov [ebx+ncavbx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	66h
	jmp	einback
	db	66h
	jmp	einstand

	page
;--------------------------------------------------------------------
;		send-stage ds:edx for length in cx
;--------------------------------------------------------------------
senddsdx proc  near
	mov	ax,ds
	mov	es,ax
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	8bh,01110011b		; mov esi,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	mov	ds,ax
	mov	di,bx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	;	  11...111		; reg=edi
	db	offset nca:ncabufer
	shr	cx,2
	rep	movsw
	mov	ax,es			; fix ds back to normal
	mov	ds,ax

; set v86 ds:dx

	mov	ax,bx
	shr	ax,4			; segment portion
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncavds],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavds
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavdx],offset nca:ncabufer
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	dw	offset nca:ncabufer	; immediate data
	db	66h
	ret
senddsdx endp

	page
;--------------------------------------------------------------------
;		send-stage es:edi for 64 bytes to es:di
;--------------------------------------------------------------------
sendesdi proc  near
	db	8bh,01000011b		; mov eax,[ebx+ncanes]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	8bh,01110011b		; mov esi,[ebx+ncavdi]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdi
	mov	ds,ax
	xor	cx,cx
	mov	cl,64/4
	rep	movsw
	mov	ax,es			; fix ds back to normal
	mov	ds,ax

; set v86 es:di

	mov	ax,bx
	shr	ax,4			; segment portion
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncaves],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncaves
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavdi],offset nca:ncabufer+64
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdi
	dw	offset nca:ncabufer+64	; immediate data
	db	66h
	ret
sendesdi endp

	page
;--------------------------------------------------------------------
;		send-stage ds:esi for 64 bytes to ds:si
;--------------------------------------------------------------------
senddssi proc  near
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	8bh,01110011b		; mov esi,[ebx+ncauregs+00] (esi)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	mov	ds,ax
	mov	di,bx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	;	  11...111		; reg=edi
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,64/4
	rep	movsw
	mov	ax,es			; fix ds back to normal
	mov	ds,ax

; set v86 ds:si

	mov	ax,bx
	shr	ax,4			; segment portion
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncavds],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavds
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavsi],offset nca:ncabufer
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavsi
	dw	offset nca:ncabufer	; immediate data
	db	66h
	ret
senddssi endp

	page
;--------------------------------------------------------------------
;		 switch from native mode to v-86 mode
;--------------------------------------------------------------------
einfun90:
	db	66h
	mov	sp,offset mmgrp:s0ip-28 ; make room for 7 gp registers

; set s0cs:soip

	db	8bh,01000011b		; mov ax,[ebx+ncancs]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncancs
	db	66h
	call	makesel
	db	67h
	mov	ss:[s0cs],ax
	db	8bh,01000011b		; mov ax,[ebx+ncanip]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanip
	db	67h			; 16-bit address
	mov	ss:[s0ip],ax		; 32-bit data

; set s0ss:s0sp

	db	8bh,01000011b		; mov ax,[ebx+ncanss]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanss
	db	66h
	call	makesel
	db	67h
	mov	ss:[s0ss],ax
	db	8bh,01000011b		; mov ax,[ebx+ncansp]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncansp
	db	67h			; 16-bit address
	mov	ss:[s0sp],ax		; 32-bit data

; set s0flags

	mov	ax,3000h		; iopl=3,
	dw	0002h			;   vm=on
	db	66h			; 16-bit data
	db	0bh,01000011b		; or ax,[ebx+ncanflag]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanflag
	and	ah,00111111b		; 0,nt off
	db	67h
	or	ah,ss:[trapflag]	; tf on if tracing
	db	67h			; 16-bit address
	mov	ss:[s0flags],ax 	; 32-bit data

; set segment registers in p0stack

	db	8bh,01000011b		; mov ax,[ebx+ncanes]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	66h
	call	makesel
	db	67h			; 16-bit address
	mov	ss:[s0es],ax		; 32-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	db	66h
	call	makesel
	db	67h			; 16-bit address
	mov	ss:[s0ds],ax		; 32-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncanfs]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanfs
	db	66h
	call	makesel
	db	67h			; 16-bit address
	mov	ss:[s0fs],ax		; 32-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncangs]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncangs
	db	66h
	call	makesel
	db	67h			; 16-bit address
	mov	ss:[s0gs],ax		; 32-bit data

; set general registers in p0stack

	mov	ax,ss
	mov	es,ax
	mov	si,bx			; start with di
	db	83h,11000110b		; add esi,offset nca:ncairegs+4
	;	  11...110		; reg=esi
	db	offset nca:ncairegs+4
	mov	di,sp
	xor	cx,cx
	mov	cl,6
	cld
	rep	movsw
	add	si,8			; skip es,ds to pick up bp
	movsw

; resume application in virtual mode

	pop	di
	pop	si
	pop	dx
	pop	ax
	pop	bx
	pop	cx
	pop	bp
	iret				; loads ss,sp,es,ds,fs,gs
					; and switches to virtual mode

;--------------------------------------------------------------------
;      translate native-mode selector in ax to segment address
;--------------------------------------------------------------------
makesel  proc  near
	and	al,0f8h 		; clear low 3 bits
	db	66h
	or	ax,ax			; skip if null selector
	jz	makesnul
	mov	si,ax
	db	67h
	mov	ax,ss:[si+gdt+2]	; get linear address from gdt entry
	shr	ax,4			; shift to get segment address
makesnul:
	db	67h
	and	ax,ss:[zero1631]	; clear bits 16-31
	db	66h
	ret
makesel  endp

	page
;--------------------------------------------------------------------
;	   allocate extended memory for native-mode task
;--------------------------------------------------------------------

; save ecx to ncauregs

einfun91:
	db	8bh,01000011b		; mov eax,[ebx+ncavcx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; compute number of banks into ncavcx

	db	8bh,01000011b		; mov eax,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	add	ax,0fffh		; round up to 4k
	dw	0
	shr	ax,12			; and convert to a number of pages
	db	89h,01000011b		; mov [ebx+ncavcx],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	89h,01000011b		; mov [ebx+ncauregs+04],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04

; call allocation routine in virtual mode

	db	66h
	mov	dx,offset mmgrp:rhentry ; nonzero dh has special meaning
	db	0c6h,01000011b		; mov [ebx+ncavax+1],01h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	db	01h			; request code moved to ah
	db	66h
	call	dovmint

; compute selector from ncavbx

	xor	dx,dx			; put number of pages into dx
	db	66h
	db	8bh,01010011b		; mov dx,[ebx+ncavcx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	66h
	db	3bh,01010011b		; cmp dx,[ebx+ncauregs+04]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04
	jb	ei91err 		; error, not enough memory
	xor	ax,ax			; put starting page number into ax
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	66h
	add	ax,0110h		; 121288  oops, make that 110h
	shl	ax,12
	db	66h
	call	makegdtx		; make gdt entry
	db	89h,01000011b		; mov [ebx+ncanes],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes

; set return code

	db	80h,01100011b		; and [ebx+ncavflag],0feh clear carry
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	0feh			; immediate data
	xor	ax,ax
ei91wrap:
	db	89h,01000011b		; mov [ebx+ncavax],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax

; compute actual number of bytes allocated in ncavbx

	shl	dx,12			; still got pages in dx
	db	89h,01010011b		; mov [ebx+ncavbx],edx
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx

; restore ecx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs
	db	89h,01000011b		; mov [ebx+ncavcx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	66h
	jmp	einback

; not enough memory could be allocated
; deallocate the partial allocation
	
ei91err:
	db	66h
	mov	dx,offset mmgrp:rhentry ; nonzero dh has special meaning
	db	0c6h,01000011b		; mov [ebx+ncavax+1],02h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	db	02h			; request code moved to ah
	db	66h
	call	dovmint

; set carry flag and return code

	db	80h,01001011b		; or [ebx+ncavflag],01h set carry
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
	xor	ax,ax			; put return code in eax
	mov	al,8			; 8 = "insufficient memory"
	xor	dx,dx			; also indicate zero bytes allocated
	jmp	short ei91wrap		; jump to wrapup code

	page
;--------------------------------------------------------------------
;	 deallocate extended memory for native-mode task
;--------------------------------------------------------------------

; save ebx,ecx to ncauregs

einfun92:
	db	8bh,01000011b		; mov eax,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	8bh,01000011b		; mov eax,[ebx+ncavcx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	89h,01000011b		; mov [ebx+ncauregs+04],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04

; look up gdt entry

	xor	si,si
	db	66h
	db	8bh,01110011b		; mov si,[ebx+ncanes]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	66h
	and	si,0fff8h		; clear bits 0-2

; compute starting page number

	db	67h
	mov	ax,ss:[si+gdt+2]	; get base bits 0-23
	shr	ax,12			; convert to page number
	and	ax,0fffh		; 12 bits are left
	dw	0
	db	67h
	mov	dl,byte ptr ss:[si+gdt+7]  ; get base bits 24-27
	shl	dl,4
	or	ah,dl
	db	66h			; 121288  oops, make that 110h
	sub	ax,0110h
	db	89h,01000011b		; mov [ebx+ncavbx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx

; set number of pages

	db	66h
	db	67h
	mov	ax,ss:[si+gdt]		; get number of pages
	db	89h,01000011b		; mov [ebx+ncavcx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx

; flag the gdt slot as available

	db	66h
	sub	si,gdtspace-gdt
	shr	si,3
	db	67h
	mov	ss:[si+dtitable],0ffh

; call deallocation routine in virtual mode

	db	66h
	mov	dx,offset mmgrp:rhentry ; nonzero dh has special meaning
	db	0c6h,01000011b		; mov [ebx+ncavax+1],02h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	db	02h			; request code moved to ah
	db	66h
	call	dovmint

; set return code

	xor	ax,ax
	db	89h,01000011b		; mov [ebx+ncavax],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	db	80h,01100011b		; and [ebx+ncavflag],0feh clear carry
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	0feh			; immediate data

; restore ebx,ecx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs
	db	89h,01000011b		; mov [ebx+ncavbx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+04]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+04
	db	89h,01000011b		; mov [ebx+ncavcx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;		     93 - make a gdt alias
;--------------------------------------------------------------------

; set carry flag in case of error

einfun93:
	db	80h,01001011b		; or [ebx+ncavflag],01h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data

; look up gdt entry

	xor	si,si
	db	66h
	db	8bh,01110011b		; mov si,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	66h
	and	si,0fff8h		; clear bits 0-2

; find a vacant slot

	xor	di,di
e93loop:
	db	67h
	cmp	ss:[di+dtitable],0ffh	; available entry?
	je	e93gotav		; yes, jump
	inc	di			; no, look again
	cmp	di,dtilen
	jb	e93loop
	xor	ax,ax			; table full - return null selector
	jmp	short e93exit
e93gotav:
	db	67h
	mov	ss:[di+dtitable],0feh	; set as permanent entry

; create new descriptor

	shl	di,3
	db	66h
	add	di,gdtspace-gdt
	db	67h
	mov	ax,ss:[si+gdt]
	db	67h
	mov	ss:[di+gdt],ax
	db	67h
	mov	ax,ss:[si+gdt+4]
	db	67h
	mov	ss:[di+gdt+4],ax
	db	8ah,01000011b		; mov al,[ebx+ncavax]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	and	al,03h
	shl	al,2
	or	al,11110010b
	db	67h
	mov	byte ptr ss:[di+gdt+5],al  ; set requested access rights

; wrap up

	db	80h,01100011b		; and [ebx+ncavflag],0feh  clear carry
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	0feh			; immediate data
	mov	ax,di			; return selector with rpl=3
	or	al,3
e93exit:
	db	89h,01000011b		; mov [ebx+ncavax],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	db	66h
	jmp	einback


; push remaining registers

einative:				; bp,ds,es,cx,bx already pushed
	push	ax
	push	dx
	push	si
	push	di

; get nca address

	db	66h
	call	addrnca 		; get nca address in ebx
	db	66h
	call	cidl			; dl = this task's client id: cached for
	db	67h			;  einvh1 and e0300s, which run before
	mov	ss:[entcid],dl		;  any v-86 or task switch (UPDATE 75)

; save user registers into nca

	cld				; prepare for movsw instructions
	mov	ax,ds
	mov	es,ax
	mov	ax,ss
	mov	ds,ax
	mov	di,bx			; move flags to ncairegs
	db	83h,11000111b		; add edi,offset nca:ncairegs
	;	  11...111		; reg=edi
	db	offset nca:ncairegs
	mov	si,offset mmgrp:p0stack-12  ; user flags
	dw	0			; 32-bit operand
	movsw
	mov	si,sp			; move di,si,dx,ax,bx,cx,es,ds,bp
	xor	cx,cx			;   to ncairegs
	mov	cl,9
	rep	movsw
	nop
	mov	si,bp			; move es,ds,fs,gs to ncap0stk
	sub	si,8			; must use bp because error code
	movsw				;   may or may not be present
	movsw
	db	8ch,11100000b		; mov ax,fs
	stosw
	db	8ch,11101000b		; mov ax,gs
	stosw
	db	0b8h			; mov eax,imm32 (UPDATE 73; EAXI is defined
	dw	gdthook-gdt,0		;  further down -- a phase error): gs ->
	db	8eh,0e8h		;  mov gs,ax: the hook table, from here on
	db	66h			; 16-bit operand
	mov	si,offset mmgrp:p0stack-20  ; move eip,cs,flags,esp,ss
	mov	cl,5
	rep	movsw
	nop
	mov	ax,es			; fix ds back
	mov	ds,ax

; vector for custom handling of int 21/38 functions

	xor	dx,dx			; dx to contain vector number
	db	67h
	mov	dl,ss:[iveccode]
	db	66h
	jmp	einvhook		; pm vector hooks, default stubs
eindisp:
	cmp	dl,38h			
	je	eint38
	cmp	dl,0d4h
	je	eint38
	cmp	dl,31h			; DPMI services
	jne	e31skip
	db	66h
	jmp	einint31
e31skip:
	cmp	dl,21h
	jne	einstd0
;
; UPDATE 82: a 16-bit client's int 21h. The translators take pointers
; and counts from the 32-bit slots (3Fh/40h: ecx bytes at ds:edx; 39h-
; 3Dh, 41h, 43h, 4Eh, 56h, 5Ah: ds:edx, es:edi; 47h: ds:esi). For a
; 16-bit client the high words are junk: clear them in cx, dx, si, di
; before any translator runs. (A reflected call already returns these
; slots with whatever the v-86 side left in the high words.)
;
	push	dx			; push edx: the vector (21h)
	db	66h
	call	c32edc			; edx bit 22 = 32-bit client
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	pop	dx			; pop edx (flags kept)
	jnz	e21w32
	db	66h
	db	0c7h,01000011b		; mov word ptr [ebx+ncavcx+2],0
	db	offset nca:ncavcx+2
	dw	0
	db	66h
	db	0c7h,01000011b		; mov word ptr [ebx+ncavdx+2],0
	db	offset nca:ncavdx+2
	dw	0
	db	66h
	db	0c7h,01000011b		; mov word ptr [ebx+ncavsi+2],0
	db	offset nca:ncavsi+2
	dw	0
	db	66h
	db	0c7h,01000011b		; mov word ptr [ebx+ncavdi+2],0
	db	offset nca:ncavdi+2
	dw	0
e21w32:
	xor	ax,ax
	db	8ah,01000011b		; mov al,[ebx+ncavax+1]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	cmp	al,39h
	jb	einlt39
	cmp	al,5ch
	ja	einstd0
	sub	al,39h
	shl	ax,1
	mov	si,ax
	db	66h
	db	67h
	jmp	cs:[si+eintable]

;
; einstand is out of short-jump range from the dispatch above
; since einfun4c/freeclsel were inserted ahead of it.
;
einstd0:
	db	66h
	jmp	einstand
einlt39:
	cmp	al,0ah			; 0a - buffered input
	jne	e0askip
	db	66h
	jmp	einfun0a
e0askip:
	cmp	al,09h			; 09 - display string
	jne	einlt39b
	db	66h
	jmp	einfun09
einlt39b:
	cmp	al,1ah			; UPDATE 80: set / get DTA
	jne	e1askip
	db	66h
	jmp	einfun1a
e1askip:
	cmp	al,2fh
	jne	e2fskip
	db	66h
	jmp	einfun2f
e2fskip:
	cmp	al,1ch
	jne	einstd0
;######	db	66h
	jmp	short einfun1c
eint38:
	xor	ax,ax
	db	8ah,01000011b		; mov al,[ebx+ncavax+1]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1
	cmp	al,02h
	jb	einstd0
	cmp	al,13h
	ja	einstd0
	sub	al,02h
	shl	ax,1
	mov	si,ax
	db	66h
	db	67h
	jmp	cs:[si+eixtable]


;--------------------------------------------------------------------
;		      1c - allocation info
;--------------------------------------------------------------------

; save ebx to ncauregs

einfun1c:
	db	8bh,01000011b		; mov eax,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	db	89h,01000011b		; mov [ebx+ncauregs+00],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; execute vm handler

	db	66h
	call	dovmint 		; edx contains vector number

; move byte addressed by new ds:bx to ncaiah

	xor	dx,dx
	db	66h			; 16-bit data
	db	8bh,01010011b		; mov dx,[ebx+ncavds]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavds
	shl	dx,4			; got v86 segment portion of address
	xor	ax,ax
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncavbx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	add	ax,dx			; add in v86 offset
	db	8ah,00000000b		; mov al,[eax]
	;	  00...000		; disp=none,base=eax
	db	88h,01000011b		; mov [ebx+ncavax+1],al (ah)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax+1

; recover ebx from ncauregs

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavbx],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
;#####	db	66h
	db	66h
	jmp	einback			; out of short range since einfun0a



; execute virtual-mode interrupt handler

	page
;--------------------------------------------------------------------
;		4c - terminate: release client descriptors
;--------------------------------------------------------------------
;
; A DPMI client is a program inside the shell's task, so tcbunreg (and
; with it the driver's Unregister path, which calls int 6fh 778Fh)
; never runs for it: without this, every client program leaks its
; tagged 80h|taskid slots. Its own int 21h ah=4Ch is the one point
; that is guaranteed to be reached, so the release happens here and
; the call then reflects as an ordinary termination.
;
	page
;--------------------------------------------------------------------
;		0a - buffered keyboard input
;--------------------------------------------------------------------
;
; ds:(e)dx is a buffer whose first byte is the maximum length; DOS
; fills in the actual length at byte 1 and the text from byte 2. It is
; therefore staged in BOTH directions: max+2 bytes out (so DOS sees the
; size byte), then len+2 bytes back into the client's own buffer.
;
; As with einfun09, a 16-bit client may have junk in the high word of
; edx, so the offset is zero-extended off the D bit of its cs.
;

; save edx to ncauregs

einfun0a:
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,01000011b		; mov [ebx+ncauregs+00],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00

; zero-extend the offset for a 16-bit client, in place

	db	66h
	call	c32eax		; eax bit 22 = 32-bit client (UPDATE 62)
	db	0a9h			; test eax,00400000h (D bit)
	dd	00400000h
	jnz	e0ais32
	db	8bh,01000011b		; mov eax,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	0fh,0b7h,11000000b	; movzx eax,ax
	db	89h,01000011b		; mov [ebx+ncavdx],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
e0ais32:

; read the caller's maximum length from byte 0 of its buffer

	mov	ax,ds			; es = absolute zero
	mov	es,ax
	db	8bh,01110011b		; mov esi,[ebx+ncavdx]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	mov	ds,ax			; client's data selector
	cld
	lodsb				; al = maximum length
	mov	si,es
	mov	ds,si			; fix ds back to normal
	db	0fh,0b6h,11001000b	; movzx ecx,al
	db	83h,11000001b		; add ecx,2 (size byte + length byte)
	db	02h

; stage the buffer out and execute the vm handler

	db	66h
	call	senddsdx
	db	66h
	call	dovmint 		; edx contains vector number

; move the reply back into the client's buffer: len+2 bytes

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00] (edx)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdx],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	db	89h,11000111b		; mov edi,eax
	db	8bh,01000011b		; mov eax,[ebx+ncands]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncands
	mov	es,ax			; es:edi = the client's buffer
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	;	  11...110		; reg=esi
	db	offset nca:ncabufer
	db	8ah,01000110b		; mov al,[esi+1] (length DOS returned)
	db	01h
	db	0fh,0b6h,11001000b	; movzx ecx,al
	db	83h,11000001b		; add ecx,2
	db	02h
	cld
	rep	movsb
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;		48 - allocate memory
;--------------------------------------------------------------------
;
; DOS returns a real-mode segment in ax, which a client in protected
; mode cannot load. The block is therefore handed back as a data
; selector for the same base, built by makegdte and tagged
; 80h|taskid like the ones 8eh/86h make, so einfun4c releases it when
; the client terminates.
;
; Table full is reported as DOS reports "insufficient memory":
; ax=8 with carry set.
;
einfun48:
	db	66h
	call	dovmint 		; edx contains vector number
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
	jnz	e48done 		; carry set: allocation failed
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncavax] (segment)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	push	ax			; 32-bit cs: pushes eax
	db	66h
	call	addrnca 		; esi -> tcb, ebx -> nca
	db	66h
	call	cidh			; dh = client id (UPDATE 67)
	or	dh,80h			; the client-descriptor tag
	pop	ax			; segment again
	mov	dl,11110010b		; p=1,dpl=3,s=1,type=001 data r/w
	db	66h
	call	makegdte		; ax = selector, 0 = table full
	or	ax,ax
	jz	e48fail
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncavax],ax (selector)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	jmp	short e48done
e48fail:
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavax],8 (insufficient memory)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	dw	8			; immediate data
	db	80h,01001011b		; or [ebx+ncavflag],01h (set carry)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
e48done:
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;		49 - release memory
;--------------------------------------------------------------------
;
; The counterpart of 48h: the client holds a SELECTOR in es where DOS
; wants the real-mode segment, so the descriptor's base is read back
; out of the gdt and shifted down. On success the gdt slot is handed
; back too, otherwise a client that allocates and frees in a loop
; would exhaust dtitable while DOS itself stayed happy.
;
; An es that is not one of this task's tagged selectors is left alone
; and passed through, so a client that legitimately holds a real-mode
; segment still works.
;
einfun49:
	db	66h			; 16-bit data
	db	8bh,01110011b		; mov si,[ebx+ncanes] (client's es)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	66h
	and	si,0fff8h		; clear rpl bits 0-2
	db	66h
	cmp	si,gdtspace-gdt 	; below the user area?
	jb	e49pass
	db	66h
	cmp	si,gdtspace-gdt+8*dtilen
	jae	e49pass

; convert the descriptor base back to a real-mode segment

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	ax,ss:[si+gdt+2]	; base bits 0-15
	db	67h
	mov	dl,byte ptr ss:[si+gdt+4]  ; base bits 16-23
	db	66h
	shr	ax,4
	shl	dl,4
	or	ah,dl			; paragraph number
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncaves],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncaves

; execute vm handler, then release the gdt slot if dos agreed

; MOS returns CF unchanged on success, so a carry the client happened
; to be carrying in would come back looking like a failure -- and would
; also suppress the slot release below. Enter with CF clear.

	db	66h			; 16-bit data
	db	83h,01100011b		; and [ebx+ncavflag],0fffeh
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	0feh			; immediate data, sign-extended

; dovmint takes the VECTOR in edx, and the conversion above used dl
; for base bits 16-23: 49h was being reflected through vector 10h
; (dl = base byte << 4), the video BIOS -- never reaching DOS. That
; was the whole "49h does nothing from PM" story (UPDATE 25/35/45).
	xor	dx,dx			; xor edx,edx
	mov	dl,21h
	db	66h
	call	dovmint 		; edx contains vector number
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
	jnz	e49done 		; carry set: dos refused, keep it
	db	66h			; 16-bit data
	db	8bh,01110011b		; mov si,[ebx+ncanes]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	66h
	and	si,0fff8h
	db	66h
	sub	si,gdtspace-gdt
	db	66h
	shr	si,3			; dtitable index
	db	67h
	mov	ss:[si+dtitable],0ffh	; slot is free again
	db	66h
	jmp	einback
e49pass:
	db	66h
	call	dovmint 		; not ours: straight reflection
e49done:
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;		int 31h - DPMI services from a native-mode client
;--------------------------------------------------------------------
;
; Until now a client's int 31h fell through to einstand and was
; reflected to the REAL-MODE vector 31h, which points at nothing:
; garbage v86 frame, int 3, invalid opcode (UPDATE 36). The host's own
; protected-mode dispatcher (_DPMI.ASM Interupt31) has never run and
; needs repairs first (UPDATE 37), so this is the routing point, with
; the monitor answering what it can directly -- the same way einative
; already answers int 21h. Results go into the v86 register set,
; which einback copies to the client.
;
; 0400h  get DPMI version
;	ax = 005Ah (0.90), bx = 0001h (32-bit programs supported,
;	interrupts reflected in v86 mode), cl = 03h (386-class, the
;	floor this host requires), dh/dl = 08h/70h (master/slave PIC
;	bases as the BIOS programs them)
;
; anything else: carry set, registers unchanged
;
einint31:
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncavax]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	db	66h
	cmp	ax,0010h		; 0000h-000Fh: descriptor functions
	jae	e31nf0		; UPDATE 76: hot functions first
	db	66h
	jmp	e31desc
e31nf0:					; UPDATE 76: fast path for the calls
	db	66h			;  extenders make all the time; the
	cmp	ax,0300h		;  chain below is unchanged and still
	jne	e31nf1		;  handles everything else
	db	66h
	jmp	e310300
e31nf1:
	db	66h
	cmp	ax,0301h
	je	e31nfj
	db	66h
	cmp	ax,0302h
	jne	e31nf2
e31nfj:
	db	66h
	jmp	e310301
e31nf2:
	db	66h
	cmp	ax,0501h		; 0501h-0503h: memory blocks
	jb	e31n00
	db	66h
	cmp	ax,0503h
	ja	e31nf3
	db	66h
	jmp	e31save
e31nf3:
	db	66h
	cmp	ax,0900h		; 0900h-0902h: virtual IF
	jb	e31n00
	db	66h
	cmp	ax,0902h
	ja	e31n00
	db	66h
	jmp	e3190x
e31n00:
	db	66h
	cmp	ax,0100h
	jne	e31n01
	db	66h
	jmp	e310100
e31n01:
	db	66h
	cmp	ax,0101h
	jne	e31n02
	db	66h
	jmp	e310101
e31n02:
	db	66h
	cmp	ax,0102h
	jne	e31n03
	db	66h
	jmp	e310102
e31n03:
	db	66h
	cmp	ax,0200h
	jne	e31n20
	db	66h
	jmp	e310200
e31n20:
	db	66h
	cmp	ax,0201h
	jne	e31n21
	db	66h
	jmp	e310201
e31n21:
	db	66h
	cmp	ax,0202h
	jne	e31n22
	db	66h
	jmp	e310202
e31n22:
	db	66h
	cmp	ax,0203h
	jne	e31n23
	db	66h
	jmp	e310203
e31n23:
	db	66h
	cmp	ax,0204h
	jne	e31n24
	db	66h
	jmp	e310204
e31n24:
	db	66h
	cmp	ax,0205h
	jne	e31n25
	db	66h
	jmp	e310205
e31n25:
	db	66h
	cmp	ax,0300h
	jne	e31n30
	db	66h
	jmp	e310300
e31n30:
	db	66h
	cmp	ax,0305h
	jne	e31n35
	db	66h
	jmp	e310305
e31n35:
	db	66h
	cmp	ax,0303h
	jne	e31n33
	db	66h
	jmp	e310303
e31n33:
	db	66h
	cmp	ax,0304h
	jne	e31n34
	db	66h
	jmp	e310304
e31n34:
	db	66h
	cmp	ax,0306h
	jne	e31n36
	db	66h
	jmp	e310306
e31n36:
	db	66h
	cmp	ax,0301h
	je	e31n31
	db	66h
	cmp	ax,0302h
	jne	e31n32
e31n31:
	db	66h
	jmp	e310301
e31n32:
	db	66h
	cmp	ax,0600h
	jb	e31n70
	db	66h
	cmp	ax,0603h
	ja	e31n64
	db	66h
	jmp	e31nop
e31n64:
	db	66h
	cmp	ax,0604h
	jne	e31n70
	db	66h
	jmp	e310604
e31n70:
	db	66h
	cmp	ax,0702h
	jb	e31n90
	db	66h
	cmp	ax,0703h
	ja	e31n90
	db	66h
	jmp	e31nop
e31n90:
	db	66h
	cmp	ax,0900h
	jb	e31n99
	db	66h
	cmp	ax,0902h
	ja	e31n99
	db	66h
	jmp	e3190x
e31n99:
	db	66h			; UPDATE 81: physical address mapping
	cmp	ax,0800h
	jne	e31n9a
	db	66h
	jmp	e310800
e31n9a:
	db	66h
	cmp	ax,0400h
	je	e310400
	db	66h
	cmp	ax,0500h
	jne	e31n05
	db	66h
	jmp	e310500
e31n05:
	db	66h
	cmp	ax,0501h
	jb	e31bad
	db	66h
	cmp	ax,0503h
	ja	e31bad
	db	66h
	jmp	e31save
e310400:
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavax],005Ah
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavax
	dw	005Ah			; immediate data
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavbx],0001h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavbx
	dw	0001h			; immediate data
	db	0c6h,01000011b		; mov byte [ebx+ncavcx],03h (cl)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavcx
	db	03h			; immediate data
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncavdx],0870h
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdx
	dw	0870h			; immediate data
	db	66h			; 16-bit data
	db	83h,01100011b		; and [ebx+ncavflag],0fffeh (CF clear)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	0feh			; immediate data, sign-extended
	db	66h
	jmp	einback
e31bad:
	db	80h,01001011b		; or [ebx+ncavflag],01h (CF set)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	01h			; immediate data
	db	66h
	jmp	einback

;---- int 31h 0800h - physical address mapping (UPDATE 81)
;
; bx:cx = physical address, si:di = size. Out: bx:cx = linear address,
; cf clear; cf set if refused. The work is e31phys (res32, phyptr).

e310800:
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncavbx]
	db	offset nca:ncavbx
	shl	ax,16			; shl eax,16
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncavcx]
	db	offset nca:ncavcx
	push	ax			; push eax: physical address
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncavsi]
	db	offset nca:ncavsi
	shl	ax,16
	db	66h
	db	8bh,01000011b		; mov ax,[ebx+ncavdi]
	db	offset nca:ncavdi
	mov	cx,ax			; mov ecx,eax: size
	pop	ax			; pop eax
	db	67h
	call	word ptr ss:[phyptr]	; call dword: e31phys
	jc	e0800n
	db	66h
	db	89h,01000011b		; mov [ebx+ncavcx],ax
	db	offset nca:ncavcx
	shr	ax,16			; shr eax,16
	db	66h
	db	89h,01000011b		; mov [ebx+ncavbx],ax
	db	offset nca:ncavbx
	db	66h
	jmp	e31dok
e0800n:
	db	66h
	jmp	e31bad

; DPMI task reserve, pages -- set by int 6fh 7790h (e6f90), read by
; 0500h through ss. Kept HERE, after an unconditional jump, and NOT
; in the parmgran/parmtot/parmused block: that block is read by
; layout, and inserting a field there shifted parm6ec and everything
; after it -- the keyboard died (UPDATE 40).
dpmirsv dw	0,0

; DPMI extended memory blocks per task (UPDATE 43), ss-addressable
DBLKN	equ	128			; 128 blocks system-wide (1 KB)
dblktab db	DBLKN*8 dup(0)

; DPMI protected-mode interrupt hooks and default stubs (UPDATE 50)
DPHKN	equ	1024			; UPDATE 67: nested clients (a DOS/4GW child
					;  under a DOS/4GW parent needs 2 x 288).
					;  UPDATE 64: was 32, shared by 0203h and 0205h
					;  across all tasks. One DOS/4GW client hooks all
					;  256 vectors and 32 exceptions (288); its 33rd
					;  hook failed, cf=1, and it aborted.
hookok	db	0			; UPDATE 73: 1 once hookinit made the table
hooklin	dd	0			; UPDATE 74: linear of the hook table
hookhwm	dw	0			; UPDATE 69: offset just past the highest
					;  phooktab entry ever used; the lookups stop
					;  here (never lowered, so nothing is missed)
stubsel16 dw	0
stubsel32 dw	0
stublin	dd	0			; UPDATE 71: linear address of the stubs
stbptr	dw	0,0			; UPDATE 71: offset of stbget (res32), set
					;  by e6f8e -- a use16 segment cannot hold it
nlgptr	dw	0,0			; UPDATE 72: offset of nlargest (res32), set by e6f8e
phyptr	dw	0,0			; UPDATE 81: offset of e31phys (res32), set by e6f8e
cbeax	dd	0			; callback entry scratch (e6f91)
cbedx	dd	0
cbesi	dd	0
cbedi	dd	0
cbrmsel	dw	0
einb_ptr dw	offset mmgrp:einback,0	; use32 -> einback (use16); dw+0, not
					;  dd: a dd emits a segment fixup exe2bin rejects
cbr_ptr	dd	0			; -> e6fcbret: filled by e6f91 (use16 cannot
					;  refer forward into the use32 segment)
raw_ptr	dd	0			; -> e6frawpm: filled by e6f8e, as cbr_ptr

c32tab	db	128 dup(0)		; per task id: DPMI client type, 0 none,
					;  1 16-bit, 2 32-bit (e6f8e; UPDATE 62)
envtab	dd	128 dup(0)		; per task id: environment segment << 16 |
					;  PSP segment, 0 = nothing to put back
					;  (e6f93, envr16, envrest; UPDATE 63)
curcid	db	128 dup(0)		; per task id: current DPMI client id,
					;  0 none (UPDATE 67)
cidtask	db	128 dup(0)		; per client id: owner task id + 1, 0 free
parcid	db	128 dup(0)		; per client id: parent client id, 0 none
savnca	dw	128 dup(0)		; per client id: the parent's tcbncadr
cidpsp	dw	128 dup(0)		; per client id: its PSP
pendsw	db	128 dup(0)		; per task id: client id of a pending DPMI
					;  switch, for nmswitch (UPDATE 67)
entcid	db	0			; UPDATE 75: client id of the task that
					;  last entered einative (see c32edc)
; DPMI real-mode callbacks (UPDATE 59): records and real-mode stubs
DCBN	equ	8
DCBSZ	equ	96
dcbtab	db	DCBN*DCBSZ dup(0)
dcbstub label	byte			; push ax / mov ax,7791h / push n / int 6fh
DCBI	=	0
	rept	DCBN
	db	50h,0b8h,91h,77h,6ah,DCBI,0cdh,6fh
DCBI	=	DCBI+1
	endm
rawstub	db	50h,0b8h,92h,77h,0cdh,6fh	; push ax / mov ax,7792h / int 6fh
; UPDATE 71: the default stubs (4.2 KB) are generated at run time
; into extended memory by e31stubs -- see there for the layout.

	page
;--------------------------------------------------------------------
;		int 31h 0500h - get free memory information
;--------------------------------------------------------------------
;
; es:(e)di -> 48-byte buffer. Filled as DPMI 0.9 defines it:
;	+00  largest available free block, bytes
;	+04  maximum unlocked page allocation, pages
;	+08  maximum locked page allocation, pages
;	+14  number of free pages
;	all other dwords 0FFFFFFFFh (not available)
;
; The figure comes from the memory device itself, reached the way
; einfun91 reaches it (dovmint with dx = rhentry): valloc asked for
; everything returns the largest block it could have given in cx, and
; is released again at once with vrelease. Nothing stays allocated.
; ncabufer holds the page count across the second call, since dovmint
; resets the monitor stack.
;
; Registers are preserved (the memory device changes the v86 set, so
; the client's di/ax/bx/cx are saved in ncauregs and put back).
;
e310500:
	db	8bh,01000011b		; mov eax,[ebx+ncavdi]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavdi
	db	89h,01000011b		; mov [ebx+ncauregs+00],eax
	db	offset nca:ncauregs+00
	db	8bh,01000011b		; mov eax,[ebx+ncavax]
	db	offset nca:ncavax
	db	89h,01000011b		; mov [ebx+ncauregs+04],eax
	db	offset nca:ncauregs+04
	db	8bh,01000011b		; mov eax,[ebx+ncavbx]
	db	offset nca:ncavbx
	db	89h,01000011b		; mov [ebx+ncauregs+08],eax
	db	offset nca:ncauregs+08
	db	8bh,01000011b		; mov eax,[ebx+ncavcx]
	db	offset nca:ncavcx
	db	89h,01000011b		; mov [ebx+ncauregs+12],eax
	db	offset nca:ncauregs+12

; UPDATE 72: the largest block a 0501h could get, without allocating
; anything: min(the longest free run, free pages - reserve), never
; below 0 -- 0501h's own conditions (UPDATE 70). Was: valloc
; everything and vrelease, two v-86 round trips and two passes
; over all free memory.

	db	67h
	call	word ptr ss:[nlgptr]	; call dword: nlargest -> eax, ecx
	db	67h
	sub	cx,word ptr ss:[dpmirsv]	; sub ecx,dword: leave the reserve
	jns	e05rsva
	xor	cx,cx			; xor ecx,ecx
e05rsva:
	cmp	ax,cx			; cmp eax,ecx
	jbe	e05rsvb
	mov	ax,cx			; mov eax,ecx
e05rsvb:
	db	89h,01000011b		; mov [ebx+ncabufer],eax
	db	offset nca:ncabufer
; client buffer offset, zero-extended for a 16-bit client

	db	8bh,01111011b		; mov edi,[ebx+ncauregs+00]
	db	offset nca:ncauregs+00
	db	66h
	call	c32eax		; eax bit 22 = 32-bit client (UPDATE 62)
	db	0a9h			; test eax,00400000h (D bit)
	dd	00400000h
	jnz	e05is32
	db	0fh,0b7h,11111111b	; movzx edi,di
e05is32:
	db	8bh,01001011b		; mov ecx,[ebx+ncabufer] (pages)
	db	offset nca:ncabufer
	db	8bh,01000011b		; mov eax,[ebx+ncanes]
	db	offset nca:ncanes
	mov	es,ax			; the client's buffer selector
	cld
	mov	ax,cx			; mov eax,ecx
	shl	ax,12			; shl eax,12: bytes
	stosw				; stosd +00 largest block, bytes
	mov	ax,cx			; mov eax,ecx
	stosw				; stosd +04 max unlocked, pages
	stosw				; stosd +08 max locked, pages
	db	83h,11001000b,0ffh	; or eax,-1 (sign-extended imm8; MASM's
					;  0D FFFF would take a 32-bit imm here
					;  and swallow the next two stosd)
	stosw				; stosd +0C
	stosw				; stosd +10
	mov	ax,cx			; mov eax,ecx
	stosw				; stosd +14 free pages
	db	83h,11001000b,0ffh	; or eax,-1 (sign-extended imm8; MASM's
					;  0D FFFF would take a 32-bit imm here
					;  and swallow the next two stosd)
	stosw				; stosd +18
	stosw				; stosd +1C
	stosw				; stosd +20
	stosw				; stosd +24
	stosw				; stosd +28
	stosw				; stosd +2C

; put the client's registers back, CF clear

	db	8bh,01000011b		; mov eax,[ebx+ncauregs+00]
	db	offset nca:ncauregs+00
	db	89h,01000011b		; mov [ebx+ncavdi],eax
	db	offset nca:ncavdi
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+04]
	db	offset nca:ncauregs+04
	db	89h,01000011b		; mov [ebx+ncavax],eax
	db	offset nca:ncavax
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+08]
	db	offset nca:ncauregs+08
	db	89h,01000011b		; mov [ebx+ncavbx],eax
	db	offset nca:ncavbx
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+12]
	db	offset nca:ncauregs+12
	db	89h,01000011b		; mov [ebx+ncavcx],eax
	db	offset nca:ncavcx
	db	66h			; 16-bit data
	db	83h,01100011b		; and [ebx+ncavflag],0fffeh (CF clear)
	db	offset nca:ncavflag
	db	0feh
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;	int 31h 0501h/0502h/0503h - extended memory blocks
;--------------------------------------------------------------------
;
; Encoding helpers for this block, all [ebx+disp8] into the nca under
; the 32-bit cs (the same bytes the rest of the file writes by hand):
;
NLD	macro	fld			;; mov eax,[ebx+fld]
	db	8bh,01000011b
	db	offset nca:fld
	endm
NST	macro	fld			;; mov [ebx+fld],eax
	db	89h,01000011b
	db	offset nca:fld
	endm
NLDW	macro	fld			;; mov ax,[ebx+fld] (16-bit)
	db	66h,8bh,01000011b
	db	offset nca:fld
	endm
NSTW	macro	fld			;; mov [ebx+fld],ax (16-bit)
	db	66h,89h,01000011b
	db	offset nca:fld
	endm
NADD	macro	fld			;; add eax,[ebx+fld]
	db	03h,01000011b
	db	offset nca:fld
	endm
NSUB	macro	fld			;; sub eax,[ebx+fld]
	db	2bh,01000011b
	db	offset nca:fld
	endm
NCMP	macro	fld			;; cmp eax,[ebx+fld]
	db	3bh,01000011b
	db	offset nca:fld
	endm
EAXI	macro	op,lo,hi		;; op eax,imm32 (05 add, 25 and,
	db	op			;;  0D or, A9 test) -- MASM would
	dw	lo,hi			;;  emit imm16 and misalign
	endm
MEMDEV	macro	fn			;; memory device call via dovmint
	db	66h
	mov	dx,offset mmgrp:rhentry
	db	0c6h,01000011b
	db	offset nca:ncavax+1
	db	fn
	db	66h
	call	dovmint
	endm
;
; Handle = SI:DI: SI = pages, DI = starting bank. Linear address =
; (bank + 110h) * 4096, as einfun91 maps extended banks.
;
; Scratch (disp8 must stay below 80h, so ncabufer+0..0Fh only):
;	ncauregs+00/04/08  client ax/bx/cx (restored on failure)
;	ncauregs+0C        requested pages; bit 31 = 0503h grow
;	ncabufer+00        pages the probe obtained (largest block)
;	ncabufer+04        its starting bank, then the kept block's
;	ncabufer+08        0503h old block: start<<16 | pages
;	ncabufer+0C        requested pages, clean
;
; No ownership is tracked: a client could free banks it does not
; own, and blocks are NOT released at 4Ch (both open, UPDATE 41).
;
e31save:				; common entry: save ax/bx/cx
	NLD	ncavax
	NST	ncauregs+00
	NLD	ncavbx
	NST	ncauregs+04
	NLD	ncavcx
	NST	ncauregs+08
e31disp2:
	NLDW	ncavax
	db	66h
	cmp	ax,0501h
	jne	e31d2
	db	66h
	jmp	e310501
e31d2:
	db	66h
	cmp	ax,0502h
	jne	e31d3
	db	66h
	jmp	e310502
e31d3:
	db	66h
	jmp	e310503


;---- block table helpers (no dovmint: near subroutines are safe)
;
; dblktab: DBLKN entries of 8 bytes: +0 in use (1/0), +1 task id,
; +4 dword handle = start bank << 16 | pages (as SI:DI packs it).

e31tid:					; dl = caller's task id
	db	66h
	call	addrnca 		; esi -> tcb, ebx -> nca
	db	66h
	call	cidl			; dl = client id (UPDATE 67)
	db	66h
	ret
;
; cidl / cidh: dl (dh) = the client id of the task whose tcb esi points
; to: curcid[task id], 0 = no DPMI client. Keeps everything else.
; (UPDATE 67: per-client ownership -- every table that e31tid keyed by
; task id is keyed by client id now.)
;
cidl:
	push	ax			; push eax
	push	si			; push esi
	db	8ah,46h,tcbid		; mov al,[esi+tcbid]
	and	al,7fh
	db	0fh,0b6h,0f0h		; movzx esi,al
	db	67h
	mov	dl,ss:[si+curcid]
	pop	si
	pop	ax
	db	66h
	ret
cidh:
	push	ax			; push eax
	push	si			; push esi
	db	8ah,46h,tcbid		; mov al,[esi+tcbid]
	and	al,7fh
	db	0fh,0b6h,0f0h		; movzx esi,al
	db	67h
	mov	dh,ss:[si+curcid]
	pop	si
	pop	ax
	db	66h
	ret
;
; cidpop: the calling client exits (its 4Ch, einfun4c after its
; resources are released): its id is freed, the task's current client
; is its parent again and, if there is one, the task's nca the
; parent's -- DOS returns into the parent's pending exec and the host
; finds its context through tcbncadr. Preserves all registers.
; (UPDATE 67)
;
cidpop:
	push	ax			; push eax
	push	cx
	push	si
	push	di
	push	bx
	db	66h
	call	addrnca			; esi -> tcb, ebx -> nca
	db	8ah,46h,tcbid		; mov al,[esi+tcbid]
	and	al,7fh
	db	0fh,0b6h,0f8h		; movzx edi,al: task id
	db	67h
	mov	al,ss:[di+curcid]
	or	al,al
	jz	cidpx
	db	0fh,0b6h,0d8h		; movzx ebx,al: client id
	db	67h
	mov	byte ptr ss:[bx+cidtask],0
	db	67h
	mov	al,ss:[bx+parcid]
	db	67h
	mov	ss:[di+curcid],al
	or	al,al
	jz	cidpx			; no parent: the task leaves DPMI
	shl	bx,1			; shl ebx,1
	db	67h
	mov	ax,ss:[bx+savnca]	; mov eax,dword (low word used)
	db	66h,89h,46h,tcbncadr	; mov [esi+tcbncadr],ax: the parent's nca
cidpx:
	pop	bx
	pop	di
	pop	si
	pop	cx
	pop	ax
	db	66h
	ret
;
; cidtagsw: in nmswitch, after cleardti: if a DPMI session switch is
; pending for the task (cidstart), dh = 80h | its client id, so the
; session's initial selectors belong to the client -- a nested child's
; cleardti leaves them alone, the client's freeclsel frees them.
; dh = task id (as nmswitch loaded it). Preserves all but dh. (UPDATE 67)
;
cidtagsw:
	push	ax			; push eax
	push	si			; push esi
	mov	al,dh			; task id: dh, as nmswitch loaded it -- esi
					;  no longer points to the tcb after cleardti
	and	al,7fh
	db	0fh,0b6h,0f0h		; movzx esi,al
	db	67h
	mov	al,ss:[si+pendsw]
	or	al,al
	jz	ctsx
	db	67h
	mov	byte ptr ss:[si+pendsw],0
	or	al,80h
	mov	dh,al
ctsx:
	pop	si
	pop	ax
	db	66h
	ret

;
; c32edx: edx = 00400000h if the calling task's DPMI client is 32-bit,
; 0 if 16-bit -- from c32tab, recorded at the mode switch (e6f8e). A
; task with no DPMI session (c32tab 0) keeps the old rule: the D bit
; of the interrupted CS. Replaces 'lar edx,[ebx+ncancs]' before the
; callers' 'test edx,00400000h'. Preserves everything but edx.
; (UPDATE 62)
;
c32edc:					; UPDATE 75: c32edx with the id einative
	push	ax			;  cached -- only on a path from einative
	push	si			;  with no v-86 run in between (e0300s)
	push	bx
	db	67h
	mov	dl,ss:[entcid]
	jmp	short c32edj
c32edx:
	push	ax			; push eax
	push	si
	push	bx
	db	66h
	call	e31tid		; dl = task id (clobbers esi, ebx)
c32edj:
	xor	ax,ax			; xor eax,eax
	mov	al,dl
	and	al,7fh
	mov	si,ax			; mov esi,eax
	db	67h
	mov	al,byte ptr ss:[si+c32tab]
	pop	bx			; ebx -> nca again
	pop	si
	or	al,al
	jz	c32lar
	xor	dx,dx			; xor edx,edx
	cmp	al,2
	jne	c32x
	db	0bah			; mov edx,00400000h
	dw	0,0040h
c32x:
	pop	ax
	db	66h
	ret
c32lar:
	db	0fh,02h,01010011b	; lar edx,[ebx+ncancs]
	db	offset nca:ncancs
	pop	ax
	db	66h
	ret
;
; c32eax: the same in eax; preserves everything but eax (UPDATE 62)
;
c32eax:
	push	dx
	db	66h
	call	c32edx
	mov	ax,dx			; mov eax,edx
	pop	dx
	db	66h
	ret

;
; envr16: put this task's environment segment back into PSP:2Ch
; (e6f93 replaced it with a selector); DOS frees the environment
; through that word once the 4Ch is reflected. ds is flat (einative
; context). Preserves all registers but flags. (UPDATE 63)
;
envr16:
	push	ax			; push eax
	push	dx
	push	si
	push	di
	push	bx
	db	66h
	call	e31tid			; dl = task id (clobbers esi, ebx)
	pop	bx			; ebx -> nca again
	xor	ax,ax			; xor eax,eax
	mov	al,dl
	and	al,7fh
	shl	ax,2			; shl eax,2
	mov	si,ax			; mov esi,eax
	db	67h
	mov	ax,word ptr ss:[si+envtab]	; mov eax,dword: env<<16 | PSP
	db	0a9h			; test eax,0ffff0000h
	dw	0,0ffffh
	jz	envr16x
	xor	di,di			; xor edi,edi
	db	67h
	mov	word ptr ss:[si+envtab],di	; mov dword: entry used up
	db	0fh,0b7h,0f8h		; movzx edi,ax: PSP segment
	db	0c1h,0e7h,04h		; shl edi,4
	db	0c1h,0e8h,10h		; shr eax,16: environment segment
	db	66h,89h,47h,2ch		; mov [edi+2Ch],ax
envr16x:
	pop	di
	pop	si
	pop	dx
	pop	ax
	db	66h
	ret

e31new:					; si = a free entry, CF set if full
	xor	si,si
e31nlp:
	db	67h
	cmp	byte ptr ss:[si+dblktab],0
	je	e31nok
	add	si,8
	db	66h
	cmp	si,DBLKN*8
	jb	e31nlp
	stc
	db	66h
	ret
e31nok:
	clc
	db	66h
	ret

e31find:				; eax = handle; si = its entry for
	push	ax			;  this task, CF set if none (eax kept)
	db	66h
	call	e31tid
	pop	ax
	xor	si,si
e31flp:
	db	67h
	cmp	byte ptr ss:[si+dblktab],1
	jne	e31fnx
	db	67h
	cmp	byte ptr ss:[si+dblktab+1],dl
	jne	e31fnx
	db	67h
	cmp	ax,word ptr ss:[si+dblktab+4]	; cmp eax,dword
	je	e31fok
e31fnx:
	add	si,8
	db	66h
	cmp	si,DBLKN*8
	jb	e31flp
	stc
	db	66h
	ret
e31fok:
	clc
	db	66h
	ret

e31pages:				; eax = pages for size bx:cx, 0 = bad
	xor	ax,ax			; xor eax,eax
	NLDW	ncavbx
	shl	ax,16			; shl eax,16
	NLDW	ncavcx
	EAXI	05h,0fffh,0		; add eax,0fffh
	shr	ax,12			; shr eax,12
	EAXI	0a9h,0,0ffffh		; test eax,0ffff0000h
	jz	e31pgok
	xor	ax,ax			; > 65535 pages: refuse
e31pgok:
	db	66h
	ret

;---- 0501h allocate memory block

e310501:
	db	66h
	call	e31pages
	or	ax,ax			; or eax,eax
	jnz	e01ok
	db	66h
	jmp	e31fail
e01ok:
	NST	ncauregs+12		; mode bit clear: plain allocation

; common allocation: probe the largest block, keep the head

e31alc:
;
; UPDATE 70: no more "valloc everything". The old probe (cx = FFFFh)
; made nalloc walk all free memory and mark it, and the tail release
; walk it again: ~3,600 iterations per 0501h. The reserve (dpmirsv)
; is checked against the free page count instead -- parsize/4 pages,
; parmused in use -- and exactly the request is allocated (first
; fit; no contiguous block that large: given back, fail, as before).
; Meaning: the reserve now stays free IN TOTAL, not in one block.
;
	NLD	ncauregs+12
	EAXI	25h,0ffffh,0		; and eax,0ffffh: requested pages
	push	dx			; push edx
	db	67h
	add	ax,ss:[dpmirsv]		; add eax,dword ss:[dpmirsv]
	mov	dx,ax			; mov edx,eax: request + reserve
	db	67h
	mov	ax,word ptr ss:[parsize]	; mov eax,dword: page map bytes
	shr	ax,2			; shr eax,2: pages
	db	67h
	sub	ax,ss:[parmused]	; sub eax,dword: free pages
	cmp	ax,dx			; cmp eax,edx
	pop	dx
	jae	e31alr
	db	66h
	jmp	e31fail			; would cut into the reserve
e31alr:
	NLD	ncauregs+12
	NSTW	ncavcx			; exactly the request
	MEMDEV	01h			; valloc
	xor	ax,ax
	NLDW	ncavcx
	NST	ncabufer+00		; L = pages obtained
	xor	ax,ax
	NLDW	ncavbx
	NST	ncabufer+04		; start
	NLD	ncauregs+12
	EAXI	25h,0ffffh,0		; and eax,0ffffh: requested pages
	NST	ncabufer+12
					; UPDATE 70: reserve checked above
	NCMP	ncabufer+00		; request + reserve <= L ?
	jbe	e31fit
	NLD	ncabufer+00		; no: give back whatever was obtained
	or	ax,ax
	jz	e31nog
	NLD	ncabufer+04
	NSTW	ncavbx
	NLD	ncabufer+00
	NSTW	ncavcx
	MEMDEV	02h			; vrelease
e31nog:
	db	66h
	jmp	e31fail
e31fit:
	NLD	ncabufer+00		; release the tail beyond the request
	NSUB	ncabufer+12
	jz	e31ntail
	NSTW	ncavcx
	NLD	ncabufer+04
	NADD	ncabufer+12
	NSTW	ncavbx
	MEMDEV	02h
e31ntail:
	NLD	ncauregs+12		; 0503h grow?
	EAXI	0a9h,0,8000h		; test eax,80000000h
	jz	e31out

; 0503h grow: copy the old block's pages across, then free it

	mov	ax,ds			; es = ds = absolute zero, flat
	mov	es,ax
	NLD	ncabufer+08
	shr	ax,16			; shr eax,16: old start
	EAXI	05h,110h,0
	shl	ax,12
	mov	si,ax			; mov esi,eax
	NLD	ncabufer+04
	EAXI	05h,110h,0
	shl	ax,12
	mov	di,ax			; mov edi,eax
	NLD	ncabufer+08
	EAXI	25h,0ffffh,0		; old pages
	shl	ax,10			; dwords
	mov	cx,ax			; mov ecx,eax
	cld
	rep	movsw			; rep movsd
	NLD	ncabufer+08
	NSTW	ncavcx			; old pages
	shr	ax,16
	NSTW	ncavbx			; old start
	MEMDEV	02h

; results: bx:cx linear address, si:di handle, ax as it was, CF clear

e31out:
	NLD	ncauregs+00		; which function brought us here?
	EAXI	25h,0ffffh,0
	db	3dh			; cmp eax,0501h
	dw	0501h,0
	jne	e31o3

; 0501h: record the new block for this task. Table full: give the
; block back and fail rather than hand out untracked memory.

	db	66h
	call	e31tid
	db	66h
	call	e31new
	jnc	e31o1ok
	NLD	ncabufer+04
	NSTW	ncavbx
	NLD	ncabufer+12
	NSTW	ncavcx
	MEMDEV	02h
	db	66h
	jmp	e31fail
e31o1ok:
	db	67h
	mov	byte ptr ss:[si+dblktab],1
	db	67h
	mov	byte ptr ss:[si+dblktab+1],dl
	jmp	short e31o3n

; 0503h: the entry recorded for the old handle takes the new one

e31o3:
	NLD	ncabufer+08		; old handle
	db	66h
	call	e31find
	jc	e31outc 		; cannot happen: checked on entry
e31o3n:
	NLD	ncabufer+04
	shl	ax,16			; shl eax,16
	db	0bh,01000011b		; or eax,[ebx+ncabufer+12]
	db	offset nca:ncabufer+12
	db	67h
	mov	word ptr ss:[si+dblktab+4],ax	; mov dword, handle
e31outc:
	NLD	ncabufer+04
	EAXI	05h,110h,0
	shl	ax,12
	NSTW	ncavcx
	shr	ax,16
	NSTW	ncavbx
	NLD	ncabufer+12
	NSTW	ncavsi
	NLD	ncabufer+04
	NSTW	ncavdi
	NLD	ncauregs+00
	NST	ncavax
	db	66h,83h,01100011b	; and [ebx+ncavflag],0fffeh
	db	offset nca:ncavflag
	db	0feh
	db	66h
	jmp	einback

e31fail:				; registers back as they came, CF set
	NLD	ncauregs+00
	NST	ncavax
	NLD	ncauregs+04
	NST	ncavbx
	NLD	ncauregs+08
	NST	ncavcx
	db	80h,01001011b		; or [ebx+ncavflag],01h
	db	offset nca:ncavflag
	db	01h
	db	66h
	jmp	einback

;---- 0502h free memory block: si = pages, di = start bank

e310502:
	xor	ax,ax
	NLDW	ncavsi
	or	ax,ax
	jnz	e02ok
	db	66h
	jmp	e31fail
e02ok:
	xor	ax,ax
	NLDW	ncavdi
	shl	ax,16
	NLDW	ncavsi			; eax = handle
	db	66h
	call	e31find			; this task's block?
	jnc	e02own
	db	66h
	jmp	e31fail
e02own:
	db	67h
	mov	byte ptr ss:[si+dblktab],0
	NLDW	ncavsi
	NSTW	ncavcx
	NLDW	ncavdi
	NSTW	ncavbx
	MEMDEV	02h
	NLD	ncauregs+00
	NST	ncavax
	NLD	ncauregs+04
	NST	ncavbx
	NLD	ncauregs+08
	NST	ncavcx
	db	66h,83h,01100011b	; CF clear
	db	offset nca:ncavflag
	db	0feh
	db	66h
	jmp	einback

;---- 0503h resize memory block: bx:cx new size, si:di handle

e310503:
	db	66h
	call	e31pages
	or	ax,ax
	jnz	e03ok1
	db	66h
	jmp	e31fail
e03ok1:
	NST	ncauregs+12		; new pages
	xor	ax,ax
	NLDW	ncavdi
	shl	ax,16
	NLDW	ncavsi			; eax = start<<16 | pages
	NST	ncabufer+08
	db	66h
	call	e31find			; this task's block? (eax kept)
	jnc	e03own
	db	66h
	jmp	e31fail
e03own:
	EAXI	25h,0ffffh,0
	or	ax,ax
	jnz	e03ok2
	db	66h
	jmp	e31fail
e03ok2:
	NST	ncabufer+00		; old pages
	NLD	ncauregs+12
	NCMP	ncabufer+00
	ja	e03grow

; shrink (or same size): keep the start, release the tail in place

	NLD	ncabufer+00
	NSUB	ncauregs+12
	jz	e03same
	NSTW	ncavcx
	NLD	ncabufer+08
	shr	ax,16
	NADD	ncauregs+12
	NSTW	ncavbx
	MEMDEV	02h
e03same:
	NLD	ncabufer+08
	shr	ax,16
	NST	ncabufer+04		; start unchanged
	NLD	ncauregs+12
	NST	ncabufer+12
	db	66h
	jmp	e31out

e03grow:
	NLD	ncauregs+12
	EAXI	0dh,0,8000h		; or eax,80000000h: grow mode
	NST	ncauregs+12
	db	66h
	jmp	e31alc

	page
;--------------------------------------------------------------------
;	int 31h 0000h/0001h/0006h/0007h/0008h - descriptors
;--------------------------------------------------------------------
;
; There is no LDT: client descriptors are gdtspace slots, tagged
; 80h|taskid in dtitable like those 8eh/86h/48h make, so freeclsel
; releases them at the client's 4Ch. The tag also gives ownership:
; 0001h/0006h/0007h/0008h refuse any selector not tagged for the
; calling task, so a client cannot rewrite the host's or another
; task's descriptors.
;
; No dovmint here, so near subroutines (66h call / 66h ret) are safe.
; dh holds the caller's tag throughout.
;
e31desc:
	db	66h
	call	addrnca 		; esi -> tcb, ebx -> nca
	db	66h
	call	cidh			; dh = client id (UPDATE 67)
	or	dh,80h			; the client-descriptor tag
	xor	ax,ax			; xor eax,eax (UPDATE 72): NLDW loads 16 bits,
					;  the code after it uses all of eax
	NLDW	ncavax
	or	ax,ax
	jz	e3100
	db	66h
	cmp	ax,0003h
	jne	e31dn3
	db	66h
	jmp	e3103
e31dn3:
	db	66h
	cmp	ax,0001h
	jne	e31dn1
	db	66h
	jmp	e3101
e31dn1:
	db	66h
	cmp	ax,0006h
	jne	e31dn6
	db	66h
	jmp	e3106
e31dn6:
	db	66h
	cmp	ax,0007h
	jne	e31dn7
	db	66h
	jmp	e3107
e31dn7:
	db	66h
	cmp	ax,0008h
	jne	e31dm
	db	66h
	jmp	e3108
e31dm:
	db	66h
	cmp	ax,0002h
	jne	e31dm9
	db	66h
	jmp	e3102
e31dm9:
	db	66h
	cmp	ax,0009h
	jne	e31dmA
	db	66h
	jmp	e3109
e31dmA:
	db	66h
	cmp	ax,000Ah
	jne	e31dmB
	db	66h
	jmp	e310A
e31dmB:
	db	66h
	cmp	ax,000Bh
	jne	e31dmC
	db	66h
	jmp	e310B
e31dmC:
	db	66h
	cmp	ax,000Ch
	jne	e31dbad
	db	66h
	jmp	e310C
e31dbad:
	db	66h
	jmp	e31bad

;---- 0000h allocate CX descriptors: CONTIGUOUS gdtspace slots, each
;     data, present, dpl 3, base 0, limit 0. AX = the first selector,
;     the others follow at the 0003h increment (8).

e3100:
	xor	cx,cx			; xor ecx,ecx
	xor	ax,ax			; xor eax,eax (UPDATE 72): NLDW loads 16 bits,
					;  the code after it uses all of eax
	NLDW	ncavcx			; ax = count
	mov	cx,ax			; mov ecx,eax
	or	cx,cx
	jnz	e3100c1
	db	66h
	jmp	e31bad
e3100c1:
	db	66h
	cmp	cx,dtilen
	jbe	e3100c2
	db	66h
	jmp	e31bad
e3100c2:
	xor	si,si			; candidate first slot
e3100o:
	mov	ax,si			; mov eax,esi
	add	ax,cx			; add eax,ecx
	db	66h
	cmp	ax,dtilen		; run would pass the end?
	jbe	e3100o2
	db	66h
	jmp	e31bad
e3100o2:
	mov	di,si			; mov edi,esi
e3100i:
	db	67h
	cmp	ss:[di+dtitable],0ffh
	jne	e3100adv
	inc	di
	mov	ax,di			; mov eax,edi
	sub	ax,si			; sub eax,esi: run length so far
	cmp	ax,cx			; cmp eax,ecx
	jb	e3100i
	jmp	short e3100run		; slots si .. si+cx-1 are free
e3100adv:
	inc	si
	jmp	short e3100o

e3100run:
	mov	ax,si			; first selector, for the caller
	shl	ax,3
	db	66h
	add	ax,gdtspace-gdt
	or	al,3
	NSTW	ncavax
e3100set:
	db	67h
	mov	ss:[si+dtitable],dh	; claim it for this task
	mov	di,si			; mov edi,esi
	shl	di,3			; shl edi,3
	db	66h
	add	di,gdtspace-gdt
	db	66h,67h
	mov	word ptr ss:[di+gdt],0		; limit 0-15
	db	66h,67h
	mov	word ptr ss:[di+gdt+2],0	; base 0-15
	db	67h
	mov	byte ptr ss:[di+gdt+4],0	; base 16-23
	db	67h
	mov	byte ptr ss:[di+gdt+5],0f2h	; p=1,dpl=3,s=1,data r/w
	db	67h
	mov	byte ptr ss:[di+gdt+6],0	; g=0,d=0, limit 16-19 = 0
	db	67h
	mov	byte ptr ss:[di+gdt+7],0	; base 24-31
	inc	si
	loop	e3100set		; ecx under the 32-bit cs
	db	66h
	jmp	e31dok

;---- 0003h get selector increment value: AX = 8

e3103:
	db	66h,0c7h,01000011b	; mov word [ebx+ncavax],0008h
	db	offset nca:ncavax
	dw	0008h
	db	66h
	jmp	e31dok

;---- common: bx = one of this task's selectors?  di = its gdt offset
;     out: CF clear ok, CF set not a selector this task owns

e31sel:
	xor	ax,ax
	NLDW	ncavbx
	EAXI	25h,0fff8h,0		; and eax,0fff8h: drop rpl/ti
	db	66h
	cmp	ax,gdtspace-gdt
	jb	e31selx
	db	66h
	cmp	ax,gdtspace-gdt+8*dtilen
	jae	e31selx
	mov	di,ax			; mov edi,eax
	mov	si,ax			; mov esi,eax
	db	66h
	sub	si,gdtspace-gdt
	shr	si,3			; dtitable index
	db	67h
	cmp	ss:[si+dtitable],dh	; owned by this task?
	je	e31selok		; the client's own (80h|taskid)
	push	ax			; UPDATE 64: or one the kernel made for this
	push	si			;  task at the switch (taskid): the client's
	push	bx			;  initial cs/ds/ss. UPDATE 67: compare with
	db	66h			;  the TASK id -- dh holds the client id now
	call	addrnca			; esi -> tcb (ebx -> nca, as before)
	db	8ah,46h,tcbid		; mov al,[esi+tcbid]
	and	al,7fh
	pop	bx
	pop	si
	db	67h			;  to 4 GB (0008h); 0006h asks their bases.
	cmp	ss:[si+dtitable],al	;  They live for the session: cleardti runs
	pop	ax			;  only at the switch itself.
	jne	e31selx
e31selok:
	clc
	db	66h
	ret
e31selx:
	stc
	db	66h
	ret

;---- 0001h free descriptor

e3101:
	db	66h
	call	e31sel
	jnc	e31ok1
	db	66h
	jmp	e31bad
e31ok1:
	db	67h
	cmp	ss:[si+dtitable],dh	; UPDATE 64: never free a kernel-made
	je	e31ok1f			;  initial selector, only 80h|taskid
	db	66h
	jmp	e31bad
e31ok1f:
	db	67h
	mov	ss:[si+dtitable],0ffh
	db	66h
	jmp	e31dok

;---- 0006h get base: cx:dx

e3106:
	db	66h
	call	e31sel
	jnc	e31ok2
	db	66h
	jmp	e31bad
e31ok2:
	db	66h,67h
	mov	ax,ss:[di+gdt+2]	; base 0-15
	NSTW	ncavdx
	db	67h
	mov	al,byte ptr ss:[di+gdt+4]	; base 16-23
	db	67h
	mov	ah,byte ptr ss:[di+gdt+7]	; base 24-31
	NSTW	ncavcx
	db	66h
	jmp	e31dok

;---- 0007h set base from cx:dx

e3107:
	db	66h
	call	e31sel
	jnc	e31ok3
	db	66h
	jmp	e31bad
e31ok3:
	NLDW	ncavdx
	db	66h,67h
	mov	ss:[di+gdt+2],ax	; base 0-15
	NLDW	ncavcx
	db	67h
	mov	byte ptr ss:[di+gdt+4],al	; base 16-23
	db	67h
	mov	byte ptr ss:[di+gdt+7],ah	; base 24-31
	db	66h
	jmp	e31dok

;---- 0008h set limit from cx:dx. Above 1 MB the low 12 bits must be
;     all ones and the limit goes page-granular (G=1).

e3108:
	db	66h
	call	e31sel
	jnc	e31ok4
	db	66h
	jmp	e31bad
e31ok4:
	xor	ax,ax
	NLDW	ncavcx
	shl	ax,16
	NLDW	ncavdx			; eax = limit
	mov	dl,0			; G=0
	EAXI	0a9h,0,0fff0h		; test eax,0fff00000h
	jz	e3108set
	mov	cx,ax			; mov ecx,eax
	db	81h,0e1h		; and ecx,0fffh
	dw	0fffh,0
	db	81h,0f9h		; cmp ecx,0fffh
	dw	0fffh,0
	je	e31ok5
	db	66h
	jmp	e31bad
e31ok5:
	shr	ax,12			; shr eax,12
	mov	dl,80h			; G=1
e3108set:
	db	66h,67h
	mov	ss:[di+gdt],ax		; limit 0-15
	shr	ax,16			; al = limit 16-19
	and	al,0fh
	or	al,dl
	db	67h
	mov	ah,byte ptr ss:[di+gdt+6]
	and	ah,70h			; keep D/B, reserved, AVL
	or	al,ah
	db	67h
	mov	byte ptr ss:[di+gdt+6],al
e31dok:
	db	66h,83h,01100011b	; and [ebx+ncavflag],0fffeh: CF clear
	db	offset nca:ncavflag
	db	0feh
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;	int 31h 0100h - allocate DOS memory block
;--------------------------------------------------------------------
;
; bx = paragraphs. Reflects DOS 48h (as einfun48 does), then builds a
; selector for the block: base = segment * 16, limit = size - 1,
; byte-granular, data r/w, dpl 3, tagged 80h|taskid so freeclsel
; releases it at 4Ch; DOS reclaims the block itself at termination.
;
; out: CF clear: ax = real-mode segment, dx = selector
;      CF set:   ax = DOS error, bx = largest available (from DOS)
;
; DEVIATION: DPMI 0.9 gives a block over 64 KB several consecutive
; selectors, one per 64 KB. This gives ONE selector with the whole
; limit (up to 1 MB): fine for 32-bit clients, not for 16-bit ones
; needing more than 64 KB. 0101h/0102h are not implemented: DOS 49h
; from a native-mode task does not take effect (UPDATE 45).
;
e310100:
	NLD	ncavbx
	NST	ncauregs+00		; paragraphs, for the limit
	db	0c6h,01000011b		; mov [ebx+ncavax+1],48h
	db	offset nca:ncavax+1
	db	48h
	xor	dx,dx			; xor edx,edx
	mov	dl,21h			; vector for dovmint
	db	66h
	call	dovmint
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	db	offset nca:ncavflag
	db	01h
	jz	e0100ok
	db	66h			; DOS refused: ax = error, bx =
	jmp	einback 		;  largest, CF set -- as DPMI wants

e0100ok:
	db	66h
	call	e31tid			; dl = task id
	mov	dh,dl
	or	dh,80h			; the client-descriptor tag
	xor	si,si
e0100lp:
	db	67h
	cmp	ss:[si+dtitable],0ffh
	je	e0100got
	inc	si
	db	66h
	cmp	si,dtilen
	jb	e0100lp
	db	66h,0c7h,01000011b	; no descriptor: ax = 8, CF set
	db	offset nca:ncavax	;  (the DOS block goes back at exit)
	dw	8
	db	66h
	jmp	e31bad
e0100got:
	db	67h
	mov	ss:[si+dtitable],dh
	mov	di,si			; mov edi,esi
	shl	di,3
	db	66h
	add	di,gdtspace-gdt
	xor	ax,ax
	NLDW	ncavax			; segment
	shl	ax,4			; shl eax,4: linear base
	db	66h,67h
	mov	ss:[di+gdt+2],ax	; base 0-15
	shr	ax,16
	db	67h
	mov	byte ptr ss:[di+gdt+4],al	; base 16-23
	db	67h
	mov	byte ptr ss:[di+gdt+7],0	; base 24-31
	db	67h
	mov	byte ptr ss:[di+gdt+5],0f2h	; p=1,dpl=3,s=1,data r/w
	NLD	ncauregs+00
	EAXI	25h,0ffffh,0		; paragraphs
	shl	ax,4
	dec	ax			; dec eax: limit = size - 1
	db	66h,67h
	mov	ss:[di+gdt],ax		; limit 0-15
	shr	ax,16
	and	al,0fh			; limit 16-19, g=0, d=0
	db	67h
	mov	byte ptr ss:[di+gdt+6],al
	mov	ax,di
	or	al,3
	NSTW	ncavdx			; dx = selector; ax = segment already
	db	66h
	jmp	e31dok

	page
;--------------------------------------------------------------------
;		4a - modify allocated memory block
;--------------------------------------------------------------------
;
; As 49h, the client holds a SELECTOR in es where DOS wants a segment;
; it is converted the same way. Nothing else changes: makegdte gives
; every descriptor the same fixed limit and never records a block
; size, so a resized block keeps its descriptor as it is. bx (new size
; in, largest available out on failure) passes through untouched.
;
; A selector outside gdtspace is passed straight through.
;
einfun4a:
	db	66h			; 16-bit data
	db	8bh,01110011b		; mov si,[ebx+ncanes] (client's es)
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncanes
	db	66h
	and	si,0fff8h		; clear rpl bits 0-2
	db	66h
	cmp	si,gdtspace-gdt 	; below the user area?
	jb	e4apass
	db	66h
	cmp	si,gdtspace-gdt+8*dtilen
	jae	e4apass

; convert the descriptor base back to a real-mode segment

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	ax,ss:[si+gdt+2]	; base bits 0-15
	db	67h
	mov	dl,byte ptr ss:[si+gdt+4]  ; base bits 16-23
	db	66h
	shr	ax,4
	shl	dl,4
	or	ah,dl			; paragraph number
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncaves],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncaves
e4apass:

; MOS returns CF unchanged on success (see einfun49): enter clear

	db	66h			; 16-bit data
	db	83h,01100011b		; and [ebx+ncavflag],0fffeh
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	0feh			; immediate data, sign-extended
	xor	dx,dx			; dovmint takes the VECTOR in edx; the
	mov	dl,21h			;  conversion above used dl (UPDATE 48)
	db	66h
	call	dovmint 		; edx contains vector number
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;	int 31h 0101h/0102h - free / resize DOS memory block
;--------------------------------------------------------------------
;
; dx = selector from 0100h (must be this task's: e31sel). Its base is
; turned back into the real-mode segment for DOS 49h/4Ah.
; 0101h: on success the descriptor is freed too.
; 0102h: bx = new paragraphs; on success the descriptor's limit follows
;        the new size; on failure ax = DOS error, bx = largest possible.
; edx is set to 21h right before dovmint: it carries the VECTOR, and a
; clobbered dl is exactly what made 49h/4Ah no-ops (UPDATE 48).
;
e31dsel:				; common: dx must be one of our selectors
	NLD	ncavbx
	NST	ncauregs+04		; client bx
	NLDW	ncavdx
	NSTW	ncavbx			; e31sel checks ncavbx
	db	66h
	call	e31tid
	mov	dh,dl
	or	dh,80h
	db	66h
	call	e31sel			; di = gdt offset, CF = not ours
	pushf
	NLD	ncauregs+04
	NST	ncavbx			; client bx back
	popf
	jnc	e31ds1
	db	66h
	jmp	e31bad
e31ds1:
	mov	ax,di			; mov eax,edi
	NST	ncauregs+00		; kept across dovmint
	xor	ax,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+4]	; base 16-23
	shl	ax,16
	db	66h,67h
	mov	ax,ss:[di+gdt+2]	; base 0-15
	shr	ax,4			; segment
	NSTW	ncaves
	db	66h,83h,01100011b	; and [ebx+ncavflag],0fffeh: CF clear
	db	offset nca:ncavflag
	db	0feh
	NLD	ncauregs+08		; function 49h or 4Ah, set by caller
	db	88h,01100011b		; mov [ebx+ncavax+1],ah
	db	offset nca:ncavax+1
	xor	dx,dx
	mov	dl,21h			; the vector
	db	66h
	call	dovmint
	db	0f6h,01000011b		; test [ebx+ncavflag],01h
	db	offset nca:ncavflag
	db	01h
	jz	e31ds2
	db	66h			; DOS refused: ax/bx/CF as DOS left them
	jmp	einback
e31ds2:
	NLD	ncauregs+00
	mov	di,ax			; mov edi,eax: the descriptor again
	NLD	ncauregs+08
	cmp	ah,49h
	jne	e3102lim

; 0101h: DOS freed the block; free the descriptor

	mov	si,di
	db	66h
	sub	si,gdtspace-gdt
	shr	si,3
	db	67h
	mov	ss:[si+dtitable],0ffh
	db	66h
	jmp	e31dok

; 0102h: limit = new paragraphs * 16 - 1 (bits 16-19 into byte 6)

e3102lim:
	NLD	ncauregs+04		; new size, paragraphs (client bx)
	EAXI	25h,0ffffh,0
	shl	ax,4
	dec	ax			; dec eax
	db	66h,67h
	mov	ss:[di+gdt],ax		; limit 0-15
	shr	ax,16
	and	al,0fh
	db	67h
	mov	ah,byte ptr ss:[di+gdt+6]
	and	ah,0f0h 		; keep g/d/avl
	or	al,ah
	db	67h
	mov	byte ptr ss:[di+gdt+6],al
	NLD	ncauregs+04
	NST	ncavbx			; bx as the client gave it
	db	66h
	jmp	e31dok

e310101:
	mov	ah,49h
	NST	ncauregs+08
	db	66h
	jmp	e31dsel
e310102:
	mov	ah,4ah
	NST	ncauregs+08
	db	66h
	jmp	e31dsel

	page
;--------------------------------------------------------------------
;	int 31h 0200h/0201h - get/set real-mode interrupt vector
;--------------------------------------------------------------------
;
; bl = vector; cx:dx = segment:offset. The vector table is read and
; written at linear bl*4 through ds, the absolute-zero flat selector
; einative leaves loaded -- i.e. the CURRENT task's real-mode table.
; [esi] is hand-encoded (8B 06 / 89 06): MASM's [si] form (rm=100) is
; a SIB byte under the 32-bit cs.
;
e310200:
	NLD	ncavbx
	EAXI	25h,0ffh,0		; vector
	shl	ax,2			; shl eax,2
	mov	si,ax			; mov esi,eax
	db	8bh,06h 		; mov eax,[esi]
	NSTW	ncavdx			; offset
	shr	ax,16
	NSTW	ncavcx			; segment
	db	66h
	jmp	e31dok

e310201:
	NLD	ncavbx
	EAXI	25h,0ffh,0
	shl	ax,2
	mov	si,ax			; mov esi,eax
	xor	ax,ax
	NLDW	ncavcx
	shl	ax,16
	NLDW	ncavdx			; eax = segment:offset
	pushf				; pushfd: keep the caller's IF -- a bare sti
					;  here let IRQ 0 into the monitor at cpl 0
					;  and killed DJGPP's 0201h (UPDATE 63)
	cli				; no interrupt may see half a vector
	db	89h,06h 		; mov [esi],eax
	popf				; popfd
	db	66h
	jmp	e31dok

	page
;--------------------------------------------------------------------
;	int 31h 0204h/0205h - protected-mode interrupt vectors
;--------------------------------------------------------------------
;
; A client may hook vector N with 0205h. From then on, an int N it
; raises is DELIVERED to its handler (eindeliv, called from einative
; before the normal dispatch): an iret frame goes onto the client's
; own stack (16/32-bit by the D bit of its cs) and the return frame
; on p0stack is pointed at the handler, so the handler's iret goes
; straight back to the client, ring 3 to ring 3.
;
; 0204h returns the hook, or a DEFAULT handler: one 4-byte stub per
; vector (dpmistub: int 0E6h / N / iret) reached through two stub
; selectors (16- and 32-bit). The monitor accepts int 0E6h only from
; a stub selector, reads N, steps eip past it onto the iret, and
; re-enters the normal dispatch with vector N -- so chaining to the
; default behaves exactly like an unhooked int N (int 21h
; translations included) and cannot re-enter the client's hook.
;
; Scope: interrupts that reach einative. Exceptions (0202h/0203h) are
; not delivered. IF/TF are not cleared for the handler (a ring-3
; handler could not set IF back when IOPL < 3).
;
; phooktab: DPHKN entries of 12 bytes: +0 in use, +1 task id,
; +2 vector, +4 handler offset (dd), +8 handler selector (dw).

e31hclr:				; free every hook of task dl
	xor	si,si			;  (no dovmint: a subroutine is safe)
e31hclp:
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab],1
	jne	e31hcnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+1],dl
	jne	e31hcnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab],0
e31hcnx:
	add	si,12
	db	66h,67h
	cmp	si,ss:[hookhwm]		; UPDATE 69: not DPHKN*12
	jb	e31hclp
	xor	si,si			; and its real-mode callbacks
e31hcc:
	db	67h
	cmp	byte ptr ss:[si+dcbtab],1
	jne	e31hcn
	db	67h
	cmp	byte ptr ss:[si+dcbtab+1],dl
	jne	e31hcn
	db	67h
	mov	byte ptr ss:[si+dcbtab],0
e31hcn:
	db	66h
	add	si,DCBSZ
	db	66h
	cmp	si,DCBN*DCBSZ
	jb	e31hcc
	db	66h
	ret

e31hfind:				; cl = vector, ch = task: si = entry
	db	67h			; UPDATE 74: no table yet -- nothing
	cmp	byte ptr ss:[hookok],0	;  is hooked (do not read gs:0, the IVT)
	jne	e31hfg1
	stc
	db	66h
	ret
e31hfg1:
	push	ax			; push eax: UPDATE 74, the client's
	push	cx			;  "maybe hooked" bit at gs:[3000h +
	db	0fh,0b6h,0f5h		;  movzx esi,ch -- client * 32 +
	shl	si,5			;  shl esi,5     vector / 8]
	mov	al,cl
	shr	al,3
	db	0fh,0b6h,0c0h		; movzx eax,al
	add	si,ax			; add esi,eax
	and	cl,7
	mov	ah,1
	shl	ah,cl			; the vector's bit
	pop	cx
	db	67h,65h			; gs:, 16-bit addressing
	test	byte ptr [si+3000h],ah
	pop	ax
	jnz	e31hfsc			; maybe: scan
	stc				; never hooked by this client
	db	66h
	ret
e31hfsc:
	xor	si,si			;  CF set if not hooked
e31hflp:
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab],1
	jne	e31hfnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+1],ch
	jne	e31hfnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+2],cl
	jne	e31hfnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+3],0	; kind: interrupt
	jne	e31hfnx
	clc
	db	66h
	ret
e31hfnx:
	add	si,12
	db	66h,67h
	cmp	si,ss:[hookhwm]		; UPDATE 69: not DPHKN*12
	jb	e31hflp
	stc
	db	66h
	ret

e31hnew:				; si = free entry, CF set if full
	xor	si,si
e31hnlp:
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab],0
	je	e31hnok
	add	si,12
	db	66h
	cmp	si,DPHKN*12
	jb	e31hnlp
	stc
	db	66h
	ret
e31hnok:
	push	ax			; push eax: UPDATE 69, raise hookhwm
	mov	ax,si			; mov eax,esi
	db	83h,0c0h,0ch		; add eax,12
	db	66h,67h
	cmp	ax,ss:[hookhwm]
	jbe	e31hnk2
	db	66h,67h
	mov	ss:[hookhwm],ax
e31hnk2:
	pop	ax
	clc
	db	66h
	ret

e31stubs:				; make the two stub selectors once
	db	66h,67h
	cmp	word ptr ss:[stubsel16],0
	je	e31stb0
	clc
	db	66h
	ret
;
; UPDATE 71: the stubs no longer live in res16 (4.2 KB of every task's
; conventional memory). Two pages from the memory device, at linear
; (start + 110h) << 12 like any 0501h block -- global, never freed,
; owned by no client -- are filled here on first use. Layout as before:
;	+000h	256 x int 0E6h / N / iret
;	+400h	retf (0305h pm routine); +401h int 0E7h / nop
;	+404h	32 x int 0E8h / N / nop (default exception stubs)
;	+484h	int 0E9h / nop / nop; +488h int 0EAh / nop / nop
;	+48Ch	256 x int 0E6h / N / retf 2
;	+A8Ch	256 x int 0E6h / N / retf 4
;
e31stb0:
	db	67h
	call	word ptr ss:[stbptr]	; call dword: stbget, eax = linear
	jnc	e31stbm
	db	66h
	ret
e31stbm:
	db	67h
	mov	word ptr ss:[stublin],ax	; mov dword
	push	es
	push	di
	push	cx
	mov	di,ax			; mov edi,eax
	EAXI	0b8h,gdtzero-gdt,0	; mov eax,imm32: flat (no 16-bit immediates here)
	mov	es,ax
	cld
	xor	cx,cx			; xor ecx,ecx
e31sg1:
	mov	al,0cdh			; int 0E6h / N / iret
	stosb
	mov	al,0e6h
	stosb
	mov	al,cl
	stosb
	mov	al,0cfh
	stosb
	inc	cl
	jnz	e31sg1
	mov	al,0cbh			; +400h retf
	stosb
	mov	al,0cdh			; +401h int 0E7h / nop
	stosb
	mov	al,0e7h
	stosb
	mov	al,90h
	stosb
e31sg2:
	mov	al,0cdh			; +404h int 0E8h / N / nop
	stosb
	mov	al,0e8h
	stosb
	mov	al,cl
	stosb
	mov	al,90h
	stosb
	inc	cl
	cmp	cl,32
	jb	e31sg2
	mov	al,0cdh			; +484h int 0E9h / nop / nop
	stosb
	mov	al,0e9h
	stosb
	mov	al,90h
	stosb
	stosb
	mov	al,0cdh			; +488h int 0EAh / nop / nop
	stosb
	mov	al,0eah
	stosb
	mov	al,90h
	stosb
	stosb
	mov	ch,2			; +48Ch retf 2, then +A8Ch retf 4
e31sg3:
	xor	cl,cl
e31sg4:
	mov	al,0cdh			; int 0E6h / N / retf ch
	stosb
	mov	al,0e6h
	stosb
	mov	al,cl
	stosb
	mov	al,0cah
	stosb
	mov	al,ch
	stosb
	xor	al,al
	stosb
	inc	cl
	jnz	e31sg4
	add	ch,2
	cmp	ch,4
	jbe	e31sg3
	pop	cx
	pop	di
	pop	es
	mov	dl,0			; 16-bit first, then 32-bit (40h)
e31stb2:
	xor	si,si
e31stb3:
	db	67h
	cmp	ss:[si+dtitable],0ffh
	je	e31stb4
	inc	si
	db	66h
	cmp	si,dtilen
	jb	e31stb3
	stc
	db	66h
	ret
e31stb4:
	db	67h
	mov	ss:[si+dtitable],0feh	; permanent: never swept, never freed
	mov	di,si
	shl	di,3
	db	66h
	add	di,gdtspace-gdt
	db	66h,67h
	mov	word ptr ss:[di+gdt],108bh	; limit: stubs, retf, E7, E8s, E9, EA,
					;  retf-n stubs (UPDATE 64)
	push	ax
	db	67h
	mov	ax,word ptr ss:[stublin]		; mov eax,dword: base (UPDATE 71)
	db	66h,67h
	mov	ss:[di+gdt+2],ax
	shr	ax,16			; shr eax,16
	db	67h
	mov	byte ptr ss:[di+gdt+4],al
	db	67h
	mov	byte ptr ss:[di+gdt+7],ah
	pop	ax
	db	67h
	mov	byte ptr ss:[di+gdt+5],0fah	; p=1,dpl=3,s=1,code r/x
	db	67h
	mov	byte ptr ss:[di+gdt+6],dl	; d=0 or d=1
	mov	ax,di
	or	al,3
	or	dl,dl
	jnz	e31stb5
	db	66h,67h
	mov	ss:[stubsel16],ax
	mov	dl,40h
	jmp	short e31stb2
e31stb5:
	db	66h,67h
	mov	ss:[stubsel32],ax
	clc
	db	66h
	ret

e31vtask:				; cl = vector (from bl), ch = task id
	NLD	ncavbx
	mov	cl,al
	db	66h
	call	e31tid
	mov	ch,dl
	db	66h
	ret

;---- 0204h get protected-mode vector: cx:(e)dx

e310204:
	db	66h
	call	e31vtask
	db	66h
	call	e31hfind
	jc	e0204d
	db	66h,67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+8]
	NSTW	ncavcx
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+4]	; mov eax,dword
	NST	ncavdx
	db	66h
	jmp	e31dok
e0204d:					; not hooked: the default stub
	push	cx
	db	66h
	call	e31stubs
	pop	cx
	jnc	e0204s
	db	66h
	jmp	e31bad
e0204s:
	db	66h,67h
	mov	ax,ss:[stubsel16]
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jz	e0204t
	db	66h,67h
	mov	ax,ss:[stubsel32]
e0204t:
	NSTW	ncavcx
	xor	ax,ax
	mov	al,cl
;
; UPDATE 66: hardware IRQ vectors keep the iret stub (N*4). The retf-n
; stubs return the host's result flags -- right for int 21h/31h (cf),
; wrong for an IRQ: DOS/4GW chains its timer handler to the default,
; and the interrupted code resumed with the v-86 handler's flags. A
; `cmp` just before the tick lost its result (FDIAG: IRQ between
; `cmp al,[esp+1Ch]` and `je`, ZF=1 in, the je not taken after).
;
	cmp	cl,08h
	jb	e0204n
	cmp	cl,0fh
	jbe	e0204i
	cmp	cl,70h
	jb	e0204n
	cmp	cl,77h
	ja	e0204n
e0204i:
	shl	ax,2			; shl eax,2: N*4, the iret stub
	jmp	short e0204u
e0204n:
	db	0bah			; mov edx,6 -- UPDATE 64: retf-n stubs,
	dw	6,0
	mul	dx			;  6 bytes each (dx:ax; ax < 600h)
	EAXI	05h,48ch,0		; add eax,48Ch: 16-bit table
	push	ax
	db	66h
	call	c32edx
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	pop	ax
	jz	e0204u
	EAXI	05h,600h,0		; add eax,600h: 32-bit table at +A8Ch
e0204u:
	NST	ncavdx
	db	66h
	jmp	e31dok

;---- 0205h set protected-mode vector from cx:(e)dx

e310205:
	db	66h
	call	e31vtask
	NLDW	ncavcx			; the handler selector
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	jne	e0205j1		; UPDATE 74: e0205u is out of short range
	db	66h
	jmp	e0205u
e0205j1:
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	jne	e0205j2		; UPDATE 74: e0205u is out of short range
	db	66h
	jmp	e0205u
e0205j2:
	EAXI	25h,0fff8h,0		; must be a present dpl-3 code descriptor
	db	66h			;  inside the gdt
	cmp	ax,gdtlen
	jae	e0205x
	mov	di,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+5]
	and	al,0f8h
	cmp	al,0f8h
	jne	e0205x
	db	66h
	call	e31hfind
	jnc	e0205s
	db	66h
	call	e31hnew
	jnc	e0205s
e0205x:
	db	66h
	jmp	e31bad
e0205s:					; si = entry for (task, vector)
	push	si			; push esi: UPDATE 74, set the client's
	push	ax			;  bit for this vector (only ever set;
	push	cx			;  cidstart clears a client id's bits)
	db	0fh,0b6h,0f5h		; movzx esi,ch
	shl	si,5			; shl esi,5
	mov	al,cl
	shr	al,3
	db	0fh,0b6h,0c0h		; movzx eax,al
	add	si,ax			; add esi,eax
	and	cl,7
	mov	ah,1
	shl	ah,cl
	db	67h,65h
	or	byte ptr [si+3000h],ah
	pop	cx
	pop	ax
	pop	si
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab+3],0	; kind: interrupt
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab],1
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab+1],ch
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab+2],cl
	NLDW	ncavcx
	db	66h,67h
	db	65h			; gs: (UPDATE 73)
	mov	word ptr [si+phooktab+8],ax
	NLD	ncavdx			; offset; 16-bit client: dx only
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jnz	e0205o
	EAXI	25h,0ffffh,0
e0205o:
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	word ptr [si+phooktab+4],ax	; mov dword
	db	66h
	jmp	e31dok
e0205u:					; the default again: unhook
	db	66h
	call	e31hfind
	jc	e0205v
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab],0
e0205v:
	db	66h
	jmp	e31dok

;---- einative: stub re-entry and hook delivery. dl = vector,
;     ebx = nca. Falls back to eindisp with edx = the vector.

einvhook:
	cmp	dl,08h			; UPDATE 77: 08h-0E5h is a plain vector --
	jb	einvhk0			;  not a stub re-entry (E6h-EAh), not an
	cmp	dl,0e6h			;  exception einxcpt handles (0-7): the
	jae	einvhk0			;  chain below always ends at einvh1
	db	66h
	jmp	einvh1
einvhk0:
	cmp	dl,0e6h 		; default-stub re-entry?
	jne	einvh0
	NLDW	ncancs			; (was ss:[p0stack-16])
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	je	einvst
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	je	einvst
	db	66h
	jmp	eindisp 		; a plain int 0E6h: normal handling
einvst:
	NLD	ncanip			; (was ss:[p0stack-20])
	db	67h
	add	ax,word ptr ss:[stublin]		; add eax,dword: the stubs' linear (UPDATE 71)
	mov	si,ax			; mov esi,eax: linear, via flat ds
	xor	ax,ax			; xor eax,eax (UPDATE 71): the high word of
					;  the stubs' linear (now >= 10000h) must not
					;  ride along -- NLDW callers (e31desc) test eax
	db	8ah,06h 		; mov al,[esi]: N
	db	0ffh,01000011b		; inc dword [ebx+ncanip]: onto the iret
	db	offset nca:ncanip
	xor	dx,dx
	mov	dl,al
;
; UPDATE 66: the stub ends in retf 2 / retf 4 (UPDATE 64: so the host's
; cf reaches the caller), which skips the frame's flags -- the caller
; then got the CHAINING handler's IF. DOS/4GW's int 31h hook runs with
; IF=0: every int 31h of the application left it with interrupts off
; (W4TTEST: clock() hung). Take IF and TF from that frame (flags at
; [sp+4], 16-bit stub, or [esp+8], 32-bit) into ncavflag and ncanflag;
; the return merge (einback) and dovmcont carry them to the caller.
;
	push	dx			; push edx: N
	push	cx			; push ecx -- e31sslin and this code use
	push	si			;  ecx, esi, edi; eindisp must get them
	push	di			;  as they were
	push	ax			; push eax
	db	66h
	call	e31sslin		; eax = linear of the client's ss:(e)sp
	mov	si,ax			; mov esi,eax
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	db	8ah,46h,05h		; mov al,[esi+5]: 16-bit frame
	jne	einvsf
	db	8ah,46h,09h		; mov al,[esi+9]: 32-bit frame
einvsf:
	and	al,02h			; the frame's IF only
	db	80h,01100011b		; and byte [ebx+ncavflag+1],0fch
	db	offset nca:ncavflag+1
	db	0fdh
	db	08h,01000011b		; or [ebx+ncavflag+1],al
	db	offset nca:ncavflag+1
	db	80h,01100011b		; and byte [ebx+ncanflag+1],0fch
	db	offset nca:ncanflag+1
	db	0fdh
	db	08h,01000011b		; or [ebx+ncanflag+1],al
	db	offset nca:ncanflag+1
	pop	ax			; pop eax
	pop	di			; pop edi
	pop	si			; pop esi
	pop	cx			; pop ecx
	pop	dx
	db	66h
	jmp	eindisp 		; as if the client raised int N
einvh0:					; E7/E8 from an exception stub, else faults
	cmp	dl,0e9h			; callback return from stub 484h?
	jne	einvh0b
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	je	einvx9
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	jne	einvh0b
einvx9:
	db	67h,36h,0ffh,26h	; jmp dword ptr ss:[cbr_ptr] (use32 target)
	dw	offset mmgrp:cbr_ptr
einvh0b:
	cmp	dl,0eah			; raw switch to real mode from stub 488h?
	jne	einvh0c
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	je	einvxa
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	jne	einvh0c
einvxa:
	db	67h,36h,0ffh,26h	; jmp dword ptr ss:[raw_ptr] (use32 target)
	dw	offset mmgrp:raw_ptr
einvh0c:
	cmp	dl,0e7h
	je	einvx7
	cmp	dl,0e8h
	je	einvx8
	db	66h
	jmp	einxcpt
einvx7:
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	je	einvx7s
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	jne	einvh1
einvx7s:
	db	66h
	jmp	einxret
einvx8:
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	je	einvx8s
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	jne	einvh1
einvx8s:
	db	66h
	jmp	einxdef
einvh1:
	mov	cl,dl
	db	67h			; UPDATE 75: the id einative cached (was
	mov	dl,ss:[entcid]		;  call e31tid: addrnca + cidl again)
	mov	ch,dl
	db	66h
	call	e31hfind
	jnc	einvdl
	xor	dx,dx
	mov	dl,cl
	db	66h
	jmp	eindisp
einvdl:
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+4]	; mov eax: handler offset
	NST	ncabufer+00
	xor	ax,ax
	db	66h,67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+8]
	NST	ncabufer+04		; handler selector
	db	66h
	call	c32eax		; client type (UPDATE 62)
	db	0c1h,0e8h,10h		; shr eax,16: 40h = 32-bit
	NST	ncabufer+08		; nonzero: 32-bit client
	NLD	ncanss			; (was ss:[p0stack-4])
	EAXI	25h,0fff8h,0
	mov	di,ax
	xor	ax,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+7]
	shl	ax,8
	db	67h
	mov	al,byte ptr ss:[di+gdt+4]
	shl	ax,16
	db	66h,67h
	mov	ax,ss:[di+gdt+2]
	NST	ncabufer+12		; ss base
	NLD	ncabufer+08
	or	ax,ax
	jz	einvd16

					; 32-bit client: eip, cs, eflags
	NLD	ncansp			; (was ss:[p0stack-8]) esp
	db	83h,0e8h,0ch		; sub eax,12
	NST	ncansp			; (was ss:[p0stack-8])
	NADD	ncabufer+12
	mov	di,ax			; mov edi,eax: linear, flat ds
	NLD	ncanip			; (was ss:[p0stack-20])
	db	89h,07h 		; mov [edi],eax
	NLD	ncancs			; (was ss:[p0stack-16])
	db	89h,47h,04h		; mov [edi+4],eax
	NLD	ncanflag			; (was ss:[p0stack-12])
	db	89h,47h,08h		; mov [edi+8],eax
	jmp	short einvdgo

einvd16:				; 16-bit client: ip, cs, flags
	NLD	ncansp			; (was ss:[p0stack-8])
	db	83h,0e8h,06h		; sub eax,6
	EAXI	25h,0ffffh,0		; sp wraps within the segment
	NST	ncansp			; (was ss:[p0stack-8])
	NADD	ncabufer+12
	mov	di,ax
	NLD	ncanip			; (was ss:[p0stack-20])
	db	66h,89h,07h		; mov [edi],ax
	NLD	ncancs			; (was ss:[p0stack-16])
	db	66h,89h,47h,02h 	; mov [edi+2],ax
	NLD	ncanflag			; (was ss:[p0stack-12])
	db	66h,89h,47h,04h 	; mov [edi+4],ax

einvdgo:				; return into the handler
	NLD	ncabufer+00
	NST	ncanip			; (was ss:[p0stack-20])
	NLD	ncabufer+04
	NST	ncancs			; (was ss:[p0stack-16])
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;	int 31h 0300h - simulate real mode interrupt
;--------------------------------------------------------------------
;
; bl = vector, cx = stack words to copy, es:(e)di -> 50-byte real-mode
; call structure (DPMI 0.9): +00 EDI +04 ESI +08 EBP +0C reserved
; +10 EBX +14 EDX +18 ECX +1C EAX, words +20 FLAGS +22 ES +24 DS +26 FS
; +28 GS +2A IP +2C CS +2E SP +30 SS.
;
; The v-86 register set (ncav*) is loaded from the structure, the
; interrupt is reflected by dovmint exactly like any other, and the
; results are written back into the structure. The client's own
; protected-mode registers (ncairegs, 10 dwords) are parked in
; ncabufer meanwhile and put back, so only CF (clear) changes for it.
;
; LIMITS: CX (stack words) must be 0, else CF set; the structure's
; SS:SP is ignored -- dovmint always supplies the real-mode stack,
; which is what DPMI specifies when SS:SP is 0. FS/GS/IP/CS are not
; used by an interrupt and are left as they were.
;
;---- 0301h/0302h call real-mode far procedure (retf / iret frame):
;     0300h with the structure's CS:IP as target (see dovmfar)
e310301:
	xor	ax,ax			; xor eax,eax (UPDATE 72): NLDW loads 16 bits,
					;  the code after it uses all of eax
	NLDW	ncavcx
	or	ax,ax
	jz	e0301a
	db	66h
	jmp	e31bad
e0301a:
	db	83h,11001000b,0ffh	; or eax,-1: the far-call marker
	NST	ncauregs+04
	db	66h
	jmp	e0300s

e310300:
	xor	ax,ax			; xor eax,eax (UPDATE 72): NLDW loads 16 bits,
					;  the code after it uses all of eax
	NLDW	ncavcx
	or	ax,ax
	jz	e0300a
	db	66h
	jmp	e31bad
e0300a:
	NLD	ncavbx
	EAXI	25h,0ffh,0
	NST	ncauregs+04		; vector
e0300s:					; 0301h/0302h join here

; linear address of the structure: es base + (e)di

	NLD	ncanes
	EAXI	25h,0fff8h,0
	mov	di,ax			; mov edi,eax
	xor	ax,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+7]
	shl	ax,8
	db	67h
	mov	al,byte ptr ss:[di+gdt+4]
	shl	ax,16
	db	66h,67h
	mov	ax,ss:[di+gdt+2]
	mov	cx,ax			; mov ecx,eax: es base
	NLD	ncavdi
	db	66h
	call	c32edc		; edx bit 22 = 32-bit client (UPDATE 62, 75)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jnz	e0300b
	EAXI	25h,0ffffh,0		; 16-bit client: di
e0300b:
	add	ax,cx			; add eax,ecx
	NST	ncauregs+00		; structure, linear

; park the client's protected-mode registers in ncabufer

	mov	ax,ds			; es = ds = absolute zero, flat
	mov	es,ax
	mov	si,bx			; mov esi,ebx: ncairegs is at nca+0
	mov	di,bx
	db	83h,11000111b		; add edi,offset nca:ncabufer
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,10
	cld
	rep	movsw			; rep movsd: 10 dwords

; real-mode registers from the structure

	NLD	ncauregs+00
	mov	si,ax			; mov esi,eax
	NLD	ncauregs+04		; far call? its target from the structure
	EAXI	3dh,0ffffh,0ffffh	; cmp eax,-1
	jne	e0300t
	xor	ax,ax
	db	66h,8bh,46h,2ch 	; mov ax,[esi+2Ch]: CS
	shl	ax,16
	db	66h,8bh,46h,2ah 	; mov ax,[esi+2Ah]: IP
	NST	ncauregs+08
e0300t:
	db	8bh,46h,00h		; mov eax,[esi+00]
	NST	ncavdi
	db	8bh,46h,04h
	NST	ncavsi
	db	8bh,46h,08h
	NST	ncavbp
	db	8bh,46h,10h
	NST	ncavbx
	db	8bh,46h,14h
	NST	ncavdx
	db	8bh,46h,18h
	NST	ncavcx
	db	8bh,46h,1ch
	NST	ncavax
	xor	ax,ax
	db	66h,8bh,46h,20h 	; mov ax,[esi+20h]: flags
	NST	ncavflag
	xor	ax,ax
	db	66h,8bh,46h,22h 	; es
	NST	ncaves
	xor	ax,ax
	db	66h,8bh,46h,24h 	; ds
	NST	ncavds

; reflect: dovmint takes the VECTOR in edx (UPDATE 46/48)

	NLD	ncauregs+04
	EAXI	3dh,0ffffh,0ffffh	; cmp eax,-1: 0301h/0302h?
	jne	e0300v
	db	66h
	call	dovmfar			; far call to the structure's CS:IP
	jmp	short e0300r
e0300v:
	mov	dx,ax			; mov edx,eax
	db	66h
	call	dovmint
e0300r:

; results back into the structure

	NLD	ncauregs+00
	mov	si,ax
	NLD	ncavdi
	db	89h,46h,00h		; mov [esi+00],eax
	NLD	ncavsi
	db	89h,46h,04h
	NLD	ncavbp
	db	89h,46h,08h
	NLD	ncavbx
	db	89h,46h,10h
	NLD	ncavdx
	db	89h,46h,14h
	NLD	ncavcx
	db	89h,46h,18h
	NLD	ncavax
	db	89h,46h,1ch
	NLD	ncavflag
	db	66h,89h,46h,20h 	; mov [esi+20h],ax
	NLD	ncaves
	db	66h,89h,46h,22h
	NLD	ncavds
	db	66h,89h,46h,24h

; the client's own registers back, CF clear

	mov	ax,ds
	mov	es,ax
	mov	di,bx			; mov edi,ebx: ncairegs
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncabufer
	db	offset nca:ncabufer
	xor	cx,cx
	mov	cl,10
	cld
	rep	movsw			; rep movsd
	db	66h,83h,01100011b	; and [ebx+ncavflag],0fffeh
	db	offset nca:ncavflag
	db	0feh
	db	66h
	jmp	einback

	page
;--------------------------------------------------------------------
;	int 31h 0002h/0009h/000Ah/000Bh/000Ch, 0600h-0604h,
;	0702h/0703h, 0900h-0902h (UPDATE 53)
;--------------------------------------------------------------------

e31base:				; di = gdt offset -> eax = base
	xor	ax,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+7]
	shl	ax,8
	db	67h
	mov	al,byte ptr ss:[di+gdt+4]
	shl	ax,16
	db	66h,67h
	mov	ax,ss:[di+gdt+2]
	db	66h
	ret

e31free1:				; si = free slot claimed for tag dh,
	xor	si,si			;  di = its gdt offset; CF if none
e31f1lp:
	db	67h
	cmp	ss:[si+dtitable],0ffh
	je	e31f1ok
	inc	si
	db	66h
	cmp	si,dtilen
	jb	e31f1lp
	stc
	db	66h
	ret
e31f1ok:
	db	67h
	mov	ss:[si+dtitable],dh
	mov	di,si
	shl	di,3
	db	66h
	add	di,gdtspace-gdt
	clc
	db	66h
	ret

e31ptr:					; ncauregs+00 = linear es:(e)di
	push	di			;  of the caller (edi preserved)
	NLD	ncanes
	EAXI	25h,0fff8h,0
	mov	di,ax
	db	66h
	call	e31base
	mov	cx,ax			; mov ecx,eax
	NLD	ncavdi
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jnz	e31pt32
	EAXI	25h,0ffffh,0
e31pt32:
	add	ax,cx			; add eax,ecx
	NST	ncauregs+00
	pop	di
	db	66h
	ret

;---- 0002h segment to descriptor: bx = segment -> ax = selector.
;     Reuses this task's existing data descriptor for the same base
;     and a 64 KB limit, as DPMI asks; otherwise claims a new one.

e3102:
	NLD	ncavbx
	EAXI	25h,0ffffh,0
	shl	ax,4			; base
	NST	ncauregs+04
	xor	si,si
e3102lp:
	db	67h
	cmp	ss:[si+dtitable],dh	; one of ours?
	jne	e3102nx
	mov	di,si
	shl	di,3
	db	66h
	add	di,gdtspace-gdt
	db	67h
	cmp	byte ptr ss:[di+gdt+5],0f2h	; data r/w dpl 3
	jne	e3102nx
	db	66h,67h
	cmp	word ptr ss:[di+gdt],0ffffh	; 64 KB
	jne	e3102nx
	db	67h
	test	byte ptr ss:[di+gdt+6],8fh	; byte-granular, <= 1 MB
	jnz	e3102nx
	push	si
	db	66h
	call	e31base
	pop	si
	NCMP	ncauregs+04
	je	e3102hit
e3102nx:
	inc	si
	db	66h
	cmp	si,dtilen
	jb	e3102lp
	db	66h
	call	e31free1
	jnc	e3102new
	db	66h
	jmp	e31bad
e3102new:
	NLD	ncauregs+04
	db	66h,67h
	mov	ss:[di+gdt+2],ax	; base 0-15
	shr	ax,16
	db	67h
	mov	byte ptr ss:[di+gdt+4],al
	db	67h
	mov	byte ptr ss:[di+gdt+7],0
	db	66h,67h
	mov	word ptr ss:[di+gdt],0ffffh
	db	67h
	mov	byte ptr ss:[di+gdt+5],0f2h
	db	67h
	mov	byte ptr ss:[di+gdt+6],0
e3102hit:
	mov	ax,di
	or	al,3
	NSTW	ncavax
	db	66h
	jmp	e31dok

;---- 0009h set access rights: bx = selector, cl = access byte,
;     ch = G/D/AVL (bits 7/6/4). DPL must stay 3 and S = 1.

e3109:
	db	66h
	call	e31sel
	jnc	e3109a
	db	66h
	jmp	e31bad
e3109a:
	NLDW	ncavcx
	mov	cl,al
	and	cl,70h
	cmp	cl,70h			; dpl 3, system bit set
	je	e3109b
	db	66h
	jmp	e31bad
e3109b:
	db	67h
	mov	byte ptr ss:[di+gdt+5],al
	and	ah,0d0h 		; G, D, AVL
	db	67h
	mov	al,byte ptr ss:[di+gdt+6]
	and	al,0fh			; limit 16-19 kept
	or	al,ah
	db	67h
	mov	byte ptr ss:[di+gdt+6],al
	db	66h
	jmp	e31dok

;---- 000Ah create alias descriptor: bx = selector -> ax = data
;     selector with the same base and limit

e310A:
	db	66h
	call	e31sel
	jnc	e310Aa
	db	66h
	jmp	e31bad
e310Aa:
	push	di			; source
	db	66h
	call	e31free1
	pop	si			; si = source gdt offset
	jnc	e310Ab
	db	66h
	jmp	e31bad
e310Ab:
	db	67h
	mov	ax,word ptr ss:[si+gdt]		; mov eax: limit 0-15, base 0-15
	db	67h
	mov	word ptr ss:[di+gdt],ax		; mov dword
	db	67h
	mov	ax,word ptr ss:[si+gdt+4]	; mov eax: base, access, g/lim, base
	db	67h
	mov	word ptr ss:[di+gdt+4],ax	; mov dword
	db	67h
	mov	byte ptr ss:[di+gdt+5],0f2h	; data r/w dpl 3
	mov	ax,di
	or	al,3
	NSTW	ncavax
	db	66h
	jmp	e31dok

;---- 000Bh get descriptor / 000Ch set descriptor: bx = selector,
;     es:(e)di = 8 bytes. 000Ch keeps DPL 3 and S = 1.

e310B:
	db	66h
	call	e31sel
	jnc	e310Ba
	db	66h
	jmp	e31bad
e310Ba:
	db	66h
	call	e31ptr
	NLD	ncauregs+00
	mov	si,ax			; mov esi,eax
	db	67h
	mov	ax,word ptr ss:[di+gdt]		; mov eax
	db	89h,06h 		; mov [esi],eax
	db	67h
	mov	ax,word ptr ss:[di+gdt+4]	; mov eax
	db	89h,46h,04h		; mov [esi+4],eax
	db	66h
	jmp	e31dok

e310C:
	db	66h
	call	e31sel
	jnc	e310Ca
	db	66h
	jmp	e31bad
e310Ca:
	db	66h
	call	e31ptr
	NLD	ncauregs+00
	mov	si,ax
	db	8bh,46h,04h		; mov eax,[esi+4]
	mov	cl,ah			; access byte
	and	cl,70h
	cmp	cl,70h
	je	e310Cb
	db	66h
	jmp	e31bad
e310Cb:
	db	67h
	mov	word ptr ss:[di+gdt+4],ax	; mov dword
	db	8bh,06h 		; mov eax,[esi]
	db	67h
	mov	word ptr ss:[di+gdt],ax		; mov dword
	db	66h
	jmp	e31dok

;---- 0600h-0603h, 0702h/0703h: nothing pages to disk here -- succeed

e31nop:
	db	66h
	jmp	e31dok

;---- 0604h get page size: bx:cx = 0000:1000h

e310604:
	db	66h,0c7h,01000011b	; mov word [ebx+ncavbx],0
	db	offset nca:ncavbx
	dw	0
	db	66h,0c7h,01000011b	; mov word [ebx+ncavcx],1000h
	db	offset nca:ncavcx
	dw	1000h
	db	66h
	jmp	e31dok

;---- 0900h/0901h/0902h virtual interrupt state. The client's IF
;     lives in ncavflag, which einback folds into its returned flags.
;     al = the state BEFORE the call (1 = enabled).

e3190x:
	mov	cx,ax			; function, low byte 00/01/02
	NLD	ncavflag
	mov	dl,ah
	shr	dl,1
	and	dl,1			; old IF
	cmp	cl,0
	jne	e3190y
	and	ah,0fdh 		; 0900h: disable
e3190y:
	cmp	cl,1
	jne	e3190z
	or	ah,02h			; 0901h: enable
e3190z:
	NST	ncavflag
	db	88h,01010011b		; mov [ebx+ncavax],dl: al = old state
	db	offset nca:ncavax
	db	66h
	jmp	e31dok

	page
;--------------------------------------------------------------------
;	int 31h 0305h - get state save/restore addresses
;--------------------------------------------------------------------
;
; This host keeps no per-switch state a client must save, so the size
; is 0 and both routines are a bare far return, as DPMI allows:
;	BX:CX   real mode: mysegadr:rhe1, the memory-device dispatcher's
;	        own retf in this driver's real-mode code
;	SI:(E)DI protected mode: the retf byte after the 256 stubs
;	        (dpmistub+400h), through the stub selector matching the
;	        client's bitness
;
e310305:
	db	66h
	call	e31stubs
	jnc	e0305a
	db	66h
	jmp	e31bad
e0305a:
	db	66h,0c7h,01000011b	; mov word [ebx+ncavax],0: size
	db	offset nca:ncavax
	dw	0
	db	66h,67h
	mov	ax,ss:[mysegadr]
	NSTW	ncavbx
	db	66h,0c7h,01000011b	; mov word [ebx+ncavcx],offset rhe1
	db	offset nca:ncavcx
	dw	offset mmgrp:rhe1
	db	66h,67h
	mov	ax,ss:[stubsel16]
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jz	e0305b
	db	66h,67h
	mov	ax,ss:[stubsel32]
e0305b:
	NSTW	ncavsi
	db	0c7h,01000011b		; mov dword [ebx+ncavdi],400h
	db	offset nca:ncavdi
	dw	400h,0
	db	66h
	jmp	e31dok

	page
;--------------------------------------------------------------------
;	int 31h 0202h/0203h - protected-mode exception handlers
;--------------------------------------------------------------------
;
; Client faults that reach einative: vectors 0, 1, 3-7 directly, and
; #GP, which entint0d/dobad turns into int 6 with parm6ec = 2 (the
; error code is gone by then: delivered as exception 0Dh, error 0).
; 8-0Fh arriving here are IRQs (the monitor splits them off earlier
; by error-code position), so they are never exceptions.
;
; A 0203h hook (phooktab kind byte +3 = 1) gets the DPMI exception
; frame on the CLIENT's own stack (DPMI wants a host-locked stack;
; this differs only for stack faults): return address = stub:401h
; (int 0E7h), error code, then ip/cs/flags/sp/ss -- words for a
; 16-bit client, dwords for 32-bit. The handler's retf lands on the
; E7 stub; the monitor resumes the client from the (possibly changed)
; frame. The DEFAULT handler (0202h, unhooked) is stub 404h + N*4
; (int 0E8h / N): it restores the client from the frame and handles
; the fault exactly as without DPMI -- MOS reports and terminates.
;
; Client stack linear address: ncanss base + ncansp.
;
; UPDATE 85: for a 32-bit client the frame sits 128 bytes BELOW the
; fault esp, not right under it. DJGPP's handler copies its 64-byte
; exception state to fault esp - 92 (a host-locked stack in every
; other host); right under the fault esp that copy overwrote the
; frame's return eip, the handler's retf went astray, and a DJGPP
; program never saw SIGFPE/SIGSEGV (MOS's "Divide by zero error").

e31sslin:				; eax = linear of client ss:(e)sp
	NLD	ncanss
	EAXI	25h,0fff8h,0
	mov	di,ax
	db	66h
	call	e31base
	mov	cx,ax			; mov ecx,eax: ss base
	NLD	ncansp
	add	ax,cx			; add eax,ecx
	db	66h
	ret

e31xfind:				; as e31hfind, kind 1 (exception)
	db	67h			; UPDATE 74: no table yet, no handler
	cmp	byte ptr ss:[hookok],0
	jne	e31xfg1
	stc
	db	66h
	ret
e31xfg1:
	push	ax			; push eax: UPDATE 85, the client's
	push	cx			;  "maybe hooked" exception bit at
	db	0fh,0b6h,0f5h		;  gs:[4400h + client * 4 + exc / 8]
	shl	si,2			;  shl esi,2 (movzx esi,ch above)
	mov	al,cl
	shr	al,3
	db	0fh,0b6h,0c0h		; movzx eax,al
	add	si,ax			; add esi,eax
	and	cl,7
	mov	ah,1
	shl	ah,cl			; the exception's bit
	pop	cx
	db	67h,65h			; gs:, 16-bit addressing
	test	byte ptr [si+4400h],ah
	pop	ax
	jnz	e31xfsc			; maybe: scan
	stc				; never hooked by this client
	db	66h
	ret
e31xfsc:
	xor	si,si
e31xflp:
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab],1
	jne	e31xfnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+1],ch
	jne	e31xfnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+2],cl
	jne	e31xfnx
	db	67h
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [si+phooktab+3],1
	jne	e31xfnx
	clc
	db	66h
	ret
e31xfnx:
	add	si,12
	db	66h,67h
	cmp	si,ss:[hookhwm]		; UPDATE 69: not DPHKN*12
	jb	e31xflp
	stc
	db	66h
	ret

;---- 0202h get exception handler: bl = 0..1Fh -> cx:(e)dx

e310202:
	db	66h
	call	e31vtask		; cl = exception, ch = task
	cmp	cl,20h
	jb	e0202a
	db	66h
	jmp	e31bad
e0202a:
	db	66h
	call	e31xfind
	jc	e0202d
	db	66h,67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+8]
	NSTW	ncavcx
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+4]	; mov eax
	NST	ncavdx
	db	66h
	jmp	e31dok
e0202d:
	push	cx
	db	66h
	call	e31stubs
	pop	cx
	jnc	e0202s
	db	66h
	jmp	e31bad
e0202s:
	db	66h,67h
	mov	ax,ss:[stubsel16]
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jz	e0202t
	db	66h,67h
	mov	ax,ss:[stubsel32]
e0202t:
	NSTW	ncavcx
	xor	ax,ax
	mov	al,cl
	shl	ax,2
	db	05h			; add eax,404h
	dw	404h,0
	NST	ncavdx
	db	66h
	jmp	e31dok

;---- 0203h set exception handler from cx:(e)dx

e310203:
	db	66h
	call	e31vtask
	cmp	cl,20h
	jb	e0203a
	db	66h
	jmp	e31bad
e0203ut:				; UPDATE 85: e0203u out of short range
	db	66h
	jmp	e0203u
e0203a:
	NLDW	ncavcx
	db	66h,67h
	cmp	ax,ss:[stubsel16]
	je	e0203ut
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	je	e0203ut
	EAXI	25h,0fff8h,0
	db	66h
	cmp	ax,gdtlen
	jae	e0203x
	mov	di,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+5]
	and	al,0f8h
	cmp	al,0f8h 		; present dpl-3 code
	jne	e0203x
	db	66h
	call	e31xfind
	jnc	e0203s
	db	66h
	call	e31hnew
	jnc	e0203s
e0203x:
	db	66h
	jmp	e31bad
e0203s:
	push	si			; push esi: UPDATE 85, set the client's
	push	ax			;  bit for this exception (only ever
	push	cx			;  set; cidstart clears an id's bits)
	db	0fh,0b6h,0f5h		; movzx esi,ch
	shl	si,2			; shl esi,2
	mov	al,cl
	shr	al,3
	db	0fh,0b6h,0c0h		; movzx eax,al
	add	si,ax			; add esi,eax
	and	cl,7
	mov	ah,1
	shl	ah,cl
	db	67h,65h
	or	byte ptr [si+4400h],ah
	pop	cx
	pop	ax
	pop	si
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab],1
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab+1],ch
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab+2],cl
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab+3],1	; kind: exception
	NLDW	ncavcx
	db	66h,67h
	db	65h			; gs: (UPDATE 73)
	mov	word ptr [si+phooktab+8],ax
	NLD	ncavdx
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h
	dw	0,0040h
	jnz	e0203o
	EAXI	25h,0ffffh,0
e0203o:
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	word ptr [si+phooktab+4],ax	; mov dword
	db	66h
	jmp	e31dok
e0203u:
	db	66h
	call	e31xfind
	jc	e0203v
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [si+phooktab],0
e0203v:
	db	66h
	jmp	e31dok

;---- einative side. einxcpt: dl = vector, from einvhook's interrupt
;     path; delivers an exception if one is hooked, else falls back.

einxcpt:
	cmp	dl,06h			; int 6: #UD, or a #GP turned into int 6?
	jne	einx1
	mov	cl,06h
	db	66h,67h
	cmp	ss:[parm6ec],2		; word compare: 66h 67h
	jne	einx2
	mov	cl,0dh			; #GP, delivered as exception 0Dh
	jmp	short einx2
einx1:					; 0, 1, 3-7 only -- NOT 0Dh: a dl of 0Dh
	cmp	dl,02h			;  here is IRQ5 (jentirq2)
	je	einxno
	cmp	dl,07h
	ja	einxno
	mov	cl,dl
einx2:
	push	cx
	push	dx
	db	66h
	call	e31tid
	mov	ch,dl
	pop	dx
	pop	ax
	mov	cl,al
	db	66h
	call	e31xfind
	jnc	einxdl
einxno:
	db	66h
	jmp	einvh1			; the normal interrupt-hook path

einxdl:					; si = hook entry
	db	67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+4]	; mov eax: handler offset
	NST	ncabufer+00
	xor	ax,ax
	db	66h,67h
	db	65h			; gs: (UPDATE 73)
	mov	ax,word ptr [si+phooktab+8]
	NST	ncabufer+04		; handler selector
	db	66h
	call	e31stubs		; the E7 return stub must exist
	db	66h
	call	c32eax		; client type (UPDATE 62)
	db	0c1h,0e8h,10h		; shr eax,16: 40h = 32-bit
	NST	ncabufer+08
	db	66h
	call	e31sslin
	NST	ncabufer+12		; old stack, linear
	NLD	ncabufer+08
	or	ax,ax
	jz	einxd16

	NLD	ncansp			; 32-bit: 8 dwords
	db	2dh			; sub eax,0A0h: UPDATE 85, the frame 128
	dw	0a0h,0			;  bytes below the fault esp (see einxdl)
	NST	ncansp
	NLD	ncabufer+12
	db	2dh			; sub eax,0A0h
	dw	0a0h,0
	mov	di,ax			; mov edi,eax
	db	0b8h			; mov eax,401h
	dw	401h,0
	db	89h,07h 		; [edi+00] return eip
	db	66h,67h
	mov	ax,ss:[stubsel32]
	db	89h,47h,04h		; [edi+04] return cs
	xor	ax,ax
	db	89h,47h,08h		; [edi+08] error code 0
	NLD	ncanip
	db	89h,47h,0ch
	NLD	ncancs
	db	89h,47h,10h
	NLD	ncanflag
	db	89h,47h,14h
	NLD	ncansp
	db	05h			; add eax,0A0h: sp at the fault
	dw	0a0h,0
	db	89h,47h,18h
	NLD	ncanss
	db	89h,47h,1ch
	jmp	short einxdgo

einxd16:				; 16-bit: 8 words
	NLD	ncansp
	db	83h,0e8h,10h		; sub eax,16
	EAXI	25h,0ffffh,0
	NST	ncansp
	NLD	ncabufer+12
	db	83h,0e8h,10h
	mov	di,ax
	db	66h,0c7h,07h		; mov word [edi],401h
	dw	401h
	db	66h,67h
	mov	ax,ss:[stubsel16]
	db	66h,89h,47h,02h
	xor	ax,ax
	db	66h,89h,47h,04h 	; error code 0
	NLD	ncanip
	db	66h,89h,47h,06h
	NLD	ncancs
	db	66h,89h,47h,08h
	NLD	ncanflag
	db	66h,89h,47h,0ah
	NLD	ncansp
	db	83h,0c0h,10h		; add eax,16: sp at the fault
	db	66h,89h,47h,0ch
	NLD	ncanss
	db	66h,89h,47h,0eh

einxdgo:
	NLD	ncabufer+00
	NST	ncanip
	NLD	ncabufer+04
	NST	ncancs
	db	66h
	jmp	einback

;---- int 0E7h from the stub at 401h: the handler returned (retf).
;     Client stack now at the error code; resume from the frame.

einxret:
	db	66h
	call	e31sslin
	mov	si,ax			; mov esi,eax
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	je	einxr32
	xor	ax,ax			; 16-bit frame: err ip cs fl sp ss
	db	66h,8bh,46h,02h
	NST	ncanip
	xor	ax,ax
	db	66h,8bh,46h,04h
	NST	ncancs
	xor	ax,ax
	db	66h,8bh,46h,06h
	NST	ncanflag
	NST	ncavflag
	xor	ax,ax
	db	66h,8bh,46h,08h
	NST	ncansp
	xor	ax,ax
	db	66h,8bh,46h,0ah
	NST	ncanss
	db	66h
	jmp	einback
einxr32:
	db	8bh,46h,04h		; mov eax,[esi+4]: eip
	NST	ncanip
	db	8bh,46h,08h
	NST	ncancs
	db	8bh,46h,0ch
	NST	ncanflag
	NST	ncavflag
	db	8bh,46h,10h
	NST	ncansp
	db	8bh,46h,14h
	NST	ncanss
	db	66h
	jmp	einback

;---- int 0E8h from a default stub at 404h+N*4: unhandled exception N.
;     Client stack at the return address; restore the client from the
;     frame, then handle the fault as without DPMI.

einxdef:
	NLD	ncanip			; eip is on N (stub offset + 2)
	mov	cx,ax			; mov ecx,eax
	db	66h,67h
	mov	ax,ss:[stubsel16]	; any stub selector: same base
	EAXI	25h,0fff8h,0
	mov	di,ax
	db	66h
	call	e31base
	add	ax,cx			; add eax,ecx
	mov	si,ax
	db	8ah,16h 		; mov dl,[esi]: N
	push	dx
	db	66h
	call	e31sslin
	mov	si,ax
	NLDW	ncancs
	db	66h,67h
	cmp	ax,ss:[stubsel32]
	je	einxf32
	xor	ax,ax			; 16-bit: ret ip, ret cs, err, then frame
	db	66h,8bh,46h,06h
	NST	ncanip
	xor	ax,ax
	db	66h,8bh,46h,08h
	NST	ncancs
	xor	ax,ax
	db	66h,8bh,46h,0ah
	NST	ncanflag
	NST	ncavflag
	xor	ax,ax
	db	66h,8bh,46h,0ch
	NST	ncansp
	xor	ax,ax
	db	66h,8bh,46h,0eh
	NST	ncanss
	jmp	short einxfgo
einxf32:
	db	8bh,46h,0ch
	NST	ncanip
	db	8bh,46h,10h
	NST	ncancs
	db	8bh,46h,14h
	NST	ncanflag
	NST	ncavflag
	db	8bh,46h,18h
	NST	ncansp
	db	8bh,46h,1ch
	NST	ncanss
einxfgo:
	pop	dx
	cmp	dl,0dh			; #GP goes back the way it came: int 6
	jne	einxfg2 		;  with parm6ec still saying "protection"
	mov	dl,06h
	db	66h,67h			; word store: 66h 67h
	mov	ss:[parm6ec],2
einxfg2:
	xor	dh,dh			; edx = the vector (dx held N only)
	db	66h
	jmp	eindisp

	page
;--------------------------------------------------------------------
;	int 31h 0303h/0304h - real-mode callbacks (step 2a: bookkeeping)
;--------------------------------------------------------------------
;
; dcbtab: DCBN records of DCBSZ bytes: +0 in use, +1 task id, +4 proc
; offset (dd), +8 proc selector, +10 structure selector, +12 structure
; offset (dd); +16.. room for the outer v-86 state saved when the
; callback fires (step 2b).
; dcbstub: one real-mode stub per record, in this driver's real-mode
; code (mysegadr:offset): push ax / mov ax,7791h / push idx / int 6fh.
;
e31cfind:				; dx = stub offset, ch = task:
	xor	si,si			;  si = record, CF set if none
	db	0bfh			; mov edi,offset dcbstub (imm32: MASM's BF iw
	dw	offset mmgrp:dcbstub,0 ;  would swallow 2 bytes under the 32-bit cs)
e31cflp:
	db	67h
	cmp	byte ptr ss:[si+dcbtab],1
	jne	e31cfnx
	db	67h
	cmp	byte ptr ss:[si+dcbtab+1],ch
	jne	e31cfnx
	cmp	di,dx
	je	e31cfok
e31cfnx:
	db	66h
	add	si,DCBSZ
	add	di,8
	db	66h
	cmp	si,DCBN*DCBSZ
	jb	e31cflp
	stc
	db	66h
	ret
e31cfok:
	clc
	db	66h
	ret

;---- 0303h allocate real-mode callback: ds:(e)si = procedure,
;     es:(e)di = real-mode call structure -> cx:dx = real-mode address

e310303:
	db	66h			; the return stub (484h) must exist before a
	call	e31stubs		;  callback can fire: e6f91 puts its selector
	jnc	e0303s			;  into the procedure's iret frame
	db	66h
	jmp	e31bad
e0303s:
	db	66h
	call	e31tid
	mov	ch,dl			; task
	NLD	ncands			; the procedure selector must be a
	EAXI	25h,0fff8h,0		;  present dpl-3 code descriptor
	db	66h
	cmp	ax,gdtlen
	jae	e0303x
	mov	di,ax
	db	67h
	mov	al,byte ptr ss:[di+gdt+5]
	and	al,0f8h
	cmp	al,0f8h
	jne	e0303x
	xor	si,si			; a free record
	db	0bfh			; mov edi,offset dcbstub (imm32: MASM's BF iw
	dw	offset mmgrp:dcbstub,0 ;  would swallow 2 bytes under the 32-bit cs)
e0303lp:
	db	67h
	cmp	byte ptr ss:[si+dcbtab],0
	je	e0303got
	db	66h
	add	si,DCBSZ
	add	di,8
	db	66h
	cmp	si,DCBN*DCBSZ
	jb	e0303lp
e0303x:
	db	66h
	jmp	e31bad
e0303got:
	db	67h
	mov	byte ptr ss:[si+dcbtab],1
	db	67h
	mov	byte ptr ss:[si+dcbtab+1],ch
	NLD	ncavsi			; procedure offset
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jnz	e0303a
	EAXI	25h,0ffffh,0
e0303a:
	db	67h
	mov	word ptr ss:[si+dcbtab+4],ax	; mov dword
	NLDW	ncands
	db	66h,67h
	mov	word ptr ss:[si+dcbtab+8],ax
	NLDW	ncanes
	db	66h,67h
	mov	word ptr ss:[si+dcbtab+10],ax
	NLD	ncavdi			; structure offset
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jnz	e0303b
	EAXI	25h,0ffffh,0
e0303b:
	db	67h
	mov	word ptr ss:[si+dcbtab+12],ax	; mov dword

; NCA2 -- used while a callback runs -- is NCA1's block + its total
; size (256 + ncalen + ncabufsz); give it the same buffer size.

	NLD	ncabufsz
	push	ax
	db	05h			; add eax,256+ncalen
	dw	256+ncalen,0
	db	03h,0c3h		; add eax,ebx: NCA2's nca, linear
	mov	si,ax			; mov esi,eax
	pop	ax
	db	89h,46h 		; mov [esi+ncabufsz],eax
	db	offset nca:ncabufsz

	db	66h,67h
	mov	ax,ss:[mysegadr]
	NSTW	ncavcx			; cx = real-mode segment
	mov	ax,di
	NSTW	ncavdx			; dx = the stub
	db	66h
	jmp	e31dok

;---- 0304h free real-mode callback: cx:dx = its real-mode address

e310304:
	db	66h
	call	e31tid
	mov	ch,dl
	xor	ax,ax			; xor eax,eax (UPDATE 72): NLDW loads 16 bits,
					;  the code after it uses all of eax
	NLDW	ncavdx
	mov	dx,ax
	db	66h
	call	e31cfind
	jnc	e0304a
	db	66h
	jmp	e31bad
e0304a:
	db	67h
	mov	byte ptr ss:[si+dcbtab],0
	db	66h
	jmp	e31dok

	page
;--------------------------------------------------------------------
;	int 31h 0306h - get raw mode switch addresses (UPDATE 61)
;--------------------------------------------------------------------
;
; BX:CX    real -> protected: rawstub, in this driver's real-mode code
; SI:(E)DI protected -> real: stub 488h (int 0EAh) via the stub
;          selector matching the client's bitness
; The switches themselves: e6f92 (int 6fh 7792h) and e6frawpm.
;
e310306:
	db	66h
	call	e31stubs
	jnc	e0306a
	db	66h
	jmp	e31bad
e0306a:
	db	66h,67h
	mov	ax,ss:[mysegadr]
	NSTW	ncavbx
	db	66h,0c7h,01000011b	; mov word [ebx+ncavcx],offset rawstub
	db	offset nca:ncavcx
	dw	offset mmgrp:rawstub
	db	66h,67h
	mov	ax,ss:[stubsel16]
	db	66h
	call	c32edx		; edx bit 22 = 32-bit client (UPDATE 62)
	db	0f7h,0c2h		; test edx,00400000h
	dw	0,0040h
	jz	e0306b
	db	66h,67h
	mov	ax,ss:[stubsel32]
e0306b:
	NSTW	ncavsi
	db	0c7h,01000011b		; mov dword [ebx+ncavdi],488h
	db	offset nca:ncavdi
	dw	488h,0
	db	66h
	jmp	e31dok

einfun4c:
	db	66h
	call	freeclsel		; descriptors; preserves ebx (nca)
	db	66h
	call	envr16			; PSP:2Ch back to a segment before DOS
					;  frees the environment (UPDATE 63)

; and this task's DPMI memory blocks (UPDATE 43). Inline, not a
; subroutine: the memory device call goes through dovmint. Loop state
; lives in ncauregs; the client's ax (4Ch) is put back before the
; termination is reflected.

	NLD	ncavax
	NST	ncauregs+08		; client ax
	db	66h
	call	e31tid			; dl = task id
	db	66h
	call	e31hclr			; its protected-mode interrupt hooks
	xor	ax,ax
	mov	al,dl
	NST	ncauregs+00
	xor	ax,ax
	NST	ncauregs+04		; entry offset
e4cblk:
	NLD	ncauregs+04
	db	66h
	cmp	ax,DBLKN*8
	jae	e4cdone
	mov	si,ax			; mov esi,eax
	db	67h
	cmp	byte ptr ss:[si+dblktab],1
	jne	e4cnext
	db	67h
	mov	al,byte ptr ss:[si+dblktab+1]
	db	3ah,01000011b		; cmp al,[ebx+ncauregs+00]
	db	offset nca:ncauregs+00
	jne	e4cnext
	db	67h
	mov	byte ptr ss:[si+dblktab],0	; entry free
	db	67h
	mov	ax,word ptr ss:[si+dblktab+4]	; mov eax,dword: handle
	NSTW	ncavcx			; pages
	shr	ax,16
	NSTW	ncavbx			; start bank
	MEMDEV	02h			; vrelease
e4cnext:
	NLD	ncauregs+04
	db	83h,11000000b,08h	; add eax,8 (MASM's 05 0008 would take
					;  an imm32 here: UPDATE 43)
	NST	ncauregs+04
	jmp	short e4cblk
e4cdone:
	NLD	ncauregs+08
	NST	ncavax			; 4Ch again

; dovmint takes the VECTOR in edx. e31tid (dl = task id) and the
; memory device calls (dx = rhentry) have overwritten it: without
; this the termination was reflected through vector <task id> --
; vector 0 for task 0, MOS's divide handler, "Divide by zero error"
; after EVERY client exit since UPDATE 43 (found in UPDATE 46).
	xor	dx,dx			; xor edx,edx
	mov	dl,21h			; int 21h, as einative found it
	db	66h
	call	cidpop			; the parent is current again (UPDATE 67)
	db	66h
	jmp	einstand

	page
;--------------------------------------------------------------------
;	   release the calling task's client descriptors
;--------------------------------------------------------------------
;
; Frees every gdt entry tagged 80h|taskid for the calling task -- the
; ones 8eh handed a DPMI client. cleardti will not: tagged entries are
; deliberately exempt from the per-switch sweep so a client keeps its
; selectors across switches.
;
; Shared by int 6fh 778Fh (the driver's Unregister path) and by a
; client's own int 21h ah=4Ch in einative. Preserves every register it
; uses, including ebx, which einative holds the nca address in and
; nca_ptr clobbers.
;
freeclsel proc	near
	push	ax			; 32-bit cs: pushes eax
	push	dx
	push	si
	push	di
	push	bx
	db	66h
	call	addrnca			; esi -> tcb, ebx -> nca
	db	66h
	call	cidh			; dh = client id (UPDATE 67)
	or	dh,80h			; the client-descriptor tag
	xor	si,si
fcsloop:
	db	67h
	cmp	ss:[dtitable+si],dh	; one of this task's client entries?
	jne	fcsskip
	db	67h
	mov	ss:[dtitable+si],0ffh	; yes, free it
fcsskip:
	inc	si
	db	66h
	cmp	si,dtilen
	jb	fcsloop
	pop	bx
	pop	di
	pop	si
	pop	dx
	pop	ax
	db	66h
	ret
freeclsel endp

einstand:
	db	66h
	call	dovmint 		; uses/modifies ncairegs

; restore registers to p0stack
einback:
	cld				; set up movsw
	mov	ax,ss
	mov	es,ax
	mov	si,bx
	db	83h,11000110b		; add esi,offset nca:ncairegs+4
					;	  11...110		; reg=esi
	db	offset nca:ncairegs+4
	db	66h			; 16-bit data
	mov	sp,offset mmgrp:p0stack-72  ; make room for 18 registers
	mov	di,sp
	xor	cx,cx
	mov	cl,18
	rep	movsw
	nop

; merge new flags with old flags

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	and	ss:[p0stack-12],7000h	; trash everything but nt,iopl
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncavflag]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	db	66h			; 16-bit data
	and	ax,0fd7h		; save of,df,if,tf,sf,zf,af,pf,1,cf
	db	67h
	mov	dl,ss:[trapsave]	; resume tracing if appropriate
	db	67h
	mov	ss:[trapflag],dl
	or	ah,dl
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	or	ss:[p0stack-12],ax

; resume native-mode application

	pop	di
	pop	si
	pop	dx
	pop	ax
	pop	bx
	pop	cx
	add	sp,8			; skip v-86 es,ds
	pop	bp
	pop	es
	pop	ds
	db	0fh,10100001b		; pop fs
	db	0fh,10101001b		; pop gs
	iret				; also loads ss,sp,eflags
					;   because privilege level changes

	page
;--------------------------------------------------------------------
;		      int 21h function table
;--------------------------------------------------------------------
	even
eintable label word
	dw	offset mmgrp:einfun39	; 39 - make directory
	dw	offset mmgrp:einfun39	; 3a - remove directory
	dw	offset mmgrp:einfun39	; 3b - change directory
	dw	offset mmgrp:einfun39	; 3c - create file
	dw	offset mmgrp:einfun39	; 3d - open file
	dw	offset mmgrp:einstand	; 3e
	dw	offset mmgrp:einfun3f	; 3f - read
	dw	offset mmgrp:einfun40	; 40 - write
	dw	offset mmgrp:einfun39	; 41 - delete
	dw	offset mmgrp:einstand	; 42 - set position: DOS cx:dx / dx:ax (UPDATE 80)
	dw	offset mmgrp:einfun39	; 43 - get/set attr
	dw	offset mmgrp:einstand	; 44
	dw	offset mmgrp:einstand	; 45
	dw	offset mmgrp:einstand	; 46
	dw	offset mmgrp:einfun47	; 47 - get curr dir
	dw	offset mmgrp:einfun48	; 48 - allocate memory
	dw	offset mmgrp:einfun49	; 49 - release memory
	dw	offset mmgrp:einfun4a	; 4a - modify memory block
	dw	offset mmgrp:einstand	; 4b
	dw	offset mmgrp:einfun4c	; 4c - terminate
	dw	offset mmgrp:einstand	; 4d
	dw	offset mmgrp:einfun4e	; 4e - find first
	dw	offset mmgrp:einfun4f	; 4f - find next
	dw	offset mmgrp:einstand	; 50
	dw	offset mmgrp:einstand	; 51
	dw	offset mmgrp:einstand	; 52
	dw	offset mmgrp:einstand	; 53
	dw	offset mmgrp:einstand	; 54
	dw	offset mmgrp:einstand	; 55
	dw	offset mmgrp:einfun56	; 56 - rename
	dw	offset mmgrp:einstand	; 57
	dw	offset mmgrp:einstand	; 58
	dw	offset mmgrp:einstand	; 59
	dw	offset mmgrp:einfun5a	; 5a - create temp file
	dw	offset mmgrp:einfun39	; 5b - create new file
	dw	offset mmgrp:einstand	; 5c - lock/unlock: DOS cx:dx, si:di (UPDATE 82)

	page
;--------------------------------------------------------------------
;		 int 38h extended function table
;--------------------------------------------------------------------
	even
eixtable label word
	dw	offset mmgrp:einfun82	; 02 - get scb address
	dw	offset mmgrp:einfun83	; 03 - get/set extended directory info
	dw	offset mmgrp:einfun82	; 04 - get tcb address
	dw	offset mmgrp:einstand	; 05
	dw	offset mmgrp:einstand	; 06
	dw	offset mmgrp:einstand	; 07
	dw	offset mmgrp:einstand	; 08
	dw	offset mmgrp:einstand	; 09
	dw	offset mmgrp:einstand	; 0a
	dw	offset mmgrp:einstand	; 0b
	dw	offset mmgrp:einstand	; 0c
	dw	offset mmgrp:einstand	; 0d
	dw	offset mmgrp:einstand	; 0e
	dw	offset mmgrp:einstand	; 0f
	dw	offset mmgrp:einfun90	; 10 - mode change
	dw	offset mmgrp:einfun91	; 11 - allocate extended memory
	dw	offset mmgrp:einfun92	; 12 - deallocate extended memory
	dw	offset mmgrp:einfun93	; 13 - get alias



	page
;--------------------------------------------------------------------
;  this procedure enters and exits in native mode. its job is to
;  execute an interrupt handler in virtual mode. fields used are:
;
;    edx      - the interrupt number
;    p0stack  - scratch area for regs to & from virtual mode
;    ncaretad - saves return address from this routine
;    ncastack - stack used during virtual mode processing
;    ncairegs - register values loaded on entry to the interrupt
;		routine, and saved on completion of the routine
;
;  on entry to this routine, ds addresses absolute zero, ebx is the
;  offset mmgrp:(from ds) to the nca, and ss points to this driver.
;
;  it is the caller's responsibility to save all user context that
;  is not preserved in ncairegs by the interrupt handler. ncap0stk
;  and other fields in the nca are provided for this purpose.
;--------------------------------------------------------------------
;
; dovmfar: as dovmint, but the real-mode target is an explicit far
; address -- ncauregs+08 = cs<<16|ip -- instead of an interrupt
; vector. Used by int 31h 0301h/0302h (UPDATE 52). The frame built
; is the same iret frame; a procedure that returns with retf leaves
; the flags word behind, which dovmcont discards when it resets sp.
;
dovmfar:
	db	66h
	db	8fh,01000011b		; pop [ebx+ncaretad]
	db	offset nca:ncaretad
	db	66h			; 16-bit data
	mov	sp,offset mmgrp:s0ip-28 ; as dovmint
	db	8bh,01000011b		; mov eax,[ebx+ncauregs+08]
	db	offset nca:ncauregs+08
	mov	cx,ax			; mov ecx,eax
	db	0c1h,0e9h,10h		; shr ecx,16: cs
	db	25h			; and eax,0ffffh: ip
	dw	0ffffh,0
	jmp	dovmrbak

dovmrh: 				; enter at dovmint, not here!
	db	66h
	mov	ax,dx
	db	66h
	db	67h
	mov	cx,ss:[mysegadr]
	jmp	short dovmrbak

; save return address

dovmint  proc  near
	db	66h
	db	8fh,01000011b		; pop [ebx+ncaretad]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncaretad
	db	66h			; 16-bit data
	mov	sp,offset mmgrp:s0ip-28 ; make room for 7 gp registers

; set s0cs:soip to the handler entry address

	xor	ax,ax
	mov	cx,ax
	or	dh,dh			; special case for request handler?
	jnz	dovmrh			; yes, jump
	shl	dx,2			; address interrupt vector

; new logic added 12/12/88; if the entry in ivtable for this
; interrupt is nonzero, use it instead of the entry in the
; normal interrupt vector table.

	cmp	dh,02h			; skip if int 80-ff
	jae	nirq1
	xchg	bx,dx
	db	66h
	db	67h			; 16-bit address
	mov	ax,ss:[bx+ivtable]	; ax holds offset
	db	66h
	db	67h			; 16-bit address
	mov	cx,ss:[bx+ivtable+2]	; cx holds segment
	xchg	bx,dx
	db	66h
	or	cx,cx			; is one there?
	jnz	dovmrbak		; yes, jump
nirq1:					
	db	66h			; 16-bit data
	db	8bh,00000010b		; mov ax,[edx]
	;	  00...010		; disp=none,base=edx
	db	66h			; 16-bit data
	db	8bh,01001010b		; mov cx,[edx+2]
	;	  01...010		; disp=byte,base=edx
	db	2
dovmrbak:
	db	67h			; 16-bit address
	mov	ss:[s0ip],ax		; 32-bit data
	db	67h			; 16-bit address
	mov	ss:[s0cs],cx		; 32-bit data

; set s0ss:s0sp to point to ncastack

	db	67h			; 16-bit address
	mov	ss:[s0sp],256-6 	; room for virtual mode flags,cs,ip
	dw	0			; 32-bit data
	mov	ax,bx
	shr	ax,4
	db	66h
	sub	ax,256/16
	db	67h			; 16-bit address
	mov	ss:[s0ss],ax

; set s0flags

	mov	ax,3000h		; 32-bit immediate data:iopl=3,
	dw	0002h			;   vm=on,rf=off
	db	66h			; 16-bit data
	db	0bh,01000011b		; or ax,[ebx+ncavflag]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	and	ah,00111101b		; 0,nt,if off

; special handling for trap flag

	db	67h
	mov	cl,ss:[iveccode]
	cmp	cl,8			; timer interrupt?
	je	dovmcltf		; yes, clear trap flag
	cmp	cl,1ch			; timer interrupt?
	je	dovmcltf		; yes, clear trap flag
	cmp	cl,1			; single step interrupt?
	je	dovmcltf		; yes, clear trap flag
	db	67h
	or	ah,ss:[trapflag]	; tf on if tracing
	jmp	short dovmoktf
dovmcltf:
	and	ah,11111110b		; clear trap flag
dovmoktf:
	db	67h			; 16-bit address
	mov	ss:[s0flags],ax 	; 32-bit data

; set segment registers in p0stack

	xor	ax,ax
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncaves]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncaves
	db	67h			; 16-bit address
	mov	ss:[s0es],ax		; 32-bit data
	db	66h			; 16-bit data
	db	8bh,01000011b		; mov ax,[ebx+ncavds]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavds
	db	67h			; 16-bit address
	mov	ss:[s0ds],ax		; 32-bit data

; set general registers in p0stack

	mov	ax,ss
	mov	es,ax
	mov	si,bx			; start with di
	db	83h,11000110b		; add esi,offset nca:ncairegs+4
	;	  11...110		; reg=esi
	db	offset nca:ncairegs+4
	mov	di,sp
	xor	cx,cx
	mov	cl,6
	cld
	rep	movsw
	add	si,8			; skip es,ds to pick up bp
	movsw

; set up flags in virtual-mode stack

	db	66h
	mov	ax,3000h		; iopl=3
	db	66h			; 16-bit data
	db	0bh,01000011b		; or ax,[ebx+ncavflag]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncavflag
	and	ah,00111111b		; 0,nt off
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncastack-2],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncastack-2

; set up cs,ip in virtual-mode stack

	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	ax,ss:[mysegadr]
	db	66h			; 16-bit data
	db	89h,01000011b		; mov [ebx+ncastack-4],ax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncastack-4
	db	66h			; 16-bit data
	db	0c7h,01000011b		; mov [ebx+ncastack-6],offset mmgrp:dovmcont
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncastack-6
	dw	offset mmgrp:dovmcont	; immediate data

; exit to virtual-mode interrupt handler

	pop	di
	pop	si
	pop	dx
	pop	ax
	pop	bx
	pop	cx
	pop	bp
	iret				; loads ss,sp,es,ds,fs,gs
					; and switches to virtual mode

; return from virtual-mode interrupt handler

dovmcont:				; ss:sp addresses ncastack
	mov	cs:[trapflag],0 	; don't let tracing screw us up

; save registers in ncairegs while still in virtual mode

	mov	sp,256+offset nca:ncairegs+40  ; important that it follows ncastack
	db	66h			; must push 32 bits at a time
	push	bp
	db	66h
	push	ds
	db	66h
	push	es
	db	66h
	push	cx
	db	66h
	push	bx
	db	66h
	push	ax
	db	66h
	push	dx
	db	66h
	push	si
	db	66h
	push	di
	db	66h
	pushf

; get back into native mode

	mov	ax,7702h		; request transfer to native mode
	int	6fh			; returns ss:sp in p0stack, ds at 0

; re-establish ebx as pointer to nca

	xor	bx,bx
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	mov	bx,ss:[s0ss]		; address nca with ds:bx
	add	bx,256/16		; 8-bit operand
	shl	bx,4

;
; UPDATE 66: the client's IF and TF back into ncavflag. dovmcont just
; saved the v-86 registers into ncairegs -- flags included, so ncavflag
; now holds the v-86 service's flags. The callers need its CF (and the
; arithmetic flags) from there, but the int 31h/21h return (einback)
; builds the client's EFLAGS from ncavflag & 0FD7h, IF included: the
; memory device and DOS run with IF=0, so a client whose call went
; through dovmint (0501h..0503h, 0100h..0102h, DOS translations) got
; IF=0 back and ran on with interrupts off for good -- no timer, no
; keyboard (DJGPP and DOS/4GW clock() hung). ncanflag still holds the
; client's EFLAGS from its entry (einative); dovmint never writes it.
;
	push	ax			; push eax
	db	8ah,01000011b		; mov al,[ebx+ncanflag+1]
	db	offset nca:ncanflag+1
	and	al,03h			; the client's IF, TF
	db	80h,01100011b		; and byte [ebx+ncavflag+1],0fch
	db	offset nca:ncavflag+1
	db	0fch
	db	08h,01000011b		; or [ebx+ncavflag+1],al
	db	offset nca:ncavflag+1
	pop	ax
; return to caller

	db	66h
	db	0ffh,01110011b		; push [ebx+ncaretad]
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncaretad
	db	66h
	ret
dovmint  endp


	page
;--------------------------------------------------------------------
;	    execute a request to switch to native mode
;--------------------------------------------------------------------
nmswitch:
	push	ax			; save remaining registers
	push	dx
	push	si
	push	di
	sub	sp,8			; room to put fs,gs
	db	66h
	call	addrnca 		; get tcb address into esi
	db	66h			; set nca address into tcb
	db	89h,01010110b		; mov [esi+tcbncadr],dx
	;	  01...110		; disp=byte,base=esi
	db	tcbncadr
	db	66h
	call	addrnca 		; get nca address into ebx
	xor	ax,ax
	db	66h
	db	67h
	mov	ax,[bp-12]		; original cx
	sub	ax,256+ncalen		; compute size left for i/o buffer
	dw	0			; 32-bit operand
	db	89h,01000011b		; mov [ebx+ncabufsz],eax
	;	  01...011		; disp=byte,base=ebx
	db	offset nca:ncabufsz
	db	8ah,01110110b		; mov dh,[esi+tcbid] get task id in dh
	;	  01...110		; disp=byte,base=esi
	db	tcbid
	db	66h
	call	cleardti		; clear dti entries for this task
	db	66h
	call	cidtagsw		; a DPMI switch: dh = 80h|client id (UPDATE 67)
	mov	dl,11110010b		; p=1,dpl=3,s=1,type=001,a=0
	db	66h
	db	67h
	mov	ax,ss:[s0ds]		; translate ds selector
	db	66h
	call	makegdte
	db	66h
	call	clrgran			; g=0: a 64 KB limit (UPDATE 65)
	db	66h
	db	67h
	mov	[bp-4],ax
	db	66h
	db	67h
	mov	ax,ss:[s0es]		; translate es selector
	db	66h
	call	makegdte
	db	66h
	call	clrgran			; g=0: a 64 KB limit (UPDATE 65)
	db	66h
	db	67h
	mov	[bp-8],ax
	db	66h
	db	67h
	mov	ax,ss:[s0gs]		; translate gs selector
	db	66h
	call	makegdte
	db	66h
	call	clrgran			; g=0: a 64 KB limit (UPDATE 65)
	db	66h
	db	67h
	mov	[bp-36],ax
	db	66h
	db	67h
	mov	ax,ss:[s0fs]		; translate fs selector
	db	66h
	call	makegdte
	db	66h
	call	clrgran			; g=0: a 64 KB limit (UPDATE 65)
	db	66h
	db	67h
	mov	[bp-40],ax
	db	66h
	db	67h
	mov	ax,ss:[s0ss]		; translate ss selector
	db	66h
	call	makegdte
	db	66h
	call	clrgran			; g=0: a 64 KB limit (UPDATE 65)
	db	66h
	db	67h
	mov	ss:[s0ss],ax
	db	66h
	db	67h
	mov	ax,ss:[s0cs]		; translate cs selector
	mov	dl,11111010b		; set type=101 for executable
;
; Tag the cs descriptor like a client selector (80h|taskid) so the
; cleardti sweep on the NEXT native-mode switch cannot free it while
; it is still loaded -- a freed-but-live slot is handed out again by
; makegdte and overwritten (UPDATE 29/30). On the next switch makegdte
; matches this entry (same tag, access, base) and reuses it, so it
; does not accumulate; freeclsel releases it at the client's 4Ch.
;
	or	dh,80h
	db	66h
	call	makegdte
	and	dh,7fh			; plain task id again for anything after
	db	66h
	db	67h
	mov	ss:[s0cs],ax
	db	67h			; 16-bit address
	db	36h			; ss override
	db	0fh,01h,00010110b	; lgdt using disp16
	dw	offset mmgrp:wsgdtr
	db	67h
	and	byte ptr ss:[s0flags+2],0fch  ; turn off vm flag
	db	0fh,10100001b		; pop fs
	db	0fh,10101001b		; pop gs
	pop	di
	pop	si
	pop	dx
	pop	ax
	pop	bx
	pop	cx
	pop	es
	pop	ds
	pop	bp
	db	66h
	mov	sp,offset mmgrp:s0ip	; throw away error code
	iret				; enters privilege level 3



	page
;--------------------------------------------------------------------
;		  establish ebx as pointer to nca
;		  also returns tcb address in esi
;--------------------------------------------------------------------
addrnca  proc  near
	xor	bx,bx			; compute scb address in ebx
	mov	si,bx
	db	66h
	db	67h
	mov	bx,ss:[parmscb+2]
	shl	bx,4
	db	66h
	db	67h
	mov	si,ss:[parmscb]
	add	bx,si
	db	66h			; now get tcb address into esi
	db	8bh,01110011b		; mov si,[ebx+scbtcbpc]
	;	  01...011		; disp=byte,base=ebx
	db	scbtcbpc
	shl	si,4
	xor	bx,bx			; get nca address into ebx
	db	66h
	db	8bh,01011110b		; mov bx,[esi+tcbncadr]
	;	  01...110		; disp=byte,base=esi
	db	tcbncadr
	db	66h
	add	bx,256/16		; ncastack length is 256 bytes
	shl	bx,4
	db	66h
	ret				; 16-bit near return
addrnca  endp

;
; MASM cannot encode a direct call from a use32 segment to a label
; in a use16 one: it emits a 66h operand-size override together
; with a rel32 displacement, and the cpu then takes rel16 and
; executes the trailing two bytes. Call through these pointers
; instead. Operand size must match the callee's ret: addrnca ends
; with a 66h-prefixed ret (pops 2), makegdte with a plain one.
;
nca32	proc	near			; wrapper: 32-bit call in, 16-bit call out
	db	66h			; 16-bit call: addrnca pops 2 bytes
	call	addrnca
	ret				; plain ret: 32-bit here, matches the caller
nca32	endp

mgd32	proc	near			; same wrapper for makegdte: it also ends
	db	66h			;  with a 66h-prefixed ret (pops 2)
	call	makegdte
	ret
mgd32	endp

fcs32	proc	near			; same wrapper for freeclsel: it also ends
	db	66h			;  with a 66h-prefixed ret (pops 2)
	call	freeclsel
	ret
fcs32	endp

nca_ptr	dd	offset nca32		; 32-bit indirect target
fcs_ptr	dd	offset fcs32		; 32-bit indirect target
mgd_ptr	dd	offset mgd32		; 32-bit indirect target
					;  plain dd label emits a segment fixup and
					;  exe2bin then demands a base segment)


	page
;--------------------------------------------------------------------
;		   make a gdt entry for a task
;--------------------------------------------------------------------
makegdte proc  near
	db	67h
	and	ax,ss:[zero1631]	; clear high word of eax
	shl	ax,4			; and shift eax to get 20-bit address
	xor	si,si
	mov	di,gdtspace-gdt
	dw	0			; 32-bit operand
mgdloop1:
	db	67h
	cmp	ss:[si+dtitable],dh	; entry for same task?
	jne	mgdcont1		; no, skip
	db	67h
	cmp	byte ptr ss:[di+gdt+5],dl  ; same access rights byte?
	jne	mgdcont1		; no, skip
	db	67h
	mov	cx,ss:[di+gdt+2]	; get segment base address bits 0-23
	db	81h,0e1h		;and ecx,00ffffffh
	dw	0ffffh,00ffh
	cmp	ax,cx
	je	mgdret			; same base: reuse it AS IT IS (UPDATE 65)
mgdcont1:
	db	67h
	cmp	ss:[si+dtitable],0ffh	; available entry?
	je	mgdgotav		; yes, jump
	inc	si			; no, look again
	add	di,8
	db	66h
	cmp	si,dtilen
	jb	mgdloop1
	xor	ax,ax			; table full - return null selector
	jmp	short mgdexit
mgdgotav:
	db	67h
	mov	ss:[si+dtitable],dh	; set ownership by this task
	db	66h
	db	67h
	mov	ss:[di+gdt],0ffffh	; set segment length in pages
	db	67h
	mov	ss:[di+gdt+2],ax	; set segment base address bits 0-23
	db	67h
	mov	byte ptr ss:[di+gdt+5],dl  ; access rights byte
	db	66h
	db	67h
	mov	ss:[di+gdt+6],00c0h	; g=1,d=1
;
; UPDATE 65: a matching entry (same task, access, base) used to fall
; into mgdgotav and get limit FFFFh and g=1,d=1 again. That undid the
; switch's g=0 (clrgran) on the client's ds/ss and any limit a client
; set itself with 0008h (DOS/32A: ds to 4 GB) as soon as the kernel
; translated the same segment again. Only a fresh entry is written.
;
mgdret:
	mov	ax,di			; return selector with rpl=3
	or	al,3
mgdexit:
	db	66h
	ret
makegdte endp

	page
;--------------------------------------------------------------------
;		make a gdt entry for extended memory
;--------------------------------------------------------------------
makegdtx proc  near
	xor	si,si
	mov	di,gdtspace-gdt
	dw	0			; 32-bit operand
mgxloop1:
	db	67h
	cmp	ss:[si+dtitable],0ffh	; available entry?
	je	mgxgotav		; yes, jump
	inc	si			; no, look again
	add	di,8
	db	66h
	cmp	si,dtilen
	jb	mgxloop1
	xor	ax,ax			; table full - return null selector
	jmp	short mgxexit
mgxgotav:
	db	67h
	mov	ss:[si+dtitable],0feh	; set as permanent entry
	db	66h
	db	67h
	mov	ss:[di+gdt],dx		; set segment length in pages
	db	67h
	mov	ss:[di+gdt+4],ax	; set segment base address bits 24-31
	db	67h
	mov	ss:[di+gdt+2],ax	; set segment base address bits 0-23
	db	67h
	mov	byte ptr ss:[di+gdt+5],11110010b  ; access rights byte
	db	66h
	db	67h
	mov	ss:[di+gdt+6],00c0h	; g=1,d=1
	mov	ax,di			; return selector with rpl=3
	or	al,3
mgxexit:
	db	66h
	ret
makegdtx endp

	page
;--------------------------------------------------------------------
;		clear all gdt entries for this task
;--------------------------------------------------------------------
cleardti proc  near
	xor	si,si
cdtloop1:
	db	67h
	cmp	ss:[dtitable+si],dh	; task match for this entry?
	jne	cdtskip1		; no, jump
	db	67h
	mov	ss:[dtitable+si],0ffh	; yes, clear it
cdtskip1:
	inc	si
	db	66h
	cmp	si,dtilen
	jb	cdtloop1
	db	66h
	ret
cleardti endp

;--------------------------------------------------------------------
;	clrgran: g=0 on the descriptor of selector ax (UPDATE 65)
;--------------------------------------------------------------------
;
; makegdte builds every descriptor with g=1,d=1 (00C0h). For the
; data selectors of the native-mode switch that is a 256 MB limit on
; a 64 KB real-mode segment; DPMI 0.9 gives the client 64 KB ones
; (HDPMI32: 0040h). A bad stack pointer then faults (#SS) instead of
; silently using memory above the segment (UPDATE 64, bug 4). ax = 0
; (table full) is left alone. Preserves all registers.
;
clrgran proc	near
	or	ax,ax
	jz	clrgx
	push	di
	db	0fh,0b7h,0f8h		; movzx edi,ax
	and	di,0fff8h		; drop the rpl: makegdte returns it or 3
	db	67h
	and	byte ptr ss:[di+gdt+6],7fh	; g=0, keep d/b and limit 19:16
	pop	di
clrgx:
	db	66h
	ret
clrgran endp

	page
;--------------------------------------------------------------------
;	    common entry logic for interrupt handlers
;--------------------------------------------------------------------
eicommon proc  near
	db	66h			; 16-bit data
	db	67h			; 16-bit address
	pop	ss:[trash1]		; return address
	push	bp
	mov	bp,sp			; bp is at [bp]
	push	ds			; ds is at [bp-4]
	push	es			; es is at [bp-8]
	push	cx			; cx is at [bp-12]
	push	bx			; bx is at [bp-16]

;------------- let's see where we stand at this point: --------------
;   bp = p0stack-24		means native mode, no error code
;   bp = p0stack-28		means native mode, with error code
;   bp = p0stack-40 = s0ip-4	means v-86 mode, no error code
;   bp = p0stack-44 = s0error-4 means v-86 mode, with error code
;--------------------------------------------------------------------

	db	66h
	mov	bx,gdtzero-gdt		; load segment selectors
	mov	ds,bx
	mov	bx,ss
	mov	es,bx
	db	66h
	db	67h
	jmp	ss:[trash1]		; return to handler
eicommon endp


res16  ends


;======================== 32 bit resident code =========================

	.386p
res32	segment para public 'CODE' use32
assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing

	subttl find_byte - search forward cx bytes for a match with al
	page
;======================================================================
;,fs
; find_byte - search forward cx bytes for a match with al
;
; in:	al = byte to find
;	ss:edi -> starting search location
;	ecx = # of bytes to search
;
; out:	zr flag if find match
;	 ss:edi -> point of match
;	nz flag if not found
;	 edi undefined
;
;,fe
;======================================================================
assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing

find_byte:
	push	ecx
	push	es
	push	ss
	pop	es
	cld
	repne	scasb
	jne	fb1
	dec	edi			; adjust edi
	cmp	edi,edi 		; insure zr flag is set
fb1:
	pop	es
	pop	ecx
	ret


	subttl write_gdt - write values into a gdt descriptor
	page
;======================================================================
;,fs
; write_gdt - write values into a gdt descriptor
;
; in:	eax = base (all 32 bits used)
;	ebx = limit  (bits 0-23 used)
;	cx = type/limit/uxdg
;	 b0  - accessed bit - set to 0
;	 b1  - segment type
;	 b2  - segment type
;	 b3  - segment type
;	 b4  - system bit
;	 b5  - descriptor privilege level
;	 b6  - descriptor privilege level
;	 b7  - present bit
;	 b8  - not used
;	 b9  - not used
;	 b10 - not used
;	 b11 - not used
;	 b12 - user bit
;	 b13 - reserved
;	 b14 - default operand size (0 for 16, 1 for 32)
;	 b15 - granularity
;
;	ss:edi -> location descriptor is to be written
;
; out:	none - all regs preserved
;
;,fe
;======================================================================
assume	cs:mmgrp,ds:nothing,es:nothing,ss:mmgrp,fs:nothing,gs:nothing

write_gdt:
	push	ecx
	push	edx
	mov	ss:[edi+4],eax		; write in base bits 24 - 31
	mov	ss:[edi+2],eax		; write in base bits 0 - 23
	and	ch,0f0h 		; make sure 3rd nibble is clear
	mov	edx,ebx
	shr	edx,8
	and	dh,0fh			; bring in high nibble of limit
	or	ch,dh
	mov	ss:[edi+5],cx		; write in type, ar and limit
	mov	ss:[edi],bx		; write in limit bits 0 - 15
	pop	edx
	pop	ecx
	ret


	subttl entint02 - protected mode nmi handling logic
	page
;======================================================================
;,fs
; entint02 - protected mode nmi handling logic
;
; in:	ss:esp -> p0stack
;
; out:	none - all regs must be preserved
;
;,fe
;======================================================================
assume	cs:mmgrp,ds:nothing,es:nothing,ss:mmgrp,fs:nothing,gs:nothing

entint02:
	pushad
	push	ds
	push	es
	push	fs
	push	gs
	mov	bx,gdtvideo-gdt 	; load segment selectors
	mov	es,bx
	mov	bx,ss:[nmi_slctr]
	mov	ds,bx
	call	fword ptr ss:[nmi_vector]
	pop	gs
	pop	fs
	pop	es
	pop	ds
	popad
	iretd


nmimsg	db	'P',70h,'A',70h,'R',70h,'I',70h,'T',70h,'Y',70h
	db	' ',70h,'E',70h,'R',70h,'R',70h,'O',70h,'R',70h
nmimsglen equ $-nmimsg

	subttl dflt_int2 - protected mode nmi handling logic
	page
;======================================================================
;,fs
; dflt_int2 - protected mode nmi handling logic
;
; ss:esp could be a user stack - no ss: relative data access!!!
;
; in:	ds = selector for nmi data area
;	es = selector for video buffer
;
; out:	none - all regs must be preserved
;
;,fe
;======================================================================
assume	cs:mmgrp,ds:mmgrp,es:nothing,ss:nothing,fs:nothing,gs:nothing
dflt_int2:	   
	push	eax
	in	al,61h
	test	al,0c0h
	jnz	dfnm1
	in	al,61h
	jmp	$+2
	or	al,0ch
	out	61h,al
	jmp	$+2
	and	al,not 0ch
	out	61h,al
	pop	eax
	retf
dfnm1:
	mov	ecx,nmimsglen
	mov	esi,offset mmgrp:nmimsg
	xor	edi,edi
	cld
	rep	movsb
	cli
	hlt

;=======================================================================

i6f_tbl	label	dword
	dd	offset mmgrp:e6f00
	dd	offset mmgrp:e6f01
	dd	offset mmgrp:e6f02
	dd	offset mmgrp:e6f03
	dd	offset mmgrp:e6f04
	dd	offset mmgrp:e6f05
	dd	offset mmgrp:e6f06
	dd	offset mmgrp:e6f07
	dd	offset mmgrp:e6f08
	dd	offset mmgrp:e6f09
	dd	offset mmgrp:e6f0a
	dd	offset mmgrp:e6f0b
;
; VCPI\DPMI functions
;
	dd	offset mmgrp:e6f0c	; translate meg0 to physical
	dd	offset mmgrp:e6f0d	; read cr0
	dd	offset mmgrp:e6f0e	; read debug registers
	dd	offset mmgrp:e6f0f	; write debug registers
;
i6f_tbl_entries equ	($-i6f_tbl)/4

;
; DPMI memory-manager function block.  _DPMI.INC declares a second set
; of int 6fh services based at 7780h ("All DPMI related Memory manager
; functions start from 80h...") which this driver never implemented --
; i6f_tbl above only covers 7700h-770Fh, so every one of them fell
; through to contirq, got reflected to the never-hooked real-mode int
; 6fh vector, and executed whatever happened to be there.  That is why
; $DPMI.SYS could not install.
;
; Implemented here as a SECOND table with its own range check rather
; than padding i6f_tbl out to 142 mostly-empty entries.
;
; Note the two components disagree on numbering: this driver already
; implements read/write debug registers at 770Eh/770Fh (labelled "VCPI\
; DPMI functions" above) while _DPMI.ASM calls the same capability at
; READ_DEBUG=7783h / WRITE_DEBUG=7784h.  They were evidently written
; against diverging revisions of the same interface.  Only 86h/87h are
; implemented so far; the rest fail cleanly rather than crashing.
;
i6f_dpmi_tbl label dword
	dd	offset mmgrp:e6funimp	; 80h MEM_GET_DESC
	dd	offset mmgrp:e6funimp	; 81h MEM_SET_DESC
	dd	offset mmgrp:e6funimp	; 82h MEM_VIRTUAL
	dd	offset mmgrp:e6funimp	; 83h READ_DEBUG
	dd	offset mmgrp:e6funimp	; 84h WRITE_DEBUG
	dd	offset mmgrp:e6funimp	; 85h MEM_DESCRIPTOR
	dd	offset mmgrp:e6f86	; 86h SEGMENT_SELECTOR
	dd	offset mmgrp:e6f87	; 87h SELECTOR_SEGMENT
	dd	offset mmgrp:e6funimp	; 88h GET_PROT_EXCEPTION
	dd	offset mmgrp:e6funimp	; 89h SET_PROT_EXCEPTION
	dd	offset mmgrp:e6funimp	; 8ah GET_REAL_EXCEPTION
	dd	offset mmgrp:e6funimp	; 8bh SET_REAL_EXCEPTION
	dd	offset mmgrp:e6funimp	; 8ch CREATE_ALIAS
	dd	offset mmgrp:e6funimp	; 8dh ALLOC_SPEC_SELECTOR
	dd	offset mmgrp:e6f8e	; 8eh CODE_SELECTOR
	dd	offset mmgrp:e6f8f	; 8fh FREE_CLIENT_SEL
	dd	offset mmgrp:e6f90	; 90h SET_DPMI_RESERVE
	dd	offset mmgrp:e6f91	; 91h CALLBACK (real-mode stub fired)
	dd	offset mmgrp:e6f92	; 92h RAW real -> protected
	dd	offset mmgrp:e6f93	; 93h CLIENT_PSP (UPDATE 63)
;
i6f_dpmi_entries equ	($-i6f_dpmi_tbl)/4


	subttl entint6f - int6f function handler
	page
;======================================================================
;,fs
; entint6f - int6f function handler
;
; in:	specific to sub-function
;
; out:	specific to sub-function
;
;,fe
;======================================================================
assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing

entint6f:
	calls32 eicommon		; kludge until eicommon is moved to use32
	mov	ch,6fh
	mov	ss:[debugint],ch
	mov	ss:[iveccode],ch
	cmp	bp,offset mmgrp:p0stack-28
	jnae	e6fa
	jmps32 ei38nat
e6fa:
	cmp	ax,7700h
	jb	e6fb
	cmp	ax,(7700h+i6f_tbl_entries)
	jae	e6fdpmi

	push	ebx
	push	ebx
	push	ebp
	mov	ebp,esp
	movzx	ebx,ax
	sub	ebx,7700h
	shl	ebx,2
	mov	ebx,mmgrp:[i6f_tbl+ebx]
	mov	[ebp+8],ebx
	pop	ebp
	pop	ebx
	ret

e6fdpmi:
;
; second dispatch range: the DPMI memory-manager block based at 7780h.
; Same mechanism as above -- plant the handler address in the return
; slot and ret to it.  Out of range still falls through to contirq.
;
	cmp	ax,7780h
	jb	e6fb
	cmp	ax,(7780h+i6f_dpmi_entries)
	jae	e6fb

	push	ebx
	push	ebx
	push	ebp
	mov	ebp,esp
	movzx	ebx,ax
	sub	ebx,7780h
	shl	ebx,2
	mov	ebx,mmgrp:[i6f_dpmi_tbl+ebx]
	mov	[ebp+8],ebx
	pop	ebp
	pop	ebx
	ret

e6fb:
	jmps32 contirq


;==== special func 0 - go to real mode

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f00:
	push	eax
	mov	ss:[realsw],'Y' 	; indicate continuation to realret
	jmps32	realhent

;==== call nlistmap

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f01:
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	push	fs
	mov	ax,gdtzero-gdt
	mov	fs,ax
	assume	fs:nothing
	mov	ebx,mmgrp:[ntrash1]
	mov	ecx,mmgrp:[ntrash2]
	call	nlistmap
	call	flushtlb
	pop	fs
	jmp	cgrm7

;==== go to native mode from vm86

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f02:
	db	5bh			; pop bx
	db	59h			; pop cx
	db	83h,0c4h,8		; add sp,8
	db	5dh			; pop bp
	db	66h,67h
	db	36h,0ffh,26h		; jmp ss:[s0ip]
 	dw	mmgrp:s0ip

;==== call nremap

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f03:
	push	esi
	push	edi
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	esi,mmgrp:[ntrash1]
	mov	edi,mmgrp:[ntrash2]
	mov	ecx,mmgrp:[ntrash3]
	call	nremap
	call	flushtlb
	pop	edi
	pop	esi
	jmp	cgrm7

;==== call nphymap

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f04:
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	eax,mmgrp:[ntrash1]
	mov	ebx,mmgrp:[ntrash2]
	mov	ecx,mmgrp:[ntrash3]
	call	nphymap
	call	flushtlb
	jmp	cgrm7

;==== call nalloc

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f05:
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	ecx,mmgrp:[ntrash1]
	call	nalloc
	mov	mmgrp:[ntrash1],eax
	mov	mmgrp:[ntrash2],ebx
	mov	mmgrp:[ntrash3],ecx
	jmp	cgrm7

;==== call nrelease

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f06:
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	ebx,mmgrp:[ntrash1]
	mov	ecx,mmgrp:[ntrash2]
	call	nrelease
	mov	mmgrp:[ntrash1],eax
	jmp	cgrm7

;==== call nprotect

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f07:
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	ebx,mmgrp:[ntrash1]
	mov	ecx,mmgrp:[ntrash2]
	call	nprotect
	call	flushtlb
	mov	mmgrp:[ntrash1],eax
	jmp	cgrm7

;==== call nunprot

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f08:
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	ebx,mmgrp:[ntrash1]
	mov	ecx,mmgrp:[ntrash2]
	call	nunprot
	call	flushtlb
	mov	mmgrp:[ntrash1],eax
	jmp	cgrm7

;==== establish new nmi handler

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f09:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
	push	edi
	mov	edx,ss:[nmi_vector]
	xchg	edx,ss:[ntrash1]
	mov	ss:[ntrash3],1		; presume 'out of gdt space' error

; seek a free gdt slot for the code descriptor

	mov	al,0ffh
	mov	edi,offset mmgrp:dtitable
	mov	ecx,dtilen
	call	find_byte
	jne	cgrm14a 		; error
	mov	byte ptr ss:[edi],0feh	; mark as permanently reserved
	mov	esi,edi 		; just remember offset for now

; seek a free gdt slot for the data descriptor

	mov	al,0ffh
	mov	edi,offset mmgrp:dtitable
	mov	ecx,dtilen
	call	find_byte
	je	cgrm14b

; if an error with the 2nd call, must undo the 1st reservation

	mov	byte ptr ss:[esi],0ffh	; free up first entry
	jmp	cgrm14a 		; error
cgrm14b:
	mov	byte ptr ss:[edi],0feh	; mark as permanently reserved
	mov	ss:[ntrash3],0		; past the point of error

; derive the base and limit values for write_gdt

	movzx	edx,dx			; insure high word is 0
	shl	edx,4			; derive base in edx
	mov	eax,edx 		; from entry cs
	mov	ebx,16			; 16 * 4096 = 64k = limit

; init the code descriptor

	push	edi
	mov	edi,esi
	sub	edi,offset mmgrp:dtitable
	shl	edi,3			; convert byte index to gdt index
	add	edi,offset mmgrp:gdtspace
	mov	cx,1100000010011010b	; execute/read, pl0, present, 32 bit
	call	write_gdt
	sub	edi,offset mmgrp:gdt	; derive selector
	mov	si,di			; save in si for now

; init the data descriptor

	pop	edi
	sub	edi,offset mmgrp:dtitable
	shl	edi,3			; convert byte index to gdt index
	add	edi,offset mmgrp:gdtspace
	mov	cx,1100000010010010b	; read/write, pl0, present, 32 bit
	call	write_gdt
	sub	edi,offset mmgrp:gdt	; derive selector

; update the nmi handler pointers and return data

	movzx	ebx,word ptr ss:[ntrash2]
	pushf
	cli
	mov	al,8dh
	out	70h,al			; mask off nmis
	mov	ss:[nmi_vector],ebx
	xchg	word ptr ss:[nmi_vector+4],si
	mov	word ptr ss:[ntrash2+2],si
	xchg	word ptr ss:[nmi_slctr],di
	mov	word ptr ss:[ntrash2],di
	mov	al,0dh
	out	70h,al
	popf
cgrm14a:
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	jmp	cgrm7

;==== restore previous nmi handler

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f0a:
	push	eax
	push	ebx
	push	ecx
	push	edx

; restore previous 32 bit offset and code and data selectors

	mov	ebx,ss:[ntrash1]
	mov	cx,word ptr ss:[ntrash2]
	mov	dx,word ptr ss:[ntrash3]
	pushf
	cli
	mov	al,8dh
	out	70h,al			; mask off nmis
	xchg	ss:[nmi_vector],ebx
	xchg	word ptr ss:[nmi_vector+4],cx
	xchg	word ptr ss:[nmi_slctr],dx
	mov	al,0dh
	out	70h,al
	popf

; convert the code selector to a dtitable offset
; and mark the selector as free

	movzx	ecx,cx
	add	ecx,offset mmgrp:gdt
	sub	ecx,offset mmgrp:gdtspace
	shr	ecx,3
	mov	ss:[dtitable+ecx],0ffh

; convert the data selector to a dtitable offset
; and mark the selector as free

	movzx	edx,dx
	add	edx,offset mmgrp:gdt
	sub	edx,offset mmgrp:gdtspace
	shr	edx,3
	mov	ss:[dtitable+edx],0ffh	   
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	jmp	cgrm7

;==== extended memory block copy

; in:	[ntrash1].lo = task handle
;	[ntrash1].hi = offset within task page
;	[ntrash2]    = phyaddr of global buffer
;	[ntrash3].lo = # of bytes to copy
;	[ntrash3].hi = direction flag (0 for g->t, 1 for t->g)
;
; out:	[ntrash2].lo = 0 if no error, 1 if invalid handle

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f0b:
	pushset	eax,esi,edi
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing

; fetch the handle and convert it to an address which will end up
; using that handle's parspace entry as a page table entry.
; then add in the offset within the page to form the final 
; task buffer address.
  
	movzx	esi,word ptr [ntrash1]
	shl	esi,2
	cmp	esi,[parsize]
	jae	e6f0b1
	add	esi,nparspace
	shl	esi,10
	movzx	eax,word ptr [ntrash1+2]
	add	esi,eax

; fetch the phyaddr of the global buffer.  it can be used as is.

	mov	edi,[ntrash2]

; if the direction flag == 1, copy from global buffer to task

	cmp	word ptr [ntrash3+2],0
	jne	e6f0b4
	xchg	esi,edi
e6f0b4:
	mov	word ptr [ntrash2],0	; return good status
	movzx	ecx,word ptr [ntrash3]	; fetch byte count
	shr	ecx,1
	setc	al			; al = 1 if leftover byte
	shr	ecx,1
	setc	ah			; ah = 1 if leftover word
	cld
	mov	bx,gdtzero-gdt
	mov	ds,bx
	assume	ds:nothing
	mov	es,bx
	assume	es:nothing
	rep	movsd			; move dwords
	mov	cl,ah
	rep	movsw			; move words
	mov	cl,al
	rep	movsb			; move bytes
e6f0b2:
	popset	eax,esi,edi
	jmp	cgrm7
e6f0b1:
	assume	ds:mmgrp
	mov	word ptr [ntrash2],1	; return error status
	jmp	short e6f0b2



;==== special func 0c - translate meg0 into physical address

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f0c:
	push	eax
	push	esi
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	cmp	word ptr [ntrash1],0100h	; is linear address in meg0?
	jb	short e6f0ca			; yes...then continue on...
	mov	word ptr [ntrash3],1		; indicate error
	jmp	short e6f0cx
e6f0ca:
	xor	eax,eax
	mov	ax,word ptr [ntrash1]		; get page # from caller
	mov	esi,eax
	mov	eax,dword ptr es:[esi*4]	; grab page table entry
	and	eax,NOT 0fffh			; mask out low 12 bits
	mov	dword ptr [ntrash1],eax		; return to caller
	mov	word ptr [ntrash3],0		; indicate ok
e6f0cx:
	pop	esi
	pop	eax
	jmp	cgrm7


;==== special func 0d - readcr0

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f0d:
	push	eax
	push	esi
	push	edi
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	mov	eax,cr0			; read CR0
	mov	[ntrash2],eax
	mov	word ptr [ntrash3],00
	pop	edi
	pop	esi
	pop	eax
	jmp	cgrm7

;==== special func 0e - read debug register

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f0e:
	push	eax
	push	esi
	push	edi
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	call	nreaddb			; native mode read debug registers
	mov	[ntrash1],eax

	pop	edi
	pop	esi
	pop	eax
	jmp	cgrm7

;==== special func 0f - write debug registers

assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f0f:
	push	eax
	push	esi
	push	edi
	call	adrpage 		; ds -> driver data, es -> page table
	assume	ds:mmgrp,es:nothing
	call	nloaddb			; native mode load debug registers
	mov	[ntrash1],eax

	pop	edi
	pop	esi
	pop	eax
	jmp	cgrm7

;==== dpmi func 86 - convert real-mode segment to selector
;
; This is what _DPMI.ASM's SegToSel needs (and, through it, DPMI
; function 0002h "Segment to Descriptor").  The hard part already
; existed: makegdte takes a real-mode segment in ax, an owning task id
; in dh and an access-rights byte in dl, reuses an existing descriptor
; when one already maps the same base for the same task, otherwise
; allocates a free slot from gdtspace/dtitable (30 user selectors), and
; returns a selector with rpl=3 -- or ax=0 when the table is full.
; Descriptor reuse on an identical base is exactly the DPMI 0002h
; semantic, so this handler is only plumbing.
;
; in:	caller's bx = real-mode segment (saved at [bp-16] by eicommon)
; out:	caller's bx = selector, cf clear
;	cf set if no descriptor could be allocated
;
; NOTE: descriptors are tagged with the current task id, and nmswitch
; calls cleardti for a task on every native-mode switch, which frees
; every descriptor that task owns.  A DPMI client's selectors will not
; survive that.  Not addressed here -- flagged in the addendum.
;
assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
;==== dpmi func 8f - release this task's client descriptors
;
; Frees every gdt entry tagged 80h|taskid for the calling task --
; the ones 8eh handed a DPMI client. Called from the driver's
; Unregister path at task termination, because cleardti will not:
; tagged entries are deliberately exempt from the per-switch sweep
; so a client keeps its selectors across switches.
;
;
;==== dpmi func 90 - set the DPMI task reserve
;
; bx = pages of extended memory DPMI must leave for task creation.
; Set once by $DPMI.SYS at install from its /R:nnnn parameter;
; int 31h 0500h reports free memory minus this, never below 0.
;
e6f90:
	db	66h
	db	67h
	mov	ax,[bp-16]		; caller's bx = reserve, pages
	mov	word ptr ss:[dpmirsv],ax
	and	byte ptr ss:[s0flags],0feh   ; cf clear
	jmp	cgrm7

;
; nca field offsets as plain constants: MASM will not address the nca
; segment's labels through ds/ss in use32 code (A2068)
;
N_ncabufsz	=	06Ch			; offset nca:ncabufsz, from the listing
N_ncancs	=	03Ch			; offset nca:ncancs, from the listing
N_ncands	=	02Ch			; offset nca:ncands, from the listing
N_ncanes	=	028h			; offset nca:ncanes, from the listing
N_ncanflag	=	040h			; offset nca:ncanflag, from the listing
N_ncanfs	=	030h			; offset nca:ncanfs, from the listing
N_ncangs	=	034h			; offset nca:ncangs, from the listing
N_ncanip	=	038h			; offset nca:ncanip, from the listing
N_ncansp	=	044h			; offset nca:ncansp, from the listing
N_ncanss	=	048h			; offset nca:ncanss, from the listing
N_ncavax	=	010h			; offset nca:ncavax, from the listing
N_ncavbp	=	024h			; offset nca:ncavbp, from the listing
N_ncavbx	=	014h			; offset nca:ncavbx, from the listing
N_ncavcx	=	018h			; offset nca:ncavcx, from the listing
N_ncavdi	=	004h			; offset nca:ncavdi, from the listing
N_ncavds	=	020h			; offset nca:ncavds, from the listing
N_ncavdx	=	00Ch			; offset nca:ncavdx, from the listing
N_ncaves	=	01Ch			; offset nca:ncaves, from the listing
N_ncavflag	=	000h			; offset nca:ncavflag, from the listing
N_ncavsi	=	008h			; offset nca:ncavsi, from the listing

;
;==== dpmi func 91 - a real-mode callback fired (UPDATE 60)
;
; Reached from a dcbstub in v-86 (push ax / mov ax,7791h / push idx /
; int 6fh), i.e. from INSIDE an excursion the monitor started for this
; task (NCA1). Saves the whole outer v-86 state in the callback's
; record, fills the client's real-mode call structure, points the
; task's nca at NCA2 (so everything the callback does -- including its
; own DOS calls -- uses NCA2 and leaves NCA1 alone) and enters the
; client's protected-mode procedure through einback, with
; ds:(e)si = the real-mode stack, es:(e)di = the structure, and an
; iret frame on its stack that leads to the int 0E9h stub (e6fcbret).
;
; On entry: [esp] = ebx ecx es ds ebp (eicommon), then the 9-dword
; v-86 frame s0ip..s0gs; eax edx esi edi live in the CPU.
;
e6f91:
	mov	dword ptr ss:[cbr_ptr],offset mmgrp:e6fcbret
	mov	ss:[cbeax],eax		; the stub left ax = 7791h, high word ours
	mov	ss:[cbedx],edx
	mov	ss:[cbesi],esi
	mov	ss:[cbedi],edi
	mov	ax,gdtzero-gdt		; flat ds
	mov	ds,ax
	movzx	edi,word ptr ss:[s0ss]	; the v-86 stack: idx, then the caller's ax
	shl	edi,4
	movzx	eax,word ptr ss:[s0sp]
	add	edi,eax
	movzx	ecx,byte ptr [edi]
	cmp	ecx,DCBN
	jae	e6f91x
	imul	ecx,ecx,DCBSZ		; ecx = record offset
	cmp	byte ptr ss:[ecx+dcbtab],1
	jne	e6f91x
	mov	ax,[edi+2]		; the caller's own ax
	mov	word ptr ss:[cbeax],ax

; the outer state into the record: s0 frame (sp without the two
; pushes), then eax..ebp

	mov	esi,offset mmgrp:s0ip
	xor	edx,edx
e6f91s:
	mov	eax,ss:[esi+edx*4]
	mov	dword ptr ss:[ecx+dcbtab+16+edx*4],eax
	inc	edx
	cmp	edx,9
	jb	e6f91s
	add	word ptr ss:[ecx+dcbtab+16+12],4	; s0sp: idx and ax dropped
	mov	eax,ss:[cbeax]
	mov	dword ptr ss:[ecx+dcbtab+52],eax
	mov	eax,[esp]		; ebx
	mov	dword ptr ss:[ecx+dcbtab+56],eax
	mov	eax,[esp+4]		; ecx
	mov	dword ptr ss:[ecx+dcbtab+60],eax
	mov	eax,ss:[cbedx]
	mov	dword ptr ss:[ecx+dcbtab+64],eax
	mov	eax,ss:[cbesi]
	mov	dword ptr ss:[ecx+dcbtab+68],eax
	mov	eax,ss:[cbedi]
	mov	dword ptr ss:[ecx+dcbtab+72],eax
	mov	eax,[esp+16]		; ebp
	mov	dword ptr ss:[ecx+dcbtab+76],eax

; the client's structure gets the real-mode registers

	movzx	esi,word ptr ss:[ecx+dcbtab+10]
	and	esi,0fff8h
	mov	edi,dword ptr ss:[esi+gdt+2]
	and	edi,00ffffffh
	mov	al,byte ptr ss:[esi+gdt+7]
	shl	eax,24
	or	edi,eax
	add	edi,dword ptr ss:[ecx+dcbtab+12]	; edi = structure, linear
	mov	eax,dword ptr ss:[ecx+dcbtab+72]
	mov	[edi+00h],eax		; EDI
	mov	eax,dword ptr ss:[ecx+dcbtab+68]
	mov	[edi+04h],eax		; ESI
	mov	eax,dword ptr ss:[ecx+dcbtab+76]
	mov	[edi+08h],eax		; EBP
	mov	dword ptr [edi+0ch],0
	mov	eax,dword ptr ss:[ecx+dcbtab+56]
	mov	[edi+10h],eax		; EBX
	mov	eax,dword ptr ss:[ecx+dcbtab+64]
	mov	[edi+14h],eax		; EDX
	mov	eax,dword ptr ss:[ecx+dcbtab+60]
	mov	[edi+18h],eax		; ECX
	mov	eax,dword ptr ss:[ecx+dcbtab+52]
	mov	[edi+1ch],eax		; EAX
	mov	ax,word ptr ss:[ecx+dcbtab+24]
	mov	[edi+20h],ax		; FLAGS
	mov	ax,word ptr ss:[ecx+dcbtab+36]
	mov	[edi+22h],ax		; ES
	mov	ax,word ptr ss:[ecx+dcbtab+40]
	mov	[edi+24h],ax		; DS
	mov	ax,word ptr ss:[ecx+dcbtab+44]
	mov	[edi+26h],ax		; FS
	mov	ax,word ptr ss:[ecx+dcbtab+48]
	mov	[edi+28h],ax		; GS
	mov	ax,word ptr ss:[ecx+dcbtab+16]
	mov	[edi+2ah],ax		; IP
	mov	ax,word ptr ss:[ecx+dcbtab+20]
	mov	[edi+2ch],ax		; CS
	mov	ax,word ptr ss:[ecx+dcbtab+28]
	mov	[edi+2eh],ax		; SP
	mov	ax,word ptr ss:[ecx+dcbtab+32]
	mov	[edi+30h],ax		; SS

; a data selector for the real-mode stack (tagged: freed at exit)

	push	ecx
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb, ebx -> NCA1
	pop	ecx
	push	eax
	call	cidof32			; client id (UPDATE 67)
	mov	dh,al
	pop	eax
	or	dh,80h
	mov	dl,11110010b
	movzx	eax,word ptr ss:[ecx+dcbtab+32]	; real-mode ss
	push	ecx
	push	esi
	push	ebx
	call	dword ptr mmgrp:[mgd_ptr]	; ax = selector
	pop	ebx
	pop	esi
	pop	ecx
	mov	ss:[cbrmsel],ax

; NCA1 -> NCA2: NCA2 = NCA1 + 256 + ncalen + ncabufsz

	mov	ax,[esi+tcbncadr]
	mov	word ptr ss:[ecx+dcbtab+80],ax	; NCA1, for the way back
	mov	edx,[ebx+N_ncabufsz]
	add	edx,256+ncalen
	shr	edx,4
	add	ax,dx
	mov	[esi+tcbncadr],ax
	mov	byte ptr ss:[ecx+dcbtab+2],1	; active
	mov	edi,ebx 		; NCA1
	movzx	ebx,ax
	shl	ebx,4
	add	ebx,256 		; ebx = NCA2, linear

; NCA2's native frame: the procedure, ds:(e)si = real-mode stack,
; es:(e)di = structure, the client's flags with IF clear

	mov	eax,[edi+N_ncanflag]
	and	eax,not 200h
	mov	[ebx+N_ncanflag],eax
	mov	[ebx+N_ncavflag],eax
	mov	eax,dword ptr ss:[ecx+dcbtab+12]
	mov	[ebx+N_ncavdi],eax
	movzx	eax,word ptr ss:[ecx+dcbtab+28]
	mov	[ebx+N_ncavsi],eax
	xor	eax,eax
	mov	[ebx+N_ncavdx],eax
	mov	[ebx+N_ncavax],eax
	mov	[ebx+N_ncavbx],eax
	mov	[ebx+N_ncavcx],eax
	mov	[ebx+N_ncavbp],eax
	mov	[ebx+N_ncaves],eax
	mov	[ebx+N_ncavds],eax
	mov	[ebx+N_ncanfs],eax
	mov	[ebx+N_ncangs],eax
	movzx	eax,word ptr ss:[ecx+dcbtab+10]
	mov	[ebx+N_ncanes],eax
	movzx	eax,word ptr ss:[cbrmsel]
	mov	[ebx+N_ncands],eax
	mov	eax,dword ptr ss:[ecx+dcbtab+4]
	mov	[ebx+N_ncanip],eax
	movzx	eax,word ptr ss:[ecx+dcbtab+8]
	mov	[ebx+N_ncancs],eax

; stack: the client's, 512 bytes below where its outer call left it,
; with an iret frame to stub 484h (int 0E9h) on top

	mov	eax,[edi+N_ncanss]
	mov	[ebx+N_ncanss],eax
	and	eax,0fff8h
	mov	esi,dword ptr ss:[eax+gdt+2]
	and	esi,00ffffffh
	mov	dl,byte ptr ss:[eax+gdt+7]
	shl	edx,24
	or	esi,edx 		; esi = ss base
	movzx	eax,byte ptr ss:[ecx+dcbtab+1]	; procedure frame: by client type
	and	eax,7fh			;  (task id), not the CS D bit (UPDATE 62)
	cmp	byte ptr ss:[eax+c32tab],2
	mov	eax,[edi+N_ncansp]
	je	e6f91f32
	sub	eax,512+6
	and	eax,0ffffh
	mov	[ebx+N_ncansp],eax
	add	esi,eax
	mov	word ptr [esi],484h	; ip
	mov	ax,ss:[stubsel16]
	mov	[esi+2],ax		; cs
	mov	ax,word ptr [ebx+N_ncanflag]
	mov	[esi+4],ax		; flags
	jmp	short e6f91go
e6f91f32:
	sub	eax,512+12
	mov	[ebx+N_ncansp],eax
	add	esi,eax
	mov	dword ptr [esi],484h
	movzx	eax,word ptr ss:[stubsel32]
	mov	[esi+4],eax
	mov	eax,[ebx+N_ncanflag]
	mov	[esi+8],eax
e6f91go:
	jmp	dword ptr mmgrp:[einb_ptr]	; einback: p0stack from NCA2, iret

e6f91x:					; not a live callback: ignore it
	mov	eax,ss:[cbeax]
	mov	edx,ss:[cbedx]
	mov	esi,ss:[cbesi]
	mov	edi,ss:[cbedi]
	or	byte ptr ss:[s0flags],01h	; cf set
	jmp	cgrm7

;
; e6fcbret: the callback procedure returned (iret onto stub 484h,
; int 0E9h, routed here from einvhook). Resume the real-mode caller
; from the structure, give the task NCA1 back, leave via cgrm7 into
; v-86. ds is flat, ebx = NCA2 (einative context, discarded).
;
e6fcbret:
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb
	push	eax
	call	cidof32			; client id (UPDATE 67)
	mov	dl,al
	pop	eax
	xor	ecx,ecx
e6fcbf:
	cmp	byte ptr ss:[ecx+dcbtab],1
	jne	e6fcbn
	cmp	byte ptr ss:[ecx+dcbtab+2],1	; the active one
	jne	e6fcbn
	cmp	byte ptr ss:[ecx+dcbtab+1],dl
	je	e6fcbg
e6fcbn:
	add	ecx,DCBSZ
	cmp	ecx,DCBN*DCBSZ
	jb	e6fcbf
	jmp	cgrm7			; cannot happen
e6fcbg:
	mov	byte ptr ss:[ecx+dcbtab+2],0
	mov	ax,word ptr ss:[ecx+dcbtab+80]
	mov	[esi+tcbncadr],ax	; NCA1 again

	movzx	esi,word ptr ss:[ecx+dcbtab+10]	; structure, linear
	and	esi,0fff8h
	mov	edi,dword ptr ss:[esi+gdt+2]
	and	edi,00ffffffh
	mov	al,byte ptr ss:[esi+gdt+7]
	shl	eax,24
	or	edi,eax
	add	edi,dword ptr ss:[ecx+dcbtab+12]

	movzx	eax,word ptr [edi+2ah]
	mov	dword ptr ss:[s0ip],eax
	movzx	eax,word ptr [edi+2ch]
	mov	dword ptr ss:[s0cs],eax
	mov	eax,dword ptr ss:[ecx+dcbtab+24]	; saved eflags (VM, IOPL)
	mov	ax,[edi+20h]		; with the structure's flags
	mov	dword ptr ss:[s0flags],eax
	movzx	eax,word ptr [edi+2eh]
	mov	dword ptr ss:[s0sp],eax
	movzx	eax,word ptr [edi+30h]
	mov	dword ptr ss:[s0ss],eax
	movzx	eax,word ptr [edi+22h]
	mov	dword ptr ss:[s0es],eax
	movzx	eax,word ptr [edi+24h]
	mov	dword ptr ss:[s0ds],eax
	movzx	eax,word ptr [edi+26h]
	mov	dword ptr ss:[s0fs],eax
	movzx	eax,word ptr [edi+28h]
	mov	dword ptr ss:[s0gs],eax

	mov	esp,offset mmgrp:s0ip	; rebuild what cgrm7 pops
	push	dword ptr [edi+08h]	; ebp
	push	0			; ds
	push	0			; es
	push	dword ptr [edi+18h]	; ecx
	push	dword ptr [edi+10h]	; ebx
	mov	eax,[edi+1ch]
	mov	edx,[edi+14h]
	mov	esi,[edi+04h]
	mov	edi,[edi+00h]
	jmp	cgrm7

;
;==== raw mode switch (int 31h 0306h), UPDATE 61
;
; e6frawpm: protected -> real. The client jumped to stub 488h (int
; 0EAh) with AX = real DS, CX = ES, DX = SS, BX = SP, SI = CS, DI = IP.
; Build the v-86 iret frame from them -- flags as dovmint makes them:
; VM, IOPL 3, the arithmetic flags, NT and IF off (MOS keeps the
; virtual IF) -- abandon the native context and iretd into v-86.
; Reached from einvhook via raw_ptr: ds flat, ebx = the task's nca.
;
e6frawpm:
	movzx	eax,word ptr [ebx+N_ncavdi]
	mov	dword ptr ss:[s0ip],eax
	movzx	eax,word ptr [ebx+N_ncavsi]
	mov	dword ptr ss:[s0cs],eax
	mov	eax,[ebx+N_ncavflag]
	and	eax,0cd5h		; CF PF AF ZF SF DF OF
	or	eax,00023000h		; VM, IOPL 3
	mov	dword ptr ss:[s0flags],eax
	movzx	eax,word ptr [ebx+N_ncavbx]
	mov	dword ptr ss:[s0sp],eax
	movzx	eax,word ptr [ebx+N_ncavdx]
	mov	dword ptr ss:[s0ss],eax
	movzx	eax,word ptr [ebx+N_ncavcx]
	mov	dword ptr ss:[s0es],eax
	movzx	eax,word ptr [ebx+N_ncavax]
	mov	dword ptr ss:[s0ds],eax
	xor	eax,eax
	mov	dword ptr ss:[s0fs],eax
	mov	dword ptr ss:[s0gs],eax
	mov	ebp,[ebx+N_ncavbp]
	mov	eax,[ebx+N_ncavax]
	mov	ecx,[ebx+N_ncavcx]
	mov	edx,[ebx+N_ncavdx]
	mov	esi,[ebx+N_ncavsi]
	mov	edi,[ebx+N_ncavdi]
	mov	ebx,[ebx+N_ncavbx]
	mov	esp,offset mmgrp:s0ip
	iretd

;
;==== dpmi func 92 - real -> protected raw switch (rawstub fired)
;
; rawstub in v-86: push ax / mov ax,7792h / int 6fh, with AX (pushed)
; = DS, CX = ES, DX = SS, (E)BX = (E)SP, SI = CS, (E)DI = (E)IP --
; selectors. CS must be a present dpl-3 code descriptor and SS a
; present dpl-3 writable data descriptor, else CF back into v-86. The
; new native frame goes into the task's nca and einback enters it.
; On entry: [esp] = ebx ecx es ds ebp (eicommon); eax edx esi edi live.
;
e6f92:
	mov	ss:[cbedx],edx
	mov	ss:[cbesi],esi
	mov	ss:[cbedi],edi
	mov	ax,gdtzero-gdt
	mov	ds,ax
	movzx	edi,word ptr ss:[s0ss]	; the pushed ax: the new DS
	shl	edi,4
	movzx	eax,word ptr ss:[s0sp]
	add	edi,eax
	movzx	eax,word ptr [edi]
	mov	ss:[cbeax],eax
	movzx	eax,word ptr ss:[cbesi]	; CS: present dpl-3 code?
	and	eax,0fff8h
	cmp	eax,gdtlen
	jae	e6f92x
	mov	al,byte ptr ss:[eax+gdt+5]
	and	al,0f8h
	cmp	al,0f8h
	jne	e6f92x
	movzx	eax,word ptr ss:[cbedx]	; SS: present dpl-3 writable data?
	and	eax,0fff8h
	cmp	eax,gdtlen
	jae	e6f92x
	mov	al,byte ptr ss:[eax+gdt+5]
	and	al,0fah
	cmp	al,0f2h
	jne	e6f92x

	call	dword ptr mmgrp:[nca_ptr]	; ebx -> the task's nca
	movzx	eax,word ptr ss:[cbesi]
	mov	[ebx+N_ncancs],eax
	and	eax,0fff8h
	test	byte ptr ss:[eax+gdt+6],40h	; 16-bit target: 16-bit ip/sp
	mov	eax,ss:[cbedi]
	mov	ecx,[esp]		; the caller's (e)bx: the new (e)sp
	jnz	e6f92w
	movzx	eax,ax
	movzx	ecx,cx
e6f92w:
	mov	[ebx+N_ncanip],eax
	mov	[ebx+N_ncansp],ecx
	movzx	eax,word ptr ss:[cbedx]
	mov	[ebx+N_ncanss],eax
	movzx	eax,word ptr ss:[cbeax]
	mov	[ebx+N_ncands],eax
	movzx	eax,word ptr [esp+4]	; the caller's cx: the new ES
	mov	[ebx+N_ncanes],eax
	xor	eax,eax
	mov	[ebx+N_ncanfs],eax
	mov	[ebx+N_ncangs],eax
	mov	eax,dword ptr ss:[s0flags]
	and	eax,0dd5h		; arithmetic flags and DF
	or	eax,3200h		; IOPL 3, IF on
	mov	[ebx+N_ncanflag],eax
	mov	[ebx+N_ncavflag],eax
	mov	eax,ss:[cbeax]		; general registers as the caller left them
	mov	[ebx+N_ncavax],eax
	mov	eax,[esp]
	mov	[ebx+N_ncavbx],eax
	mov	eax,[esp+4]
	mov	[ebx+N_ncavcx],eax
	mov	eax,ss:[cbedx]
	mov	[ebx+N_ncavdx],eax
	mov	eax,ss:[cbesi]
	mov	[ebx+N_ncavsi],eax
	mov	eax,ss:[cbedi]
	mov	[ebx+N_ncavdi],eax
	mov	eax,[esp+16]
	mov	[ebx+N_ncavbp],eax
	jmp	dword ptr mmgrp:[einb_ptr]

e6f92x:					; refused: CF, back to the caller
	mov	eax,ss:[cbeax]		;  with its ax, stub push dropped
	add	word ptr ss:[s0sp],2
	mov	edx,ss:[cbedx]
	mov	esi,ss:[cbesi]
	mov	edi,ss:[cbedi]
	or	byte ptr ss:[s0flags],01h
	jmp	cgrm7

e6f8f:
	call	dpmiclr
	call	cidend			; the task's client id is free (UPDATE 67)
	and	byte ptr ss:[s0flags],0feh   ; cf clear
	jmp	cgrm7

;
; dpmiclr: release everything tagged for the calling task -- client
; descriptors (freeclsel via fcs_ptr), DPMI memory blocks (nrelease)
; and protected-mode interrupt/exception hooks. Preserves all
; registers. Called at the driver's Unregister (e6f8f) AND at the
; start of every DPMI session (e6f8e, CODE_SELECTOR, which GoProtect
; calls before the switch): a task runs one client at a time, so
; anything still tagged then belongs to a dead predecessor that ended
; without int 21h ah=4Ch -- default exception handler, Ctrl-C,
; critical-error abort, int 20h (UPDATE 57).
;
dpmiclr:
	call	envrest			; PSP:2Ch back to a segment (UPDATE 63)
	;
	; No client type recorded until the next session's e6f8e (UPDATE 62)
	;
	push	eax
	push	ebx
	push	esi
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	call	cidof32			; eax = client id (UPDATE 67)
	and	eax,7fh
	mov	byte ptr ss:[eax+c32tab],0
	pop	esi
	pop	ebx
	pop	eax
	call	dword ptr mmgrp:[fcs_ptr]	; use32 -> use16 wrapper
;
; Also release this task's DPMI memory blocks (UPDATE 44). This path
; runs from v-86 (the driver's Unregister), where dovmint is not
; available, but the release itself is monitor code: e6f06, behind
; memman's vrelease, is just adrpage + nrelease, and both live here in
; the use32 int 6fh region, so they are called directly. The task id
; is read before adrpage moves ds.
;
; int 6fh handlers preserve the caller's registers (cf e6f8e); this
; loop uses all of them and adrpage moves ds/es, so save everything
; -- without it the caller got garbage back (UPDATE 44).
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
	push	edi
	push	ds
	push	es
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	push	eax
	call	cidof32			; client id (UPDATE 67)
	mov	dl,al
	pop	eax
	xor	edi,edi
e6f8flp:
	cmp	byte ptr ss:[edi+dblktab],1
	jne	e6f8fnx
	cmp	byte ptr ss:[edi+dblktab+1],dl
	jne	e6f8fnx
	mov	byte ptr ss:[edi+dblktab],0
	mov	eax,dword ptr ss:[edi+dblktab+4]
	movzx	ecx,ax			; pages
	shr	eax,16
	movzx	ebx,ax			; start bank
	push	edi
	push	edx
	call	adrpage 		; ds -> gdtdata, es -> gdtpage
	call	nrelease
	pop	edx
	pop	edi
e6f8fnx:
	add	edi,8
	cmp	edi,DBLKN*8
	jb	e6f8flp
	cmp	byte ptr ss:[hookok],0	; UPDATE 73: no table yet, no hooks
	je	e6f8fhx
	push	gs
	push	eax
	mov	ax,gdthook-gdt
	mov	gs,ax
	pop	eax
	xor	edi,edi			; and the task's pm interrupt hooks
e6f8fh:
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [edi+phooktab],1
	jne	e6f8fhn
	db	65h			; gs: (UPDATE 73)
	cmp	byte ptr [edi+phooktab+1],dl
	jne	e6f8fhn
	db	65h			; gs: (UPDATE 73)
	mov	byte ptr [edi+phooktab],0
e6f8fhn:
	add	edi,12
	cmp	edi,DPHKN*12
	jb	e6f8fh
	pop	gs
e6f8fhx:
	xor	edi,edi			; and the task's real-mode callbacks
e6f8fc:
	cmp	byte ptr ss:[edi+dcbtab],1
	jne	e6f8fcn
	cmp	byte ptr ss:[edi+dcbtab+1],dl
	jne	e6f8fcn
	mov	byte ptr ss:[edi+dcbtab],0
e6f8fcn:
	add	edi,DCBSZ
	cmp	edi,DCBN*DCBSZ
	jb	e6f8fc
	pop	es
	pop	ds
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret


;==== dpmi func 8e - code selector for a real-mode segment
;
; As 86h, but the descriptor is executable+readable rather than
; data. A DPMI client must resume at a code selector for its own
; code; nmswitch only ever builds one for whatever was running at
; switch time, which is the host, and 86h builds data descriptors.
;
; makegdte compares the access byte as well as the base, so this
; does not collide with the data alias of the same segment.
;
; in:	caller's bx = real-mode segment (saved at [bp-16])
; out:	caller's bx = selector, cf clear; cf set if the table is full
;
e6f8e:
	mov	dword ptr ss:[cbr_ptr],offset mmgrp:e6fcbret	; use16 -> use32 targets:
	mov	dword ptr ss:[raw_ptr],offset mmgrp:e6frawpm	;  set before any client runs
	call	hookinit		; UPDATE 73: the hook table, once
	mov	dword ptr ss:[stbptr],offset mmgrp:stbget	; UPDATE 71: group offset
	mov	dword ptr ss:[nlgptr],offset mmgrp:nlargest	; UPDATE 72: for 0500h
	mov	dword ptr ss:[phyptr],offset mmgrp:e31phys	; UPDATE 81: for 0800h
	call	cidstart		; a new session: nest under a live parent,
					;  or drop a dead predecessor (UPDATE 67)
	push	eax
	push	edx
	push	esi
	push	edi
	db	66h
	db	67h
	mov	ax,[bp-16]		; caller's bx = segment to translate
	push	eax
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	push	eax
	call	cidof32			; client id (UPDATE 67)
	mov	dh,al
	pop	eax
	;
	; Tag client descriptors 80h|taskid. cleardti matches the plain
	; task id, so tagged entries survive the per-switch sweep: a
	; client that switches, returns and switches again keeps its
	; selectors, and descriptors the task made for other reasons are
	; no longer collateral. 8fh releases them at termination.
	; (Assumes task ids stay below 80h.)
	;
	or	dh,80h
	pop	eax			; ax = segment again
	mov	dl,11111010b		; p=1,dpl=3,s=1,type=101 code r/x
	call	dword ptr mmgrp:[mgd_ptr]	; ax = selector, 0 = table full
	or	ax,ax
	jz	e6f8ef
	;
	; DPMI 0.9 5.2: a client resumes on a 16-bit CS with a 64K limit,
	; 32-bit clients included -- only the interrupt and exception frames
	; follow the client type (UPDATE 62). makegdte hardcodes 00c0h
	; (g=1,d=1): clear g and d, keep the byte limit makegdte set.
	;
	push	di
	mov	di,ax
	and	di,0fff8h
	db	67h
	and	byte ptr ss:[di+gdt+6],0fh   ; g=0,d=0, keep limit 19:16
	pop	di
	;
	; Record the client type for this task in c32tab (1 = 16-bit,
	; 2 = 32-bit, from the caller's cl = the client's ax at the entry
	; call). c32edx/c32eax read it instead of the D bit of the
	; interrupted CS, which says nothing about the client type now.
	;
	push	eax
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	push	eax
	call	cidof32			; client id (UPDATE 67)
	mov	edi,eax
	pop	eax
	and	edi,7fh
	db	66h
	db	67h
	mov	cx,[bp-12]		; caller's cx
	mov	al,1
	or	cl,cl
	jz	e6f8e16
	mov	al,2
e6f8e16:
	mov	byte ptr ss:[edi+c32tab],al
	pop	eax
	db	66h
	db	67h
	mov	[bp-16],ax		; hand the selector back in caller's bx
	and	byte ptr ss:[s0flags],0feh   ; cf clear = success
	jmp	short e6f8ex
e6f8ef:
	or	byte ptr ss:[s0flags],1      ; cf set = failure
e6f8ex:
	pop	edi
	pop	esi
	pop	edx
	pop	eax
	jmp	cgrm7

;==== dpmi func 93 - CLIENT_PSP: PSP and environment selectors (UPDATE 63)
;
; DPMI 0.9 5.2: after the mode switch ES is a selector for the PSP
; with a 100h limit, and the environment segment in PSP:2Ch has been
; replaced by a selector. GoProtect calls this before the switch.
;
; Both descriptors are data r/w dpl 3, byte-granular, 16-bit, tagged
; 80h|taskid (freed at the client's 4Ch like every client selector).
; The environment limit comes from its MCB ('M'/'Z', size at +3);
; FFFFh if that does not look like an MCB. The original segment is
; kept in envtab and put back by envr16 (int 21h 4Ch, einfun4c) or
; envrest (dpmiclr): DOS frees the environment through PSP:2Ch.
;
; in:	caller's bx = PSP segment
; out:	caller's bx = PSP selector, caller's cx = environment selector
;	(0 if PSP:2Ch was 0), cf clear
;	cf set if the table is full; PSP:2Ch is then unchanged
;
e6f93:
	push	eax
	push	edx
	push	esi
	push	edi
	push	fs
	mov	ax,gdtzero-gdt		; flat
	mov	fs,ax
	db	66h
	db	67h
	mov	ax,[bp-16]		; caller's bx = PSP segment
	movzx	edi,ax			; edi = PSP segment, kept
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	push	eax
	call	cidof32			; client id (UPDATE 67)
	mov	dh,al
	pop	eax
	or	dh,80h			; dh = client tag, kept (makegdte reads it)
	mov	eax,edi
	mov	ecx,0ffh		; DPMI 0.9: 100h bytes
	call	e93sel
	or	ax,ax
	jz	e6f93f
	db	66h
	db	67h
	mov	[bp-16],ax		; caller's bx = PSP selector
	mov	ebx,edi
	shl	ebx,4			; ebx = PSP, linear
	movzx	eax,word ptr fs:[ebx+2ch]	; environment segment
	xor	esi,esi			; environment selector: none yet
	or	eax,eax
	jz	e6f93n
	mov	ecx,0ffffh		; limit if there is no usable MCB
	push	eax
	dec	eax
	shl	eax,4			; its MCB, linear
	mov	dl,fs:[eax]
	cmp	dl,'M'
	je	e6f93m
	cmp	dl,'Z'
	jne	e6f93d
e6f93m:
	movzx	esi,word ptr fs:[eax+3]	; size in paragraphs
	or	esi,esi
	jz	e6f93d
	cmp	esi,1000h
	jae	e6f93d
	shl	esi,4
	dec	esi
	mov	ecx,esi
e6f93d:
	pop	eax			; environment segment
	push	eax
	call	e93sel
	movzx	esi,ax			; environment selector
	pop	eax
	or	esi,esi
	jz	e6f93f			; table full: PSP:2Ch untouched
	mov	word ptr fs:[ebx+2ch],si	; PSP:2Ch = selector
	shl	eax,16
	or	eax,edi			; env<<16 | PSP
	push	esi
	push	eax
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	call	cidof32			; eax = client id (UPDATE 67)
	and	eax,7fh
	pop	dword ptr ss:[eax*4+envtab]
	pop	esi
e6f93n:
	mov	eax,esi
	db	66h
	db	67h
	mov	[bp-12],ax		; caller's cx = environment selector
	and	byte ptr ss:[s0flags],0feh   ; cf clear = success
	jmp	short e6f93x
e6f93f:
	or	byte ptr ss:[s0flags],1      ; cf set = failure
e6f93x:
	pop	fs
	pop	edi
	pop	esi
	pop	edx
	pop	eax
	jmp	cgrm7

;
; e93sel: data selector for segment eax, byte limit ecx, tag dh.
; out: ax = selector, 0 if the table is full. Keeps ecx, edx, esi, edi.
;
e93sel:
	push	ecx
	push	esi
	push	edi
	mov	dl,11110011b		; p=1,dpl=3,s=1,data r/w, accessed (UPDATE 82:
					;  makegdte reuses only F3h entries now; was
					;  F2h, patched to F3h afterwards, UPDATE 78)
	call	dword ptr mmgrp:[mgd_ptr]	; ax = selector, 0 = table full
	pop	edi
	pop	esi
	pop	ecx
	or	ax,ax
	jz	e93sx
	push	ebx
	movzx	ebx,ax
	and	ebx,0fff8h
	mov	word ptr ss:[ebx+gdt],cx	; limit 15:0
	mov	byte ptr ss:[ebx+gdt+6],0	; g=0,d=0, limit 19:16 = 0
	pop	ebx
e93sx:
	ret

;
; envrest: put this task's environment segment back into PSP:2Ch if
; e6f93 replaced it and no 4Ch has done so yet (UPDATE 63). Called by
; dpmiclr. Preserves all registers.
;
envrest:
	push	eax
	push	ebx
	push	esi
	push	fs
	mov	ax,gdtzero-gdt		; flat
	mov	fs,ax
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	call	cidof32			; eax = client id (UPDATE 67)
	and	eax,7fh
	mov	ebx,dword ptr ss:[eax*4+envtab]
	test	ebx,0ffff0000h
	jz	envrx
	mov	dword ptr ss:[eax*4+envtab],0
	movzx	esi,bx			; PSP segment
	shl	esi,4
	shr	ebx,16			; environment segment
	mov	word ptr fs:[esi+2ch],bx
envrx:
	pop	fs
	pop	esi
	pop	ebx
	pop	eax
	ret


;
; UPDATE 67: client ids. A DPMI session gets its own id (1..127) at
; the switch (cidnew, from e6f8e); descriptors, memory blocks, hooks,
; callbacks, c32tab and envtab are owned by it, not by the task.
; curcid[task id] = the task's current client id (0: none);
; cidtask[client id] = owner task id + 1 (0: free).
;
; cidof32: eax = client id of the task whose tcb esi points to.
;
cidof32:
	movzx	eax,byte ptr [esi+tcbid]
	and	eax,7fh
	movzx	eax,byte ptr ss:[eax+curcid]
	ret
;
; cidnew: the calling task gets a fresh client id. Its previous one
; (a dead predecessor: dpmiclr has just released its resources) is
; freed. Step 1 keeps one client per task. Preserves all registers.
; No free id: curcid = 0 (the session runs untagged, as a task
; without DPMI).
;
cidnew:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	movzx	edx,byte ptr [esi+tcbid]
	and	edx,7fh			; task id
	movzx	eax,byte ptr ss:[edx+curcid]
	mov	byte ptr ss:[eax+cidtask],0	; the old id is free (0: harmless)
	mov	ecx,1
cidnlp:
	cmp	byte ptr ss:[ecx+cidtask],0
	je	cidngot
	inc	ecx
	cmp	ecx,128
	jb	cidnlp
	xor	ecx,ecx			; none free
	jmp	short cidnset
cidngot:
	mov	eax,edx
	inc	eax
	mov	byte ptr ss:[ecx+cidtask],al	; owner task + 1
cidnset:
	mov	byte ptr ss:[edx+curcid],cl
	mov	byte ptr ss:[cidtask],0		; id 0 is never in use
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret
;
; cidend: the calling task's client id is released and it has none.
; Preserves all registers.
;
cidend:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	movzx	edx,byte ptr [esi+tcbid]
	and	edx,7fh
	mov	byte ptr ss:[edx+curcid],0
	mov	byte ptr ss:[edx+pendsw],0
	mov	eax,edx
	inc	eax			; owner tag: task id + 1
	mov	ecx,1
celp:
	cmp	byte ptr ss:[ecx+cidtask],al	; every client id of the task
	jne	cenx
	mov	byte ptr ss:[ecx+cidtask],0
cenx:
	inc	ecx
	cmp	ecx,128
	jb	celp
	mov	byte ptr ss:[cidtask],0
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

;
; cidstart: the calling task starts a DPMI session (e6f8e, before the
; switch). If its current client is an ancestor of the new client (its
; PSP is on the new PSP's parent chain, PSP:16h, up to 8 levels --
; system() puts COMMAND.COM in between), the new client NESTS: parent =
; that client, savnca = the task's nca now (nmswitch replaces it).
; Otherwise the current client is dead (no 4Ch): dpmiclr releases its
; resources and the new client inherits its parent. The new client id
; is current, and pendsw tells nmswitch to tag the session's initial
; selectors with it. Preserves all registers. (UPDATE 67)
;
cidstart:
	push	eax
	push	ebx
	push	ecx
	push	edx
	push	esi
	push	edi
	push	fs
	mov	ax,gdtzero-gdt		; flat
	mov	fs,ax
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	movzx	edx,byte ptr [esi+tcbid]
	and	edx,7fh			; task id
	movzx	edi,word ptr [esi+tcbpsp]	; the new client's PSP
	movzx	eax,byte ptr ss:[edx+curcid]	; the task's current client
	xor	ebx,ebx			; parent of the new one
	xor	ecx,ecx			; its savnca
	or	eax,eax
	jz	csalloc
	push	edi
	mov	ecx,8
cswalk:
	shl	edi,4
	movzx	edi,word ptr fs:[edi+16h]	; parent PSP
	or	edi,edi
	jz	csdead
	cmp	di,word ptr ss:[eax*2+cidpsp]
	je	cslive
	loop	cswalk
csdead:
	pop	edi
	call	dpmiclr			; the dead client's resources
	movzx	ebx,byte ptr ss:[eax+parcid]	; inherit its parent
	movzx	ecx,word ptr ss:[eax*2+savnca]
	mov	byte ptr ss:[eax+cidtask],0
	jmp	short csalloc
cslive:
	pop	edi
	mov	ebx,eax			; nest under it
	movzx	ecx,word ptr [esi+tcbncadr]	; its nca, still current
csalloc:
	mov	esi,ecx			; savnca (the tcb is not needed now)
	mov	ecx,1
cslp:
	cmp	byte ptr ss:[ecx+cidtask],0
	je	csgot
	inc	ecx
	cmp	ecx,128
	jb	cslp
	xor	ecx,ecx			; none free: untagged session
	jmp	csset
csgot:
	mov	eax,edx
	inc	eax
	mov	byte ptr ss:[ecx+cidtask],al	; owner task + 1
	mov	byte ptr ss:[ecx+parcid],bl
	mov	word ptr ss:[ecx*2+savnca],si
	mov	word ptr ss:[ecx*2+cidpsp],di
	cmp	byte ptr ss:[hookok],0	; UPDATE 74: a fresh hook bitmap
	je	csnobm			;  for this client id
	push	es
	push	edi
	push	eax
	push	ecx
	mov	edi,ecx
	shl	edi,5
	add	edi,dword ptr ss:[hooklin]
	add	edi,DPHKN*12
	mov	ax,gdtzero-gdt
	mov	es,ax
	xor	eax,eax
	mov	ecx,8			; 32 bytes
	cld
	rep	stosd
	pop	ecx
	mov	edi,ecx			; UPDATE 80: and no DTA for this id:
	shl	edi,3			;  8 bytes at gs:[4000h + id*8]
	add	edi,dword ptr ss:[hooklin]
	add	edi,DPHKN*12+1000h
	stosd				; eax is still 0
	stosd
	mov	edi,ecx			; UPDATE 85: and no exception hooked:
	shl	edi,2			;  4 bytes at gs:[4400h + id*4]
	add	edi,dword ptr ss:[hooklin]
	add	edi,DPHKN*12+1400h
	stosd
	pop	eax
	pop	edi
	pop	es
csnobm:
csset:
	mov	byte ptr ss:[edx+curcid],cl
	mov	byte ptr ss:[edx+pendsw],cl
	mov	byte ptr ss:[cidtask],0
	pop	fs
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	pop	eax
	ret

e6f86:
	push	eax
	push	edx
	push	esi
	push	edi
	db	66h
	db	67h
	mov	ax,[bp-16]		; caller's bx = segment to translate
	push	eax
	call	dword ptr mmgrp:[nca_ptr]	; esi -> tcb (clobbers ebx, si)
	db	8ah,01110110b		; mov dh,[esi+tcbid] get task id in dh
	;	  01...110		; disp=byte,base=esi
	db	tcbid
	pop	eax			; ax = segment again
	mov	dl,11110010b		; p=1,dpl=3,s=1,type=001,a=0
	call	dword ptr mmgrp:[mgd_ptr]	; ax = selector, 0 = table full
	or	ax,ax
	jz	e6f86f
	db	66h
	db	67h
	mov	[bp-16],ax		; hand the selector back in caller's bx
	and	byte ptr ss:[s0flags],0feh   ; cf clear = success
	jmp	short e6f86x
e6f86f:
	or	byte ptr ss:[s0flags],1      ; cf set = failure
e6f86x:
	pop	edi
	pop	esi
	pop	edx
	pop	eax
	jmp	cgrm7

;==== dpmi func 87 - convert selector back to real-mode segment
;
; Inverse of the above, for _DPMI.ASM's SelToSeg.  Reads the descriptor
; base straight out of the gdt and shifts it down.  Only meaningful for
; a segment whose base is para-aligned and below 1Mb, which is true of
; anything func 86 produced.
;
; in:	caller's bx = selector
; out:	caller's bx = real-mode segment, cf clear
;	cf set if the selector is outside the gdt
;
assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6f87:
	push	eax
	push	edx
	push	edi
	db	66h
	db	67h
	mov	ax,[bp-16]		; caller's bx = selector
	and	al,0f8h 		; strip rpl / ti
	movzx	edi,ax
	cmp	edi,gdtlen		; inside the gdt?
	jae	e6f87f			; no, refuse
	movzx	eax,word ptr ss:[edi+gdt+2]	; base bits 0-15
	movzx	edx,byte ptr ss:[edi+gdt+4]	; base bits 16-23
	shl	edx,16
	or	eax,edx
	shr	eax,4			; linear base -> real-mode segment
	db	66h
	db	67h
	mov	[bp-16],ax
	and	byte ptr ss:[s0flags],0feh   ; cf clear = success
	jmp	short e6f87x
e6f87f:
	or	byte ptr ss:[s0flags],1      ; cf set = failure
e6f87x:
	pop	edi
	pop	edx
	pop	eax
	jmp	cgrm7

;==== dpmi block - not yet implemented
;
; Everything in the 7780h block except 86h/87h lands here.  Returning
; with cf set makes _DPMI.ASM take its documented error path instead of
; being reflected to the real-mode int 6fh vector, which is what used
; to take DOSBox down with it.  Failing cleanly is the point.
;
assume	cs:mmgrp,ds:nothing,es:nothing,ss:nothing,fs:nothing,gs:nothing
e6funimp:
	or	byte ptr ss:[s0flags],1      ; cf set = not supported
	jmp	cgrm7

cgrm7:
	pop	ebx
	pop	ecx
	pop	es
	pop	ds
	pop	ebp
	mov	sp,offset mmgrp:s0ip
	iretd


;-------------------------------------------------------------------
; nreaddb - native mode read debug registers
; Input:
;	ds -> gdtdata
;	es -> gdtpage
;-------------------------------------------------------------------
	assume	ds:mmgrp,es:nothing

nreaddb:
	mov	eax,dr0		; get debug register 0
	mov	[debugregs],eax
	mov	eax,dr1	        ; get debug register 1
	mov	[debugregs+4],eax		
	mov	eax,dr2		; get debug register 2
	mov	[debugregs+8],eax
	mov	eax,dr3	        ; get debug register 3
	mov	[debugregs+12],eax		
	mov	eax,dr6		; get debug register 6
	mov	[debugregs+24],eax
	mov	eax,dr7	        ; get debug register 7
	mov	[debugregs+28],eax		
	xor	eax,eax	
	ret


;-------------------------------------------------------------------
; nloaddb - native mode load debug registers
; Input:
;	ds -> gdtdata
;	es -> gdtpage
;-------------------------------------------------------------------
	assume	ds:mmgrp,es:nothing

nloaddb:
	mov	eax,[debugregs]
	mov	dr0,eax	        ; load debug register 0
	mov	eax,[debugregs+4]		
	mov	dr1,eax		; load debug register 1
	mov	eax,[debugregs+8]
	mov	dr2,eax	        ; load debug register 2
	mov	eax,[debugregs+12]
	mov	dr3,eax		; load debug register 3
	mov     eax,[debugregs+24]
	mov	dr6,eax	        ; load debug register 6
	mov	eax,[debugregs+28]
	mov	dr7,eax		; load debug register 7
	xor	eax,eax	
	ret




;======================================================================
;,fs
; flushtlb
;
; flush the tlb to validate a page table change.
; also, while we're at privilege level 0, clear the task-switched flag
; so that use of the 80287 won't generate int7; it is actually
; required only once but this is an easy place to do it.
;
; in:	none
;
; out:	none
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing
flushtlb:
	push	eax
	mov	eax,cr3
	mov	cr3,eax
	clts
	pop	eax
	ret

;======================================================================
;,fs
; adrpage
;
; initialize the ds and es segment selector registers
;
; in:	none
;
; out:	ds -> gdtdata
;	es -> gdtpage
;
;,fe
;======================================================================
	assume	ds:nothing,es:nothing,ss:nothing
adrpage:
	push	ax
	mov	ax,gdtdata-gdt		; ds -> this driver's data
	mov	ds,ax
	assume	ds:mmgrp
	mov	ax,gdtpage-gdt		; es -> page table
	mov	es,ax
	assume	es:nothing
	pop	ax
	ret

;======================================================================
;,fs
; nalloc
; 
; allocate a block of extended memory
;
; in:	ecx = number of banks desired
;	ds -> gdtdata
;	es -> gdtpage
;
; out:	eax = 0 if successful, 1 if less allocated than requested
;	ebx = starting bank number
;	ecx = actual number of banks allocated
;	other registers are preserved
;
;,fe
;======================================================================
	assume	ds:mmgrp,es:nothing
;
; stbget (UPDATE 71): two pages of extended memory for the default
; stubs, straight from the memory manager (nalloc, as int 6Fh 7705h
; does) -- no MEMDEV: e31stubs is a nested call and dovmint would
; reset the monitor stack under it. Banks are mapped at linear
; (bank + 110h) << 12. Out: eax = linear, cf = 1 if none.
; Preserves all but eax. Reached from res16 through stbptr.
;
;
; nlargest (UPDATE 72, for 0500h): a read-only pass over the page map
; from nhint (everything below it is in use). Out: eax = the longest
; run of free pages, ecx = free pages in total (parsize/4 - parmused).
; Nothing is allocated or marked -- the old "valloc everything" probe
; walked and marked all free memory twice. Preserves all but eax, ecx.
; Reached from res16 through nlgptr.
;
nlargest:
	push	ds
	push	es
	push	ebx
	push	edx
	call	adrpage			; ds -> driver data, es -> page table
	mov	ebx,[nhint]
	xor	eax,eax			; longest run so far
	xor	edx,edx			; current run
nlg1:
	cmp	ebx,[parsize]
	jae	nlgx
	test	byte ptr es:[nparspace+1+ebx],08h
	jz	nlg2			; in use: the run ends
	inc	edx
	cmp	edx,eax
	jbe	nlg3
	mov	eax,edx
	jmp	short nlg3
nlg2:
	xor	edx,edx
nlg3:
	add	ebx,4
	jmp	short nlg1
nlgx:
	mov	ecx,[parsize]
	shr	ecx,2
	sub	ecx,dword ptr [parmused]
	pop	edx
	pop	ebx
	pop	es
	pop	ds
	ret

;
; hookinit (UPDATE 73): the pm hook table lives in extended memory, not
; in res16 -- 12 KB more for every task. Three pages from nalloc (as
; stbget), zeroed (a free entry is 0), base into gdthook. Once; e6f8e
; calls it before every session start. gs = gdthook is loaded by
; einative after it saved the client's segments, and by dpmiclr around
; its scan. Until hookok is set nothing may touch the table.
; Preserves all registers.
;
hookinit:
	cmp	byte ptr ss:[hookok],0
	jne	hix
	push	eax
	push	ebx
	push	ecx
	push	edi
	push	es
	push	ds
	call	adrpage			; ds -> driver data, es -> page table
	mov	ecx,5			; UPDATE 74: + the hook bitmap, UPDATE 80: + DTAs
	call	nalloc			; eax = 0 ok, ebx = start, ecx = count
	or	eax,eax
	jz	hi1
	jecxz	hiout
	call	nrelease		; a partial block back
	jmp	short hiout
hi1:
	lea	eax,[ebx+110h]
	shl	eax,12			; linear
	push	eax
	mov	edi,eax
	mov	ax,gdtzero-gdt		; flat
	mov	es,ax
	xor	eax,eax
	mov	ecx,(DPHKN*12+2000h)/4
	cld
	rep	stosd			; every entry free
	pop	eax
	mov	dword ptr ss:[hooklin],eax	; UPDATE 74: for cidstart
	mov	word ptr ss:[gdthook+2],ax
	shr	eax,16
	mov	byte ptr ss:[gdthook+4],al
	mov	byte ptr ss:[gdthook+7],ah
	mov	byte ptr ss:[hookok],1
hiout:
	pop	ds
	pop	es
	pop	edi
	pop	ecx
	pop	ebx
	pop	eax
hix:
	ret


;
; e31phys (UPDATE 81): int 31h 0800h, physical address mapping.
;
; Maps a physical range at the SAME linear address (identity), above
; everything this memory manager uses: the range's page-directory
; entries must all lie at or above pt_pages, so RAM's linear space is
; never touched. A frame buffer near E0000000h lands far above it.
;
; Page tables for the range come from nalloc (one bank each), are
; zeroed, and entered in the page directory. The page directory is the
; physical page below the page table, so it is reached at gdtpage's
; base - 1000h (the parspace maps extended memory contiguously).
; phytab/phylin remember the PDE indices made here and their page
; tables' linear addresses (PHYN of them), so a second mapping in the
; same 4 MB reuses its page table. A present PDE not in phytab is
; uninitialised directory memory and is overwritten.
;
; PTEs: present, writable, user, cache disabled + write-through (PCD,
; PWT), as for memory-mapped I/O. Mappings stay (0.9 has no 0801h).
;
; In:	eax = physical address, ecx = size in bytes
; Out:	cf = 0: eax = linear address
;	cf = 1: refused (below 1 MB, size 0, wraps, collides with RAM's
;	linear space, phytab full, no memory for a page table)
; Preserves all registers but eax. Reached from res16 through phyptr.
;
PHYN	equ	16

ephn0:					; refusals from the entry checks: a jcc
	jmp	ephno			;  reaches only +-127 (MASM 5.1)
e31phys:
	push	ebx
	push	ecx
	push	edx
	push	esi
	push	edi
	push	ds
	push	es
	push	fs
	call	adrpage			; ds -> driver data, es -> page table
	mov	dx,gdtzero-gdt		; fs: flat, for the directory and
	mov	fs,dx			;  the new page tables
	cmp	eax,100000h		; nothing below 1 MB
	jb	ephn0
	jecxz	ephn0			; size 0
	lea	edx,[eax+ecx-1]		; last byte
	cmp	edx,eax
	jb	ephn0			; wraps past 4 GB
	mov	esi,eax			; esi = physical start (kept)
	mov	edi,edx			; edi = last byte (kept)
	shr	edx,22			; last PDE index
	mov	ebx,eax
	shr	ebx,22			; first PDE index
	cmp	ebx,dword ptr ss:[pt_pages]	; inside RAM's linear space?
	jb	ephn0

; directory linear = gdtpage base - 1000h

	movzx	ecx,word ptr ss:[gdtpage+2]
	movzx	eax,byte ptr ss:[gdtpage+4]
	shl	eax,16
	or	ecx,eax
	movzx	eax,byte ptr ss:[gdtpage+7]
	shl	eax,24
	or	ecx,eax
	sub	ecx,1000h
	mov	dword ptr ss:[phypd],ecx

; one page table per PDE index ebx .. edx

eph1:
	cmp	ebx,edx
	ja	eph4
	call	ephown			; ours already: ecx = slot
	jnc	eph3
	cmp	dword ptr ss:[phyhwm],PHYN
	jae	ephn0			; table full
	push	edx
	push	ebx
	mov	ecx,1
	call	nalloc			; eax = 0 ok, ebx = bank, ecx = count
	or	eax,eax
	jz	eph2
	jecxz	eph2x
	call	nrelease
eph2x:
	pop	ebx
	pop	edx
	jmp	ephno
eph2:
	lea	eax,[ebx+110h]		; the bank's linear page number
	mov	ecx,es:[eax*4]		; its PTE: the physical frame
	and	ecx,0fffff000h
	shl	eax,12			; the bank's linear address
	pop	ebx			; PDE index
	pop	edx
	push	ecx			; frame
	push	edi
	push	es
	mov	edi,eax			; zero the new page table, flat
	push	eax
	push	fs
	pop	es
	xor	eax,eax
	mov	ecx,1024
	cld
	rep	stosd
	pop	eax			; its linear
	pop	es
	pop	edi
	mov	ecx,dword ptr ss:[phyhwm]	; record index and linear
	mov	dword ptr ss:[phytab+ecx*4],ebx
	mov	dword ptr ss:[phylin+ecx*4],eax
	inc	dword ptr ss:[phyhwm]
	pop	ecx			; frame
	or	ecx,7			; present, writable, user
	mov	eax,dword ptr ss:[phypd]
	mov	fs:[eax+ebx*4],ecx	; the PDE
eph3:					; (already ours: nothing to make)
	inc	ebx
	jmp	eph1

; the PTEs, page by page from the start

eph4:
	call	flushtlb		; the new PDEs
	mov	eax,esi
	and	eax,0fffff000h		; first frame
eph5:
	mov	ebx,eax
	shr	ebx,22
	call	ephown			; ecx = slot (always found here)
	jc	ephno
	mov	ecx,dword ptr ss:[phylin+ecx*4]	; the page table, linear
	mov	ebx,eax
	shr	ebx,12
	and	ebx,3ffh
	mov	edx,eax
	or	edx,1fh			; present, rw, user, PWT, PCD
	mov	fs:[ecx+ebx*4],edx
	add	eax,1000h
	jc	eph6			; wrapped past 4 GB: done
	cmp	eax,edi
	jbe	eph5
eph6:
	call	flushtlb
	mov	eax,esi			; linear = physical
	clc
	jmp	short ephx
ephno:
	stc
ephx:
	pop	fs
	pop	es
	pop	ds
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	pop	ebx
	ret

;
; ephown: PDE index ebx in phytab? cf = 0 and ecx = its slot, else
; cf = 1. Preserves all but ecx.
;
ephown:
	xor	ecx,ecx
epo1:
	cmp	ecx,dword ptr ss:[phyhwm]
	jae	epo2
	cmp	dword ptr ss:[phytab+ecx*4],ebx
	je	epo3
	inc	ecx
	jmp	short epo1
epo2:
	stc
	ret
epo3:
	clc
	ret

phypd	dd	0			; linear of the page directory
phyhwm	dd	0			; slots used in phytab / phylin
phytab	dd	PHYN dup(0)		; PDE indices made by e31phys
phylin	dd	PHYN dup(0)		; their page tables' linear addresses

stbget:
	push	ds
	push	es
	push	ebx
	push	ecx
	call	adrpage			; ds -> driver data, es -> page table
	mov	ecx,2
	call	nalloc			; eax = 0 ok, ebx = start, ecx = count
	or	eax,eax
	jz	stbg1
	jecxz	stbg2			; nothing allocated
	call	nrelease		; a partial block back
stbg2:
	stc
	jmp	short stbgx
stbg1:
	lea	eax,[ebx+110h]
	shl	eax,12
	clc
stbgx:
	pop	ecx
	pop	ebx
	pop	es
	pop	ds
	ret

nalloc:
	push	esi
	mov	ebx,mmgrp:[nhint]	; UPDATE 70: start at the hint, not 0
	mov	dword ptr mmgrp:[nfirst],-1
	xor	eax,eax
	mov	mmgrp:[ntrash1],eax	; tracks position of biggest block
	mov	mmgrp:[ntrash2],eax	; tracks size of biggest block
	mov	mmgrp:[ntrash3],eax	; default return code
nal1:
	xif ebx ae [parsize] else nal3	; check for limit
	mov	mmgrp:[ntrash3],1	; return code for ax
	mov	eax,mmgrp:[ntrash2]	; biggest chunk will have to do
	mov	esi,mmgrp:[ntrash1]
	jmp	short nal2
nal3:
	xif <byte ptr es:[nparspace+1+ebx]> test0 08h else nal4  ; if already alloc, advance
	add	ebx,4
	jmp	short nal1
nal4:
	cmp	dword ptr mmgrp:[nfirst],-1	; UPDATE 70: note the first
	jne	nal4a			;  free entry seen
	mov	mmgrp:[nfirst],ebx
nal4a:
	xor	eax,eax 		; ax counts pages found
	mov	esi,ebx 		; si saves starting index
nal5:
	xif <byte ptr es:[nparspace+1+ebx]> test0 08h then nal6  ; if already alloc, exit loop
	inc	eax
	add	ebx,4			; bump index
	xif eax ae ecx then nal2	; if got enough, exit the big loop
	xif ebx b [parsize] then nal5	; if not past limit, go round again
nal6:
	xif eax na mmgrp:[ntrash2] then nal1  ; if not biggest, go round again
	mov	mmgrp:[ntrash2],eax	; else save size & page number
	mov	mmgrp:[ntrash1],esi
	jmp	nal1
nal2:
	mov	ecx,eax 		; number of banks
	mov	ebx,esi 		; starting bank number
	shr	ebx,2			; convert parspace offset to handle
	or	eax,eax
	jz	short nal7
nal8:
	xor	byte ptr es:[nparspace+1+esi],08h  ; bit 11 off means in use
	add	esi,4
	dec	eax
	jnz	short nal8
	push	edx			; UPDATE 70: advance the hint. esi = end of
	lea	edx,[ebx*4]		;  the run just marked, edx = its start.
	cmp	edx,mmgrp:[nfirst]	; started at the first free entry:
	jne	nalh1			;  everything below its end is in use
	mov	mmgrp:[nhint],esi
	jmp	short nalh2
nalh1:
	mov	edx,mmgrp:[nfirst]	; else the first free entry is still
	mov	mmgrp:[nhint],edx	;  free: the hint goes there
nalh2:
	pop	edx
nal7:
	add	dword ptr [parmused],ecx; keep running tally
	mov	eax,mmgrp:[ntrash3]
	pop	esi
	ret

;======================================================================
;,fs
; nrelease
;
; de-allocate a block of extended memory
;
; in:	ebx = starting bank number to release
;	ecx = number of banks
;	ds -> gdtdata
;	es -> gdtpage
;
; out:	eax = 0 if no errors, 1 if releasing unallocated blocks, or if cx=0
;	ebx,ecx destroyed
;
;,fe
;
;======================================================================
	assume	ds:mmgrp,es:nothing
nrelease:
	mov	eax,1
	or	ecx,ecx
	jz	short nrl1
	shl	ebx,2
	cmp	ebx,mmgrp:[nhint]	; UPDATE 70: freed below the hint:
	jae	nrl0			;  lower it
	mov	mmgrp:[nhint],ebx
nrl0:
nrl2:
	xif <byte ptr es:[nparspace+1+ebx]> test1 08h then nrl1
	or	byte ptr es:[nparspace+1+ebx],08h
	dec	dword ptr [parmused]
	add	ebx,4
	loop	short	nrl2
	xor	eax,eax
nrl1:
	ret

;======================================================================
;,fs
; nremap
; 
; copy parspace entries into meg0 page frames to effect remapping
;
; in:	esi = handle # (parspace entry number)
;	edi = page frame # within 1st meg
;	ecx = # of pages to remap
;	ds -> gdtdata
;	es -> gdtpage
;
; out:	none
;
;,fe
;======================================================================
	assume	ds:mmgrp,es:nothing
nremap:
	push	ecx
	push	esi
	push	edi
	push	ds
	push	es
	pop	ds			; need both es and ds -> page table
	assume	ds:nothing
	shl	edi,2			; derive pointer to meg0 page frame
	shl	esi,2			; derive pointer to parspace entry
	add	esi,nparspace
	cld
	push	esi
	push	edi
	rep	movsd
	pop	edi
	pop	esi

; any remapping to meg0 page0 must be echoed to meg1 page0
; (unless the /C switch was used to reset the feature bit)

	xif <byte ptr [parmfeat+1]> test1 2 && edi == 0 else nrmp1
	mov	edi,4*100h
	movsd
nrmp1:
	pop	ds
	pop	edi
	pop	esi
	pop	ecx
	ret

;======================================================================
;,fs
; nphymap
; 
; do a physical remap
;
; in:	eax = page # to be remapped
;	ebx = page frame # to remap into
;	ecx = number of pages
;	ds -> gdtdata
;	es -> gdtpage
;
; out:	none
;
;,fe
;======================================================================
	assume	ds:mmgrp,es:nothing
nphymap:
	push	eax
	push	ebx

; this next bit of bit flipping is for the sake of the maxspeed series 1
; smart serial board when running on a 20Mhz Compaq 386.  When the high
; bit of the entry page # is set, make the msg within the page table
; entry high.  asserting addresses with this line high will disable
; the compaq's cacheing feature (which conflicts with the maxspeed).

	push	edx
	mov	edx,eax
	and	edx,00008000h		; isolate high bit of entry word
	shl	edx,4
	and	eax,not 00008000h	; erase entry high bit in eax
	or	eax,edx			; bring high bit in new position
	pop	edx
	shl	eax,12			; position page # as pfa
	shl	ebx,2			; convert page # to pte offset
	push	eax
	push	ebx
npm1:
	and	dword ptr es:[ebx],0fffh; mask off existing pfa
	or	es:[ebx],eax		; implant new pfa
	add	eax,1000h		; increment pfa by 1
	add	ebx,4			; advance to next pte
	loop	short npm1
	pop	ebx
	pop	eax

; any remapping to meg0 page0 must be echoed to meg1 page0
; (unless the /C switch was used to reset the feature bit)

	xif <byte ptr [parmfeat+1]> test1 2 && ebx == 0 else npm3
	mov	ebx,4*100h
	and	dword ptr es:[ebx],0fffh; mask off existing pfa
	or	es:[ebx],eax		; implant new pfa
npm3:
	pop	ebx
	pop	eax
	ret

;======================================================================
;,fs
; nprotect
; 
; clear the pl3 write enable bit in the pte
;
; in:	ebx = starting physical bank number, or else starting handle + 110h
;	ecx = number of banks
;	ds -> gdtdata
;	es -> gdtpage
;
; out:	eax = 0 if no errors, ebx and ecx destroyed
;
;,fe
;======================================================================
	assume	ds:mmgrp,es:nothing
nprotect:
	mov	eax,1
	or	ecx,ecx
	jz	short npt1
	shl	ebx,2			; convert page # to table offset
npt2:
	and	byte ptr es:[ebx],0fdh	; clear the pl3 write enable bit
	add	ebx,4
	loop	short npt2

	xor	eax,eax
npt1:
	ret

;======================================================================
;,fs
; nunprot
; 
; set the pl3 write enable bit in the pte
;
; in:	ebx = starting physical bank number, or else starting handle + 110h
;	ecx = number of banks
;	ds -> gdtdata
;	es -> gdtpage
;
; out:	eax = 0 if no errors, ebx and ecx destroyed
;
;,fe
;======================================================================
	assume	ds:mmgrp,es:nothing
nunprot:
	mov	eax,1
	or	ecx,ecx
	jz	short nup1
	shl	ebx,2			; convert page # to table offset
nup2:
	or	byte ptr es:[ebx],2	; set the pl3 write enable bit
	add	ebx,4
	loop	short nup2

	xor	eax,eax
nup1:
	ret

;======================================================================
;,fs
; nlistmap
; 
; process a list of remap, unmap and phymap commands
;
; list record format:
; 
;  +0	action code	word	0 skip, 3 remap, 4 unmap, 5 phymap
;  +2	segment 	word
;  +4	1st bank #	word	(n/a for unmap)
;  +6	1st page count	word
;  +8	2nd bank #	word	** these 2nd bank # and page count
;  +10	2nd page count	word	** fields are only for the remap case.
;
; in:	ebx = offset of caller's list - relative to gdtzero
;	ecx = number of list entries
;	ds -> gdtdata
;	es -> gdtpage
;	fs -> gdtzero
;
; out:	none
;
;,fe
;======================================================================
	assume	ds:mmgrp,es:nothing
nlistmap:
	push	eax
	push	esi
	push	edi
nlm1:
	push	ebx
	push	ecx
	movzx ecx,word ptr fs:[ebx+6]	; get 1st page count
	movzx edi,word ptr fs:[ebx+2]	; get segment
	shr	edi,8			; convert seg to page frame #
	movzx eax,word ptr fs:[ebx]	; get command code from list
	case eax == 3 else nlm3 	; remap command
	movzx esi,word ptr fs:[ebx+4]	; get 1st handle
	call	nremap
	add	edi,ecx 		; advance page frame # for 2nd block
	movzx ecx,word ptr fs:[ebx+10]	; get 2nd page count
	xif ecx != 0 else nlm4		; anything to do?
	movzx esi,word ptr fs:[ebx+8]	; get 2nd handle
	call	nremap
nlm4:
	jmp	nlm5

nlm3:	case eax == 4 else nlm6 	; unmap command
	mov	eax,edi 		; get page # to be remapped
	mov	ebx,edi 		; get page frame to be remapped into
	call	nphymap
	jmp	nlm5

nlm6:	case eax == 5 else nlm7 	; phymap command
	movzx eax,word ptr fs:[ebx+4]	; get 1st handle
	mov	ebx,edi 		; get page frame #
	call	nphymap
twolbl nlm7 nlm5
	pop	ecx
	pop	ebx
	add	ebx,12			; advance to next list entry
	loop	nlm1

	pop	edi
	pop	esi
	pop	eax
	ret

res32	ends


;======================== 16 bit initialization code ===================

	.286
init16	segment para public 'CODE'
	assume	cs:mmgrp,ds:mmgrp

	even
progend  label byte			; end of retained code


; The following 512 bytes is necessary for when esdi bios needs to
; be relocated.  The space is necessary because of
; MJS's modifications for 386 driver and conflicts with ESDI bios
; relocation logic would copy bios information into INIT code.

	db	1024	dup (0)

msgodm	db	'  nnnK RAM found in first megabyte;    ',13,10,'$'  ;@@xlat
ermsize db	'Insufficient RAM available!  ',13,10,'$'  ;@@xlat
mmpar_bad db	13,10,'MEMDEV parameter error, load aborted              ',07,13,10,'$'  ;@@xlat
msgvm	db	'386 Protected mode and paging are now active.  ',13,10,13,10,'$'  ;@@xlat
msg386	db	'This driver requires an Intel 80386 microprocessor!',13,10,'$'  ;@@xlat
slashl	db	0			; not slash L option
slashb	db	'N'			; not slashb

;--------------------------------------------------------------------
;	     task state segment #1 - saves native mode
;--------------------------------------------------------------------
	align 16			; align to paragraph boundary

	db	'******TSS1******'

tss1	label word
	dw	0,0			; link to previous tss
	dw	offset mmgrp:p0stack,0	; esp/ss for level 0 stack switch
	dw	gdtdata-gdt,0
	dw	0,0,0,0 		; esp/ss for level 1 stack switch
	dw	0,0,0,0 		; esp/ss for level 2 stack switch
	dw	26h dup(0)
tss1len  equ   $-tss1


	subttl dectobin - decimal-to-binary conversion routine
	page
;======================================================================
;,fs
; dectobin - decimal-to-binary conversion routine
;
; in:	es:bx -> parameter to convert
;
; out:	ax = converted value
;	es:bx -> char just after parameter
;	crashes dx
;
;,fe
;======================================================================
dectobin:
	xor	ax,ax			; ax will contain the result
dtbloop:				; es:bx is source address
	mov	dl,es:[bx]
	cmp	dl,'0'
	jb	dtbwrap
	cmp	dl,'9'
	ja	dtbwrap
	push	dx
	mul	[wordten]
	pop	dx
	and	dx,000fh
	add	ax,dx
	inc	bx
	jmp	dtbloop
dtbwrap:
	ret



	subttl pass_space - advance es:bx past blanks
	page
;======================================================================
;,fs
; pass_space - advance es:bx past blanks
;
; in:	es:bx -> string
;
; out:	al = stop char
;	es:bx -> stop char
;
;,fe
;======================================================================
pass_space:
	mov	al,es:[bx]
	cmp	al,' '
	jne	pass_done
	inc	bx
	jmp	short pass_space
pass_done:
	ret


	subttl find_space - advance es:bx to 1st space or eol
	page
;======================================================================
;,fs
; find_space - advance es:bx to 1st space or eol
;
; in:	es:bx -> string
;
; out:	al = 1st space found or eol marker
;	es:bx -> stop char
;
;,fe
;======================================================================
find_space:
	mov	al,es:[bx]
	cmp	al,0dh
	je	find_done
	cmp	al,' '
	je	find_done
	inc	bx
	jmp	short find_space
find_done:
	ret


	subttl parse - parse the parameter line
	page
;======================================================================
;,fs
; parse - parse the parameter line
;
; in:	data in [rhoff]
;
; out:	ax != 0 if error
;	global vars set from parameters found
;
;,fe
;======================================================================
parse:
	les	bx,dword ptr [rhoff]
	les	bx,dword ptr es:[bx+18] ; get parameter pointer
	call	find_space		; parse past the memdev name
	call	pass_space		; find 1st parameter
	cmp	al,0dh
	jne	sw_a
	jmp	swdone
sw_a:
	cmp	al,'/'
	je	sw_loop

; if first thing found isn't a slash, presume its a new meg0new value

	call	dectobin		; get the number in ax
	cmp	ax,64			; range must be reasonable
	jb	badparm
	cmp	ax,704
	ja	badparm
	add	ax,3			; round up to 4k
	shr	ax,2			; convert from kbytes to 4k banks
	mov	[meg0new],ax
	dec	bx
sw_hunt:
	inc	bx
	call	pass_space		; find next parameter
	cmp	al,0dh
	jne	sw_b
	jmp	swdone
sw_b:
	cmp	al,'/'			; if not eol, should be a switch
	je	sw_loop
badparm:
	jmp	sw_synerr

; at this point, es:bx -> '/'  so check for switch options

sw_loop:
	inc	bx
	mov	al,es:[bx]		; scan for a slash
	cmp	al,'D'			; /d=nn for custom staging buffer
	jne	sw_not_d
	cmp	byte ptr es:[bx+1],'='
	jne	badparm
	add	bx,2
	call	dectobin		; get the number in ax
	dec	bx			; leave bx -> last char of parm
	cmp	ax,64			; range must be reasonable
	ja	badparm
	je	sw_max
	cmp	ax,4			; must have >= 4k for parmpfa use
	jb	badparm							   
	shl	ax,10			; * 1024
	jmp	short swdma
sw_not_d:
	cmp	al,'P'			; ps/2 needs 16k dma buffer
	jne	sw_not_p
	mov	ax,4000h
	jmp	short swdma
sw_not_p:
	cmp	al,'M'			; midrange 32k buffer
	jne	sw_not_m
	mov	ax,8000h
	jmp	short swdma
sw_not_m:
	cmp	al,'E'			; emulex needs 64k dma buffer
	jne	sw_not_e
sw_max:
	mov	ax,0ffffh
	jmp	short swdma
sw_not_e:
	cmp	al,'X'			; xt needs 9k dma buffer
	jne	sw_not_x
	mov	ax,18*512
swdma:
	mov	[buffsize],ax
	mov	[dmajump],9090h 	; nop out conditional jump
	jmp	sw_hunt
sw_not_x:

IF TRACE
	cmp	al,'T'			; trace option
	jne	sw_not_t
	mov	[trapflag],1
	mov	[trapsave],1
	jmp	sw_hunt
sw_not_t:
ENDIF

IF INT6
	cmp	al,'6'			; /6 disables IO protection
	jne	sw_not_6
	and	[parmfeat], NOT 04000h	; disable IO Protection
	jmp	sw_hunt
sw_not_6:
ENDIF

	cmp	al,'L'			; /L for disable compaq memory test
	jne	sw_not_l
	mov	[slashl],1
	jmp	sw_hunt
sw_not_l:

	cmp	al,'I'			; /i for "simple" interrupt management
	jne	sw_not_i
	and	byte ptr [parmfeat+1],not 04h
	jmp	sw_hunt
sw_not_i:
	cmp	al,'C'			; /c for "conventional" memory
	jne	sw_not_c
	and	byte ptr [parmfeat+1],not 02h
	jmp	sw_hunt
sw_not_c:
	cmp	al,'F'			; /f for full reboot (skip warm boot)
	jne	sw_not_f
	mov	[foption],1
	jmp	sw_hunt
sw_not_f:
	cmp	al,'B'			; /b enable full fill 
	jne	sw_not_b
	mov	[slashb],'Y'
	jmp	sw_hunt
sw_not_b:
	cmp	al,'N'			; /n for protected mode nmi
	jne	sw_not_n
	mov	ax,[et2ofs]
	mov	[idt+16],ax
	or	[dvstat1],2		; indicate protected mode nmi
	jmp	sw_hunt

et2ofs	dw	mmgrp:entint02

sw_not_n:


; when reach this point, report syntax error

sw_synerr:
	mov	dx,offset mmgrp:mmpar_bad
	mov	ah,9
	int	21h
	mov	ax,1
	ret
swdone:
	xor	ax,ax
	ret


	page
;--------------------------------------------------------------------
;		     binary-to-decimal routine
;--------------------------------------------------------------------
bintodec proc  near
	push	cx
btdloop1:
	div	word ptr [wordten]	; dx:ax is source integer
	add	dl,'0'			; cx is length of target
	mov	[bx],dl 		; bx is end of target
	dec	bx
	xor	dx,dx
	loop	btdloop1
	pop	cx
btdloop2:
	inc	bx
	dec	cx
	jz	btdret
	cmp	byte ptr [bx],'0'
	jne	btdret
	mov	byte ptr [bx],' '
	jmp	btdloop2
btdret:
	ret
bintodec endp

	subttl init - device driver initialization logic
	page
;======================================================================
;,fs
; init - device driver initialization logic
;
; in:	none
;
; out:	all sorts of stuff setup
;
;,fe
;======================================================================
init:
	mov	dx,offset mmgrp:loadmsg0
	mov	ah,9
	int	21h
	mov	ah,2
	mov	dl,'$'
	int	21h
	mov	dx,offset mmgrp:loadmsg
	mov	ah,9
	int	21h

; check memory mangment hardware

	pushf
	xor	ax,ax
	push	ax
	popf				; try to put zero in flags
	pushf
	pop	ax
	and	ax,0f000h
	cmp	ax,0f000h
	je	no386
	mov	ax,0f000h		; try to but 1's in high bits
	push	ax
	popf
	pushf
	pop	ax
	and	ax, 0f000h
	jne	is386
no386:
	popf
	mov	dl,'$'
	mov	ah,2
	int	21h
	mov	dx,offset mmgrp:msg386
	mov	ah,9
	int	21h
	jmp	ddabort
is386:
	popf


;
; check to see if on a 486 and if so than change the boot message 
; so that it displays that it is on a 486.  This is mainly added for
; information.
;


	.386
	mov	edx,esp
	and	esp,not 3
	pushfd
	pop     eax
	mov	ecx,eax
	xor	eax,40000h
	push	eax
	popfd
	pushfd	
	pop	eax
	xor	eax,40000h
	shr	eax,18
	and	eax,1
	push	ecx
	popfd
	mov	esp,edx
	.286
	or	al,al
	jnz	not386
	mov	[msgvm],'4'		; change it so that it displays 486
not386:

IF  REGDISP
	.386p
	mov	eax,cr0
	push	eax
	.286
	mov	bx,offset mmgrp:cr0low+3
	call	bin2hex
	.386
	pop	eax
	shr	eax,16
	.286
	mov	bx,offset mmgrp:cr0high+3
	call	bin2hex
	.386p
	mov	eax,cr2
	push	eax
	.286
	mov	bx,offset mmgrp:cr2low+3
	call	bin2hex
	.386
	pop	eax
	shr	eax,16
	.286
	mov	bx,offset mmgrp:cr2high+3
	call	bin2hex
	.386p
	mov	eax,cr3
	push	eax
	.286
	mov	bx,offset mmgrp:cr3low+3
	call	bin2hex
	.386
	pop	eax
	shr	eax,16
	.286
	mov	bx,offset mmgrp:cr3high+3
	call	bin2hex
	mov	dx,offset mmgrp: crxregs
	mov	ah,9
	int	21h
	.386p
	sgdt	fword ptr mmgrp:ptestmem
	.286
	mov	bx,offset mmgrp:gword1+3
	mov	ax,word ptr cs:[ptestmem+4]
	call	bin2hex
	mov	bx,offset mmgrp:gword2+3
	mov	ax,word ptr cs:[ptestmem+2]
	call	bin2hex
	mov	bx,offset mmgrp:gword3+3
	mov	ax,word ptr cs:[ptestmem]
	call	bin2hex
	.386p
	sidt	fword ptr mmgrp:ptestmem
	.286
	mov	bx,offset mmgrp:iword1+3
	mov	ax,word ptr cs:[ptestmem+4]
	call	bin2hex
	mov	bx,offset mmgrp:iword2+3
	mov	ax,word ptr cs:[ptestmem+2]
	call	bin2hex
	mov	bx,offset mmgrp:iword3+3
	mov	ax,word ptr cs:[ptestmem]
	call	bin2hex
	.386p
	str	ax
	.286
	mov	bx,offset mmgrp:tword+3
	call	bin2hex
	.386p
	sldt	ax
	.286
	mov	bx,offset mmgrp:lword+3
	call	bin2hex
	mov	dx,offset mmgrp:pregmsg
	mov	ah,9
	int	21h
	xor	ax,ax
	int	16h
ENDIF



; Make sure that we save correct Interupt mask from port 21h
; and make sure that we mask out IRQ 1, on IBM Model 70 486,
; Turning on bit 20 cause an unwanted IRQ 1 to be issued

	in	al,21h
	mov	[p21bits],al		; save current state for later
	or	al,2			; disable INT 9 during INIT
	out	21h,al

; get video ram address

	mov	es,[zero]
	mov	ax,es:[0410h]		; get equip_flag
	and	al,30h
	cmp	al,30h			; monochrome card?
	je	skipcolr		; yes, skip
	mov	[videoadr],0b800h	; no, set address for color card
	jmp	donevid
skipcolr:
	mov	word ptr [gdtvideo+2],0
donevid:


; determine original base memory size

	mov	es,[zero]
	mov	ax,es:[0413h]		; get default value
	mov	bx,ax
	add	ax,3			; model 80 is 639k
	shr	ax,2			; convert to a multiple of 4k
	mov	[meg0old],ax
	mov	[meg0new],ax
	mov	[parmused],ax
	mov	[dmabank],al		; for dma logic
	mov	ax,bx
	xor	dx,dx			; put old meg0 size in message
	mov	bx,offset mmgrp:msgodm+4
	mov	cx,5
	call	bintodec
	or	[dvstat1],1		; indicate 386 or above
	call	parse			; parse the parameter line
	or	ax,ax
	jz	parseok
	jmp	ddabort
parseok:
	mov	es,[zero]		; set bios ram size in kilobytes
	mov	ax,[meg0new]
	shl	ax,2
;
; compare new size to current size in bios
;
	cmp	ax,es:[413h]
	je	nochange
	mov	bx,es:[040eh]
	cmp	bx,9fc0h
	je	nochange
	cmp	[slashb],'Y'
	je	nochange
	mov	ax,es:[413h] 		; check to see if on 64k boundary
	mov	bx,ax
	and	bx,0fc0h
	cmp	ax,bx
	je	nochange	
	shr	ax,2
	mov	[meg0new],ax
	mov	[meg0old],ax
	mov	[parmused],ax
	mov	[dmabank],al		; for dma logic
nochange:
;
;--------------------------------------------------------------------
;		      80386 initialization
;--------------------------------------------------------------------

	mov	[loadaddr],cs		; save initial load address
	call	bit20on 		; turn on address bit 20 gate

; if tracing, initialize serial port

IF TRACE
	cmp	[trapflag],0
	je	spiskip
ENDIF

IF TRACE
	mov	dx,[portaddr]		; address it
	add	dl,3			; 3fb=lcr
	mov	al,80h			; access baud rate divisor
	out	dx,al
	jmp	$+2
	sub	dl,3			; 3f8=divisor low byte
	mov	al,06h			; set 19200 baud
	out	dx,al
	jmp	$+2
	inc	dl			; 3f9=divisor high byte
	xor	al,al
	out	dx,al
	jmp	$+2
	add	dl,2			; 3fb=lcr
	mov	al,03h			; dlab off
	out	dx,al
	sub	dl,2			; 3f9=ier
	mov	al,00h			; enable no interrupts
	out	dx,al
	jmp	$+2
	add	dl,3			; 3fc=mcr
	mov	al,03h
	out	dx,al
	jmp	$+2
ENDIF

spiskip:

; patch up device driver entries

	mov	es,[loadaddr]
	mov	es:[stratvec],offset mmgrp:tostrat
	mov	es:[intervec],offset mmgrp:tointer
	mov	word ptr es:[tostrat+3],cs
	mov	word ptr es:[tointer+3],cs

; relocate some addresses

	mov	[realcs],cs		; init a jmp instruction
	mov	al,[uioplb]		; set user i/o privilege level

IF TRACE
	or	al,[trapflag]		; turn trap flag on if appropriate
ENDIF

	or	byte ptr [t2eflags+1],al

	mov	ax,cs			; relocation factor in dl:ax
	mov	dl,ah
	shl	ax,4
	shr	dl,4
	add	word ptr [wsgdtr+2],ax	; relocate control register contents
	adc	byte ptr [wsgdtr+4],dl
	add	word ptr [wsvmidtr+2],ax				    
	adc	byte ptr [wsvmidtr+4],dl
	add	word ptr [gdtcode+2],ax ; relocate gdt descriptors
	adc	byte ptr [gdtcode+4],dl
	add	word ptr [gdtdata+2],ax
	adc	byte ptr [gdtdata+4],dl
	add	word ptr [gdtcod16+2],ax
	adc	byte ptr [gdtcod16+4],dl
	add	word ptr [gdtdat16+2],ax
	adc	byte ptr [gdtdat16+4],dl
	add	word ptr [gdttss1+2],ax
	adc	byte ptr [gdttss1+4],dl
	add	word ptr [gdttss2+2],ax
	adc	byte ptr [gdttss2+4],dl
	mov	[t2es],cs		; set up selectors for v86 mode
	mov	[t2cs],cs
	mov	[t2ds],cs
	mov	[t2fs],cs
	mov	[t2gs],cs
	mov	[t2ss],ss
	mov	[t2sp],sp
			  
; setup for transfer to protected mode


	cli				; no interrupts allowed
	db	0fh,01h,00010110b	; lgdt using disp16
	dw	offset mmgrp:wsgdtr
	db	0fh,01h,00011110b	; lidt
	dw	offset mmgrp:wsvmidtr
					       
	.386p
	mov	eax,cr0
	and	al,11110000b		; retain "et" bit (80287 vs 80387)
	or	eax,1			; or eax,1 to set "pe" bit
	mov	cr0,eax
	.286

	db	0eah			; direct intersegment jump loads cs
	dw	mmgrp:build_page	; branch to build_page
	dw	gdtcode-gdt

; native mode code at build_page will result
; in entry to this point in virtual 8086 mode

vmstart:

	sti
	mov	ah,9
	mov	dx,offset mmgrp:msgvm
	int	21h
	mov	[parmiop+2],cs		; complete iopbm pointer

; save/set disk i/o vector

	mov	es,[zero]
	mov	ax,es:[004ch]		; save int 13h vector
	mov	word ptr [oldint13],ax
	mov	ax,es:[004eh]
	mov	word ptr [oldint13+2],ax
	mov	es:[004eh],cs		; set new int 13h vector
	mov	word ptr es:[004ch],offset mmgrp:entinr13

; hook the real-mode int 6fh vector so v-86 callers can reach the
; int 6fh services. At IOPL=3 an INT n in v-86 mode is not trapped, so
; without this hook int 6fh from v-86 went to the BIOS default stub
; (measured: IVT[6Fh] = F000:1060, identical to the unused IVT[6Eh]).
; See i6fstub / doi6fgate and the addendum.

	mov	ax,es:[01bch]		; save int 6fh vector
	mov	word ptr [oldint6f],ax
	mov	ax,es:[01beh]
	mov	word ptr [oldint6f+2],ax
	mov	es:[01beh],cs		; set new int 6fh vector
	mov	word ptr es:[01bch],offset mmgrp:i6fstub

; init some more pointers

	mov	[mysegadr],cs
	mov	[parmrhad+0],offset mmgrp:rhentry
	mov	[parmrhad+2],cs

; write old memory size

	mov	ah,9
	mov	dx,offset mmgrp:msgodm
	int	21h

; extended memory is initialized

	xor	ax,ax
	mov	cx,256
	call	selfmap 		; reinitialize meg0 mapping

; write total memory size

	mov	ax,[parmtot]		; compute kbytes of total memory
	shl	ax,1
	shl	ax,1
	xor	dx,dx
	mov	bx,offset mmgrp:msgem+4
	mov	cx,5
	call	bintodec
	mov	ah,9
	mov	dx,offset mmgrp:msgem
	int	21h

	page

; change dos partition size if required

	mov	cx,[meg0new]
	sub	cx,[meg0old]
	je	noresize
	jl	shrink
	call	valloc			; get banks to extend base ram
	or	al,al
	jz	domeg0remap
	jmp	errsize
domeg0remap:
	mov	ax,bx			; map them in
	mov	bx,[meg0old]
	call	remap
	jmp	short noresize
shrink:
	neg	cx			; free up banks
	mov	bx,[meg0new]
	call	vrelease
noresize:
	mov	es,[zero]		; set bios ram size in kilobytes
	mov	ax,[meg0new]
	shl	ax,2
	mov	es:[0413h],ax

	page
;--------------------------------------------------------------------
;	move extended bios data area if needed.
;--------------------------------------------------------------------
	mov	ax,offset mmgrp:progend
	add	ax,15
	shr	ax,4
	mov	dx,cs
	add	ax,dx			; buffer begin paragraph address

; move data area used by ibm esdi bios

	push	es
	mov	es,[zero]
	mov	dx,es:[040eh]
	cmp	dx,9fc0h		; data area at 9fc0:0000?
	jne	mieskip
	mov	es:[040eh],ax		; yes, replace its address

; if the segment of int41 is 9fc, must change to match 0:40e

	cmp	es:[41h*4+2],9fc0h
	jne	not41seg
	mov	es:[41h*4+2],ax		; yes, replace its address
not41seg:
	mov	es,ax			;   and move its data to the new area
	push	ds
	mov	ds,dx			; source address
	xor	si,si
	xor	di,di
	mov	cx,512			; length is 1k
	cld
	rep	movsw
	pop	ds
	add	ax,0040h		; bump ending segment by 1k
mieskip:
	pop	es
;--------------------------------------------------------------------
;	compute buffer location - must not cross 64k boundary
;--------------------------------------------------------------------
	mov	bx,[buffsize]
	shr	bx,4
	add	bx,ax			; buffer end
	push	ax
	and	ax,0f000h
	and	bx,0f000h
	cmp	ax,bx
	pop	ax
	je	bufadrok		; jump if segment not crossed
	add	ax,0fffh		; bump to next segment
	and	ax,0f000h
bufadrok:
	mov	[buffaddr],ax
	mov	dx,ax			; put parmpfa in parms area
	add	dx,00ffh
	xor	dl,dl
	mov	[parmpfa],dx
	les	bx,dword ptr [rhoff]
	mov	dx,[buffsize]		; compute end of buffer
	shr	dx,4
	inc	dx
	add	ax,dx

; set end address of this driver

	mov	word ptr es:[bx+14],0	; set this driver's end address
	mov	word ptr es:[bx+16],ax

; protect dma channel 2

	or	[t2iopbm],10h		; protect port 04h
	or	[t2iopbm+10h],02h	; and port 81h
	or	[t2iopbm+1ch],01h	; and port 0e0h (int 6fh gateway)

; write message

	mov	es,[zero]
	mov	ax,es:[0413h]		; new mos size in kbytes
	xor	dx,dx
	mov	bx,offset mmgrp:msgndm+4
	mov	cx,5
	call	bintodec
	mov	ah,9
	mov	dx,offset mmgrp:msgndm
	int	21h

; allocate 60k for high freemem

	test	byte ptr [parmfeat+1],02h  ; requires feature bit
	jz	ahfend
	xor	ax,ax			; first map 100000 to 000000
	mov	bx,0100h
	mov	cx,1
	call	remap
	mov	cx,15			; 15*4k = 60k
	call	valloc
	cmp	cx,15			; check if we got enough memory
	jae	ahfgotit
	and	byte ptr [parmfeat+1],not 02h
	jmp	short ahfend		; nope
ahfgotit:
	mov	ax,bx
	mov	bx,0101h		; addressed with fff8:1080-ffff
	call	remap
ahfend:

; initialization completed

	mov	[tprintsw],0		; turn on trace display if applicable
	jmp	short donemm

; write error messages

errsize:
	mov	ah,9
	mov	dx,offset mmgrp:ermsize
	int	21h

; Make sure that we restore Interupt Masks back to original masks

donemm:
	mov	al,[p21bits]		; get original mask
	out	21h,al			; out to 8259
	jmp	donestat

; the following is use during 386 memory test to turn off
; nmi by setting to int 2 to an iret.	this needed because
; if an inboard 386 /pc is used, the pc bios will come up
; with parity error when 386 driver check for memory above 1 meg

p21bits db	0		; save area for Port 21
oldnmi	dd	0			; storage for original nmi vector
msgem	db    'nnnnnK total RAM found;      ',13,10,'$'  ;@@xlat
msgndm	db    '  nnnK allocated to first megabyte.   ',13,10,13,10,'$'	;@@xlat

loadmsg0 db	'Loading $'
loadmsg	db	'386.SYS  version 5.01  (921119)',13,10,'$'	;@@xlat

IF REGDISP
ptestmem   dw	3 dup (0)

crxregs	db	'CR0= '
cr0high db	'    '
cr0low	db	'    H, CR2= '
cr2high db	'    '
cr2low	db	'    H, CR3= '
cr3high db	'    '
cr3low	db	'    H.',13,10,'$'

pregmsg db	'GDT= '
gword3	db	'    '
gword2	db	'    '
gword1	db	'    H, IDT= '
iword3	db	'    '
iword2	db	'    '
iword1	db	'    H',13,10
	db	'TSS= '
tword	db	'    H, LDT= '
lword   db	'    H.',13,10,'$'


endif



newnmi:
	iret				; just make it an iret

init16 ends

;======================== 32 bit initialization code ===================

	.386p
init32	segment para public 'CODE' use32
	assume	cs:mmgrp

; use this stack when doing protected mode setup (testing extmem and
; building tables)

	align 16
	db	(16*100) dup(0)
pt_stack label word

build_page:

; now in protected mode - paging not enabled

	cld
	mov	ax,gdtdata-gdt		; ds -> this driver's data
	mov	ds,ax
	assume	ds:mmgrp

	mov	[nmi_slctr],ax
	mov	[nmi_vector+4],cs
	mov	dword ptr [nmi_vector],offset mmgrp:dflt_int2

	mov	ax,gdtpage-gdt		; es -> 0 based, 4gb segment
	mov	es,ax
	assume	es:nothing
	mov	ax,gdtdata-gdt		; ss -> data segment too
	mov	ss,ax
	assume	ss:mmgrp
	mov	esp,offset mmgrp:pt_stack
	mov	ax,word ptr [idt+16]	; save idt offset for nmi interrupt
	mov	word ptr [oldnmi],ax
	mov	word ptr [idt+16],offset mmgrp:newnmi  ; set to iret for mem tests


; found that I had to read each dword in the first page
; of meg1 to satiate the compaq.  compaq tells me that some early
; models of the 16Mhz 386 (rev A motherboards) had a problem with
; enabling A20 and that doing reads first would clear it up.

	push	ds
	push	es
	pop	ds
	mov	esi,100000h
	mov	ecx,4096/4
	cld
	rep	lodsd
	pop	ds

; test for an address wrap-around at meg17.  on machines which only
; present a0 through a23 to the memory address bus, writing to the
; 17th meg will result in a wrap-around to meg0.  if the test_extmem
; procedure were allowed to keep running to this point, it would
; find ram at address 1000000, but it would actually be meg0page0!!

	mov	eax,es:[0]		; save current zero divide vector
	mov	dword ptr es:[0],0
	mov	dword ptr es:[1000000h],0ffffffffh
	xif <dword ptr es:[0]> != 0 else bpg1
	mov	[m17wrap],'Y'
bpg1:
	mov	es:[0],eax		; restore zero divide vector

; test for extended memory starting at meg1

	mov	ebx,100000h
	call	test_extmem


; at this point, ebx holds the number of pages of extended memory
; found within the first range (2nd range search is later).
; need at least 1 for pd, 1 for pt and one to have anything
; to catalog (not that 12k of extmem is good for much).
; if the 60k high freemem is being supported (no /c option) then
; need at least 16 more or must give up that feature.

	mov	[ext_pages],ebx 	; record # of extmem pages
	xif ebx b 3 else bpg2
	mov	ax,8
	jmp	bpg3
bpg2:
	xif <byte ptr [parmfeat+1]> test1 2 && ebx b 19 else bpg4
	and	byte ptr [parmfeat+1],not 2
bpg4:

; derive location for page directory
; (presumes only one page required for the page directory)

	mov	ebx,100000h		; phyadr of start of extmem
	xif <byte ptr [parmfeat+1]> test1 2 else bpg5
	add	ebx,16*1000h
bpg5:
	mov	[pd_addr],ebx		; record base of page directory
	add	ebx,1000h		; start page tables in next page
	mov	[pt_addr],ebx		; record base of page table

; now, calc total number of pte's needed in the page table.  adding 256
; to account for page frames for meg0 and then another 16 to
; account for the wrap around record and high 60k freemem area.
; finally, since the banks in meg0 must be represented within the parspace
; resource list, the value in meg0old is added in.  the resulting page
; table will always be [meg0old]+16 pte's larger than if a simple 1:1
; page table were built.

	mov	ecx,[ext_pages] 	; retrieve # of extmem pages
	add	ecx,256+16		; add for meg0 + high60
	movzx ebx,[meg0old]
	add	ecx,ebx 		; add room for meg0 parspace data
	mov	[pt_recs],ecx		; store total pte records required

; init pte's for meg0 and high 60k area - identity map

	mov	ecx,256+16		; # of pte's for 1 meg + high 60k
	mov	edi,[pt_addr]
	mov	eax,7h			; present=1, write=1, user=1, bit11=0
bpg6:
	stosd				; init the pte
	add	eax,1000h		; increment the pfa by 1
	loop	bpg6


; start initializing the parspace table.
; init pte's for the meg0 portion of the parspace table (identity
; map as if actually the page table for meg0).

	movzx ecx,[meg0old]
	mov	eax,7h			; present=1, write=1, user=1, bit11=0
bpg8:
	stosd				; init the pte
	add	eax,1000h		; increment the pfa by 1
	loop	bpg8


; continue initializing the parspace table.
; init pte's for the first range of extmem (starting at phyadr 100000)

	mov	ecx,[ext_pages]
	mov	eax,00100807h		; present=1, write=1, user=1, bit11=1
bpg10:
	stosd				; init the pte
	add	eax,1000h		; increment the pfa by 1
	loop	bpg10


; now, edi is prepped to write more of the parspace table.  for the sake
; of compaq machines which have a block of extmem just under the 16th
; meg, will now check for a second range.  any more extmem found will
; be contiguously recorded within the parspace table.

; SAH 06/05/91  if /l is use skip checking upper 15 Meg area for
; compaq machines.  This is done to correct a problem with with Hawk 386

	cmp     [slashl],0
	jne	bpg12
	xif [ext_pages] b 0ea0h else bpg12  ; if haven't yet been up to fa0000
	mov	ebx,0fa0000h		; start there and
	call	test_extmem		; test for extended memory
	xif ebx != 0 else bpg13 	; if find anything
	mov	ecx,ebx 		; must add to the parspace table
	mov	eax,0fa0807h		; present=1, write=1, user=1, bit11=1
bpg14:
	stosd				; init the pte
	add	eax,1000h		; increment the pfa by 1
	loop	bpg14

	add	[ext_pages],ebx 	; update accounting of extmem
	add	[pt_recs],ebx		; and of page table records
bpg13:
bpg12:
	mov	ecx,[pt_recs]		; fetch total # of pte's
	add	ecx,1023		; round up to next 1024 count
	shr	ecx,10			; and div by 1024 to calc # of pde's
	mov	[pt_pages],ecx		; record number of page table pages

; now, must reserve pages used for the page directory and table.

	mov	edi,[pt_addr]		; make edi -> base of page table
	add	edi,440h		; advance to parspace
	movzx ebx,[meg0old]
	shl	ebx,2
	add	edi,ebx 		; advance past meg0 entries
	xif <byte ptr [parmfeat+1]> test1 2 else bpg16
	add	edi,16*4		; advance past high freemem entries
bpg16:
	inc	ecx			; account for page directory page
	add	dword ptr [parmused],ecx; keep running tally
bpg17:
	and	dword ptr es:[edi],not 800h  ; mask off bit11
	add	edi,4			; next pte
	loop	bpg17


; time to build the page directory

	mov	ecx,[pt_pages]		; one pde per page table page
	mov	edi,[pd_addr]		; phyadr of page directory
	mov	eax,[pt_addr]		; phyadr of page table
	or	al,7			; present=1, write=1, user=1
bpg19:
	stosd				; write the pde
	add	eax,1000h		; advance the pta by 1
	loop	bpg19



; rewrite the base for gdtpage to simplify access to the page table
; by the native mode code for jvalloc, vrelease, vremap, etc.
; the wierd thing here is that access to the page table is governed
; by a part of the page table which is not identity mapped.  must
; translate through the parspace table (similar to makegdtx)
; (this code presumes the base is currently 0)

	mov	eax,[pt_addr]		; get phyaddr for base
	shr	eax,12			; convert to page number
	movzx ebx,[meg0old]
	add	eax,ebx 		; adjust by page number
	add	eax,10h 		; adjust for high freemem recs
	shl	eax,12			; convert to adjusted phyaddr
	push	eax
	and	eax,0ffffffh		; dump high byte
	or	dword ptr [gdtpage+2],eax  ; implant wo changing bits 40-47
	pop	eax
	rol eax,8			; put eax's high byte into al
	mov	[gdtpage+7],al		; set bits 56-63 (base 24-31)
	mov	eax,[pt_pages]		; get # of page table pages
	mov	word ptr [gdtpage],ax	; set limit bits 0-15
	shr	eax,16			; mov bits 16-19 to 0-3 position
	and	byte ptr [gdtpage+6],0f0h  ; mask off old limit 16-19
	or	[gdtpage+6],al		; implant new wo changing bits 52-55
	push	ds
	pop	es

; derive value for parmtot and parsize

	mov	eax,[pt_recs]
	sub	eax,110h		; exclude pte's for meg0 and high 60k
	mov	dword ptr [parmtot],eax
	shl	eax,2
	mov	[parsize],eax
	xor	ax,ax			; indicate no error
bpg3:
	mov	bx,word ptr [oldnmi]
	mov	word ptr [idt+16],bx	; restore original nmi offset
	mov	ebx,80000000h		; prepare to set the "pg" bit
	xif ax != 0 else bpg21		; if not enough extmem
	xor	ebx,ebx 		; prevent paging
	mov	byte ptr [parmfeat+1],0 ; don't support anything if no extmem
bpg21:

; prepare for entry to vm86 mode

	mov	eax,[pd_addr]		; get phyadr of the page direcotry
	mov	dword ptr [t2cr3],eax	; set into tss2


	mov	cr3,eax 		; and into cr3


	mov	eax,cr0
	or	eax,ebx 		; set the "pg" bit (unless error)
	mov	cr0,eax 		; enable paging


	mov	ax,gdttss1-gdt
	ltr ax				; load the task register - vm prep
	db	66h,0eah		; direct interseg jump to
	dw	0,gdttss2-gdt		; enter vm86 mode at vmstart


;======================================================================
;,fs
; test_extmem
; 
; test for a contiguous range of extended memory
;
; in:	es -> gdtpage (setup for full access)
;	ebx -> phyadr of range to be tested
;
; out:	ebx = # of pages found
;
;,fe
;======================================================================
	assume ds:mmgrp
test_extmem:
	push	eax
	push	edx
	push	edi
	mov	edi,ebx
	mov	dx,7755h		; test pattern
	xor	eax,eax 		; to blank out found blocks
	cld
txm1:
	xif edi == 1000000h && [m17wrap] == 'Y' then txm2  ; quit before a wrap
	mov	es:[edi],dl
	jmp	$+2			; tiptoe around the wyse 386
	mov	es:[edi+1],dh
	jmp	$+2
	cmp	es:[edi],dl
	jmp	$+2
	xif flags == ne then txm2
	cmp	es:[edi+1],dh
	jmp	$+2
	xif flags == ne then txm2
	push	edi
	mov	ecx,4096/4		; if get this far, zero out the page
	rep	stosd
	jmp	$+2
	pop	edi
	cmp	es:[edi],eax		; did the zero'ing take?
	xif flags == ne then txm2
	add	edi,4096		; advance to next page
	jmp	txm1
txm2:
	sub	edi,ebx 		; determine total range
	shr	edi,12			; divide by 4096 to calc # of pages
	mov	ebx,edi
	pop	edi
	pop	edx
	pop	eax
	ret


init32	ends
	end   begin




