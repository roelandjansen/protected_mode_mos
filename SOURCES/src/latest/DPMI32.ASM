	.286
;--------------------------------------------------------------------
; DPMI32.COM - DPMI 0.9 client test, 32-BIT client (entry ax=1)
;
; Same start as DPMITST: int 2Fh ax=1687h, host data block, then the
; mode-switch entry, but with ax=1. DPMI 0.9 (5.2) says a 32-bit
; client still resumes on a 16-bit CS with a 64K limit; only the
; interrupt and exception frames follow the client type.
;
; Right after the switch a probe tells which CS the host gave us. It
; is hand-encoded so that it decodes correctly under either operand
; size:
;
;   B8 00 00 EB nn   16-bit: mov ax,0 / jmp short over the 32-bit
;                    block. 32-bit: mov eax,nnEB0000 and fall through.
;
; The 32-bit block is hand-encoded too (mov edx,imm32 / ah=09h / exit
; with errorlevel 32h), so a non-conforming host still produces a
; readable line instead of a crash.
;--------------------------------------------------------------------

code    segment public 'CODE'
        assume  cs:code, ds:code

        org     100h

start:
        mov     bx,1000h		; a .COM owns all of memory: shrink to
        mov     ah,4ah			;  64k first or 48h cannot succeed
        int     21h
        mov     ax,1687h
        int     2fh
        mov     [rAX],ax
        mov     [rBX],bx
        mov     [rSI],si
        mov     [rDI],di
        mov     [rES],es

        mov     dx,offset msghdr
        call    puts
        mov     ax,[rAX]
        or      ax,ax
        jz      have_host
        mov     dx,offset msgnohost
        call    puts
        jmp     done

have_host:
        mov     dx,offset msgflags
        call    puts
        mov     ax,[rBX]		; bit 0: host supports 32-bit clients
        call    puthex
        call    crlf

        mov     bx,[rSI]
        or      bx,bx
        jz      no_block
        mov     ah,48h
        int     21h
        jnc     got_block
        mov     dx,offset msgnomem
        call    puts
        jmp     done
got_block:
        mov     [rBlk],ax
        jmp     do_switch
no_block:
        mov     [rBlk],cs

do_switch:
        mov     es,[rBlk]
        mov     ax,1			; 32-bit client
        call    dword ptr [entry]
        jnc     switched		; 73 rel8: same under either size
        jmp     switch_failed		; still real mode, 16-bit

;
; The probe. Nothing between here and p16 may be assembled by MASM
; as a normal instruction: its encoding would depend on the size.
;
switched:
        db      0b8h,00h,00h,0ebh
        db      p16-b32
b32:
        db      0bah			; mov edx,offset msg32cs
        dw      offset msg32cs,0	;  (dw,0 -- never dd offset: see
					;   HANDOVER UPDATE 60)
        db      0b4h,09h		; mov ah,9
        db      0cdh,21h		; int 21h
        db      0b0h,32h		; mov al,32h
        db      0b4h,4ch		; mov ah,4ch
        db      0cdh,21h		; int 21h
p16:
;
; A conforming host: 16-bit CS. From here normal code is fine.
;
        .386
        xor     edx,edx			; a 32-bit client's ds:edx: clear
					;  the high word once, puts only
					;  touches dx
        mov     dx,offset msg16cs
        call    puts

        mov     dx,offset msgcsar
        call    puts
        mov     ax,cs
        call    arhigh
        mov     dl,' '
        call    putc
        mov     ax,ss
        call    arhigh
        mov     dl,' '
        call    putc
        mov     ax,ds
        call    arhigh
        call    crlf

        mov     ax,0400h		; DPMI version
        int     31h
        pushf
        mov     [rAX],ax
        mov     [rBX],bx
        mov     dx,offset msg0400
        call    puts
        pop     ax
        call    puthex
        mov     ax,[rAX]
        call    puthex
        mov     ax,[rBX]
        call    puthex
        call    crlf
        .286

;
; Frame proof (UPDATE 62). A 32-bit client's handlers get 32-bit
; frames even when the interrupted code is the 16-bit initial CS.
; Both handlers live on a 32-bit alias of our own code (000Ah, then
; 0009h: code r/x dpl 3, D=1) and are hand-encoded 32-bit code; a
; 16-bit frame would make their iretd/retf pop garbage.
;
        .386
        mov     ax,000ah		; alias of cs (data)
        mov     bx,cs
        int     31h
        jnc     $+5
        jmp     near ptr fr_fail
        mov     word ptr [sel32],ax
        mov     bx,ax
        mov     ax,0009h		; make it 32-bit code
        mov     cx,40fah		; ch: D=1 G=0, cl: p dpl3 code r/x
        int     31h
        jnc     $+5
        jmp     near ptr fr_fail

        mov     ax,0205h		; int 60h -> sel32:h60
        mov     bl,60h
        mov     cx,word ptr [sel32]
        xor     edx,edx
        mov     dx,offset h60
        int     31h
        jnc     $+5
        jmp     near ptr fr_fail
        int     60h
r60:
        mov     ax,0203h		; #DE -> sel32:hde
        mov     bl,0
        mov     cx,word ptr [sel32]
        xor     edx,edx
        mov     dx,offset hde
        int     31h
        jnc     $+5
        jmp     near ptr fr_fail
        xor     ax,ax
        mov     bl,0
