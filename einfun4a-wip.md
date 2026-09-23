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
	db	66h
	call	dovmint 		; edx contains vector number
	db	66h
	jmp	einback

