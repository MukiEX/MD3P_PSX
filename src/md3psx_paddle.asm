; =====================================================================
;  Magical Drop III (PlayStation, Europe) - Paddle Edition
;  PlayStation Mouse + NeGcon "virtual paddle" controls, after the
;  Neo Geo MD3 Paddle Edition (Taito F3 sensor spinner) patch.
;
;  Assembled with armips. Per-language addresses come from the
;  generated include (syms_XX.asm) written by build.py.
; =====================================================================

.psx

; ---------------------------------------------------------------------
;  constants
; ---------------------------------------------------------------------
W_UNITS     equ 128          ; paddle units per column
ST_SIZE     equ 0x60
NCARDORDER  equ 23
OPT_ROWY    equ 0x88
OPT_VALX    equ 0xB0

; per-player state offsets
ST_TYPE     equ 0x00         ; byte  0 none, 1 mouse, 2 negcon
ST_MBTN     equ 0x01         ; byte  mouse buttons (bit0 L, bit1 R)
ST_MPREVG   equ 0x02         ; byte  mouse buttons at last in-game hook
ST_DEFL     equ 0x03         ; byte  negcon twist deflected (menus)
ST_UNITS    equ 0x04         ; word  paddle position (units)
ST_DX       equ 0x08         ; word  mouse X counts since last tick
ST_DY       equ 0x0C         ; word  mouse Y counts since last tick
ST_MACC     equ 0x10         ; word  menu accumulator X
ST_MACCY    equ 0x14         ; word  menu accumulator Y
ST_TWIST    equ 0x18         ; word  negcon twist (raw)
ST_IDLE     equ 0x1C         ; word  idle ticks (mouse, in game)
ST_TCOL     equ 0x20         ; word  paddle column (with hysteresis)
ST_GSTAMP   equ 0x24         ; word  frame of last in-game hook
ST_CSTAMP   equ 0x28         ; word  frame of last card-select hook
ST_NSTAMP   equ 0x2C         ; word  frame of last name-entry hook
ST_STEP     equ 0x30         ; word  pending step for card select / name entry
ST_NACC     equ 0x34         ; word  name entry accumulator
ST_RACC     equ 0x38         ; word  negcon repeat accumulator
ST_MAG      equ 0x3C         ; word  magnet: paddle column matches held colour
ST_STEPBIT  equ 0x40         ; word  pad bit of the pending step (card select)
ST_JP3      equ 0x44         ; byte  JP3 spinner on this port: 1 = LEFT/RIGHT wiring, 2 = d-pad pairs wiring
ST_QPREV    equ 0x45         ; byte  last quadrature position (0..3)
ST_QDIR     equ 0x46         ; byte  last step direction (+1 / -1), for skipped samples
ST_VOL      equ 0x47         ; byte  1 = the ID 0x23 controller is a Namco Volume (paddle knob)
ST_VZONE    equ 0x48         ; byte  Volume: card select zone the knob is in
ST_NEG      equ 0x49         ; byte  1 = the ID 0x23 controller has shown NeGcon-only input
ST_BAD      equ 0x4A         ; byte  consecutive failed reads (30 = unplugged)
ST_NEGN     equ 0x4B         ; byte  consecutive reads with NeGcon-only input
ST_LAST     equ 0x4C         ; half  last button word returned for this port
ST_NEGS     equ 0x4E         ; byte  which NeGcon-only inputs the last read showed
ST_VBH      equ 0x50         ; byte  Volume: B held in a menu (held back as a modifier)
ST_VBACC    equ 0x51         ; byte  Volume: knob travel while B was held
ST_VCH      equ 0x52         ; byte  Volume in play, both held: 1 = pause, 2 = pull down (A first), 3 = waiting
ST_VHOLD    equ 0x53         ; byte  Volume in play: reads with both buttons held
VHOLDN      equ 100 + NTSC*20  ; 2 s to pause (100 frames PAL, 120 NTSC)
ST_PSTR     equ 0x54         ; word  this player's struct (set by the in-game hook)
ST_JSWN     equ 0x58         ; byte  d-pad pairs: a LEFT/RIGHT <-> UP/DOWN swap was seen (unlatched)
ST_JSWT     equ 0x5C         ; word  frame of that swap
JSWWIN      equ 50 + NTSC*10 ; two swaps within this many frames (1 s) latch the pairs wiring

PAD_UP      equ 0x1000
PAD_RIGHT   equ 0x2000
PAD_DOWN    equ 0x4000
PAD_LEFT    equ 0x8000
PAD_START   equ 0x0800
PAD_X       equ 0x0040
PAD_SQUARE  equ 0x0080
PAD_TRI     equ 0x0010
PAD_L1      equ 0x0004
PAD_CIRCLE  equ 0x0020
PAD_R1      equ 0x0008
PAD_SELECT  equ 0x0100

.include "syms.asm"

.open INFILE, OUTFILE, 0x8000F800

; =====================================================================
;  hooks in the game's code
; =====================================================================

; --- move the (unused) heap so InitHeap does not write into the free
;     space after the BSS
.org G_HeapLui
    lui     a0, 0x8011
    addiu   a0, a0, -0x5000         ; 0x8010B000

; --- PadInit: use InitPAD/StartPAD with raw buffers instead of the
;     outdated digital-only B(15h) driver
.org G_PadInitTail
    j       padinit_tail
    nop

; --- PadRead: build the button word from the raw buffers
.org G_PadRead
    j       pad_read
    nop

; --- per-frame input update -> our tick
.org G_InputCall
    jal     my_input

; --- in-game clown movement (s0 = player)
.org G_ClownHook
    jal     clown_hook              ; replaces lhu s2,0x366(s0); delay slot is the game's sll

; --- clown X (s3 = player)
.org G_ClownX
    jal     glide_clown             ; replaces lw v0,0x18(s3)
    lw      v1, 0x10(s3)            ; (was the next instruction)
    lw      a0, 0x14(s3)
    nop                             ; was sll v0,v0,0x14

; --- aim line X (s3 = player): lw v0,0x7500(at) -> glide offset
.org G_AimX
    jal     glide_aim

; --- balloon grid cell (s2 = player, s5 = column): lw v1,0x7500(at)
.org G_CellX
    jal     cell_hook

; --- after the grid loop: lw v0,0xcc(s2)
.org G_CellEnd
    jal     cell_end
    nop

; --- card select cursor routine (a0 = player, a1 = cursor)
.org G_Cursor
    j       cursor_hook
    nop


; --- options screen: MOUSE SPEED row
.org G_OptTabRef
    lui     s0, hi(opttab)
    addiu   s0, s0, lo(opttab)
.org G_OptLoopCnt
    slti    v0, s1, 9               ; 7 items + MOUSE SPEED + title
.org G_OptCursorCall
    jal     opt_cursor
.org G_OptDrawEnd
    jal     opt_extra               ; delay slot keeps the game's lw s4
.org G_OptScoreY
    .halfword 0xA0                  ; Score display moves down one row

; --- ranking name entry: lhu a1,pressed(at) -> name_hook (v0 = player*2)
.org G_NamePressed
    jal     name_hook

; --- NTSC (60 Hz) build: the PAL game logic is frame based and its
;     clocks already divide frames by 60, so 60 Hz is the intended speed;
;     only the video mode and the PAL centring offsets change
.if NTSC
.org G_VidMode
    ori     a0, zero, 0             ; SetVideoMode(MODE_NTSC)
.org G_ScrX
    ori     v0, zero, 0             ; screen.x (was 5)
.org G_ScrY
    ori     v0, zero, 0             ; screen.y (was 26)
.org G_MovX
    ori     v0, zero, 0             ; movie player screen.x
.org G_MovY
    ori     v0, zero, 0             ; movie player screen.y
.endif

; --- hidden cards: the three unlock-flag reads see every flag set
.if UNLOCK
.org G_Unlock1
    ori     v0, v0, 7
.org G_Unlock2
    ori     v0, v0, 7
.org G_Unlock3
    ori     v0, v0, 7
.endif

;@chunks
;@chunk cfg
cfg:
    .ascii  "PDCF"
