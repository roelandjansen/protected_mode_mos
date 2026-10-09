	include page.inc
	title	_xms.asm - XMS 3.0 driver for PC-MOS/386
;
;******************************************************************************
;*                                                                            *
;* command type: device driver                                                *
;* command name: $xms.sys                                                     *
;* command format: device=$xms.sys [wwww] [/h:n]                              *
;* purpose: provide XMS 3.0 (extended memory blocks) for PC-MOS/386, on top   *
;*          of the memory device ($$MEMDEV, i.e. $386.sys), like $ems.sys     *
;*                                                                            *
;******************************************************************************
;
; UPDATE 86 2026-10-09	new driver. See XMS-DESIGN.md.
;
;	memory device calls (far call to rhentry, as $ems.sys/$ramdisk.sys):
;	  ah=01h valloc   cx banks -> ax 0 ok / 1 short, bx start, cx got
;	  ah=02h vrelease bx start, cx banks
;	  ah=03h vremap   bx bank, cx count, es = 4k aligned segment
;	  ah=04h vunmap   cx count, es
;	  ah=12h vget0phy cx = linear page (00-ff) -> edx physical
;	a bank is a 4k page; an EMB is one run of banks.
;
;	XMS entry: far call, ah = function; ax = 1 ok, 0 error with bl = code
;

	.386

true	equ	1
false	equ	0

maxhand	equ	128			; handle table size (upper limit)
defhand	equ	32			; default handles (/h:n)

;
; handle table entry
;

hent	struc
h_used	db	0			; 1 = allocated
h_lock	db	0			; lock count
h_owner	db	0			; task id of the allocator
h_pad	db	0
h_bank	dw	0			; first bank
h_pages	dw	0			; number of 4k banks (0 = zero-length EMB)
hent	ends

hentlen	equ	8
	if	0 eq 0			; fake out public.com
tcbunreg equ	07a6h			; tcb: far pointer, called when the task is removed
	endif

	include	_xms.pub

mainseg	segment use16 para public 'CODE'
	assume	cs:mainseg,ds:nothing,es:nothing,ss:nothing

begin	label	near

;
; device header
;

	dd	-1			; next driver
	dw	8000h			; character device
	dw	strategy
	dw	interupt
	db	'XMSXXXX0'

;
; resident data
;

rhoff	dw	0			; request header
rhseg	dw	0
mroutine dd	0			; memory device entry (rhentry)
old2f	dd	0			; previous int 2fh
nhand	dw	defhand			; handles configured
winseg	dw	0			; work window segment (step 3)
taskid	db	0			; scratch: caller's task id
rnew	dw	0			; scratch: reallocate size (under cli)
unhook	db	128 dup(0)		; 1: this task id's tcbunreg points to xunreg
unprev	dd	128 dup(0)		; the handler it pointed to before

handtab	hent	maxhand dup(<>)		; handle table (only nhand used)

	page
;--------------------------------------------------------------------
;	device strategy / interrupt
;--------------------------------------------------------------------

strategy proc	far
	mov	cs:[rhseg],es
	mov	cs:[rhoff],bx
	ret
strategy endp

interupt proc	far
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	ds
	push	es
	push	cs
	pop	ds
	assume	ds:mainseg
	les	bx,dword ptr [rhoff]
	mov	al,es:[bx+2]		; command code
	or	al,al
	jnz	notinit
	jmp	init
notinit:
	mov	word ptr es:[bx+3],8103h ; done, error, unknown command
	jmp	short intexit
intdone:
	les	bx,dword ptr [rhoff]
	or	word ptr es:[bx+3],0100h ; done
intexit:
	pop	es
	pop	ds
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
interupt endp
	assume	ds:nothing

	page
;--------------------------------------------------------------------
;	int 2fh: 4300h installation check, 4310h entry point
;--------------------------------------------------------------------

int2f	proc	far
	cmp	ax,4300h
	jne	i2f1
	mov	al,80h			; XMS driver installed
	iret
i2f1:
	cmp	ax,4310h
	jne	i2f2
	push	cs
	pop	es
	mov	bx,offset xmsentry
	iret
i2f2:
	jmp	cs:[old2f]
int2f	endp

	page
;--------------------------------------------------------------------
;	XMS entry point
;--------------------------------------------------------------------
;
; The entry begins with a short jump and three nops, as the XMS spec
; requires (so others can hook it).
;

xmsentry proc	far
	jmp	short xmsgo
	nop
	nop
	nop
xmsgo:
	cmp	ah,12h
	ja	xhigh
	push	bx
	movzx	bx,ah
	shl	bx,1
	mov	bx,cs:[xtab+bx]
	xchg	bx,[esp]		; bx back, handler address on the stack
	retn				; into the handler; it returns with retf
