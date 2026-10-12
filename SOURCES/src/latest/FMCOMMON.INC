comment ^==============================================================


 this module contains functions and data common to 
 format.asm and msys.asm

 NOTE: this module contains no assume statements on purpose.
 the include statement should be preceded by an appropriate
 assume statement.  within this module, explicit segment 
 overrides should be used where necessary.


======================================================================

mjs 12/16/91	dlg mods: created this module.

======================================================================^


;==========================================================
; data used by both msys and format

drive_num	db	?	; value for bsDriveNum, from scan_partitions

bad_scan db	13,10,'Error during scan of partitions               '
	db	0dh,0ah,'$'

fattype16	db	'FAT16   '

;==========================================================
; data for scan_partitions

ourbuf	db	512 dup(?)
drives	db	?
pt0	db	4*4*16 dup(0)	; mbr copies, 64 bytes per drive (UPDATE 105)
fpri	db	4 dup(0ffh)	; slot of each drive's primary, 0ffh: none
scext	dd	0		; start sector of the extended partition (UPDATE 95)
sclba	dd	0		; sector of the next ebr, for rdsec
scdap	dw	10h,1		; int 13h 42h disk address packet: 1 sector
	dw	offset ourbuf,0	; -> ourbuf (segment set by rdsec)
scdlba	dw	0,0,0,0		; 64-bit sector number


;==========================================================
; functions

	subttl scan_partitions - determine mlg and hard drive number
	page
;======================================================================
;,fs
; scan_partitions
;
; numbers the hard disk volumes the way the kernel does (mosddblf,
; UPDATE 101/104) and finds the one asked for:
;   1. the primary partition of each drive (the first FAT entry in
;      any slot), drive 80h first;
;   2. the logical drives in the extended partitions, drive by drive;
;   3. the other FAT primaries, drive by drive.
; up to four drives (80h-83h); a drive without a valid mbr has no
; volumes.  (UPDATE 105; was two drives, primary only in slot 0)
;
; when a match is found, the return bx register value is either a
; pointer to the partition table entry for the matching partition
; or bx is 0 (when the matching partition happens to be an extended
; partition).
;
; this is done to enable the calling code to check for an mlg partition.
;
; in:	al = 0 based hard drive number to match (0 = c:, 1 = d:, etc.)
;
; out:	nc if no error
;	 al = 80 if the volume is on the first hard drive
;	    = 0 if it is on another hard drive
;	 ds:bx -> copy of partition table entry (if primary or secondary)
;	 bx = 0 (if extended)
;	cy if error
;
;,fe
;======================================================================
scan_partitions:
	pushset	cx,dx,si,di,bp,ds,es
	mov	bx,cs
	mov	ds,bx
	mov	es,bx
	mov	ah,0ffh			; volume counter, -1: none yet
	mov	bp,ax

; see how many drives there are

	mov	ah,8
	mov	dl,80h
	int	13h			; get drive parameters
	cmp	dl,0
	lje	scpx
	cmp	dl,4			; limit to 4
	jna	scpa
	mov	dl,4
scpa:
	mov	[drives],dl

; read each drive's mbr into its table, primary moved to slot 0

	xor	bx,bx
scpb:
	call	fmrdmbr
	inc	bx
	cmp	bl,[drives]
	jb	scpb

; 1. the primary partitions

	mov	dl,80h
scpc:
	call	fmptofdl		; si -> table of drive dl
	mov	bl,dl
	and	bx,3
	cmp	[fpri+bx],0ffh		; no FAT primary on this drive
	je	scpc2
	mov	ax,bp
	inc	ah
	mov	bp,ax
	cmp	ah,al
	jne	scpc2
	mov	al,dl
	mov	bx,si
	jmp	scpy
scpc2:
	inc	dl
	mov	al,dl
	and	al,7fh
	cmp	al,[drives]
	ljc	scpc			; (jb)

; 2. the extended partitions, drive by drive

	mov	dl,80h
scpg9:
	call	fmptofdl
scpg8:
	xor	di,di			; init di as a flag
	mov	cx,4			; all four slots
	sub	si,16
scpg1:
	add	si,16			; advance to next pte
	cmp	[si].peFileSystem,PTCext
	je	scpg0
	cmp	[si].peFileSystem,0fh	; extended (LBA), UPDATE 95
	jne	scpg2
