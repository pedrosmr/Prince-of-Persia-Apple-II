 lst off
 tr on
 org $D000
 xc off

*-------------------------------------------------
*
* 07/02/87
*
* Unidisk 3.5 interface for
* 18 sector read/write routine
*
* 09/05/89 Version for //e
*
*  Copyright 1985, 1987
*  by Roland Gustafsson
*
*-------------------------------------------------

sigblock = 16+315

*
* Permanent vars
*

slot = $FD
track = $FE
;lastrack = $FF ;NOT USED

* Zero page usage:

temp = $40
command = $41

*-------------------------------------------------
 jmp RW18
*-------------------------------------------------
GS? ds 1 ;bpl if not, bmi if GS

OFFSET = 16 ;default offset

*-------------------------------------------------
*
* READ/WRITE 18 sectors!
*

READ lda #1
 hex 2C
WRITE lda #2
 sta SPcommand

* Calculate starting block
* (OFFSET+track*9)

 lda track  ;0-34
 asl
 asl
 asl
 tax  ;x=lo

 lda #0
 rol
 tay  ;y=hi

 txa
 adc track
 tax

 tya
 adc #0
 tay

 txa
 adc #OFFSET
BOFFLO = *-1
 sta BLOCKLO

 tya
 adc #>OFFSET
BOFFHI = *-1
 sta BLOCKHI

* Loop for 18 sectors, 2 at a time.

 ldy #0
:0 tya
 pha

* Do 2 sectors

 lda BUFTABLE,Y
 sta ]rbuf0
 sta ]wbuf0
 ldx BUFTABLE+1,Y
 stx ]rbuf1
 stx ]wbuf1
 dex
 cpx ]rbuf0
 jsr RWSECTS

 pla
 tay

 bcs :rts

* Next 2 sectors

 inc BLOCKLO
 bne :1
 inc BLOCKHI

:1 iny
 iny
 cpy #18
 bne :0

 clc
:rts rts

*-----------
*
* Read or write 2 sectors
*
* If the two sectors are sequential
* then just go to the Device Driver.
*

RWSECTS bne :noncont

* We are dealing with contiguous sectors...
* if aux mem is set in any way, then we must
* load them using the non-contiguous routine..

 bit ]RAMread?
 bmi :noncont
 bit ]RAMwrite?
 bpl JMPSP

* Non-contiguous...

:noncont ldy SPcommand
 dey
 bne WSECTS

* Read two non-contiguous sectors

RSECTS lda ]rbuf0
 ora ]rbuf1
 clc
 beq :rts

 jsr JMPSPBUF
 bcs :rts

* Now move them to where they belong

 ldx #$2C  ; bit ABS
 ldy #$99  ; sta ABS,Y

* If this sector is to be ignored,
* then change sta $FF00,Y to bit.

 sty ]rmod0
 lda ]rbuf0
 bne *+5
 stx ]rmod0

 sty ]rmod1
 lda ]rbuf1
 bne *+5
 stx ]rmod1

 ldy #0
:0 lda BLOCKBUF,Y
]rmod0 sta $FF00,Y
]rbuf0 = *-1
 lda BLOCKBUF+256,Y
]rmod1 sta $FF00,Y
]rbuf1 = *-1
 iny
 bne :0

:rts rts

*-----------
*
* Write two non-contiguous sectors
*

WSECTS ldy #0
:0 lda $FF00,Y
]wbuf0 = *-1
 sta BLOCKBUF,Y
 lda $FF00,Y
]wbuf1 = *-1
 sta BLOCKBUF+256,Y
 iny
 bne :0

JMPSPBUF lda #>BLOCKBUF

*-------------------------------------------------
*
* Jump to Smart Port driver
*
* Enter: A - address of buffer
*

JMPSP sta SPbufhi

* If ERROR? hi bit is set, then just return sec

 asl ERROR?
 bcs ]rtserr

* Force main memory

 sta $C002
 sta $C004

* Trick here, first time through, calculates
* the entry point into the SmartPort, from
* then on, direct access is available.

]SPjsr jsr calcSPjsr
SPcommand db $11
 da SPcmdlist

restAux sta $C002
 lda #$11
]RAMread? = *-1
 bpl *+5
 sta $C003

 sta $C004
 lda #$11
]RAMwrite? = *-1
 bpl *+5
 sta $C005

]rtserr rts

calcSPjsr lda slot
 lsr
 lsr
 lsr
 lsr
 ora #$C0
 sta ]SPjsr+2
 sta :calcSPmod+2

:calcSPmod lda $C5FF
 clc
 adc #3
 sta ]SPjsr+1
 jmp (]SPjsr+1)

SPcmdlist db 3
unit_num db 1 ;unit one
 db 0 ;SPbuflo=$00
SPbufhi db $11
BLOCKLO db $11 ;"low"
BLOCKHI db $11 ;"med"
 db 0 ;"high" always zero!

*------------------------------------------------- RW18
*
* Entry point into RW18
*

RW18 pla
 sta GOTBYTE+1
 pla
 sta GOTBYTE+2

 bit $CFFF

* Remember aux memory settings

 lda $C013
 sta ]RAMread?
 lda $C014
 sta ]RAMwrite?

* Save aux text page if running on a GS

 bit GS?
 bpl *+5
 jsr saveTaux

* Save zpage

 ldx #0
:zsave lda 0,x
 sta ZPAGEBUF,x
 inx
 bne :zsave

