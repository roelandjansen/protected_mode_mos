	.286p
;--------------------------------------------------------------------
; P16.COM - a broader 16-BIT DPMI client (entry ax=0): the int 31h
; services that 16-bit protected-mode programs (Borland RTM style)
; rely on, each checked by its effect, one OK/BAD line per check.
;
;  1  0000h/0007h/0008h/0006h  allocate a descriptor, set base/limit,
;                              read the base back
;  2  0001h                    free it
;  3  000Ah                    data alias of CS: write via the alias,
;                              read via CS
;  4  0002h                    segment to selector: B800h reaches the
;                              text screen
;  5  0100h/0101h              DOS memory: write via the selector,
;                              read via real mode (0300h, int 21h 3Fh
;                              is not needed: 0002h on the segment)
;  6  0501h/0502h              64 KB extended block: write/read its
;                              last byte through a descriptor
;  7  0300h                    simulate real-mode int 21h AH=30h
;  8  0204h/0205h              protected-mode vector 60h: install,
;                              int 60h, restore
;  9  0202h/0203h              exception 0 handler, 16-bit frame:
;                              div by zero, the handler skips the div
; 10  0400h                    version
;--------------------------------------------------------------------

code	segment public 'CODE'
	assume	cs:code, ds:code

	org	100h

start:
	mov	bx,1000h		; a .COM owns all memory: shrink to 64 KB
	mov	ah,4ah
	int	21h
	mov	ax,1687h
	int	2fh
	or	ax,ax
	jnz	nohost
	mov	word ptr [entry],di
	mov	word ptr [entry+2],es
	or	si,si
	jz	doswitch
	mov	bx,si			; the host's private data
	mov	ah,48h
	int	21h
	jc	nohost
	mov	es,ax
doswitch:
	xor	ax,ax			; 16-bit client
	call	dword ptr [entry]
	jnc	inpm
nohost:
	mov	dx,offset m_nh
	mov	ah,9
	int	21h
	mov	ax,4c01h
	int	21h

;
; Print "OK  " (cf=0) or "BAD " (cf=1, counted), then the $-string at dx
;

report	proc	near
	push	dx
	mov	dx,offset m_okp
	jnc	rep1
	inc	byte ptr [nbad]
	mov	dx,offset m_badp
rep1:
	mov	ah,9
	int	21h
	pop	dx
	mov	ah,9
	int	21h
	ret
report	endp

;
; Exception 0 handler (16-bit frame: ret ip, ret cs, err, ip, cs, fl, sp, ss)
;

exc0	proc	far
	push	bp
	mov	bp,sp
	add	word ptr [bp+8],2	; skip "div bx" (2 bytes)
	push	ds
	mov	ds,cs:[myds]
	mov	byte ptr [exc_hit],1
	pop	ds
	pop	bp
	ret
exc0	endp

;
; Protected-mode int 60h handler: ax = 6060h
;

i60	proc	far
	mov	ax,6060h
	iret
i60	endp

inpm:
	mov	[myds],ds
	mov	dx,offset m_pm
	mov	ah,9
	int	21h

; 1: allocate, set base 12345h / limit 0FFFh, read base back

	xor	ax,ax
	mov	cx,1
	int	31h
	jc	t1bad
	mov	[sel1],ax
	mov	bx,ax
	mov	ax,7
	mov	cx,1
	mov	dx,2345h
	int	31h
	jc	t1bad
	mov	ax,8
	xor	cx,cx
	mov	dx,0fffh
	int	31h
	jc	t1bad
	mov	ax,6
	int	31h
	jc	t1bad
	cmp	cx,1
	jne	t1bad
	cmp	dx,2345h
	jne	t1bad
	lsl	ax,bx
	jnz	t1bad
	cmp	ax,0fffh
	jne	t1bad
	clc
	jmp	short t1rep
t1bad:
	stc
t1rep:
	mov	dx,offset m_t1
	call	report

; 2: free it; a second free must fail

	mov	ax,1
	mov	bx,[sel1]
	int	31h
	jc	t2bad
	mov	ax,1
	int	31h
	cmc
	jmp	short t2rep