xhigh:
	cmp	ah,88h
	je	xf88
	cmp	ah,89h
	je	xf89
	cmp	ah,8eh
	je	xf8e
	cmp	ah,8fh
	je	xf8f
	jmp	xbadfn
xmsentry endp

	even
xtab	label	word
	dw	xf00, xf01, xf02, xf03, xf04, xf05, xf06, xf07
	dw	xf08, xf09, xf0a, xf0b, xf0c, xf0d, xf0e, xf0f
	dw	xf10, xf11, xf12

	page
;--------------------------------------------------------------------
;	common exits (far return to the caller)
;--------------------------------------------------------------------

xok:					; ax = 1, bl = 0
	mov	ax,1
	xor	bl,bl
	retf

xerr:					; ax = 0, bl = error code (in bl)
	xor	ax,ax
	retf

xbadfn:
	xor	ax,ax
	mov	bl,80h			; function not implemented
	retf

	page
;--------------------------------------------------------------------
;	00h version, 01h-07h HMA and A20, 10h-12h UMB
;--------------------------------------------------------------------

xf00:
	mov	ax,0300h		; XMS 3.00
	mov	bx,0100h		; driver revision 1.00
	xor	dx,dx			; no HMA
	retf

xf01:					; request HMA
xf02:					; release HMA
	xor	ax,ax
	mov	bl,90h			; HMA does not exist
	retf

xf03:					; global enable A20
xf04:					; global disable A20
xf05:					; local enable A20
xf06:					; local disable A20
	jmp	xok			; paging: A20 is not a thing here

xf07:					; query A20
	mov	ax,1			; enabled
	xor	bl,bl
	retf

xf10:					; request UMB
	xor	ax,ax
	xor	dx,dx			; largest UMB: none
	mov	bl,0b1h			; no UMBs available
	retf

xf11:					; release UMB
xf12:					; reallocate UMB
	xor	ax,ax
	mov	bl,0b2h			; invalid UMB segment
	retf

	page
;--------------------------------------------------------------------
;	memory device helpers
;--------------------------------------------------------------------
;
; mlargest: cx = largest free run in banks (0 if none). Probes with
; valloc and gives the block back at once. Keeps other registers.
;

mlargest proc	near
	push	ax
	push	bx
	pushf
	cli
	mov	ah,1
	mov	cx,0ffffh
	call	cs:[mroutine]		; valloc: the largest block if short
	or	cx,cx
	jz	mlg1
	push	cx
	mov	ah,2
	call	cs:[mroutine]		; vrelease bx, cx
	pop	cx
mlg1:
	popf
	pop	bx
	pop	ax
	ret
mlargest endp

;
; mquery: ecx = largest free run, edx = total free, in banks. Takes
; the free runs one after another (largest first, up to 16), counts
; them and gives them all back. Keeps other registers.
;

mquery	proc	near
	push	ax
	push	bx
	push	si
	push	di
	pushf
	cli
	xor	edx,edx			; total
	xor	si,si			; largest (the first run)
	xor	di,di			; runs held
mq1:
	cmp	di,16
	jae	mq3
	mov	ah,1
	mov	cx,0ffffh
	push	edx
	call	cs:[mroutine]		; valloc: the largest run
	pop	edx
	jcxz	mq3
	push	bx
	push	cx
	inc	di
	cmp	di,1
	jne	mq2
	mov	si,cx
mq2:
	movzx	ecx,cx
	add	edx,ecx
	jmp	short mq1
mq3:					; give them all back
	or	di,di
	jz	mq4
	pop	cx
	pop	bx
	mov	ah,2
	push	edx
	call	cs:[mroutine]		; vrelease
	pop	edx
	dec	di
	jmp	short mq3
mq4:
	movzx	ecx,si
	popf
	pop	di
	pop	si
	pop	bx
	pop	ax
	ret
mquery	endp

;
; hookunreg: make the calling task's tcbunreg (removal) call xunreg,
; once per task id, keeping the handler that was there. Keeps
; registers. Called with interrupts off.
;

hookunreg proc	near
	push	ax
	push	bx
	push	es
	movzx	bx,cs:[taskid]
	cmp	cs:[unhook+bx],0
	jne	hu1
	mov	cs:[unhook+bx],1
	push	bx
	mov	ah,4			; this task's tcb
	mov	bx,-1
	int	0d4h
	pop	bx
	shl	bx,2
	mov	ax,es:[tcbunreg]
	mov	word ptr cs:[unprev+bx],ax
	mov	ax,es:[tcbunreg+2]
	mov	word ptr cs:[unprev+bx+2],ax
	mov	word ptr es:[tcbunreg],offset xunreg
	mov	es:[tcbunreg+2],cs