cfg_kmenu:   .halfword 20      ; +4  mouse counts per menu step
cfg_kname:   .halfword 8       ; +6  mouse counts per letter (name entry)
cfg_invert:  .byte 0           ; +8  1 = reverse mouse X / twist
cfg_nmap:    .byte 0           ; +9  negcon twist in menus: 0 = up/down, 1 = left/right
cfg_hyst:    .halfword 8       ; +10 units past a column edge before it counts
cfg_settle:  .halfword 8       ; +12 idle ticks before re-centring (0 = never)
cfg_speed:   .byte 2           ; +14 MOUSE SPEED at power-on (0 x0.25, 1 x0.5, 2 x1, 3 x2)
cfg_magnet:  .byte 1           ; +15 same-colour slowdown (mouse) / stickiness (negcon)
cfg_dark:    .byte 1           ; +16 target column pulse (0 off, 1 on)
cfg_glide:   .byte 1           ; +17 draw clown where the paddle is
cfg_ndead:   .byte 0x18        ; +18 negcon twist dead zone for menus
cfg_nrange:  .byte 0x60        ; +19 negcon twist half-range used in game
cfg_nrate:   .halfword 0x140   ; +20 negcon menu repeat (deflection sum per step)
cfg_nthr:    .byte 0x60        ; +22 negcon I/II/L analog threshold for digital
cfg_jcnt:    .byte 8           ; +23 JP3 spinner: mouse counts per quadrature edge
speedtab:    .byte 1, 2, 4, 8  ; +24 units per mouse count for each MOUSE SPEED
pulsetab:    .byte 64, 80, 96, 112, 128, 144, 160, 144, 128, 112, 96, 80
cfg_vlo:     .byte 0x00        ; +40 Volume knob value at the left wall
cfg_vhi:     .byte 0xFF        ; +41 Volume knob value at the right wall
cfg_vcnt:    .byte 2           ; +42 Volume: mouse counts per knob step (menus)
cfg_vrsvd:   .byte 0           ; +43 reserved
.align 4

;@chunk state
; ---------------- runtime state ----------------
v_frame:     .word 0
v_speed:     .word 2
v_pulse:     .word 0           ; pulse phase counter
v_brsave:    .word 0           ; saved brightness (bit16 = valid)
state:       .fill ST_SIZE*2, 0
.align 4
raw1:        .fill 0x24, 0
raw2:        .fill 0x24, 0

;@chunk padinit
; =====================================================================
;  PadInit tail
; =====================================================================
padinit_tail:
    la      a0, raw1
    li      a1, 0x22
    la      a2, raw2
    jal     G_InitPAD
    li      a3, 0x22
    jal     G_StartPAD
    nop
    jal     G_ChangeClearPad
    move    a0, zero
    lbu     t0, cfg_speed
    nop
    sw      t0, v_speed
    j       G_PadInitEpi
    nop

;@chunk padread
; =====================================================================
;  PadRead replacement: v0 = p1 | p2<<16, active high
; =====================================================================
pad_read:
    addiu   sp, sp, -0x20
    sw      ra, 0x10(sp)
    sw      s0, 0x14(sp)
    ; After each read the ID byte of the raw buffer is cleared. The
    ; driver writes it again with every transfer, so a buffer that still
    ; reads 0 next time is old data and is not looked at twice.
    jal     pad_one
    move    a0, zero
    la      t0, state
    sh      v0, ST_LAST(t0)
    la      t0, raw1
    sb      zero, 1(t0)
    move    s0, v0
    jal     pad_one
    li      a0, 1
    la      t0, state
    sh      v0, ST_SIZE+ST_LAST(t0)
    la      t0, raw2
    sb      zero, 1(t0)
    sll     v0, v0, 16
    or      v0, v0, s0
    lw      ra, 0x10(sp)
    lw      s0, 0x14(sp)
    jr      ra
    addiu   sp, sp, 0x20

;@chunk padone
; a0 = port -> v0 = 16-bit word (active high). Leaf, uses t0-t9.
pad_one:
    la      t0, raw1
    li      t1, 0x24
    mult    a0, t1
    mflo    t1
    addu    t0, t0, t1
    la      t2, state
    li      t1, ST_SIZE
    mult    a0, t1
    mflo    t1
    addu    t2, t2, t1
    lbu     t3, 0(t0)
    lbu     t4, 1(t0)
    nop
    beqz    t4, @@stale             ; the driver hasn't written since our last read
    nop
    bnez    t3, @@none
    li      t5, 0x12
    sb      zero, ST_BAD(t2)
    beq     t4, t5, @@mouse
    li      t5, 0x23
    bne     t4, t5, @@notneg
    nop
    ; NeGcon / Volume reader lives in its own chunk. v1 on return:
    ; 0 = done (v0), 1 = Volume, carry on as a mouse (t6 = buttons),
    ; 2 = garbled read
    move    a3, ra
    jal     pad_negcon
    nop
    move    ra, a3
    li      t5, 1
    beq     v1, t5, @@mbtn
    li      t5, 2
    beq     v1, t5, @@none
    nop
    jr      ra
    nop
@@notneg:
    ; ordinary pad (digital / analog / dualshock ...)
    sb      zero, ST_TYPE(t2)
    sb      zero, ST_VOL(t2)
    sb      zero, ST_NEG(t2)
@@digital:
    j       pad_digital             ; plain pad / JP3 spinner (own chunk)
    nop
@@stale:
    lhu     v0, ST_LAST(t2)
    jr      ra
    nop
@@none:
    ; a failed read: keep everything we know about the port for up to 30
    ; reads (a dropped transfer), then treat it as unplugged
    lbu     t5, ST_BAD(t2)
    nop
    addiu   t5, t5, 1
    sltiu   t6, t5, 30
    beqz    t6, @@gone
    nop
    sb      t5, ST_BAD(t2)
    sb      zero, ST_NEGN(t2)
    sb      zero, ST_NEGS(t2)
    lhu     v0, ST_LAST(t2)         ; repeat the last good read
    jr      ra
    nop
@@gone:
    sb      zero, ST_TYPE(t2)
    sb      zero, ST_JP3(t2)        ; unplugged: forget the spinner
    sb      zero, ST_VOL(t2)
    sb      zero, ST_NEG(t2)
    sb      zero, ST_NEGN(t2)
    jr      ra
    move    v0, zero

@@mouse:
    li      t5, 1
    sb      t5, ST_TYPE(t2)
    sb      zero, ST_JP3(t2)
    sb      zero, ST_VOL(t2)
    sb      zero, ST_NEG(t2)
    lb      t5, 4(t0)               ; dx
    lb      t6, 5(t0)               ; dy
    sb      zero, 4(t0)             ; consume (the BIOS rewrites it next vblank)
    sb      zero, 5(t0)
    lw      t7, ST_DX(t2)
    lw      t8, ST_DY(t2)
    addu    t7, t7, t5
    addu    t8, t8, t6
    sw      t7, ST_DX(t2)
    sw      t8, ST_DY(t2)
    lbu     t5, 3(t0)
    nop
    nor     t5, t5, zero            ; active high
    srl     t6, t5, 3
    andi    t6, t6, 1               ; bit0 = left
    srl     t7, t5, 1
    andi    t7, t7, 2               ; bit1 = right
    or      t6, t6, t7
@@mbtn:
    sb      t6, ST_MBTN(t2)
    li      t7, 3
    beq     t6, t7, @@chord
    move    v0, zero
    ; in game the clicks go straight to catch/throw (clown_hook)
    lw      t7, v_frame
    lw      t8, ST_GSTAMP(t2)
    nop
    subu    t7, t7, t8
    sltiu   t7, t7, 3
    bnez    t7, @@mret
    andi    t7, t6, 1
    beqz    t7, @@m2
    andi    t7, t6, 2
    ori     v0, v0, PAD_X
@@m2:
    beqz    t7, @@mret
    nop
    ori     v0, v0, PAD_TRI
@@mret:
    jr      ra
    nop
@@chord:
    jr      ra
    li      v0, PAD_START

