; =====================================================================
;  Magical Drop III (PlayStation, Europe) - language selector (SLES_029.64)
;  Mouse / NeGcon support for picking the language, optional NTSC.
;    mouse:  move left/right = previous/next flag, left button = X
;    NeGcon: twist left/right = previous/next flag, I = X
;    Namco Volume (same ID as the NeGcon, two buttons): assumed until the
;    controller shows NeGcon-only input. Knob = previous/next flag, A = X
;    JP3 spinner on the d-pad (LEFT = phase A, RIGHT = phase B, turned on
;    the first time both read pressed): 4 edges = previous/next flag
; =====================================================================
.psx
.open INFILE, OUTFILE, 0x8000F800

S_PadRead   equ 0x800131ac          ; returns this frame's buttons for port a0
S_PadCall   equ 0x800136b4          ; jal S_PadRead (delay: move a0,zero)
S_Raw       equ 0x8001f4c0          ; port 1 raw controller buffer
S_Free      equ 0x800122a4          ; unreachable library code (0x50c bytes)

.org S_PadCall
    jal     sles_pad

.if NTSC
.org 0x80011474
    ori     a0, zero, 0             ; SetVideoMode(MODE_NTSC)
.org 0x80011540
    ori     v0, zero, 0             ; screen.y (both buffers)
.org 0x8001155c
    ori     v0, zero, 0
.org 0x8001156c
    sh      zero, 0x2c02(at)        ; screen.h = 0 (library default)
.org 0x80011574
    sh      zero, 0x3752(at)
.endif

.if SKIPLANG
; skip the language screen: the call that runs it returns the chosen
; index (0 = English), and the caller then loads that EXE
.org 0x80011660
    ori     v0, zero, 0             ; was: jal 0x800133C0 (language select)
.endif

.org S_Free
sles_pad:
    addiu   sp, sp, -0x18
    sw      ra, 0x10(sp)
    jal     S_PadRead
    nop
    la      t0, S_Raw
    lbu     t1, 0(t0)
    lbu     t2, 1(t0)
    nop
    beqz    t2, @@stale             ; nothing new since our last read
    nop
    bnez    t1, @@unplug
    li      t3, 0x12
    la      t5, s_vol
    sw      zero, 16(t5)            ; a good read
    beq     t2, t3, @@mouse
    li      t3, 0x23
    bne     t2, t3, @@digital
    nop
    ; ---------------- NeGcon / Volume
    ; I, II and L all at 0xF0+ at once: a garbled read, not a player
    lbu     t1, 5(t0)
    lbu     t2, 6(t0)
    lbu     t4, 7(t0)
    and     t1, t1, t2
    and     t1, t1, t4
    sltiu   t1, t1, 0xF0
    beqz    t1, @@unplug
    nop
    la      t3, s_jp3
    sw      zero, 0(t3)
    ; Volume until NeGcon-only input (analog I/II/L, any other button)
    ; shows up; then NeGcon until unplugged
    lbu     t1, 5(t0)
    lbu     t2, 6(t0)
    lbu     t4, 7(t0)
    sltiu   t1, t1, 0x61            ; 0 = I pressed
    sltiu   t2, t2, 0x61
    sltiu   t4, t4, 0x61
    xori    t1, t1, 1               ; bit0 = I
    xori    t2, t2, 1
    sll     t2, t2, 1               ; bit1 = II
    xori    t4, t4, 1
    sll     t4, t4, 2               ; bit2 = L
    or      t1, t1, t2
    or      t1, t1, t4
    andi    t2, v0, 0xF7DF          ; all but START / CIRCLE
    sltu    t2, zero, t2
    sll     t2, t2, 3               ; bit3 = any other button
    or      t1, t1, t2              ; NeGcon-only input seen this read
    la      t3, s_vol
    lw      t4, 0(t3)
    bnez    t1, @@isneg
    andi    t2, v0, 0x0820
    sw      zero, 20(t3)
    sw      zero, 28(t3)
@@chkneg:
    bnez    t4, @@negcon            ; already known to be a NeGcon
    lw      t5, 12(t3)
    lbu     t1, 4(t0)
    bnez    t5, @@vol
    li      t5, 1
    sw      t5, 12(t3)              ; first frame: take the knob as reference
    sw      zero, 8(t3)
    b       @@vol
    sw      t1, 4(t3)
@@isneg:
    ; only once the same input shows on 2 reads in a row (the selector
    ; reads every other frame), so a garbled read can't switch it
    lw      t5, 28(t3)
    lw      t6, 20(t3)
    sw      t1, 28(t3)
    and     t5, t5, t1
    beqz    t5, @@n1st
    li      t5, 1
    addiu   t5, t6, 1
@@n1st:
    sw      t5, 20(t3)
    slti    t5, t5, 2
    bnez    t5, @@chkneg
    li      t5, 1
    sw      t5, 0(t3)
@@negcon:
    lbu     t1, 5(t0)               ; I
    nop
    sltiu   t1, t1, 0x60
    bnez    t1, @@n1
    lbu     t1, 4(t0)               ; twist
    ori     v0, v0, 0x0040
@@n1:
    nop                             ; the twist load above may still be in flight
    addiu   t1, t1, -0x80
    bgez    t1, @@n2
    move    t2, t1
    subu    t2, zero, t1            ; |d|
@@n2:
    la      t3, s_defl
    sltiu   t4, t2, 0x20
    beqz    t4, @@n3
    sltiu   t4, t2, 0x40
    b       @@done
    sw      zero, 0(t3)             ; back near the centre: re-arm
