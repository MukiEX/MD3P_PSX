import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
SZ=0x60   # ST_SIZE
import re
cue=sys.argv[1]; symf=sys.argv[2]; tag=sys.argv[3] if len(sys.argv)>3 else 'p'
sym={l.split()[1]:int(l.split()[0],16) for l in open(symf) if re.match(r'^[0-9A-F]{8} \w',l)}
e=Emu(cue)
D=ROOT+'/shots/jp3/'
POS=[set(),{LEFT},{LEFT,RIGHT},{RIGHT}]
q=[0,0]
def spin(port,edges,hold=2):
    d=1 if edges>0 else -1
    for k in range(abs(edges)):
        q[port]=(q[port]+d)%4
        e.pad[port]-= {LEFT,RIGHT}; e.pad[port]|=POS[q[port]]
        e.run(hold)
def st(p,off,n=4):
    a=sym['state']+SZ*p+off
    return e.r8(a) if n==1 else e.r32(a)
e.run(400); e.shot(D+tag+'_lang0.png')
spin(0,12); e.run(10); e.shot(D+tag+'_lang1.png')
spin(0,-8); e.run(10); e.shot(D+tag+'_lang2.png')
spin(0,-4); e.run(10); e.shot(D+tag+'_lang3.png')   # back to English: +3 -2 -1 flags
e.run(10); e.shot(D+tag+'_lang4.png')
e.pad[0]-={LEFT,RIGHT}; e.run(5)
e.press(0,B,4,20); e.run(600); e.press(0,B,4,20); e.run(600)
e.press(0,START,4,20); e.run(400); e.press(0,START,4,20); e.run(400)
e.shot(D+tag+'_menu.png')
print('after menu: type',st(0,0,1),'jp3',st(0,0x44,1))
# menu: spin to move cursor like the mouse (down/up comes from the pad anyway)
e.press(0,B,4,300); e.press(0,B,4,400); e.shot(D+tag+'_csel0.png')
spin(0,10); e.run(20); e.shot(D+tag+'_csel1.png')
print('after csel: type',st(0,0,1),'jp3',st(0,0x44,1))
e.press(0,B,4,300)
for i in range(6): e.press(0,START,4,300)
e.run(200)
def ingame(): return e.r32(sym['v_frame'])-st(0,0x24)<3
for k in range(6):
    if ingame(): break
    e.press(0,START,4,120)
print('ingame',ingame(),'type',st(0,0,1),'jp3',st(0,0x44,1))
e.shot(D+tag+'_g0.png'); u0=st(0,4); c0=st(0,0x20)
spin(0,8); e.run(30); print('+8 edges: units',u0,'->',st(0,4),'col',c0,'->',st(0,0x20)); e.shot(D+tag+'_g1.png')
u0=st(0,4); spin(0,-16); e.run(30); print('-16 edges: units',u0,'->',st(0,4),'col',st(0,0x20)); e.shot(D+tag+'_g2.png')
# skipped samples: change both phases at once (2 edges per read) keeps direction
u0=st(0,4)
for k in range(4):
    q[0]=(q[0]+2)%4; e.pad[0]-={LEFT,RIGHT}; e.pad[0]|=POS[q[0]]; e.run(2)
print('4 double steps after -dir: units',u0,'->',st(0,4))
u0=st(0,4); spin(0,4); u1=st(0,4)
for k in range(4):
    q[0]=(q[0]+2)%4; e.pad[0]-={LEFT,RIGHT}; e.pad[0]|=POS[q[0]]; e.run(2)
print('+4 then 4 doubles: units',u0,'->',u1,'->',st(0,4))
open(ROOT+'/st/'+tag+'_jp3game.bin','wb').write(e.save())
