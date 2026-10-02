;
; MAXTASK.COM -- print PC-MOS's maximum task size (services int D4h,
; ah=2Dh: dx = paragraphs), as ADDTASK MAX uses it. (rig tool)
;
code    segment public 'CODE'
        assume  cs:code, ds:code
        org     100h
start:
        mov     ah,2dh
        int     0d4h
        mov     ax,dx
        mov     cl,6
        shr     ax,cl                   ; paragraphs -> KB
        mov     bx,10
        xor     cx,cx
divlp:
        xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     divlp
        push    cx
        mov     dx,offset msg
        mov     ah,9
        int     21h
        pop     cx
prtlp:
        pop     dx
        add     dl,'0'
        mov     ah,2
        int     21h
        loop    prtlp
        mov     dx,offset kb
        mov     ah,9
        int     21h
        mov     ax,4c00h
        int     21h
msg     db      'MAXTASK: ','$'
kb      db      'K',13,10,'$'
code    ends
        end     start