* Get the command

 jsr GETBYTE
 sta command
 and #$0F
 asl
 tax

 lda cmdadr,X
 sta :1+1
 lda cmdadr+1,X
 sta :1+2

:1 jsr $FFFF

* Restore aux text page if running on a GS

 bit GS?
 bpl *+5
 jsr restTaux

* Restore aux memory settings

 jsr restAux

* Restore zpage

 ldy track
 ldx #0
:zrest lda ZPAGEBUF,x
 sta 0,x
 inx
 bne :zrest
 sty track

 lda GOTBYTE+2
 pha
 lda GOTBYTE+1
 pha

rts rts

cmdadr da CMdriveon
 da rts  ; CMDRIVOFF
 da CMseek
 da CMreadseq
 da CMreadgroup
 da CMwriteseq
 da CMwritegroup
 da CMid
 da CMoffset

*------------------------------------------------- CMseek
*
* SEEK
* <check disk for lastrack?>,
* <track>
*

CMseek jsr GETBYTE
 jsr GETBYTE
 sta track
 rts

*------------------------------------------------- CMreadseq
*------------------------------------------------- CMreadgroup
*
* Read sequence
* <buf adr>
*
* Read group
* <18 buf adr's>
*

CMreadseq ldx #1
 hex 2C
CMreadgroup ldx #18
 jsr CMADINFO

CMREAD2 jsr READ

*-------------------------------------------------
*
* READ/WRITE exit.
*
INCTRAK? bit command
 bcs WHOOP?

* If bit 6 set, then inc track

 bvc ]rts
 inc track
]rts rts

* If bit 7 set then whoop speaker
* WARNING:use only with READ

WHOOP? bpl ]rts
 ldy #0
:1 tya
 bit $C030
:2 sec
 sbc #1
 bne :2
 dey
 bne :1
 beq CMREAD2

*------------------------------------------------- CMdriveon
*
* "DriveOn" is when we check for the POP disk
*

ERROR? db 0

CMdriveon ldy #sigblock
 lda #>sigblock
 sty BLOCKLO
 sta BLOCKHI

 lda #1 ;read
 sta SPcommand

 jsr JMPSPBUF ;read in sig block
 bcs :9

 ldy #-1
:chksig iny
 lda :sig,y
 beq :9
 eor BLOCKBUF,y
 beq :chksig
 sec

:9 lda #0
 ror
 sta ERROR?
 rts

:sig asc 'Prince of Persia 3.5!',00

*------------------------------------------------- CMwriteseq
*------------------------------------------------- CMwritegroup
*
* Same as READ
*

CMwriteseq ldx #1
 hex 2C
CMwritegroup ldx #18
 jsr CMADINFO
 jsr WRITE
 jmp INCTRAK?

*------------------------------------------------- CMid
*
* Change offset based on ID
*

CMid jsr GETBYTE
 sta :IDmod+1

 ldy #-3
:0 iny
 iny
 iny
 lda :IDlist,y
 beq :rts

:IDmod cmp #$11
 bne :0

 lda :IDlist+1,y
 sta BOFFLO
 lda :IDlist+2,y
 sta BOFFHI

:rts rts

:IDlist db $A9
 dw 16 ;side one

 db $AD
 dw 16+315+1 ;side two

 db $79
 dw 16+315+1+315 ;side three!!!

 db 0 ;end of list

*-------------------------------------------------
*
* Set new block offset
*

CMoffset jsr GETBYTE
 sta BOFFLO
 jsr GETBYTE
 sta BOFFHI
 rts

*-------------------------------------------------
*
* Get buffer info.
*

CMADINFO stx temp
 ldx #0
:0 jsr GETBYTE
 jsr auxTfix
 sta BUFTABLE,X
 inx
 cpx temp
 bcc :0
 tay

* If sequence, then fill table

:1 iny
 cpx #18
 beq :2
 tya
 jsr auxTfix
 sta BUFTABLE,X
 inx
 bne :1

:2 rts

*-------------------------------------------------
*
* Only if running on a GS:
*
* If loading into text page, then change to
* load into internal buffer instead.
*

auxTfix bit GS?
 bpl :0

 cmp #4
 bcc :0
 cmp #8
 bcs :0
 adc #>auxTPAGEsave-$400

:0 rts

*-------------------------------------------------
*
* Only if running on a GS:
*
* Save the aux memory text page to internal buffer
*

 xc
 xc

saveTaux clc
 xce
 rep $30
 ldx #$0400
 ldy #auxTPAGEsave
 lda #$400-1
 phb
 mvn $10400,0
 plb
 sec
 xce
 rts

*-------------------------------------------------
*
* Only if running on a GS:
*
* Restore aux text page from internal buffer

restTaux clc
 xce
 rep $30
 ldx #auxTPAGEsave
 ldy #$0400
 lda #$400-1
 phb
 mvn 0,$10400
 plb
 sec
 xce
 rts

 xc off

*-------------------------------------------------

GETBYTE inc GOTBYTE+1
 bne GOTBYTE
 inc GOTBYTE+2
GOTBYTE lda $FFFF
 rts

*-------------------------------------------------

 sav rw1835.pop

*-------------------------------------------------

 lst on

ZPAGEBUF ds $100
BUFTABLE ds 18
 ds \
BLOCKBUF ds 512

auxTPAGEsave ds 1024

 da *

 lst off

*------------------------------------------------- EOF