scpg0:
	mov	di,si
	jmp	short scpg3
scpg2:
	loop	scpg1
scpg3:
	or	di,di			; was an extended partition found?
	jz	scpgz
	mov	ax,word ptr [di].peStartSector	; first ebr (UPDATE 95)
	mov	word ptr [scext],ax
	mov	word ptr [sclba],ax
	mov	ax,word ptr [di].peStartSector+2
	mov	word ptr [scext+2],ax
	mov	word ptr [sclba+2],ax

; read the next partition table

	mov	cl,[di].peBeginSector
	mov	ch,[di].peBeginCylinder
	mov	dh,[di].peBeginHead
scpg6:
	mov	ax,0201h		; read 1 sector
	mov	bx,offset ourbuf
	push	dx
	call	rdsec			; chs or lba (UPDATE 95)
	pop	dx
	ljc	scpx

; establish pointers to the first and second partition table entries

	mov	si,offset ourbuf+1beh
	mov	di,offset ourbuf+1beh+10h

; make sure the extended node points to a 'live' partition 

	cmp	cs:[si].peFileSystem,PTCnil
	je	scpg4

; see if this extended partition is the one

	mov	ax,bp
	inc	ah
	mov	bp,ax
	cmp	al,ah
	jne	scpg4
	mov	al,dl
	xor	bx,bx
	jmp	scpy

; if not, is there another extended partition table to deal with?

scpg4:
	cmp	[di].peFileSystem,PTCext
	je	scpg5
	cmp	[di].peFileSystem,0fh	; extended (LBA), UPDATE 95
	jne	scpgz
scpg5:
	mov	ax,word ptr [di].peStartSector	; next ebr = extended start
	add	ax,word ptr [scext]		; + start in entry 2 (UPDATE 95)
	mov	word ptr [sclba],ax
	mov	ax,word ptr [di].peStartSector+2
	adc	ax,word ptr [scext+2]
	mov	word ptr [sclba+2],ax
	mov	cl,[di].peBeginSector
	mov	ch,[di].peBeginCylinder
	mov	dh,[di].peBeginHead	; (dl is still the drive number)
	jmp	short scpg6

; next drive

scpgz:
	inc	dl
	mov	al,dl
	and	al,7fh
	cmp	al,[drives]
	ljc	scpg9			; (jb)

; 3. the other FAT primaries, drive by drive

	mov	dl,80h
scph5:
	call	fmptofdl
scph4:
	mov	cx,3
scph1:
	add	si,16
	cmp	[si].peFileSystem,PTCsm12
	je	scph2
	cmp	[si].peFileSystem,PTCsm16
	je	scph2
	cmp	[si].peFileSystem,PTCdlg
	je	scph2
	cmp	[si].peFileSystem,0eh	; FAT16 (LBA), UPDATE 95
	jne	scph3
scph2:

; see if this secondary partition is the one

	mov	ax,bp
	inc	ah
	mov	bp,ax
	cmp	al,ah
	jne	scph3
	mov	al,dl
	mov	bx,si
	jmp	scpy
scph3:
	loop	scph1

; next drive

	inc	dl
	mov	al,dl
	and	al,7fh
	cmp	al,[drives]
	ljc	scph5			; (jb)

; either a disk error occured or no match was found

scpx:
	stc
	jmp	short scpz

; found a match

scpy:
	cmp	al,80h
	je	scpy1
	xor	al,al
scpy1:
	clc
scpz:
	popset	cx,dx,si,di,bp,ds,es
	ret






	subttl fmrdmbr - read a drive's mbr, primary to slot 0
	page