@@n3:
    bnez    t4, @@done
    lw      t4, 0(t3)
    nop
    bnez    t4, @@done
    li      t4, 1
    sw      t4, 0(t3)
    bltz    t1, @@left
    nop
    b       @@done
    ori     v0, v0, 0x2000
@@left:
    b       @@done
    ori     v0, v0, 0x8000

    ; ---------------- mouse
@@mouse:
    la      t3, s_vol
    sw      zero, 0(t3)
    sw      zero, 12(t3)
    la      t3, s_jp3
    sw      zero, 0(t3)
    lbu     t1, 3(t0)
    lb      t2, 4(t0)               ; dx
    andi    t1, t1, 0x08            ; left button, active low
    la      t3, s_acc
    bnez    t1, @@m1
    nop
    ori     v0, v0, 0x0040
@@m1:
    lw      t4, 0(t3)
    nop
    addu    t4, t4, t2
    slti    t5, t4, 24
    bnez    t5, @@m2
    slti    t5, t4, -23
    ori     v0, v0, 0x2000
    b       @@m3
    move    t4, zero
@@m2:
    beqz    t5, @@m3
    nop
    ori     v0, v0, 0x8000
    move    t4, zero
@@m3:
    b       @@done
    sw      t4, 0(t3)

    ; ---------------- Volume: knob movement = flags, A = X
@@vol:
    andi    v0, v0, 0xF7DF          ; A / B never reach the menu raw
    andi    t2, t2, 0x0800
    beqz    t2, @@v1
    lbu     t1, 4(t0)
    ori     v0, v0, 0x0040
@@v1:
    lw      t2, 4(t3)
    sw      t1, 4(t3)
    subu    t2, t1, t2
    lw      t4, 8(t3)
    nop
    addu    t4, t4, t2
    slti    t5, t4, 24
    bnez    t5, @@v2
    slti    t5, t4, -23
    ori     v0, v0, 0x2000
    b       @@done
    sw      zero, 8(t3)
@@v2:
    beqz    t5, @@v3
    nop
    ori     v0, v0, 0x8000
    move    t4, zero
@@v3:
    b       @@done
    sw      t4, 8(t3)

    ; ---------------- JP3 spinner on LEFT / RIGHT
@@stale:
    la      t3, s_vol
    b       @@done
    lw      v0, 24(t3)
@@unplug:
    ; a failed read: keep the state for up to 30 reads, then reset
    la      t3, s_vol
    lw      t4, 16(t3)
    nop
    addiu   t4, t4, 1
    slti    t5, t4, 30
    beqz    t5, @@gone
    nop
    sw      t4, 16(t3)
    sw      zero, 20(t3)
    sw      zero, 28(t3)
    b       @@done
    lw      v0, 24(t3)              ; repeat the last good read
@@gone:
    sw      zero, 0(t3)
    sw      zero, 20(t3)
    sw      zero, 12(t3)
    la      t3, s_jp3
    b       @@done
    sw      zero, 0(t3)
@@digital:
    la      t3, s_vol
    sw      zero, 0(t3)
    sw      zero, 12(t3)
    la      t3, s_jp3
    andi    t8, v0, 0xA000          ; LEFT | RIGHT
    srl     t5, t8, 15              ; A
    srl     t6, t8, 13
    andi    t6, t6, 1               ; B
    sll     t7, t6, 1
    addu    t6, t6, t7
    xor     t5, t5, t6              ; position 0..3
    lw      t4, 0(t3)
    li      t9, 0xA000
    bnez    t4, @@j1
    nop
    bne     t8, t9, @@done          ; plain pad
    li      t4, 1
    sw      t4, 0(t3)               ; first L+R: latch
    sw      t5, 4(t3)
    sw      zero, 8(t3)
    sw      zero, 12(t3)
    b       @@done
    andi    v0, v0, 0x5FFF
@@j1:
    lw      t6, 4(t3)
    sw      t5, 4(t3)
    subu    t6, t5, t6
    andi    t6, t6, 3
    andi    v0, v0, 0x5FFF          ; the raw phases never reach the menu
    beqz    t6, @@done
    li      t7, 2
    beq     t6, t7, @@jskip
    li      t7, 1
    beq     t6, t7, @@jst
    li      t9, 1
    li      t9, -1
@@jst:
    sw      t9, 8(t3)
@@jadd:
    lw      t4, 12(t3)
    nop
    addu    t4, t4, t9
    slti    t5, t4, 4
    bnez    t5, @@j2
    slti    t5, t4, -3
    ori     v0, v0, 0x2000          ; next flag
    b       @@done
    sw      zero, 12(t3)
@@j2:
    beqz    t5, @@j3
    nop
    ori     v0, v0, 0x8000          ; previous flag
    move    t4, zero
@@j3:
    b       @@done
    sw      t4, 12(t3)
@@jskip:
    lw      t9, 8(t3)
    nop
    bnez    t9, @@jadd
    sll     t9, t9, 1
@@done:
    la      t3, s_vol
    sw      v0, 24(t3)
    la      t3, S_Raw
    sb      zero, 1(t3)             ; the driver rewrites it with each transfer
    lw      ra, 0x10(sp)
    nop
    jr      ra
    addiu   sp, sp, 0x18

.align 4
s_acc:      .word 0
s_defl:     .word 0
s_vol:      .word 0, 0, 0, 0, 0, 0, 0, 0 ; NeGcon seen, last knob value, accumulator, reference valid,
                                    ; failed reads in a row, NeGcon-only reads in a row, last word,
                                    ; NeGcon-only inputs on the last read
s_jp3:      .word 0, 0, 0, 0        ; latch, last position, last direction, edge count
s_end:
.if s_end > S_Free + 0x50c
    .error "selector patch too big"
.endif

.close