hu1:
	pop	es
	pop	bx
	pop	ax
	ret
hookunreg endp

;
; xunreg: called by the kernel (MOSRTASK) when a task is removed, ds =
; its tcb. Frees the task's EMBs (locked ones too: the task is gone),
; then calls the handler that was there before.
;

xunreg	proc	far
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	pushf
	cli
	mov	dl,ds:[10h]		; tcbid
	mov	si,offset handtab
	mov	cx,cs:[nhand]
xu1:
	cmp	cs:[si].h_used,1
	jne	xu2
	cmp	cs:[si].h_owner,dl
	jne	xu2
	push	cx
	mov	cx,cs:[si].h_pages
	mov	bx,cs:[si].h_bank
	jcxz	xu1a
	mov	ah,2
	call	cs:[mroutine]		; vrelease
xu1a:
	pop	cx
	mov	cs:[si].h_used,0
	mov	cs:[si].h_lock,0
xu2:
	add	si,hentlen
	loop	xu1
	movzx	bx,dl
	mov	cs:[unhook+bx],0
	shl	bx,2
	popf
	mov	ax,word ptr cs:[unprev+bx+2]
	or	ax,ax
	jz	xu3
	call	dword ptr cs:[unprev+bx]
xu3:
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	retf
xunreg	endp

;
; getowner: [taskid] = the calling task's id. Keeps registers.
;

getowner proc	near
	push	ax
	push	bx
	push	es
	mov	ah,4			; tcb of the current task
	mov	bx,-1
	int	0d4h
	mov	al,es:[10h]		; tcbid
	mov	cs:[taskid],al
	pop	es
	pop	bx
	pop	ax
	ret
getowner endp

;
; findhand: dx = handle -> si = entry offset, CF if not a used handle.
; Handles are 1..nhand.
;

findhand proc	near
	or	dx,dx
	jz	fh_bad
	cmp	dx,cs:[nhand]
	ja	fh_bad
	mov	si,dx
	dec	si
	shl	si,3			; * hentlen
	add	si,offset handtab
	cmp	cs:[si].h_used,1
	jne	fh_bad
	clc
	ret
fh_bad:
	stc
	ret
findhand endp

;
; freecount: cx = number of free handles
;

freecount proc	near
	push	si
	push	ax
	xor	cx,cx
	mov	si,offset handtab
	mov	ax,cs:[nhand]
fc1:
	cmp	cs:[si].h_used,0
	jne	fc2
	inc	cx
fc2:
	add	si,hentlen
	dec	ax
	jnz	fc1
	pop	ax
	pop	si
	ret
freecount endp

	page
;--------------------------------------------------------------------
;	08h query free extended memory (KB), 88h 32-bit version
;--------------------------------------------------------------------

xf08:
	push	ecx
	push	edx
	call	mquery			; ecx largest, edx total (banks)
	shl	ecx,2			; KB
	shl	edx,2
	mov	eax,ecx
	cmp	eax,0ffffh		; 16-bit call: clamp both
	jbe	x08a
	mov	ax,0ffffh
x08a:
	cmp	edx,0ffffh
	jbe	x08b
	mov	dx,0ffffh
x08b:
	mov	cx,dx
	pop	edx
	mov	dx,cx			; dx = total (high edx kept)
	pop	ecx
	or	ax,ax
	jz	x08none
	xor	bl,bl
	retf
x08none:
	mov	bl,0a0h			; all extended memory is allocated
	retf				; ax = 0

xf88:
	call	mquery
	shl	ecx,2			; KB
	shl	edx,2
	mov	eax,ecx			; largest
	mov	ecx,0ffffffffh		; highest ending address: not tracked
	or	eax,eax
	jz	x88none
	xor	bl,bl
	retf
x88none:
	mov	bl,0a0h
	retf

	page
;--------------------------------------------------------------------
;	09h allocate EMB (dx KB), 89h (edx KB)
;--------------------------------------------------------------------

xf09:
	movzx	edx,dx			; 16-bit call: KB in dx
xf89:
	push	ecx
	push	si
	push	di
	call	getowner
	pushf
	cli
	mov	si,offset handtab	; a free handle
	mov	di,1			; its number
	mov	cx,cs:[nhand]
x09h:
	cmp	cs:[si].h_used,0
	je	x09fh
	add	si,hentlen
	inc	di
	loop	x09h
	popf
	mov	bl,0a1h			; all handles in use
	jmp	short x09fail
