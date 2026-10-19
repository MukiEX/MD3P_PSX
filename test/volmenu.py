# Namco Volume in menus (knob = up/down, B + knob = left/right) and the in-play chords
import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
import re
cue=sys.argv[1]; symdir=sys.argv[2]
e=Emu(cue,ports=('negcon','standard'))
D=ROOT+'/shots/vol/'
sym={l.split()[1]:int(l.split()[0],16) for l in open(f'{symdir}/work_EN/final.sym') if re.match(r'^[0-9A-F]{8} \w',l)}
st=lambda off,n=1:(e.r8 if n==1 else e.r32)(sym['state']+off)
kv=[128]
def knob(v): kv[0]=v; e.analog[0][0]=int((v-128)/128*32767)
def turn(d,steps=10):
    v0=kv[0]
    for k in range(1,steps+1): knob(v0+d*k/steps); e.run(2)
    e.run(20)
def a(n=300): e.pad[0].add(START); e.run(5); e.pad[0].discard(START); e.run(n)
def b(n=300): e.pad[0].add(A); e.run(5); e.pad[0].discard(A); e.run(n)
def ab(n=300): e.pad[0]|={START,A}; e.run(5); e.pad[0]-={START,A}; e.run(n)
knob(128); e.run(400)
turn(72); turn(-72)                  # language screen: across and back to English
a(600); a(600); ab(400); ab(400)
e.shot(D+'m0.png')
turn(+12); e.shot(D+'m1.png')       # one step down: Two Players
turn(+12); e.shot(D+'m2.png')       # Solo
turn(-24); e.shot(D+'m3.png')       # back to One Player
turn(+48); e.shot(D+'m4.png')       # Options
a(400); e.shot(D+'o0.png')          # into Options
turn(+50); e.shot(D+'o1.png')       # down to MOUSE SPEED
e.pad[0].add(A); e.run(3); turn(-12); turn(-12); e.pad[0].discard(A); e.run(20); e.shot(D+'o2.png')   # B + knob left: value down twice
print('speed after B+knob:', e.r32(sym['v_speed']))
b(300); e.shot(D+'o3.png')          # B tap = back
print('after B tap (back):'); 
turn(-48); e.shot(D+'m5.png')       # up to One Player
a(400); e.shot(D+'d0.png')          # difficulty / next screen
turn(+12); e.shot(D+'d1.png')
turn(-12); e.shot(D+'d2.png')
