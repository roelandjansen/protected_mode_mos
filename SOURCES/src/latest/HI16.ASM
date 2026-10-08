	.286
;--------------------------------------------------------------------
; HI16.COM - a 16-BIT DPMI client (entry ax=0) whose 32-bit registers
; carry junk in their high words: int 21h create / write / delete with
; edx = 0BADxxxxh and ecx = 0BADxxxxh. A host that takes the full
; 32-bit registers for a 16-bit client misses the name and the buffer.
; (UPDATE 82 test client)
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
inpm:

; protected mode, 16-bit code; ds = a selector for the .COM

	.386
	mov	edx,0bad0000h
	mov	dx,offset m_pm
	mov	ah,9
	int	21h

	mov	edx,0bad0000h		; 3Ch create: ds:dx = name
	mov	dx,offset fname
	mov	ecx,0bad0000h		; attributes 0
	mov	ah,3ch
	int	21h
	jc	f_create
	mov	bx,ax

	mov	edx,0bad0000h		; 40h write: cx = 5 bytes at ds:dx
	mov	dx,offset data
	mov	ecx,0bad0005h
	mov	ah,40h
	int	21h
	jc	f_write
	cmp	ax,5
	jne	f_write

	mov	ah,3eh			; close
	int	21h

	mov	edx,0bad0000h		; 3Dh open, 3Fh read back, compare
	mov	dx,offset fname
	mov	ax,3d00h
	int	21h
	jc	f_read
	mov	bx,ax
	mov	edx,0bad0000h
	mov	dx,offset buf
	mov	ecx,0bad0005h
	mov	ah,3fh
	int	21h
	jc	f_read
	cmp	ax,5
	jne	f_read
	mov	ah,3eh
	int	21h
	mov	si,offset data
	mov	di,offset buf
	push	ds
	pop	es
	mov	cx,5
	cld
	repe	cmpsb
	jne	f_read

	mov	edx,0bad0000h		; 41h delete
	mov	dx,offset fname
	mov	ah,41h
	int	21h
	jc	f_del

	mov	dx,offset m_ok
	jmp	short say
f_create:
	mov	dx,offset m_fc
	jmp	short say
f_write:
	mov	dx,offset m_fw
	jmp	short say
f_read:
	mov	dx,offset m_fr
	jmp	short say
f_del:
	mov	dx,offset m_fd
say:
	mov	ah,9
	int	21h
	mov	ax,4c00h
	int	21h

entry	dd	0
fname	db	'HI16.TMP',0
data	db	'HELLO'
buf	db	5 dup(0)
m_pm	db	'HI16: 16-bit client in protected mode',13,10,'$'
m_ok	db	'HI16: create/write/read/delete with junk high words: OK',13,10,'$'
m_fc	db	'HI16: BAD create',13,10,'$'
m_fw	db	'HI16: BAD write',13,10,'$'
m_fr	db	'HI16: BAD read back',13,10,'$'
m_fd	db	'HI16: BAD delete',13,10,'$'
m_nh	db	'HI16: no DPMI host / switch failed',13,10,'$'

code	ends
	end	start