;======================================================================
;,fs
; fmrdmbr - read a drive's mbr, primary to slot 0 (UPDATE 105)
;
; the same as readmbr/pickpri in mosddblf: the mbr of drive 80h+bx is
; copied to that drive's table and its first FAT entry (01h, 04h,
; 06h, 0eh), in any slot, is swapped into slot 0.  a drive whose mbr
; cannot be read or has no 55aah signature gets an empty table.
;
; in:	bx = drive index (0-3), ds = es = cs
;
; out:	the drive's table filled in or zeroed
;	[fpri+bx] = original slot of the primary, 0ffh if none
;
;,fe
;======================================================================
fmrdmbr:
	pushset	ax,bx,cx,dx,si,di
	mov	[fpri+bx],0ffh
	mov	di,bx			; di -> this drive's table
	mov	cl,6
	shl	di,cl
	add	di,offset pt0
	push	di
	xor	ax,ax			; empty table to start with
	mov	cx,4*16/2
	cld
	rep	stosw
	pop	di
	mov	dl,bl
	or	dl,80h
	push	bx
	push	dx
	mov	ax,0401h		; verify to position to cylinder 0
	mov	cx,0001h		; c0, s1
	xor	dh,dh			; h0
	int	13h
	pop	dx
	push	dx
	mov	ah,0			; reset
	int	13h
	pop	dx
	mov	ax,0201h		; read 1 sector: the mbr
	mov	bx,offset ourbuf
	mov	cx,0001h		; c0, s1
	xor	dh,dh			; h0
	int	13h
	pop	bx
	jc	fmrb9
	cmp	word ptr [ourbuf+01feh],0aa55h
	jne	fmrb9
	mov	si,offset ourbuf+1beh
	push	di
	mov	cx,4*16/2
	cld
	rep	movsw
	pop	di

; find the first FAT entry and swap it into slot 0.  bx -> table,
; si = slot offset, dx = drive index (for fpri)

	mov	dx,bx
	mov	bx,di
	xor	si,si
	xor	al,al
fmrb1:
	mov	ah,[bx+si].peFileSystem
	cmp	ah,PTCsm12
	je	fmrb2
	cmp	ah,PTCsm16
	je	fmrb2
	cmp	ah,PTCdlg
	je	fmrb2
	cmp	ah,0eh
	je	fmrb2
	add	si,16
	inc	al
	cmp	al,4
	jb	fmrb1
	jmp	short fmrb9
fmrb2:
	push	bx
	mov	bx,dx
	mov	[fpri+bx],al
	pop	bx
	or	si,si
	jz	fmrb9
	mov	cx,8
fmrb3:
	mov	ax,[bx]
	xchg	ax,[bx+si]
	mov	[bx],ax
	add	bx,2
	loop	fmrb3
fmrb9:
	popset	ax,bx,cx,dx,si,di
	ret

	subttl fmptofdl - pointer to a drive's table
	page
;======================================================================
;,fs
; fmptofdl - pointer to a drive's table (UPDATE 105)
;
; in:	dl = drive (80h-83h)
;
; out:	si = offset pt0 + (dl and 3) * 64
;
;,fe
;======================================================================
fmptofdl:
	push	cx
	mov	si,dx
	and	si,3
	mov	cl,6
	shl	si,cl
	add	si,offset pt0
	pop	cx
	ret

	subttl rdsec - read one partition table sector
	page
;======================================================================
;,fs
; rdsec - read one partition table sector into ourbuf (UPDATE 95)
;
; with the int 13h extensions (41h) the sector in sclba is read with
; 42h, otherwise the chs address in cx/dh is used.  ebrs beyond
; cylinder 1023 have no usable chs address.
;
; in:	ds = cs, dl = bios drive, cx/dh = chs address, sclba = sector
;
; out:	cy if error
;
;,fe
;======================================================================
rdsec:
	push	bx
	push	cx
	push	dx
	push	si
	mov	ah,41h
	mov	bx,55aah
	int	13h
	jc	rdsc0
	cmp	bx,0aa55h
	jne	rdsc0
	test	cl,1
	jz	rdsc0
	pop	si
	pop	dx
	push	dx
	push	si
	mov	ax,word ptr [sclba]
	mov	[scdlba],ax
	mov	ax,word ptr [sclba+2]
	mov	[scdlba+2],ax
	mov	[scdap+6],ds
	mov	si,offset scdap
	mov	ah,42h
	int	13h
	jmp	short rdsc2
rdsc0:
	pop	si
	pop	dx
	pop	cx
	push	cx
	push	dx
	push	si
	mov	ax,0201h
	mov	bx,offset ourbuf
	int	13h
rdsc2:
	pop	si
	pop	dx
	pop	cx
	pop	bx
	ret
