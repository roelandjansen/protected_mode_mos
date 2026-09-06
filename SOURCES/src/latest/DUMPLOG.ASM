cseg	segment para public 'CODE'
	assume	cs:cseg,ds:cseg,es:cseg,ss:cseg
	org	100h
start:
	mov	ax,0040h
	mov	es,ax
	mov	ax,es:[0f0h]	; driver's cs, saved at 0040:00F0
	or	ax,ax
	jnz	gotit
	mov	dx,offset nohost
	mov	ah,9
	int	21h
	mov	ah,4ch
	int	21h
gotit:
	mov	ds,ax		; ds -> driver segment
	mov	si,0a6h		; offset of Counters (from _DPMI.LST)
	mov	cx,11
nextbyte:
	mov	al,[si]
	mov	ah,al
	push	cx
	mov	cl,4
	shr	al,cl
	call	outnib
	mov	al,ah
	and	al,0fh
	call	outnib
	push	ax
	push	dx
	mov	dl,' '
	mov	ah,2
	int	21h
	pop	dx
	pop	ax
	pop	cx
	inc	si
	dec	cx
	jnz	nextbyte
;
; also dump the two mosddint kernel-side counters at 0040:00F2/00F3
; (msdd1 entry, msdd7 -- see protected-mode assessment addendum)
;
	push	ax
	push	dx
	mov	dl,'|'
	mov	ah,2
	int	21h
	mov	dl,' '
	int	21h
	pop	dx
	pop	ax
	mov	ax,0040h
	mov	ds,ax
	mov	si,0f2h
	mov	cx,7
kbyte:
	mov	al,[si]
	mov	ah,al
	push	cx
	mov	cl,4
	shr	al,cl
	call	outnib
	mov	al,ah
	and	al,0fh
	call	outnib
	push	ax
	push	dx
	mov	dl,' '
	mov	ah,2
	int	21h
	pop	dx
	pop	ax
	pop	cx
	inc	si
	dec	cx
	jnz	kbyte
;
; also dump the 8-slot scbdrvr-value-per-pass table at 0040:0100
; (see protected-mode assessment addendum)
;
	push	ax
	push	dx
	mov	dl,'|'
	mov	ah,2
	int	21h
	mov	dl,' '
	int	21h
	pop	dx
	pop	ax
	mov	si,100h
	mov	cx,8
wbyte:
	mov	al,[si+1]	; high byte of word first (big-endian print)
	mov	ah,al
	push	cx
	mov	cl,4
	shr	al,cl
	call	outnib
	mov	al,ah
	and	al,0fh
	call	outnib
	mov	al,[si]		; low byte of word
	mov	ah,al
	mov	cl,4
	shr	al,cl
	call	outnib
	mov	al,ah
	and	al,0fh
	call	outnib
	push	ax
	push	dx
	mov	dl,' '
	mov	ah,2
	int	21h
	pop	dx
	pop	ax
	pop	cx
	add	si,2
	dec	cx
	jnz	wbyte
;
; also print the driver's own actual load segment (0040:00F0) for
; direct comparison against the scbdrvr sequence above
;
	push	ax
	push	dx
	mov	dl,'|'
	mov	ah,2
	int	21h
	mov	dl,' '
	int	21h
	pop	dx
	pop	ax
	mov	ax,0040h
	mov	es,ax
	mov	al,es:[0f1h]	; high byte of segment
	mov	ah,al
	mov	cl,4
	shr	al,cl
	call	outnib
	mov	al,ah
	and	al,0fh
	call	outnib
	mov	al,es:[0f0h]	; low byte of segment
	mov	ah,al
	mov	cl,4
	shr	al,cl
	call	outnib
	mov	al,ah
	and	al,0fh
	call	outnib
	mov	ah,4ch
	int	21h

nohost	db	'No DPMI host found (int 2Fh 1687h failed)',13,10,'$'

outnib	proc	near
	cmp	al,10
	jb	isdig
	add	al,'A'-10
	jmp	short doprint
isdig:
	add	al,'0'
doprint:
	push	ax
	mov	dl,al
	mov	ah,2
	int	21h
	pop	ax
	ret
outnib	endp
cseg	ends
	end	start
