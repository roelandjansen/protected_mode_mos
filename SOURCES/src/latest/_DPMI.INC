I86			equ	0
I186			equ	1
I286			equ	2
I386			equ	3
I486			equ	4

MOS_HOST_MAJOR		equ	0
MOS_HOST_MINOR		equ	1

DPMIVersion		equ	0100h
DPMIVersion9		equ	005Ah
AccessBits		equ	1

DEBUGAccess		equ	0
DEBUGStatus		equ	1
DEBUGLoc		equ	2
DBStrucSize		equ	6

;
; The following Equates are use for accessing Memory Manager via INT 6fh
; All DPMI related Memory manager functions start from 80h...
;

MEM_GET_DESC		equ	7780h
MEM_SET_DESC		equ	7781h
MEM_VIRTUAL		equ	7782h
READ_DEBUG		equ	7783h
WRITE_DEBUG		equ	7784h
MEM_DESCRIPTOR  	equ	7785h
SEGMENT_SELECTOR	equ	7786h
SELECTOR_SEGMENT	equ	7787h
GET_PROT_EXCEPTION	equ	7788h
SET_PROT_EXCEPTION	equ	7789h
GET_REAL_EXCEPTION	equ	778ah
SET_REAL_EXCEPTION	equ	778bh
CREATE_ALIAS		equ	778ch
ALLOC_SPEC_SELECTOR	equ	778dh
;
; below are equates use to access memory manger functions
;
VIRTUAL_DISABLE		equ	0
VIRTUAL_ENABLE		equ	1
VIRTUAL_TABLE		equ	2
;
ALLOCATE_DESCRIPTOR	equ	0
FREE_DESCRIPTOR		equ	1
DESCRIPTOR_INC		equ	2

;
; The following Equates are use for storing selector flags
;

GRANULARITY		equ	080h		; 1 = page , 0 = byte
DEFAULT_SEG		equ	040h
AVL			equ	010h
DESC_TYPE_HI		equ	004h
DESC_TYPE_LOW		equ	002h
SEG_ACCESS		equ	001h

; DPMI 1.0 Error codes

UNSUPPORTED_FUN 	equ	8001h
INVALID_STATE		equ	8002h
SYSTEM_INTEGRITY	equ	8003h
DEADLOCK		equ	8004h
REQUEST_CANCELL		equ	8005h
RESOUCE_UNAVAILABLE	equ	8010h
DESCRIPTOR_UNAVAILABLE  equ	8011h
LINEAR_MEM_UNAVAILABLE	equ	8012h
PHYS_MEM_UNAVAILABLE	equ	8013h
BACK_STORE_UNAVAILABLE	equ	8014h
CALLBACK_UNAVAILABLE	equ	8015h
HANDLE_UNAVAILABLE	equ	8016h
LOCK_COUNT_EXCEEDED	equ	8017h
RESOURCE_OWN_EXCLUSIVE  equ	8018h
RESOURCE_OWN_SHARED	equ	8019h
INVALID_VALUE		equ	8021h
INVALID_SELECTOR	equ	8022h
INVALID_HANDLE		equ	8023h
INVALID_CALLBACK	equ	8024h
INVALID_LINEAR_ADDRESS	equ	8025h
INVALID_REQUEST		equ	8026h

; use to call native mode procedures from within a use16 segment

call32 		macro lbl
local 		xyz
		db	68h	   	;; this code runs in native mode
		dw	ddt:xyz,0  	;; push on return address
		db	68h
		dw	ddt:lbl,0  	;; push on destination address
		ret		   	;; enter use32 segment
xyz:
		endm

;
; following macro is use to transfer to protected mode from vitrual mode
;

goprot		macro
		;
		; v-86 -> native mode (32-bit, privilege level 3).
		; $386.SYS's entintd4 routes ah=10h from a v-86 task to
		; nmswitch, which rebuilds ds/es/ss/fs/gs/cs as g=1,d=1
		; descriptors over the task's own segments and irets to
		; pl 3. Clobbers ax and flags; both are dead across the
		; two call sites in Init32Code.
		;
		mov	ax,1001h
		int	0d4h
		endm

;
; following macro is use to transfer to virtual mode from protected mode
;

goreal		macro
		;
		; native mode -> v-86.  The same function number: in
		; native mode entintd4 falls through to einative, which
		; dispatches ah=10h via eixtable to einfun90 ("switch
		; from native mode to v-86 mode").
		;
		db	66h		; d=1 here: without the override this takes a
					;  32-bit immediate and eats the int opcode
		mov	ax,1001h
		int	0d4h
		endm



;
; The following Vector Macros are use for defining Protected Mode INT 31
; subfunctions
;

vector		macro	parm,fun
		dw	&parm
		dd	offset ddt:fun
		endm

endvector	macro	
		dw	-1
		dd	-1
		endm