x09fh:
	add	edx,3			; KB -> 4k banks, rounded up
	shr	edx,2
	cmp	edx,0ffffh
	ja	x09nomem
	mov	cx,dx
	xor	bx,bx
	jcxz	x09got			; zero-length EMB: legal
	mov	ah,1
	call	cs:[mroutine]		; valloc cx banks
	or	ax,ax
	jz	x09got
	jcxz	x09nomem		; nothing at all
	mov	ah,2			; short: give it back
	call	cs:[mroutine]
x09nomem:
	popf
	mov	bl,0a0h			; out of extended memory
	jmp	short x09fail
x09got:
	mov	cs:[si].h_used,1
	mov	cs:[si].h_lock,0
	mov	al,cs:[taskid]
	mov	cs:[si].h_owner,al
	mov	cs:[si].h_bank,bx
	mov	cs:[si].h_pages,cx
	call	hookunreg		; free them when the task is removed
	popf
	movzx	edx,di			; the handle
	pop	di
	pop	si
	pop	ecx
	jmp	xok
x09fail:
	pop	di
	pop	si
	pop	ecx
	jmp	xerr

	page
	page
;--------------------------------------------------------------------
;	0Ah free EMB (dx)
;--------------------------------------------------------------------

xf0a:
	push	cx
	push	si
	pushf
	cli
	call	findhand
	jc	x0abad
	cmp	cs:[si].h_lock,0
	jne	x0alock
	mov	cx,cs:[si].h_pages
	jcxz	x0a1
	push	bx
	mov	bx,cs:[si].h_bank
	mov	ah,2
	call	cs:[mroutine]		; vrelease
	pop	bx
x0a1:
	mov	cs:[si].h_used,0
	popf
	pop	si
	pop	cx
	jmp	xok
x0abad:
	mov	bl,0a2h			; invalid handle
	jmp	short x0afail
x0alock:
	mov	bl,0abh			; block is locked
x0afail:
	popf
	pop	si
	pop	cx
	jmp	xerr

	page
;--------------------------------------------------------------------
;	0Eh handle information, 8Eh 32-bit version
;--------------------------------------------------------------------

xf0e:
	push	si
	call	findhand
	jc	x0ebad
	push	cx
	call	freecount		; cx = free handles
	mov	bh,cs:[si].h_lock
	mov	bl,cl			; free handles (low byte)
	pop	cx
	mov	dx,cs:[si].h_pages
	shl	dx,2			; KB (fits: 16-bit call)
	pop	si
	mov	ax,1
	retf
x0ebad:
	pop	si
	mov	bl,0a2h
	jmp	xerr

xf8e:
	push	si
	call	findhand
	jc	x8ebad
	call	freecount		; cx = free handles
	mov	bh,cs:[si].h_lock
	xor	edx,edx
	mov	dx,cs:[si].h_pages
	shl	edx,2			; KB
	pop	si
	mov	ax,1
	xor	bl,bl
	retf
x8ebad:
	pop	si
	mov	bl,0a2h
	jmp	xerr

	page
;--------------------------------------------------------------------
;	work window helpers
;--------------------------------------------------------------------
;
; mapwin: bank bx into window page dl (0 or 1); ax = its segment.
; Keeps bx, cx, dx.
;

mapwin	proc	near
	push	cx
	push	es
	xor	ax,ax
	mov	ah,dl
	add	ax,cs:[winseg]		; + dl * 100h paragraphs (4 KB)
	push	ax
	mov	es,ax
	mov	cx,1
	mov	ah,3
	call	cs:[mroutine]		; vremap bx -> es
	pop	ax
	pop	es
	pop	cx
	ret
mapwin	endp

;
; unmapwin: restore both window pages. Keeps registers.
;

unmapwin proc	near
	push	ax
	push	cx
	push	es
	mov	es,cs:[winseg]
	mov	cx,2
	mov	ah,4
	call	cs:[mroutine]		; vunmap
	pop	es
	pop	cx
	pop	ax
	ret
unmapwin endp

;
; getptr: a pointer to byte eax of a block.
;   di = handle entry (0: conventional, eax = linear address)
;   dl = window page for an EMB (0 source, 1 destination)
;   dh = 1 copying downwards (eax is the LAST byte of the chunk)
; out: ax = segment, bx = offset, ecx = bytes available in that
; direction from it (including it)
;

getptr	proc	near
	or	di,di
	jnz	gpemb
	or	dh,dh
	jnz	gpcdn
	mov	bx,ax			; conventional, upwards
	and	bx,15
	shr	eax,4
	mov	ecx,0fff0h
	ret
gpcdn:					; conventional, downwards
	cmp	eax,0fff0h
	jae	gpcd1
	mov	bx,ax
	xor	ax,ax
	jmp	short gpcd2
