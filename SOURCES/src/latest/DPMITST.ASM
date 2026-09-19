	.286
;--------------------------------------------------------------------
; DPMITST.COM - minimal DPMI 0.9 client, for testing $DPMI.SYS
;
; 1. int 2Fh ax=1687h  - is a host present, and what does it report?
; 2. allocate the host data block it asks for (si paragraphs)
; 3. far call the returned entry point with ax=0 (16-bit client)
; 4. report whether carry came back set
;
; Prints everything it gets so a failure is visible rather than assumed.
; Stays in real mode on failure, which is what DPMI 0.9 requires the
; host to guarantee.
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
        mov     [rCX],cx
        mov     [rDX],dx
        mov     [rSI],si
        mov     [rDI],di
        mov     [rES],es

        mov     dx,offset msghdr
        call    puts

        mov     dx,offset msgax
        call    puts
        mov     ax,[rAX]
        call    puthex
        call    crlf

        mov     ax,[rAX]		; puthex clobbers ax
        or      ax,ax
        jz      have_host

        mov     dx,offset msgnohost
        call    puts
        jmp     done

have_host:
        mov     dx,offset msgentry
        call    puts
        mov     ax,[rES]
        call    puthex
        mov     dl,':'
        call    putc
        mov     ax,[rDI]
        call    puthex
        call    crlf

        mov     dx,offset msgflags
        call    puts
        mov     ax,[rBX]
        call    puthex
        call    crlf

        mov     dx,offset msgver
        call    puts
        mov     ax,[rDX]
        call    puthex
        call    crlf

        mov     dx,offset msgparas
        call    puts
        mov     ax,[rSI]
        call    puthex
        call    crlf

;
; allocate the host's private data block, if it wants one
;
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
        mov     dx,offset msgcall
        call    puts

        mov     es,[rBlk]
        xor     ax,ax                   ; 16-bit client
        call    dword ptr [entry]

        jc      switch_failed

        mov     dx,offset msgok
        call    puts
        jmp     done

switch_failed:
        mov     dx,offset msgfail
        call    puts

done:
        mov     ax,4c00h
        int     21h

;--------------------------------------------------------------------

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
rCX     dw      0
rDX     dw      0
rSI     dw      0
rBlk    dw      0

msghdr     db 13,10,'DPMITST - DPMI 0.9 client test',13,10,'$'
msgax      db '  1687h ax   : ','$'
msgnohost  db '  no DPMI host installed (ax nonzero)',13,10,'$'
msgentry   db '  entry      : ','$'
msgflags   db '  flags (bx) : ','$'
msgver     db '  version(dx): ','$'
msgparas   db '  paras  (si): ','$'
msgnomem   db '  could not allocate the host data block',13,10,'$'
msgcall    db '  calling the mode-switch entry...',13,10,'$'
msgok      db '  returned with carry CLEAR: client is in protected mode',13,10,'$'
msgfail    db '  returned with carry SET: switch refused, still real mode',13,10,'$'

code    ends
        end     start