t2bad:
	stc
t2rep:
	mov	dx,offset m_t2
	call	report

; 3: data alias of cs; write a byte through it, read it through cs

	mov	ax,0ah
	mov	bx,cs
	int	31h
	jc	t3bad
	mov	es,ax
	mov	byte ptr es:[probe],5ah
	cmp	byte ptr cs:[probe],5ah
	jne	t3bad
	push	ds
	pop	es
	mov	bx,ax
	mov	ax,1
	int	31h
	jc	t3bad
	clc
	jmp	short t3rep
t3bad:
	stc
t3rep:
	mov	dx,offset m_t3
	call	report

; 4: segment B800h to a selector; the screen's first cell is readable
;    and writable (read it, write it back unchanged)

	mov	ax,2
	mov	bx,0b800h
	int	31h
	jc	t4bad
	mov	es,ax
	mov	ax,es:[0]
	mov	es:[0],ax
	push	ds
	pop	es
	clc
	jmp	short t4rep
t4bad:
	stc
t4rep:
	mov	dx,offset m_t4
	call	report

; 5: DOS memory: 2 paragraphs; write via the selector, read via the
;    0002h selector of the real-mode segment

	mov	ax,100h
	mov	bx,2
	int	31h
	jc	t5bad
	mov	[dseg],ax
	mov	[dsel],dx
	mov	es,dx
	mov	word ptr es:[1eh],0a55ah
	mov	ax,2
	mov	bx,[dseg]
	int	31h
	jc	t5bad
	mov	es,ax
	cmp	word ptr es:[1eh],0a55ah
	jne	t5bad
	push	ds
	pop	es
	mov	ax,101h
	mov	dx,[dsel]
	int	31h
	jc	t5bad
	clc
	jmp	short t5rep
t5bad:
	push	ds
	pop	es
	stc
t5rep:
	mov	dx,offset m_t5
	call	report

; 6: 64 KB of extended memory; a descriptor over it; last byte

	mov	ax,501h
	mov	bx,1
	xor	cx,cx			; bx:cx = 10000h bytes
	int	31h
	jc	t6bad
	mov	[mhi],si
	mov	[mlo],di
	mov	[blin_hi],bx
	mov	[blin_lo],cx
	xor	ax,ax
	mov	cx,1
	int	31h
	jc	t6bad
	mov	[sel1],ax
	mov	bx,ax
	mov	ax,7
	mov	cx,[blin_hi]
	mov	dx,[blin_lo]
	int	31h
	jc	t6bad
	mov	ax,8
	xor	cx,cx
	mov	dx,0ffffh
	int	31h
	jc	t6bad
	mov	es,bx
	mov	byte ptr es:[0ffffh],0c3h
	mov	byte ptr es:[0],3ch
	cmp	byte ptr es:[0ffffh],0c3h
	jne	t6bad
	cmp	byte ptr es:[0],3ch
	jne	t6bad
	push	ds
	pop	es
	mov	ax,1
	int	31h
	mov	ax,502h
	mov	si,[mhi]
	mov	di,[mlo]
	int	31h
	jc	t6bad
	clc
	jmp	short t6rep
t6bad:
	push	ds
	pop	es
	stc
t6rep:
	mov	dx,offset m_t6
	call	report

; 7: 0300h, real-mode int 21h ah=30h; compare with the pm call

	mov	ah,30h
	int	21h
	mov	[ver],ax
	push	ds
	pop	es
	mov	di,offset rmregs
	mov	cx,32h/2
	xor	ax,ax
	cld
	rep	stosw
	mov	byte ptr [rmregs+1dh],30h	; ah of eax
	mov	di,offset rmregs
	mov	ax,300h
	mov	bx,21h
	xor	cx,cx
	int	31h
	jc	t7bad
	mov	ax,word ptr [rmregs+1ch]
	cmp	ax,[ver]
	jne	t7bad
	clc
	jmp	short t7rep