gpcd1:
	push	eax
	sub	eax,0fff0h
	shr	eax,4			; segment
	mov	ebx,eax
	shl	ebx,4
	neg	ebx
	add	ebx,[esp]		; offset = address - segment * 16
	add	sp,4
gpcd2:
	movzx	ecx,bx
	inc	ecx
	ret
gpemb:
	push	eax
	shr	eax,12
	mov	bx,cs:[di].h_bank
	add	bx,ax			; the bank holding the byte
	call	mapwin			; ax = window segment
	pop	ebx
	and	bx,0fffh		; offset in the page
	movzx	ecx,bx
	or	dh,dh
	jnz	gpe1
	neg	ecx
	add	ecx,1000h		; upwards: to the end of the page
	ret
gpe1:
	inc	ecx			; downwards: to the start of the page
	ret
getptr	endp

	page
;--------------------------------------------------------------------
;	0Bh move extended memory block (ds:si -> structure)
;--------------------------------------------------------------------
;
;	+0 dd length (even), +4 dw source handle, +6 dd source offset,
;	+0Ah dw destination handle, +0Ch dd destination offset;
;	handle 0: the offset is a real-mode seg:off
;
; Moves in chunks of at most one 4 KB page per side, through the
; work window, interrupts off per chunk. An overlapping move within
; one block (or within conventional memory) with destination above
; source runs downwards.
;

	if	0 eq 0			; fake out public.com
m_len	equ	dword ptr [bp-4]
m_spos	equ	dword ptr [bp-8]
m_dpos	equ	dword ptr [bp-12]
m_sent	equ	word ptr [bp-14]
m_dent	equ	word ptr [bp-16]
m_dir	equ	byte ptr [bp-18]
m_err	equ	byte ptr [bp-19]
m_avs	equ	dword ptr [bp-24]
	endif

xf0b:
	push	bp
	mov	bp,sp
	sub	sp,24
	push	ecx
	push	edx
	push	esi
	push	edi
	push	ds
	push	es
	mov	m_dir,0
	mov	m_err,0
	mov	eax,ds:[si]		; length
	mov	m_len,eax
	test	al,1
	jnz	mvlen
; source
	mov	dx,ds:[si+4]
	mov	eax,ds:[si+6]
	mov	di,0
	or	dx,dx
	jnz	mvs1
	movzx	ebx,ax			; seg:off -> linear
	shr	eax,16
	shl	eax,4
	add	eax,ebx
	jmp	short mvs2
mvs1:
	push	si
	call	findhand
	mov	di,si
	pop	si
	jc	mvsh
	movzx	ebx,cs:[di].h_pages
	shl	ebx,12			; block size
	cmp	eax,ebx
	ja	mvso
	mov	ecx,eax
	add	ecx,m_len
	cmp	ecx,ebx
	ja	mvlen
mvs2:
	mov	m_spos,eax
	mov	m_sent,di
; destination
	mov	dx,ds:[si+0ah]
	mov	eax,ds:[si+0ch]
	mov	di,0
	or	dx,dx
	jnz	mvd1
	movzx	ebx,ax
	shr	eax,16
	shl	eax,4
	add	eax,ebx
	jmp	short mvd2
mvd1:
	push	si
	call	findhand
	mov	di,si
	pop	si
	jc	mvdh
	movzx	ebx,cs:[di].h_pages
	shl	ebx,12
	cmp	eax,ebx
	ja	mvdo
	mov	ecx,eax
	add	ecx,m_len
	cmp	ecx,ebx
	ja	mvlen
mvd2:
	mov	m_dpos,eax
	mov	m_dent,di

; overlap in the same block, destination above source: downwards

	mov	ax,m_sent
	cmp	ax,m_dent
	jne	mvgo
	mov	eax,m_dpos
	cmp	eax,m_spos
	jbe	mvgo
	mov	ecx,m_spos
	add	ecx,m_len
	cmp	eax,ecx
	jae	mvgo
	mov	m_dir,1
	mov	eax,m_len
	add	m_spos,eax		; one past the end; getptr gets pos - 1
	add	m_dpos,eax

mvgo:
	cmp	m_len,0
	je	mvdone
	cli
	mov	eax,m_spos
	mov	dh,m_dir
	or	dh,dh
	jz	mvg1
	dec	eax
mvg1:
	mov	di,m_sent
	mov	dl,0
	call	getptr			; ax:bx, ecx
	push	ax
	push	bx
	mov	m_avs,ecx
	mov	eax,m_dpos
	mov	dh,m_dir
	or	dh,dh
	jz	mvg2
	dec	eax
