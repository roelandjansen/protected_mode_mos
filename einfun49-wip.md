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