t7bad:
	stc
t7rep:
	mov	dx,offset m_t7
	call	report

; 8: protected-mode vector 60h

	mov	ax,204h
	mov	bl,60h
	int	31h
	jc	t8bad
	mov	[o60c],cx
	mov	[o60o],dx
	mov	ax,205h
	mov	bl,60h
	mov	cx,cs
	mov	dx,offset i60
	int	31h
	jc	t8bad
	xor	ax,ax
	int	60h
	push	ax
	mov	ax,205h
	mov	bl,60h
	mov	cx,[o60c]
	mov	dx,[o60o]
	int	31h
	pop	ax
	jc	t8bad
	cmp	ax,6060h
	jne	t8bad
	clc
	jmp	short t8rep
t8bad:
	stc
t8rep:
	mov	dx,offset m_t8
	call	report

; 9: exception 0 with a 16-bit frame

	mov	ax,202h
	mov	bl,0
	int	31h
	jc	t9bad
	mov	[oexc_c],cx
	mov	[oexc_o],dx
	mov	ax,203h
	mov	bl,0
	mov	cx,cs
	mov	dx,offset exc0
	int	31h
	jc	t9bad
	mov	byte ptr [exc_hit],0
	mov	ax,1234h
	xor	dx,dx
	xor	bx,bx
	div	bx			; #DE: the handler skips this (F7 F3)
	mov	ax,203h
	mov	bl,0
	mov	cx,[oexc_c]
	mov	dx,[oexc_o]
	int	31h
	jc	t9bad
	cmp	byte ptr [exc_hit],1
	jne	t9bad
	clc
	jmp	short t9rep
t9bad:
	stc
t9rep:
	mov	dx,offset m_t9
	call	report

; 10: version: 0.9 or later, flags bit 0 (32-bit host) set

	mov	ax,400h
	int	31h
	jc	t10bad
	cmp	ah,0
	jne	t10ok
	cmp	al,5ah
	jb	t10bad
t10ok:
	test	bl,1
	jz	t10bad
	clc
	jmp	short t10rep
t10bad:
	stc
t10rep:
	mov	dx,offset m_t10
	call	report

; summary

	mov	al,[nbad]
	add	al,'0'
	mov	[m_sum+5],al
	mov	dx,offset m_sum
	mov	ah,9
	int	21h
	mov	al,[nbad]
	mov	ah,4ch
	int	21h

entry	dd	0
myds	dw	0
sel1	dw	0
dseg	dw	0
dsel	dw	0
mhi	dw	0
mlo	dw	0
blin_hi	dw	0
blin_lo	dw	0
ver	dw	0
o60c	dw	0
o60o	dw	0
oexc_c	dw	0
oexc_o	dw	0
exc_hit	db	0
nbad	db	0
probe	db	0
rmregs	db	32h dup(0)
m_okp	db	'OK  $'
m_badp	db	'BAD $'
m_pm	db	'P16: 16-bit client in protected mode',13,10,'$'
m_t1	db	'0000h/0007h/0008h/0006h: base 12345h, limit 0FFFh',13,10,'$'
m_t2	db	'0001h: free, second free refused',13,10,'$'
m_t3	db	'000Ah: write via the CS alias, read via CS',13,10,'$'
m_t4	db	'0002h: B800h reaches the screen',13,10,'$'
m_t5	db	'0100h/0101h: DOS memory, same bytes via 0002h',13,10,'$'
m_t6	db	'0501h/0502h: 64 KB block, first and last byte',13,10,'$'
m_t7	db	'0300h: real-mode int 21h AH=30h = pm result',13,10,'$'
m_t8	db	'0204h/0205h: pm int 60h handler',13,10,'$'
m_t9	db	'0202h/0203h: #DE, 16-bit frame, div skipped',13,10,'$'
m_t10	db	'0400h: version, 32-bit host flag',13,10,'$'
m_sum	db	'P16: 0 bad',13,10,'$'
m_nh	db	'P16: no DPMI host / switch failed',13,10,'$'

code	ends
	end	start