dv:     div     bl			; F6 F3: the handler skips 2 bytes

        mov     dx,offset msg32i
        call    puts
        mov     eax,dword ptr [h_eip]
        call    putdw
        mov     dx,offset msgexp
        call    puts
        mov     ax,offset r60
        call    puthex
        mov     dx,offset msgcs
        call    puts
        mov     ax,word ptr [h_cs]
        call    puthex
        mov     dl,'/'
        call    putc
        mov     ax,cs
        call    puthex
        call    crlf

        mov     dx,offset msg32x
        call    puts
        mov     eax,dword ptr [x_eip]
        call    putdw
        mov     dx,offset msgexp
        call    puts
        mov     ax,offset dv
        call    puthex
        mov     dx,offset msgcs
        call    puts
        mov     ax,word ptr [x_cs]
        call    puthex
        mov     dl,'/'
        call    putc
        mov     ax,cs
        call    puthex
        mov     dx,offset msgrcs
        call    puts
        mov     ax,word ptr [x_rcs]
        call    puthex
        call    crlf
        jmp     short fr_done
fr_fail:
        pushf
        mov     [rAX],ax
        mov     dx,offset msgfrf
        call    puts
        pop     ax
        call    puthex
        mov     ax,[rAX]
        call    puthex
        call    crlf
fr_done:
        .286
        mov     dx,offset msgdone
        call    puts
        mov     ax,4c00h
        int     21h

switch_failed:
        mov     dx,offset msgfail
        call    puts

done:
        mov     ax,4c00h
        int     21h

;--------------------------------------------------------------------

;
; High word of the access rights of selector ax (lar): bits 16-23 of
; the descriptor's second dword -- limit 19:16, AVL, D/B (40h), G (80h)
;
        .386

;
; 32-bit handlers, hand-encoded (this is a use16 segment). Reached
; through sel32, a D=1 alias of this code, so offsets are the same.
; Data goes through ss: -- a .COM's ss has the same base as ds.
;
; int 60h: frame [esp] eip, [esp+4] cs, [esp+8] eflags; iretd.
;
h60:
        db      8bh,04h,24h		; mov eax,[esp]
        db      36h,0a3h		; mov ss:[h_eip],eax
        dw      offset h_eip,0
        db      8bh,44h,24h,04h		; mov eax,[esp+4]
        db      36h,0a3h		; mov ss:[h_cs],eax
        dw      offset h_cs,0
        db      0cfh			; iretd
;
; #DE: [esp] eip, [esp+4] cs back into the host, [esp+8] error code,
; [esp+0Ch] eip, [esp+10h] cs, [esp+14h] eflags, [esp+18h] esp,
; [esp+1Ch] ss. Skip the 2-byte div; 32-bit retf.
;
hde:
        db      8bh,44h,24h,0ch		; mov eax,[esp+0Ch]
        db      36h,0a3h		; mov ss:[x_eip],eax
        dw      offset x_eip,0
        db      8bh,44h,24h,10h		; mov eax,[esp+10h]
        db      36h,0a3h		; mov ss:[x_cs],eax
        dw      offset x_cs,0
        db      8bh,44h,24h,04h		; mov eax,[esp+4]
        db      36h,0a3h		; mov ss:[x_rcs],eax
        dw      offset x_rcs,0
        db      83h,44h,24h,0ch,02h	; add dword ptr [esp+0Ch],2
        db      0cbh			; retf (32-bit)

;
; eax as eight hex digits
;
        .386
putdw   proc    near
        push    eax
        shr     eax,16
        call    puthex
        pop     eax
        call    puthex
        ret
putdw   endp
        .286

        .386
arhigh  proc    near
        movzx   eax,ax
        db      66h,0fh,02h,0c0h	; lar eax,eax (MASM 5.1 rejects it)
        shr     eax,16
        call    puthex
        ret
arhigh  endp
        .286

puts    proc    near
        mov     ah,9
        int     21h
        ret
puts    endp

putc    proc    near
        mov     ah,2
        int     21h
        ret
putc    endp

crlf    proc    near
        mov     dl,13
        call    putc
        mov     dl,10
        call    putc
        ret
crlf    endp

;
; ax as four hex digits
;
puthex  proc    near
        push    cx
        push    bx
        mov     bx,ax
        mov     cx,4
ph_loop:
        rol     bx,4
        mov     al,bl
        and     al,0fh
        add     al,'0'
        cmp     al,'9'
        jbe     ph_put
        add     al,7
ph_put:
        mov     dl,al
        push    bx
        call    putc
        pop     bx
        loop    ph_loop
        pop     bx
        pop     cx
        ret
puthex  endp

;--------------------------------------------------------------------

entry   label   dword
rDI     dw      0
rES     dw      0

rAX     dw      0
rBX     dw      0
rSI     dw      0
rBlk    dw      0

msghdr     db 13,10,'DPMI32 - DPMI 0.9 32-bit client test',13,10,'$'
msgnohost  db '  no DPMI host installed',13,10,'$'
msgflags   db '  1687h flags: ','$'
msgnomem   db '  could not allocate the host data block',13,10,'$'
msgfail    db '  32: switch refused (carry set), still real mode',13,10,'$'
msg32cs    db '  32: FAIL cs is 32-bit after entry (DPMI 0.9: 16-bit)',13,10,'$'
msg16cs    db '  32: cs is 16-bit after entry',13,10,'$'
msgcsar    db '  cs/ss/ds ar-high: ','$'
msg0400    db '  0400 fl/ax/bx: ','$'
sel32      dw 0
h_eip      dd 0
h_cs       dd 0
x_eip      dd 0
x_cs       dd 0
x_rcs      dd 0
msg32i     db '  32i int60 eip:','$'
msg32x     db '  32x #DE   eip:','$'
msgexp     db ' exp:','$'
msgcs      db ' cs:','$'
msgrcs     db ' hostcs:','$'
msgfrf     db '  32f: FAIL fl/ax: ','$'
msgdone    db '  32: done',13,10,'$'

code    ends
        end     start