mvg2:
	mov	di,m_dent
	mov	dl,1
	call	getptr
	mov	es,ax
	mov	di,bx			; destination es:di
	cmp	ecx,m_avs		; n = min(avail d, avail s, length)
	jbe	mvg3
	mov	ecx,m_avs
mvg3:
	cmp	ecx,m_len
	jbe	mvg4
	mov	ecx,m_len
mvg4:
	pop	si
	pop	ds			; source ds:si
	mov	edx,ecx
	cmp	m_dir,0
	je	mvg5
	std
mvg5:
	rep	movsb
	cld
	sti
	sub	m_len,edx
	cmp	m_dir,0
	jne	mvg6
	add	m_spos,edx
	add	m_dpos,edx
	jmp	mvgo
mvg6:
	sub	m_spos,edx
	sub	m_dpos,edx
	jmp	mvgo

mvdone:
	call	unmapwin
	mov	bl,0
	jmp	short mvexit
mvlen:
	mov	bl,0a7h			; invalid length
	jmp	short mvfail
mvsh:
	mov	bl,0a3h			; invalid source handle
	jmp	short mvfail
mvso:
	mov	bl,0a4h			; invalid source offset
	jmp	short mvfail
mvdh:
	mov	bl,0a5h			; invalid destination handle
	jmp	short mvfail
mvdo:
	mov	bl,0a6h			; invalid destination offset
mvfail:
	mov	m_err,1
mvexit:
	pop	es
	pop	ds
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	mov	al,m_err
	mov	sp,bp
	pop	bp
	or	al,al
	jnz	mvx1
	jmp	xok
mvx1:
	jmp	xerr

	page
;--------------------------------------------------------------------
;	0Ch lock (dx) -> dx:bx physical address, 0Dh unlock
;--------------------------------------------------------------------

xf0c:
	push	si
	push	ecx
	pushf
	cli
	call	findhand
	jc	x0cbad
	cmp	cs:[si].h_lock,0ffh
	je	x0cover
	xor	edx,edx			; zero-length block: address 0
	cmp	cs:[si].h_pages,0
	je	x0cok
	mov	bx,cs:[si].h_bank
	push	edx
	call	x0cphys			; edx = physical of bank bx
	pop	ecx
	mov	ecx,edx			; first page
	mov	bx,cs:[si].h_pages
	dec	bx
	jz	x0cone
	push	ecx
	add	bx,cs:[si].h_bank
	call	x0cphys			; last page
	pop	ecx
	movzx	ebx,cs:[si].h_pages
	dec	ebx
	shl	ebx,12
	add	ebx,ecx
	cmp	edx,ebx
	jne	x0cfrag
x0cone:
	mov	edx,ecx
x0cok:
	call	unmapwin
	inc	cs:[si].h_lock
	mov	bx,dx			; dx:bx = 32-bit physical address
	shr	edx,16
	popf
	pop	ecx
	pop	si
	mov	ax,1
	retf
x0cbad:
	mov	bl,0a2h
	jmp	short x0cfail
x0cover:
	mov	bl,0ach			; lock count overflow
	jmp	short x0cfail
x0cfrag:
	call	unmapwin
	mov	bl,0adh			; lock failed (not contiguous)
x0cfail:
	popf
	pop	ecx
	pop	si
	jmp	xerr

x0cphys	proc	near			; bank bx -> edx physical
	push	ax
	push	cx
	push	dx
	mov	dl,0
	call	mapwin			; ax = window segment
	pop	dx
	mov	cx,ax
	shr	cx,8			; its linear page number (00-FF)
	mov	ah,12h
	call	cs:[mroutine]		; vget0phy -> edx
	pop	cx
	pop	ax
	ret
x0cphys	endp

xf0d:
	push	si
	call	findhand
	jc	x0dbad
	cmp	cs:[si].h_lock,0
	je	x0dnot
	dec	cs:[si].h_lock
	pop	si
	jmp	xok
x0dbad:
	mov	bl,0a2h
	jmp	short x0dfail
x0dnot:
	mov	bl,0aah			; block is not locked
x0dfail:
	pop	si
	jmp	xerr

	page
;--------------------------------------------------------------------
;	0Fh reallocate (dx handle, bx KB), 8Fh (ebx KB)
;--------------------------------------------------------------------

xf0f:
	movzx	ebx,bx
xf8f:
	push	ecx
	push	edx
	push	esi
	push	edi
	push	ds
	push	es
	pushf
	cli
	call	findhand
	jc	x0fbad
	cmp	cs:[si].h_lock,0
	jne	x0flock
	add	ebx,3			; KB -> banks
	shr	ebx,2
	cmp	ebx,0ffffh
	ja	x0fmem
	mov	di,bx			; di = new banks
	mov	cs:[rnew],bx
	mov	cx,cs:[si].h_pages	; cx = old banks
	cmp	di,cx
	je	x0fok
	jb	x0fshrink