;@chunk padjp3
; =====================================================================
;  Ordinary pad, plus a JP3 "sensor" spinner wired one of two ways:
;   - LEFT = phase A, RIGHT = phase B (adapters, a spinner on the pad's
;     lines): latches the first time LEFT and RIGHT read pressed together,
;     which a d-pad can't do.
;   - across the d-pad pairs, A = LEFT or RIGHT, B = UP or DOWN (an encoder
;     inside a real pad, which can't report LEFT+RIGHT): latches when the
;     pad goes straight from only-LEFT/RIGHT to only-UP/DOWN (or back)
;     between two reads twice within a second. That is the encoder skipping
;     a state; a thumb always passes a diagonal or the centre.
;  In: t0 = raw buffer, t2 = port state, ra = PadRead's caller. Out: v0.
;  Leaf, t5-t9.
; =====================================================================
pad_digital:
    lbu     t5, 2(t0)
    lbu     t6, 3(t0)
    sll     t5, t5, 8
    or      t5, t5, t6
    xori    v0, t5, 0xFFFF
    lbu     t7, ST_JP3(t2)
    li      t9, 2
    beq     t7, t9, @@pairs
    andi    t8, v0, PAD_LEFT|PAD_RIGHT
    srl     t5, t8, 15              ; A = LEFT
    srl     t6, t8, 13
    andi    t6, t6, 1               ; B = RIGHT
@@pos:
    sll     t8, t6, 1
    addu    t6, t6, t8              ; 3B
    xor     t5, t5, t6              ; position: 00->0 10->1 11->2 01->3
    bnez    t7, @@jp3
    li      t9, PAD_LEFT|PAD_RIGHT
    andi    t8, v0, PAD_LEFT|PAD_RIGHT
    bne     t8, t9, @@pairchk       ; plain pad so far
    li      t7, 1
    sb      t7, ST_JP3(t2)          ; first L+R: latch the LEFT/RIGHT wiring
    sb      t5, ST_QPREV(t2)
    b       @@jstrip
    sb      zero, ST_QDIR(t2)
@@pairs:
    sltu    t5, zero, t8            ; A = LEFT or RIGHT
    andi    t6, v0, PAD_UP|PAD_DOWN
    b       @@pos
    sltu    t6, zero, t6            ; B = UP or DOWN
@@pairchk:
    j       pad_pairchk             ; own chunk
    nop
@@jp3:
    lbu     t6, ST_QPREV(t2)
    sb      t5, ST_QPREV(t2)
    subu    t6, t5, t6
    andi    t6, t6, 3               ; 1 = +1, 3 = -1, 2 = both phases changed
    beqz    t6, @@jstrip
    li      t7, 2
    beq     t6, t7, @@jskip
    li      t7, 1
    beq     t6, t7, @@jstep
    li      t9, 1
    li      t9, -1
@@jstep:
    sb      t9, ST_QDIR(t2)
@@jadd:
    lbu     t7, cfg_jcnt
    lw      t6, ST_DX(t2)
    mult    t9, t7
    mflo    t7
    addu    t6, t6, t7
    b       @@jstrip
    sw      t6, ST_DX(t2)
@@jskip:
    ; a whole step went by between two reads: keep the last direction
    lb      t9, ST_QDIR(t2)
    nop
    bnez    t9, @@jadd
    sll     t9, t9, 1
@@jstrip:
    li      t7, 1                   ; drives the paddle like a mouse, no clicks
    sb      t7, ST_TYPE(t2)
    sb      zero, ST_MBTN(t2)
    lbu     t7, ST_JP3(t2)
    li      t8, 0xFFFF & ~(PAD_LEFT|PAD_RIGHT)
    addiu   t7, t7, -2
    bnez    t7, @@js1
    nop
    li      t8, 0x0FFF              ; pairs wiring: no direction reaches the game
@@js1:
    and     v0, v0, t8
@@dret:
    jr      ra
    nop

;@chunk padjp3b
; d-pad pairs detection for a plain pad (see padjp3). t5-t9, v0 in/out.
pad_pairchk:
    andi    t5, v0, PAD_LEFT|PAD_RIGHT
    sltu    t5, zero, t5
    andi    t6, v0, PAD_UP|PAD_DOWN
    sltu    t6, zero, t6
    sll     t6, t6, 1
    or      t5, t5, t6              ; 1 = only LEFT/RIGHT, 2 = only UP/DOWN
    lbu     t6, ST_QPREV(t2)
    sb      t5, ST_QPREV(t2)
    xor     t6, t6, t5
    li      t7, 3
    bne     t6, t7, @@dret          ; no swap
    addiu   t6, t5, -1
    sltiu   t6, t6, 2
    beqz    t6, @@dret              ; centre <-> diagonal: a thumb does that
    nop
    lw      t7, v_frame
    lw      t8, ST_JSWT(t2)
    lbu     t9, ST_JSWN(t2)
    sw      t7, ST_JSWT(t2)
    subu    t8, t7, t8
    sltiu   t8, t8, JSWWIN
    and     t9, t9, t8              ; an earlier swap within the window
    bnez    t9, @@latchp
    li      t7, 1
    b       @@dret
    sb      t7, ST_JSWN(t2)
@@latchp:
    li      t7, 2
    sb      t7, ST_JP3(t2)          ; second swap: latch the pairs wiring
    sb      zero, ST_JSWN(t2)
    sll     t6, t5, 1
    addiu   t6, t6, -1              ; position: only A -> 1, only B -> 3
    sb      t6, ST_QPREV(t2)
    sb      zero, ST_QDIR(t2)
    li      t7, 1                   ; drives the paddle like a mouse, no clicks
    sb      t7, ST_TYPE(t2)
    sb      zero, ST_MBTN(t2)
    jr      ra
    andi    v0, v0, 0x0FFF          ; pairs wiring: no direction reaches the game
@@dret:
    jr      ra
    nop

;@chunk padneg
pad_negcon:
    ; I, II and L all at 0xF0+ at once: a garbled read, not a player
    lbu     t5, 5(t0)
    lbu     t6, 6(t0)
    lbu     t7, 7(t0)
    and     t5, t5, t6
    and     t5, t5, t7
    sltiu   t5, t5, 0xF0
    bnez    t5, @@okread
    move    v1, zero
    jr      ra
    li      v1, 2
@@okread:
    li      t5, 2
    sb      t5, ST_TYPE(t2)
    sb      zero, ST_JP3(t2)
    lbu     t5, 2(t0)
    lbu     t6, 3(t0)
    sll     t5, t5, 8
    or      t5, t5, t6
    xori    v0, t5, 0xFFFF
    ; ---- Namco Volume: same ID, but only two buttons (START and CIRCLE
    ; bits) and no analog I/II/L. The port is taken as a Volume until it
    ; shows any NeGcon-only input; then it's a NeGcon until unplugged,
    ; starting with the frame that showed it.
    lbu     t9, cfg_nthr
    lbu     t5, 5(t0)               ; I
    lbu     t6, 6(t0)               ; II
    lbu     t7, 7(t0)               ; L
    sltu    t5, t9, t5              ; bit0 = I
    sltu    t6, t9, t6
    sll     t6, t6, 1               ; bit1 = II
    sltu    t7, t9, t7
    sll     t7, t7, 2               ; bit2 = L
    or      t5, t5, t6
    or      t5, t5, t7
    andi    t6, v0, 0xFFFF & ~(PAD_START|PAD_CIRCLE)
    sltu    t6, zero, t6
    sll     t6, t6, 3               ; bit3 = any other button
    or      t5, t5, t6
    lbu     t7, ST_NEG(t2)
    bnez    t5, @@isneg             ; NeGcon-only input
    nop
    sb      zero, ST_NEGN(t2)
    sb      zero, ST_NEGS(t2)
@@chkneg:
    bnez    t7, @@tonegb            ; already known to be a NeGcon
    lbu     t7, ST_VOL(t2)
    lbu     t5, 4(t0)
    bnez    t7, @@tovol
    li      t7, 1
    sb      t7, ST_VOL(t2)          ; first frame: take the knob as reference
    b       @@tovol
    sw      t5, ST_TWIST(t2)
@@isneg:
    ; only once the same input shows on 3 reads in a row, so a garbled
    ; read can't switch it
    lbu     t6, ST_NEGS(t2)
    lbu     t8, ST_NEGN(t2)
    sb      t5, ST_NEGS(t2)
    and     t6, t6, t5
    beqz    t6, @@n1st
    li      t6, 1
    addiu   t6, t8, 1
@@n1st:
    sltiu   t8, t6, 3
    bnez    t8, @@chkneg
    sb      t6, ST_NEGN(t2)
    li      t7, 1
    sb      t7, ST_NEG(t2)
    sb      zero, ST_VOL(t2)
@@tonegb:
    j       pad_negbtn
    nop
@@tovol:
    j       pad_vol
    nop

;@chunk padnegb
; NeGcon buttons: analog I / II / L count as X / SQUARE / L1
pad_negbtn:
    lbu     t5, 4(t0)
    lbu     t9, cfg_nthr
    sw      t5, ST_TWIST(t2)
    lbu     t5, 5(t0)               ; I
    lbu     t6, 6(t0)               ; II
    sltu    t7, t9, t5
    beqz    t7, @@n1
    lbu     t5, 7(t0)               ; L
    ori     v0, v0, PAD_X
@@n1:
    sltu    t7, t9, t6
    beqz    t7, @@n2
    sltu    t7, t9, t5
    ori     v0, v0, PAD_SQUARE
@@n2:
    beqz    t7, @@n3
    nop
    ori     v0, v0, PAD_L1
@@n3:
    jr      ra
    move    v1, zero

;@chunk padvol
    ; Volume: the knob is absolute in play (tick_vol), and its movement
    ; counts like mouse X in menus. A / B behave like the mouse buttons.
pad_vol:
    li      t5, 1
    sb      t5, ST_TYPE(t2)
    srl     t6, v0, 11
    andi    t6, t6, 1               ; bit0 = A (START bit)
    srl     t7, v0, 4
    andi    t7, t7, 2               ; bit1 = B (CIRCLE bit)
    or      t6, t6, t7
    lbu     t5, 4(t0)               ; knob
    lw      t7, ST_TWIST(t2)
    sw      t5, ST_TWIST(t2)
    subu    t7, t5, t7
    lbu     t5, cfg_vcnt
    nop
    mult    t7, t5
    mflo    t9                      ; knob movement in mouse counts
    ; in play the knob is absolute (tick_vol) and the buttons go straight
    ; to catch / throw
    lw      t4, v_frame
    lw      t5, ST_GSTAMP(t2)
    nop
    subu    t5, t4, t5
    sltiu   t5, t5, 3
    bnez    t5, @@tovplay
    nop
    ; name entry: the knob picks letters
    lw      t5, ST_NSTAMP(t2)
    nop
    subu    t5, t4, t5
    sltiu   t5, t5, 3
    bnez    t5, @@vdx
    nop
    ; menus: the knob alone steps UP/DOWN; with B held it steps
    ; LEFT/RIGHT. B on its own is TRIANGLE, sent when it's let go
    ; without the knob having turned.
    andi    t5, t6, 2
    beqz    t5, @@vbup
    lbu     t8, ST_VBACC(t2)
    li      t5, 3
    bne     t6, t5, @@vbonly
    li      t5, 200
    sb      t5, ST_VBACC(t2)        ; A+B = START; B's release won't be TRIANGLE
    li      t5, 1
    b       @@vdy
    sb      t5, ST_VBH(t2)
@@vbonly:
    andi    t6, t6, 1               ; B held: keep it back for now
    bgez    t9, @@vabs
    move    t5, t9
    subu    t5, zero, t9
@@vabs:
    addu    t8, t8, t5
    sltiu   t5, t8, 200
    bnez    t5, @@vacc
    nop
    li      t8, 200
@@vacc:
    sb      t8, ST_VBACC(t2)
    li      t5, 1
    b       @@vdx
    sb      t5, ST_VBH(t2)
@@vbup:
    lbu     t5, ST_VBH(t2)
    sb      zero, ST_VBH(t2)
    beqz    t5, @@vdy               ; B wasn't held
    sb      zero, ST_VBACC(t2)
    sltiu   t5, t8, 4
    beqz    t5, @@vdy               ; the knob turned while B was held
    nop
    ori     t6, t6, 2               ; a B tap: TRIANGLE now
@@vdy:
    lw      t8, ST_DY(t2)
    nop
    addu    t8, t8, t9
    b       @@vret
    sw      t8, ST_DY(t2)
@@vdx:
    lw      t8, ST_DX(t2)
    nop
    addu    t8, t8, t9
    sw      t8, ST_DX(t2)
@@vret:
    li      v1, 1
    jr      ra
    move    v0, zero
@@tovplay:
    j       pad_vplay
    nop

;@chunk padvplay
    ; in play: A = catch, B = throw (clown_hook). With A held, B is the
    ; player's "pull down" button. Both held for 2 s is START (pause).
pad_vplay:
    lbu     t7, ST_MBTN(t2)         ; buttons on the last read
    li      t5, 3
    bne     t6, t5, @@vp0
    nop
    lbu     t8, ST_VCH(t2)
    lbu     t9, ST_VHOLD(t2)
    bnez    t8, @@vp1               ; already decided for this chord
    nop
    li      t8, 3                   ; both held: wait for the pause hold
    li      t5, 1
    bne     t7, t5, @@vp1
    nop
    li      t8, 2                   ; A came first: pull down
@@vp1:
    sltiu   t5, t9, 255
    beqz    t5, @@vp1b
    nop
    addiu   t9, t9, 1
@@vp1b:
    sb      t9, ST_VHOLD(t2)
    sltiu   t5, t9, VHOLDN
    bnez    t5, @@vp1c
    nop
    li      t8, 1                   ; held long enough: pause
@@vp1c:
    b       @@vp2
    sb      t8, ST_VCH(t2)
@@vp0:
    sb      zero, ST_VCH(t2)
    sb      zero, ST_VHOLD(t2)
    move    t8, zero
@@vp2:
    sb      t6, ST_MBTN(t2)
    li      t5, 1
    beq     t8, t5, @@vpause
    li      t5, 2
    bne     t8, t5, @@vnone
    lw      t5, ST_PSTR(t2)
    nop
    beqz    t5, @@vnone
    nop
    lhu     v0, 0x35C(t5)           ; the player's pull-down button(s)
    jr      ra
    move    v1, zero
@@vpause:
    li      v0, PAD_START
    jr      ra
    move    v1, zero
@@vnone:
    move    v0, zero
    jr      ra
    move    v1, zero

;@chunk tick
; =====================================================================
;  per-frame tick (replaces the game's call to its input routine)
; =====================================================================
my_input:
    addiu   sp, sp, -0x20
    sw      ra, 0x18(sp)
    sw      s0, 0x10(sp)
    jal     G_InputFn
    nop
    lw      t0, v_frame
    nop
    addiu   t0, t0, 1
    sw      t0, v_frame
    lw      t0, v_pulse
    nop
    addiu   t0, t0, 1
    sltiu   t1, t0, 48              ; 12 steps x 4 frames
    bnez    t1, @@ph
    nop
    move    t0, zero
@@ph:
    sw      t0, v_pulse
    jal     tick_player
    move    a0, zero
    jal     tick_player
    li      a0, 1
    lw      ra, 0x18(sp)
    lw      s0, 0x10(sp)
    jr      ra
    addiu   sp, sp, 0x20

; a0 = player. Leaf (t-regs, a-regs, v-regs).
tick_player:
    la      t2, state
    li      t1, ST_SIZE
    mult    a0, t1
    mflo    t1
    addu    t2, t2, t1
    lbu     t3, ST_TYPE(t2)
    lw      t4, v_frame
    beqz    t3, @@toclear
    lw      t5, ST_GSTAMP(t2)
    nop
    subu    t5, t4, t5
    sltiu   s0, t5, 3               ; s0 = in game (s0 saved by caller)
    li      t5, 2
    beq     t3, t5, @@tonegcon
    nop

    ; ---------------- mouse ----------------
    lw      t6, ST_DX(t2)
    lw      t7, ST_DY(t2)
    sw      zero, ST_DX(t2)
    sw      zero, ST_DY(t2)
    lbu     t5, cfg_invert
    nop
    beqz    t5, @@noinv
    nop
    subu    t6, zero, t6
@@noinv:
    beqz    s0, @@tommenu
    lbu     t5, ST_VOL(t2)
    nop
    bnez    t5, @@tovol
    nop
    ; in game: move the virtual paddle
    lw      t5, v_speed
    la      t8, speedtab
    addu    t8, t8, t5
    lbu     t8, 0(t8)
    nop
    mult    t6, t8
    mflo    t8
    lw      t5, ST_MAG(t2)
    nop
    beqz    t5, @@nomag
    nop
    bgez    t8, @@magp
    nop
    addiu   t8, t8, 1
@@magp:
    sra     t8, t8, 1
@@nomag:
    lw      t5, ST_UNITS(t2)
    nop
    addu    t5, t5, t8
    ; clamp 0 .. ncols*W-1
    bgez    t5, @@c1
    nop
    move    t5, zero
@@c1:
    lw      t9, G_NCols
    nop
    sll     t9, t9, 7               ; * W_UNITS
    addiu   t9, t9, -1
    slt     t1, t9, t5
    beqz    t1, @@c2
    nop
    move    t5, t9
@@c2:
    ; idle / settle
    lw      t1, ST_IDLE(t2)
    beqz    t6, @@idle
    nop
    move    t1, zero
    b       @@stu
    nop
@@idle:
    addiu   t1, t1, 1
    lhu     t9, cfg_settle
    nop
    bne     t1, t9, @@stu
    nop
    beqz    t9, @@stu
    nop
    lw      t5, ST_TCOL(t2)
    nop
    sll     t5, t5, 7
    addiu   t5, t5, W_UNITS/2
@@stu:
    sw      t1, ST_IDLE(t2)
    sw      t5, ST_UNITS(t2)
    sw      zero, ST_MACC(t2)
    sw      zero, ST_MACCY(t2)
    jr      ra
    sw      zero, ST_STEP(t2)

@@toclear:
    j       tick_clear
    nop
@@tonegcon:
    j       tick_negcon
    nop
@@tommenu:
    j       tick_mmenu
    nop
@@tovol:
    j       tick_vol
    nop
;@chunk tick2
tick_mmenu:
    ; name entry accumulator (only while the name entry is up)
    lw      t5, ST_NSTAMP(t2)
    nop
    subu    t5, t4, t5
    sltiu   t5, t5, 3
    beqz    t5, @@nn
    lw      t8, ST_NACC(t2)
    nop
    addu    t8, t8, t6
    b       @@nd
    sw      t8, ST_NACC(t2)
@@nn:
    sw      zero, ST_NACC(t2)
@@nd:
    ; menu accumulators
    lw      t8, ST_MACC(t2)
    lw      t9, ST_MACCY(t2)
    addu    t8, t8, t6
    addu    t9, t9, t7
    lhu     t1, cfg_kmenu
    nop
    ; clamp to +-2k
    sll     t3, t1, 1
    slt     t5, t3, t8
    beqz    t5, @@k1
    subu    t5, zero, t3
    move    t8, t3
@@k1:
    slt     t5, t8, t5
    beqz    t5, @@k2
    nop
    subu    t8, zero, t3
@@k2:
    slt     t5, t3, t9
    beqz    t5, @@k3
    subu    t5, zero, t3
    move    t9, t3
@@k3:
    slt     t5, t9, t5
    beqz    t5, @@k4
    nop
    subu    t9, zero, t3
@@k4:
    ; |x| and |y|
    bgez    t8, @@ax
    move    t6, t8
    subu    t6, zero, t8
@@ax:
    bgez    t9, @@ay
    move    t7, t9
    subu    t7, zero, t9
@@ay:
    ; pick the dominant axis that reached a step
    slt     t3, t6, t1              ; x below step?
    slt     t5, t7, t1              ; y below step?
    bnez    t3, @@tryy
    nop
    bnez    t5, @@stepx
    nop
    slt     t3, t6, t7              ; both ready: larger wins
    bnez    t3, @@stepy
    nop
@@stepx:
    bgez    t8, @@sxp
    nop
    addu    t8, t8, t1
    li      a1, -1
    b       @@sx
    li      a2, PAD_LEFT
@@sxp:
    subu    t8, t8, t1
    li      a1, 1
    li      a2, PAD_RIGHT
@@sx:
    sw      t8, ST_MACC(t2)
    b       tick_emit
    sw      t9, ST_MACCY(t2)
@@tryy:
    beqz    t5, @@stepy
    nop
    ; no step
    sw      t8, ST_MACC(t2)
    jr      ra
    sw      t9, ST_MACCY(t2)
@@stepy:
    bgez    t9, @@syp
    nop
    addu    t9, t9, t1
    li      a1, -1
    b       @@sy
    li      a2, PAD_UP
@@syp:
    subu    t9, t9, t1
    li      a1, 1
    li      a2, PAD_DOWN
@@sy:
    sw      t8, ST_MACC(t2)
    sw      t9, ST_MACCY(t2)

    ; a1 = step (+-1), a2 = pad bit to inject
tick_emit:
    lw      t5, ST_CSTAMP(t2)
    nop
    subu    t5, t4, t5
    sltiu   t5, t5, 3
    bnez    t5, @@tocard            ; card select consumes steps itself
    nop
    lw      t5, ST_NSTAMP(t2)
    nop
    subu    t5, t4, t5
    sltiu   t5, t5, 3
    bnez    t5, @@done              ; name entry uses its own accumulator
    nop
    ; inject into held + pressed
    la      t5, G_Held
    sll     t6, a0, 1
    addu    t5, t5, t6
    lhu     t7, 0(t5)
    nop
    or      t7, t7, a2
    sh      t7, 0(t5)
    la      t5, G_Pressed
    addu    t5, t5, t6
    lhu     t7, 0(t5)
    nop
    or      t7, t7, a2
    sh      t7, 0(t5)
@@done:
    jr      ra
    nop
@@tocard:
    sw      a2, ST_STEPBIT(t2)
    jr      ra
    sw      a1, ST_STEP(t2)

    ; ---------------- negcon ----------------
;@chunk tick3
tick_negcon:
    lw      t6, ST_TWIST(t2)
    lbu     t5, cfg_invert
    addiu   t6, t6, -0x80           ; -128..127
    beqz    t5, @@ninv
    nop
    subu    t6, zero, t6
@@ninv:
    beqz    s0, @@nmenu
    nop
    ; in game: absolute position. units = (d + R) * ncols*W / (2R)
    lbu     t7, cfg_nrange
    lw      t9, G_NCols
    addu    t5, t6, t7              ; d + R
    bgez    t5, @@na
    nop
    move    t5, zero
@@na:
    sll     t8, t7, 1               ; 2R
    slt     t1, t5, t8
    bnez    t1, @@nb
    nop
    addiu   t5, t8, -1
@@nb:
    sll     t9, t9, 7
    mult    t5, t9
    mflo    t5
    nop                             ; no mult/div within 2 of mflo
    nop
    div     t5, t8
    mflo    t5
    sw      t5, ST_UNITS(t2)
    sw      zero, ST_RACC(t2)
    sb      zero, ST_DEFL(t2)
    jr      ra
    sw      zero, ST_STEP(t2)

@@nmenu:
    lbu     t7, cfg_ndead
    bgez    t6, @@nabs
    move    t8, t6
    subu    t8, zero, t6
@@nabs:
    slt     t1, t7, t8              ; |d| > dead ?
    bnez    t1, @@ndefl
    nop
    sb      zero, ST_DEFL(t2)
    jr      ra
    sw      zero, ST_RACC(t2)
@@ndefl:
    lbu     t1, ST_DEFL(t2)
    subu    t8, t8, t7              ; excess
    bnez    t1, @@nrep
    li      t1, 1
    sb      t1, ST_DEFL(t2)
    sw      zero, ST_RACC(t2)
    b       @@nstep
    nop
@@nrep:
    lw      t1, ST_RACC(t2)
    lhu     t3, cfg_nrate
    addu    t1, t1, t8
    slt     t5, t1, t3
    bnez    t5, @@nnostep
    nop
    subu    t1, t1, t3
    sw      t1, ST_RACC(t2)
    b       @@nstep
    nop
@@nnostep:
    jr      ra
    sw      t1, ST_RACC(t2)
@@nstep:
    lbu     t5, cfg_nmap
    bltz    t6, @@nneg
    li      a1, 1
    beqz    t5, @@go
    li      a2, PAD_DOWN
    b       @@go
    li      a2, PAD_RIGHT
@@nneg:
    li      a1, -1
    beqz    t5, @@go
    li      a2, PAD_UP
    li      a2, PAD_LEFT
@@go:
    j       tick_emit
    nop

tick_clear:
    sw      zero, ST_DX(t2)
    sw      zero, ST_DY(t2)
    sw      zero, ST_MACC(t2)
    sw      zero, ST_MACCY(t2)
    jr      ra
    sw      zero, ST_STEP(t2)

;@chunk vol
; Volume in play: absolute knob -> paddle, units = (k - lo) * ncols*W / (hi - lo + 1)
tick_vol:
    lw      t6, ST_TWIST(t2)
    lbu     t5, cfg_invert
    lbu     t7, cfg_vlo
    lbu     t8, cfg_vhi
    beqz    t5, @@vi
    li      t5, 255
    subu    t6, t5, t6
@@vi:
    subu    t6, t6, t7              ; k - lo
    bgez    t6, @@v1
    subu    t8, t8, t7
    move    t6, zero
@@v1:
    addiu   t8, t8, 1               ; span
    slt     t1, t6, t8
    bnez    t1, @@v2
    nop
    addiu   t6, t8, -1
@@v2:
    lw      t9, G_NCols
    nop
    sll     t9, t9, 7
    mult    t6, t9
    mflo    t6
    nop
    nop
    div     t6, t8
    mflo    t6
    sw      t6, ST_UNITS(t2)
    sw      zero, ST_IDLE(t2)
    sw      zero, ST_MACC(t2)
    sw      zero, ST_MACCY(t2)
    jr      ra
    sw      zero, ST_STEP(t2)

;@chunk volcard
; Volume in card select (1P / 2P grid): the knob is a dial over the
; reading order, left end = first card, right end = last. Nothing moves
; on entry; the cursor follows once the knob enters another zone.
; Called from cursor_hook with a0 = player, a1 = cursor, t2 = state, t4 = frame.
vol_card:
    lw      t9, ST_CSTAMP(t2)
    sw      t4, ST_CSTAMP(t2)
    sw      zero, ST_STEP(t2)
    subu    t9, t4, t9
    sltiu   t9, t9, 3               ; 1 = already in card select
    lw      t6, ST_TWIST(t2)
    lbu     t5, cfg_invert
    nop
    beqz    t5, @@ni
    li      t5, 255
    subu    t6, t5, t6
@@ni:
    addiu   sp, sp, -0x20
    sw      ra, 0x10(sp)
    bal     vzone
    move    t0, t6
    move    t3, t5                  ; zone of k
    bal     vzone
    addiu   t0, t6, -2
    move    t1, t5                  ; zone of k-2
    bal     vzone
    addiu   t0, t6, 2               ; t5 = zone of k+2
    lw      ra, 0x10(sp)
    addiu   sp, sp, 0x20
    beqz    t9, @@enter
    nop
    bne     t1, t5, @@orig          ; on a zone edge: hold
    lbu     t0, ST_VZONE(t2)
    nop
    beq     t0, t3, @@orig
    nop
    sb      t3, ST_VZONE(t2)
    la      t0, cardorder
    addu    t0, t0, t3
    lbu     a1, 0(t0)
    addiu   sp, sp, -0x18
    sw      ra, 0x10(sp)
    sw      a1, 0x14(sp)
    jal     G_Sound
    li      a1, 1
    lw      ra, 0x10(sp)
    lw      v0, 0x14(sp)
    jr      ra
    addiu   sp, sp, 0x18
@@enter:
    sb      t3, ST_VZONE(t2)
@@orig:
    j       cursor_orig
    nop

; t0 = knob value -> t5 = card zone 0..NCARDORDER-1 (uses t7, t8)
vzone:
    lbu     t7, cfg_vlo
    lbu     t8, cfg_vhi
    subu    t0, t0, t7
    subu    t8, t8, t7
    addiu   t8, t8, 1               ; span
    bgez    t0, @@z1
    nop
    move    t0, zero
@@z1:
    slt     t7, t0, t8
    bnez    t7, @@z2
    nop
    addiu   t0, t8, -1
@@z2:
    li      t7, NCARDORDER
    mult    t0, t7
    mflo    t0
    nop
    nop
    div     t0, t8
    mflo    t5
    jr      ra
    nop

;@chunk clown
; =====================================================================
;  in-game clown hook. s0 = player struct. Must keep v0, v1.
;  Returns s2 = this tick's (repeat-processed) buttons.
; =====================================================================
clown_hook:
    lhu     s2, 0x366(s0)
    lw      t0, 0(s0)               ; player index
    lw      t1, 4(s0)               ; 1 = computer
    sltiu   t3, t0, 2
    beqz    t3, @@ret
    la      t2, state
    li      t3, 1
    beq     t1, t3, @@ret
    li      t1, ST_SIZE
    mult    t0, t1
    mflo    t1
    addu    t2, t2, t1
    lbu     t3, ST_TYPE(t2)
    lw      t4, v_frame
    beqz    t3, @@ret
    lw      t5, ST_GSTAMP(t2)
    sw      t4, ST_GSTAMP(t2)
    sw      s0, ST_PSTR(t2)
    subu    t5, t4, t5
    sltiu   t5, t5, 3
    lw      t6, 0x18(s0)            ; clown column
    bnez    t5, @@ingame
    nop
    ; first tick in game: start the paddle on the clown
    sw      t6, ST_TCOL(t2)
    lbu     t5, ST_MBTN(t2)
    li      t7, 2
    beq     t3, t7, @@ingame        ; negcon is absolute
    sb      t5, ST_MPREVG(t2)
    lbu     t7, ST_VOL(t2)
    nop
    bnez    t7, @@ingame            ; so is the Volume
    nop
    sll     t5, t6, 7
    addiu   t5, t5, W_UNITS/2
    sw      t5, ST_UNITS(t2)
    sw      zero, ST_IDLE(t2)
@@ingame:
    ; ---- paddle column with hysteresis
    lw      t5, ST_UNITS(t2)
    lw      t7, ST_TCOL(t2)
    lhu     t8, cfg_hyst
    lw      t9, ST_MAG(t2)
    nop
    beqz    t9, @@nomag
    li      t9, 2
    beq     t3, t9, @@sticky        ; negcon / Volume: same colour makes the column sticky
    nop
    lbu     t9, ST_VOL(t2)
    nop
    beqz    t9, @@nomag
    nop
@@sticky:
    sll     t8, t8, 2
@@nomag:
    sll     t9, t7, 7
    subu    t9, t9, t8              ; left edge - hyst
    slt     t1, t5, t9
    bnez    t1, @@newcol
    addiu   t9, t7, 1
    sll     t9, t9, 7
    addu    t9, t9, t8              ; right edge + hyst
    slt     t1, t5, t9
    bnez    t1, @@havecol
    nop
@@newcol:
    sra     t7, t5, 7
    bgez    t7, @@nc1
    nop
    move    t7, zero
@@nc1:
    lw      t9, G_NCols
    nop
    slt     t1, t7, t9
    bnez    t1, @@nc2
    nop
    addiu   t7, t9, -1
@@nc2:
    sw      t7, ST_TCOL(t2)
@@havecol:
    ; ---- magnet: does the paddle column's bottom balloon match the hand?
    sw      zero, ST_MAG(t2)
    lbu     t1, cfg_magnet
    lw      t5, 0x20(s0)            ; balloons held
    beqz    t1, @@nomatch
    lbu     t8, 0x1C(s0)            ; colour held
    lw      t9, G_NRows
    lw      t1, G_NCols
    blez    t5, @@nomatch
    addiu   t9, t9, -1
@@scan:
    bltz    t9, @@nomatch
    nop
    mult    t9, t1
    mflo    a1
    addu    a1, a1, t7
    addu    a1, a1, s0
    lbu     a1, 0x337C(a1)
    li      a2, 0x24
    beq     a1, a2, @@scan
    addiu   t9, t9, -1
    li      a2, 0x2A
    beq     a1, a2, @@scan
    nop
    bne     a1, t8, @@nomatch
    li      a1, 1
    sw      a1, ST_MAG(t2)
@@nomatch:
    ; ---- replace left/right with "walk towards the paddle column"
    lhu     t8, 0x362(s0)           ; left mask
    lhu     t9, 0x364(s0)           ; right mask
    nop
    or      t1, t8, t9
    nor     t1, t1, zero
    and     s2, s2, t1
    slt     t1, t7, t6
    beqz    t1, @@notl
    slt     t1, t6, t7
    b       @@clicks
    or      s2, s2, t8
@@notl:
    beqz    t1, @@clicks
    nop
    or      s2, s2, t9
@@clicks:
    ; ---- mouse clicks -> catch / throw
    li      t1, 1
    bne     t3, t1, @@ret
    lbu     t5, ST_MBTN(t2)
    lbu     t6, ST_MPREVG(t2)
    sb      t5, ST_MPREVG(t2)
    li      t1, 3
    beq     t5, t1, @@ret           ; both = START (pad_read)
    nor     t6, t6, zero
    and     t5, t5, t6              ; new presses
    andi    t1, t5, 1
    beqz    t1, @@c2
    andi    t1, t5, 2
    lhu     t6, 0x358(s0)           ; catch
    nop
    or      s2, s2, t6
@@c2:
    beqz    t1, @@ret
    nop
    lhu     t6, 0x35A(s0)           ; throw
    nop
    or      s2, s2, t6
@@ret:
    jr      ra
    nop

;@chunk glide
; =====================================================================
;  glide: v0 = clown X offset (16.16) for player a0. Keeps all but v0/at.
; =====================================================================
glide_off:
    addiu   sp, sp, -0x20
    sw      t0, 0x00(sp)
    sw      t1, 0x04(sp)
    sw      t2, 0x08(sp)
    sw      t3, 0x0C(sp)
    sw      t4, 0x10(sp)
    lw      v0, 0x18(a0)            ; column
    lbu     t0, cfg_glide
    nop
    beqz    t0, @@plain
    lw      t0, 0(a0)
    lw      t1, 4(a0)
    sltiu   t3, t0, 2
    beqz    t3, @@plain
    la      t2, state
    li      t3, 1
    beq     t1, t3, @@plain
    nop
    li      t1, ST_SIZE
    mult    t0, t1
    mflo    t1
    addu    t2, t2, t1
    lbu     t3, ST_TYPE(t2)
    lw      t4, v_frame
    beqz    t3, @@plain
    lw      t1, ST_GSTAMP(t2)
    nop
    subu    t1, t4, t1
    sltiu   t1, t1, 3
    beqz    t1, @@plain
    lw      t1, ST_UNITS(t2)
    nop
    sra     t1, t1, 3               ; units*16/W
    addiu   t1, t1, -8              ; pixels
    ; clamp to within one column of the real column
    sll     t3, v0, 4
    addiu   t4, t3, -15
    slt     t0, t1, t4
    beqz    t0, @@g1
    addiu   t4, t3, 15
    addiu   t1, t3, -15
@@g1:
    slt     t0, t4, t1
    beqz    t0, @@g2
    nop
    move    t1, t4
@@g2:
    bgez    t1, @@g3
    nop
    move    t1, zero
@@g3:
    lw      t4, G_NCols
    nop
    addiu   t4, t4, -1
    sll     t4, t4, 4
    slt     t0, t4, t1
    beqz    t0, @@g4
    nop
    move    t1, t4
@@g4:
    b       @@out
    sll     v0, t1, 16
@@plain:
    sll     v0, v0, 20
@@out:
    lw      t0, 0x00(sp)
    lw      t1, 0x04(sp)
    lw      t2, 0x08(sp)
    lw      t3, 0x0C(sp)
    lw      t4, 0x10(sp)
    jr      ra
    addiu   sp, sp, 0x20

glide_clown:                        ; s3 = player; must keep everything but v0
    addiu   sp, sp, -0x18
    sw      ra, 0x10(sp)
    sw      a0, 0x14(sp)
    jal     glide_off
    move    a0, s3
    lw      ra, 0x10(sp)
    lw      a0, 0x14(sp)
    jr      ra
    addiu   sp, sp, 0x18

glide_aim:                          ; s3 = player; returns v0 (was table[col])
    addiu   sp, sp, -0x18
    sw      ra, 0x10(sp)
    sw      a0, 0x14(sp)
    jal     glide_off
    move    a0, s3
    lw      ra, 0x10(sp)
    lw      a0, 0x14(sp)
    jr      ra
    addiu   sp, sp, 0x18

;@chunk cell
; =====================================================================
;  pulse the target column: per cell (s2 = player, s5 = column)
; =====================================================================
cell_hook:
    lw      v1, 0x7500(at)          ; the game's column X
    addiu   sp, sp, -0x18
    sw      t0, 0x00(sp)
    sw      t1, 0x04(sp)
    sw      t2, 0x08(sp)
    sw      t3, 0x0C(sp)
    sw      t4, 0x10(sp)
    lw      t0, v_brsave
    nop
    srl     t1, t0, 16
    bnez    t1, @@have
    nop
    lhu     t0, G_Bright
    nop
    ori     t0, t0, 0
    lui     t1, 1
    or      t0, t0, t1
    sw      t0, v_brsave
@@have:
    andi    t0, t0, 0xFFFF          ; base brightness
    lbu     t1, cfg_dark
    nop
    beqz    t1, @@set
    lw      t1, 0(s2)
    nop
    sltiu   t3, t1, 2
    la      t2, state
    beqz    t3, @@set
    li      t3, ST_SIZE
    mult    t1, t3
    mflo    t1
    addu    t2, t2, t1
    lbu     t3, ST_TYPE(t2)
    lw      t4, v_frame
    beqz    t3, @@set
    lw      t1, ST_GSTAMP(t2)
    nop
    subu    t1, t4, t1
    sltiu   t1, t1, 3
    beqz    t1, @@set
    lw      t1, ST_TCOL(t2)
    nop
    lw      t3, v_pulse
    bne     t1, s5, @@set
    srl     t1, t3, 2
    la      t3, pulsetab
    addu    t3, t3, t1
    lbu     t3, 0(t3)
    nop
    mult    t0, t3
    mflo    t0
    srl     t0, t0, 7
    sltiu   t1, t0, 0x100
    bnez    t1, @@set
    nop
    li      t0, 0xFF
@@set:
    sh      t0, G_Bright
    lw      t0, 0x00(sp)
    lw      t1, 0x04(sp)
    lw      t2, 0x08(sp)
    lw      t3, 0x0C(sp)
    lw      t4, 0x10(sp)
    jr      ra
    addiu   sp, sp, 0x18

cell_end:
    lw      v0, v_brsave
    nop
    srl     v1, v0, 16
    beqz    v1, @@x
    nop
    sh      v0, G_Bright
    sw      zero, v_brsave
@@x:
    lw      v0, 0xCC(s2)
    jr      ra
    nop

;@chunk cursor
; =====================================================================
;  card select: a0 = player, a1 = cursor -> v0 = new cursor
;  X steps walk the cards in reading order (wrapping), Y steps are given
;  to the game as UP/DOWN presses.
; =====================================================================
cursor_hook:
    sltiu   t0, a0, 2
    la      t2, state
    beqz    t0, cursor_orig
    li      t1, ST_SIZE
    mult    a0, t1
    mflo    t1
    addu    t2, t2, t1
    lw      t4, v_frame
    lbu     t8, ST_VOL(t2)
    lw      t3, ST_STEP(t2)
    bnez    t8, @@volchk
    nop
@@rel:
    sw      t4, ST_CSTAMP(t2)
    beqz    t3, cursor_orig
    sw      zero, ST_STEP(t2)
    lw      t5, ST_STEPBIT(t2)
    lw      t6, G_Mode
    lbu     t7, ST_TYPE(t2)
    andi    t0, t5, PAD_UP|PAD_DOWN
    xori    t7, t7, 2
    beqz    t7, @@walkcheck         ; NeGcon twist always walks
    nop
    bnez    t8, @@walkcheck         ; so does the Volume knob (Solo / Competition)
    nop
    bnez    t0, @@viagame           ; mouse Y: let the game move the cursor
    nop
@@walkcheck:
    sltiu   t6, t6, 2
    bnez    t6, @@table
    li      t5, PAD_RIGHT           ; solo / competition: the game's own L/R
    bgtz    t3, @@viagame
    nop
    b       @@viagame
    li      t5, PAD_LEFT
@@table:
    ; walk the reading order table
    li      t0, 0x17
    bne     a1, t0, @@find
    nop
    li      a1, 8                   ; alternate Fool sits on Fool's card
@@find:
    la      t0, cardorder
    move    t1, zero
@@f1:
    addu    t4, t0, t1
    lbu     t4, 0(t4)
    nop
    beq     t4, a1, @@found
    addiu   t1, t1, 1
    slti    t4, t1, NCARDORDER
    bnez    t4, @@f1
    nop
    move    t1, zero                ; not in the table: start at the top
@@found:
    addiu   t1, t1, -1
    addu    t1, t1, t3
    bgez    t1, @@w1
    nop
    addiu   t1, t1, NCARDORDER
@@w1:
    slti    t4, t1, NCARDORDER
    bnez    t4, @@w2
    nop
    addiu   t1, t1, -NCARDORDER
@@w2:
    addu    t4, t0, t1
    lbu     a1, 0(t4)
    addiu   sp, sp, -0x18
    sw      ra, 0x10(sp)
    sw      a1, 0x14(sp)
    jal     G_Sound
    li      a1, 1
    lw      ra, 0x10(sp)
    lw      v0, 0x14(sp)
    jr      ra
    addiu   sp, sp, 0x18

@@viagame:
    ; pressed[player] = pad bit for this call only
    la      t0, G_Pressed
    sll     t1, a0, 1
    addu    t0, t0, t1
    lhu     t1, 0(t0)
    addiu   sp, sp, -0x20
    sw      ra, 0x10(sp)
    sw      t0, 0x14(sp)
    sw      t1, 0x18(sp)
    jal     cursor_orig
    sh      t5, 0(t0)
    lw      t0, 0x14(sp)
    lw      t1, 0x18(sp)
    lw      ra, 0x10(sp)
    sh      t1, 0(t0)
    jr      ra
    addiu   sp, sp, 0x20

@@volchk:
    lw      t6, G_Mode
    nop
    sltiu   t6, t6, 2
    beqz    t6, @@rel               ; Solo / Competition: one list, steps as before
    nop
    j       vol_card
    nop

cursor_orig:
    addiu   sp, sp, -0x50
    j       G_Cursor+8
    sw      s1, 0x44(sp)

; reading order of the card grid with every card available:
; hidden block (top), upper row, lower row
cardorder:
    .byte 18, 19, 20, 21, 22
    .byte 16, 0, 1, 2, 3, 4, 5, 6, 17
    .byte 7, 8, 9, 10, 11, 12, 13, 14, 15
.align 4

;@chunk opt
; =====================================================================
;  options screen: MOUSE SPEED (x0.25 / x0.5 / x1 / x2), row 7 drawn
;  between Sound and Score display. a0 = cursor -> v0 = new cursor
; =====================================================================
opt_cursor:
    addiu   sp, sp, -0x28
    sw      ra, 0x20(sp)
    sw      s0, 0x10(sp)
    sw      s1, 0x14(sp)
    sw      s2, 0x18(sp)
    move    s0, a0
    la      t0, G_Pressed
    lhu     t1, 0(t0)
    lhu     t2, 2(t0)
    nop
    or      s1, t1, t2
    li      t0, 7
    bne     s0, t0, @@other
    li      t0, PAD_UP
    ; ---- on MOUSE SPEED
    bne     s1, t0, @@n1
    li      t0, PAD_DOWN
    jal     G_OptCursorFn           ; as if UP from Score display -> Sound
    li      a0, 5
    b       @@ret
    nop
@@n1:
    bne     s1, t0, @@n2
    li      t0, PAD_LEFT
    jal     G_OptCursorFn           ; as if DOWN from Sound -> Score display
    li      a0, 4
    b       @@ret
    nop
@@n2:
    lw      s2, v_speed
    bne     s1, t0, @@n3
    li      t0, PAD_RIGHT
    beqz    s2, @@same
    nop
    b       @@chg
    addiu   s2, s2, -1
@@n3:
    bne     s1, t0, @@n4
    sltiu   t1, s2, 3
    beqz    t1, @@same
    nop
    addiu   s2, s2, 1
@@chg:
    sw      s2, v_speed
    lw      t0, G_OptSndIdx
    la      t1, G_OptSndTab
    sll     t0, t0, 2
    addu    t1, t1, t0
    lw      a0, 0(t1)
    jal     G_Sound
    li      a1, 1
@@same:
    b       @@arrows
    li      v0, 7
@@n4:
    jal     G_OptCursorFn           ; anything else (back etc.) as usual
    move    a0, s0
    li      t0, 7
    bne     v0, t0, @@ret
    nop
@@arrows:
    lw      t0, v_speed
    li      a3, 2
    bnez    t0, @@a1
    sltiu   t1, t0, 3
    li      a3, 1
@@a1:
    bnez    t1, @@a2
    nop
    move    a3, zero
@@a2:
    lui     a0, OPT_VALX
    lui     a1, OPT_ROWY
    jal     G_OptArrows
    li      a2, 9
    b       @@ret
    li      v0, 7

@@other:
    jal     G_OptCursorFn
    move    a0, s0
    li      t0, 4
    bne     s0, t0, @@o2
    li      t0, PAD_DOWN
    bne     s1, t0, @@ret
    nop
    b       @@ret
    li      v0, 7
@@o2:
    li      t0, 5
    bne     s0, t0, @@ret
    li      t0, PAD_UP
    bne     s1, t0, @@ret
    nop
    li      v0, 7
@@ret:
    lw      ra, 0x20(sp)
    lw      s0, 0x10(sp)
    lw      s1, 0x14(sp)
    lw      s2, 0x18(sp)
    jr      ra
    addiu   sp, sp, 0x28

; end of the options draw routine (s3 = cursor): draw the value
opt_extra:
    addiu   sp, sp, -0x20
    lw      t0, v_speed
    la      a2, speedstr
    sll     t0, t0, 3
    addu    a2, a2, t0
    lui     a0, OPT_VALX
    lui     a1, OPT_ROWY
    xori    a3, s3, 7
    sltiu   a3, a3, 1
    li      t1, 6
    jal     G_DrawText
    sw      t1, 0x10(sp)
    addiu   sp, sp, 0x20
    lw      ra, 0x2C(sp)            ; the instruction we replaced
    j       G_OptDrawRet
    nop

speedstr:
    .ascii "x0.25", 0, 0, 0
    .ascii "x0.5", 0, 0, 0, 0
    .ascii "x1", 0, 0, 0, 0, 0, 0
    .ascii "x2", 0, 0, 0, 0, 0, 0
.align 4
.include "opttab.asm"
.align 4

;@chunk name
; =====================================================================
;  ranking name entry: v0 = player*2. Returns a1 = pressed, with mouse
;  steps (cfg_kname counts per letter) added. Leaves at = hi(G_Held).
; =====================================================================
name_hook:
    la      t0, G_Pressed
    addu    t0, t0, v0
    lhu     a1, 0(t0)
    srl     t1, v0, 1
    sltiu   t3, t1, 2
    la      t2, state
    beqz    t3, @@ret
    li      t3, ST_SIZE
    mult    t1, t3
    mflo    t1
    addu    t2, t2, t1
    lw      t4, v_frame
    lbu     t3, ST_TYPE(t2)
    sw      t4, ST_NSTAMP(t2)
    li      t4, 1
    bne     t3, t4, @@ret
    lw      t5, ST_NACC(t2)
    lhu     t6, cfg_kname
    nop
    slt     t7, t5, t6
    bnez    t7, @@neg
    subu    t7, zero, t6
    subu    t5, t5, t6
    b       @@st
    ori     a1, a1, PAD_RIGHT
@@neg:
    slt     t7, t7, t5
    bnez    t7, @@st
    nop
    addu    t5, t5, t6
    ori     a1, a1, PAD_LEFT
@@st:
    sll     t7, t6, 1               ; clamp to +-2k
    slt     t8, t7, t5
    beqz    t8, @@c1
    subu    t8, zero, t7
    move    t5, t7
@@c1:
    slt     t8, t5, t8
    beqz    t8, @@c2
    nop
    subu    t5, zero, t7
@@c2:
    sw      t5, ST_NACC(t2)
@@ret:
    lui     at, hi(G_Held)
    jr      ra
    nop

;@endchunks

.close
