# pairtest.py cue final.sym [tag]
# JP3 encoder wired across the d-pad pairs (A = LEFT or RIGHT, B = UP or DOWN):
# a rolled d-pad must not latch; a fast spin (LEFT <-> UP with no diagonal or
# centre between two reads, twice within a second) must; then it drives the
# language screen and the paddle in play like the LEFT/RIGHT wiring.
import sys; sys.path.insert(0, __import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
import re
cue = sys.argv[1]; symf = sys.argv[2]; tag = sys.argv[3] if len(sys.argv) > 3 else 'p'
sym = {l.split()[1]: int(l.split()[0], 16) for l in open(symf) if re.match(r'^[0-9A-F]{8} \w', l)}
SZ = 0x60
e = Emu(cue)
D = ROOT + '/shots/jp3/'
fails = 0
def check(name, cond, info=''):
    global fails
    print(('ok   ' if cond else 'FAIL ') + name, info)
    if not cond: fails += 1
def st(p, off, n=4):
    a = sym['state'] + SZ * p + off
    return e.r8(a) if n == 1 else e.r32(a)
PP = [set(), {LEFT}, {LEFT, UP}, {UP}]
q = [0, 0]
def spin(port, edges, hold=2):
    d = 1 if edges > 0 else -1
    for k in range(abs(edges)):
        q[port] = (q[port] + d) % 4
        e.pad[port] -= {LEFT, RIGHT, UP, DOWN}; e.pad[port] |= PP[q[port]]
        e.run(hold)
def fast_latch(port):
    # skip a state on every read: only-LEFT <-> only-UP
    q[port] = 1; e.pad[port] -= {LEFT, RIGHT, UP, DOWN}; e.pad[port] |= PP[1]; e.run(2)
    for k in range(3):
        q[port] = (q[port] + 2) % 4
        e.pad[port] -= {LEFT, RIGHT, UP, DOWN}; e.pad[port] |= PP[q[port]]; e.run(2)
def release(port):
    e.pad[port] -= {LEFT, RIGHT, UP, DOWN}; q[port] = 0; e.run(2)

e.run(400); e.shot(D + tag + '_pairs_lang0.png')
# the selector: fast spin latches, then 4 edges = next flag, and back
fast_latch(0)        # leaves the encoder on only-UP (position 3)
spin(0, 4); e.run(10); e.shot(D + tag + '_pairs_lang1.png')
spin(0, -4); e.run(10); e.shot(D + tag + '_pairs_lang2.png')
spin(0, 1)           # to the centre (position 0): one edge, less than a flag
e.press(0, B, 4, 20); e.run(600); e.press(0, B, 4, 20); e.run(600)
e.press(0, START, 4, 20); e.run(400); e.press(0, START, 4, 20); e.run(400)
f0 = e.r32(sym['v_frame']); e.run(10)
check('back on English after +4 / -4 edges (MD3EN.EXE running)', e.r32(sym['v_frame']) - f0 >= 8, (f0, e.r32(sym['v_frame'])))
# navigate into play with port 1's buttons, then latch port 1 by a fast spin
e.press(0, B, 4, 300); e.press(0, B, 4, 400)
e.press(0, B, 4, 300)
for i in range(6): e.press(0, START, 4, 300)
e.run(200)
def ingame(): return e.r32(sym['v_frame']) - st(0, 0x24) < 3
for k in range(6):
    if ingame(): break
    e.press(0, START, 4, 120)
e.run(300)                   # past the round's opening count-down
# in play: a thumb rolling the d-pad must not latch
roll = [{UP}, {UP, RIGHT}, {RIGHT}, {RIGHT, DOWN}, {DOWN}, {DOWN, LEFT}, {LEFT}, {LEFT, UP}]
for k in range(48): e.pad[0] = set(roll[k % 8]); e.run(2)
e.pad[0] = set(); e.run(4)
check('rolled d-pad does not latch', st(0, 0x44, 1) == 0, st(0, 0x44, 1))
# one swap, a pause over a second, one more: no latch
e.pad[0] = {LEFT}; e.run(2); e.pad[0] = {UP}; e.run(2); e.pad[0] = set(); e.run(80)
e.pad[0] = {LEFT}; e.run(2); e.pad[0] = {UP}; e.run(2); e.pad[0] = set(); e.run(4)
check('swaps over a second apart do not latch', st(0, 0x44, 1) == 0, st(0, 0x44, 1))
fast_latch(0); spin(0, 1)
check('fast spin latches the pairs wiring', st(0, 0x44, 1) == 2 and st(0, 0, 1) == 1, (st(0, 0x44, 1), st(0, 0, 1)))
e.run(3)
check('in play (the clown hook stamps paddle ports)', ingame())
e.shot(D + tag + '_pairs_g0.png')
u0 = st(0, 4)
spin(0, 8); e.run(30); u1 = st(0, 4)
check('+8 edges move the paddle right', u1 > u0, (u0, u1))
spin(0, -16); e.run(30); u2 = st(0, 4)
check('-16 edges move it back left', u2 < u1, (u1, u2))
e.shot(D + tag + '_pairs_g1.png')
# directions never reach the game once latched
e.pad[0] -= {LEFT, RIGHT, UP, DOWN}; e.pad[0] |= {UP}; e.run(3)
check('raw UP is held back', not (e.r16(sym['G_Held'] if 'G_Held' in sym else 0x800A911C) & 0x1000), hex(e.r16(0x800A911C)))
print('FAILURES:', fails); sys.exit(1 if fails else 0)
