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
	db	8ah,01110110b		; mov dh,[esi+tcbid]
	;	  01...110		; disp=byte,base=esi
	db	tcbid
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