; grow: a new run, copy the old pages, free the old run
	push	cx
	mov	cx,di
	mov	ah,1
	call	cs:[mroutine]		; valloc -> bx
	or	ax,ax
	jz	x0fgot
	jcxz	x0fnone
	mov	ah,2
	call	cs:[mroutine]		; short: give it back
x0fnone:
	pop	cx
	jmp	x0fmem
x0fgot:
	pop	cx			; old banks
	push	bx			; new start
	xor	dx,dx			; page index
x0fcp:
	cmp	dx,cx
	jae	x0fcpd
	push	cx
	push	dx
	push	bx
	add	bx,dx			; new bank + i
	mov	dl,1
	call	mapwin
	mov	es,ax
	pop	bx
	pop	dx
	push	dx
	push	bx
	mov	bx,cs:[si].h_bank
	add	bx,dx			; old bank + i
	mov	dl,0
	call	mapwin
	mov	ds,ax
	push	si
	xor	si,si
	xor	di,di
	mov	cx,1000h
	rep	movsb
	pop	si
	pop	bx
	pop	dx
	pop	cx
	inc	dx
	jmp	short x0fcp
x0fcpd:
	call	unmapwin
	mov	bx,cs:[si].h_bank	; free the old run
	mov	ah,2
	jcxz	x0fnoold
	call	cs:[mroutine]
x0fnoold:
	pop	bx
	mov	cs:[si].h_bank,bx
	mov	ax,cs:[si].h_pages	; (recompute the new size)
	jmp	short x0fset
x0fshrink:				; release the tail
	mov	bx,cs:[si].h_bank
	add	bx,di
	sub	cx,di
	mov	ah,2
	call	cs:[mroutine]
x0fset:
	mov	cx,cs:[rnew]
	mov	cs:[si].h_pages,cx
x0fok:
	popf
	pop	es
	pop	ds
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	jmp	xok
x0fbad:
	mov	bl,0a2h
	jmp	short x0ffail
x0flock:
	mov	bl,0abh
	jmp	short x0ffail
x0fmem:
	mov	bl,0a0h
x0ffail:
	popf
	pop	es
	pop	ds
	pop	edi
	pop	esi
	pop	edx
	pop	ecx
	jmp	xerr

	page
;--------------------------------------------------------------------
;	initialization (discarded)
;--------------------------------------------------------------------

resend	label	byte			; end of the resident part

	assume	ds:mainseg
init:
	mov	dx,offset banner
	mov	ah,9
	int	21h

; the memory device ($$MEMDEV) and its entry

	mov	dx,offset memdev
	mov	ax,3d02h
	int	21h
	jc	inomem
	mov	bx,ax
	mov	ax,4400h		; binary mode
	int	21h
	xor	dh,dh
	or	dl,20h
	mov	ax,4401h
	int	21h
	mov	ax,3f00h		; read the 4-byte pointer to memptr
	mov	cx,4
	mov	dx,offset memptr
	int	21h
	mov	ah,3eh
	int	21h
	push	es
	les	bx,[memptr]
	mov	ax,es:[bx]
	mov	word ptr [mroutine],ax
	mov	ax,es:[bx+2]
	mov	word ptr [mroutine+2],ax
	pop	es

; parameters: /h:n

	les	bx,dword ptr [rhoff]
	les	bx,es:[bx+18]		; command line
iparm:
	mov	al,es:[bx]
	cmp	al,0dh
	je	iparmdn
	cmp	al,0ah
	je	iparmdn
	or	al,al
	jz	iparmdn
	inc	bx
	cmp	al,'/'
	jne	iparm
	mov	al,es:[bx]
	and	al,0dfh
	cmp	al,'H'
	jne	iparm
	inc	bx
	cmp	byte ptr es:[bx],':'
	jne	iparm
	inc	bx
	xor	cx,cx			; decimal number
iph1:
	mov	al,es:[bx]
	sub	al,'0'
	jb	iph2
	cmp	al,9
	ja	iph2
	inc	bx
	imul	cx,cx,10
	xor	ah,ah
	add	cx,ax
	jmp	short iph1
iph2:
	cmp	cx,8
	jb	iparm			; out of range: keep the default
	cmp	cx,maxhand
	ja	iparm
	mov	[nhand],cx
	jmp	short iparm
iparmdn:

; window segment: a 4-digit hex word after the driver name (es:bx is
; the command line again)

	les	bx,dword ptr [rhoff]
	les	bx,es:[bx+18]
iw0:					; skip the driver name
	mov	al,es:[bx]
	cmp	al,' '
	jbe	iw1
	inc	bx
	jmp	short iw0
iw1:					; skip blanks; end of line?
	mov	al,es:[bx]
	cmp	al,0dh
	je	iwdone
	cmp	al,0ah
	je	iwdone
	or	al,al
	jz	iwdone
	cmp	al,' '
	ja	iw2
	inc	bx
	jmp	short iw1
iw2:
	cmp	al,'/'			; an option: skip the token
	je	iwskip
	xor	dx,dx
	xor	cx,cx			; digits
iwh:
	mov	al,es:[bx]
	cmp	al,'0'
	jb	iwend
	cmp	al,'9'
	jbe	iwdig
	and	al,0dfh
	cmp	al,'A'
	jb	iwend
	cmp	al,'F'
	ja	iwend
	sub	al,'A'-10-'0'
iwdig:
	sub	al,'0'
	shl	dx,4
	or	dl,al
	inc	cx
	inc	bx
	jmp	short iwh
iwend:
	cmp	cx,4
	jne	iw1
	test	dx,00ffh		; 4 KB aligned
	jnz	iw1
	mov	[winseg],dx
	jmp	short iw1
iwskip:
	inc	bx
	mov	al,es:[bx]
	cmp	al,' '
	ja	iwskip
	jmp	short iw1
iwdone:

; int 2fh

	push	es
	xor	ax,ax
	mov	es,ax
	mov	ax,es:[2fh*4]
	mov	word ptr [old2f],ax
	mov	ax,es:[2fh*4+2]
	mov	word ptr [old2f+2],ax
	cli
	mov	word ptr es:[2fh*4],offset int2f
	mov	es:[2fh*4+2],cs
	sti
	pop	es

; resident: everything up to resend; without a window segment the
; 8 KB window follows, 4 KB aligned, inside the driver

	mov	dx,offset resend
	cmp	[winseg],0
	jne	irend
	mov	ax,cs
	movzx	eax,ax
	shl	eax,4
	movzx	ecx,dx
	add	eax,ecx			; linear end of the resident part
	add	eax,0fffh
	and	eax,0fffff000h		; next 4 KB boundary
	mov	ecx,eax
	shr	ecx,4
	mov	[winseg],cx
	add	eax,2000h		; + 8 KB
	mov	cx,cs
	movzx	ecx,cx
	shl	ecx,4
	sub	eax,ecx			; as an offset from cs
	mov	dx,ax
irend:
	les	bx,dword ptr [rhoff]
	mov	word ptr es:[bx+14],dx
	mov	es:[bx+16],cs

	push	ds
	pop	es
	mov	ax,[nhand]
	mov	di,offset hmsg+2
	call	dec3
	mov	ax,[winseg]		; window segment in hex
	mov	di,offset winmsg+3
	mov	cx,4
ihx:
	mov	dl,al
	and	dl,0fh
	add	dl,'0'
	cmp	dl,'9'
	jbe	ihx1
	add	dl,7
ihx1:
	mov	es:[di],dl
	dec	di
	shr	ax,4
	loop	ihx
	mov	dx,offset instmsg
	mov	ah,9
	int	21h
	jmp	intdone

inomem:
	mov	dx,offset nomemdev
	mov	ah,9
	int	21h
	les	bx,dword ptr [rhoff]
	mov	word ptr es:[bx+14],0	; nothing resident
	mov	es:[bx+16],cs
	mov	word ptr [begin+10],'\\'	; device name unusable
	jmp	intdone

;
; dec3: ax (< 1000) as 3 decimal digits at es:[di-2..di], blanks for
; leading zeros
;

dec3	proc	near
	mov	cx,3
	mov	bl,10
d3a:
	div	bl
	add	ah,'0'
	mov	es:[di],ah
	dec	di
	xor	ah,ah
	loop	d3a
	inc	di
	mov	cx,2
d3b:
	cmp	byte ptr es:[di],'0'
	jne	d3c
	mov	byte ptr es:[di],' '
	inc	di
	loop	d3b
d3c:
	ret
dec3	endp

resident_end_dummy label byte

memdev	db	'$$MEMDEV',0
memptr	dd	0
banner	db	'PC-MOS XMS 3.0 Driver v1.00 (UPDATE 86) $'
instmsg	db	'installed, window '
winmsg	db	'0000h,'
hmsg	db	'    handles',13,10,'$'
nomemdev db	'not installed: memory management (MEMDEV=) required',13,10,'$'

mainseg	ends
	end	begin
