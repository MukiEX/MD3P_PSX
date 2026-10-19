import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
import re
cue=sys.argv[1]; out=sys.argv[2]
e=Emu(cue,ports=('negcon','standard'))
D=ROOT+'/shots/vol/'
def knob(v): e.analog[0][0]=int((v-128)/128*32767)   # 0..255
def ab(n=300):
    e.pad[0]|={START,A}; e.run(5); e.pad[0]-={START,A}; e.run(n)
def a(n=300):
    e.pad[0].add(START); e.run(5); e.pad[0].discard(START); e.run(n)
def sweep(v0,v1,steps=20):
    for k in range(steps+1): knob(v0+(v1-v0)*k/steps); e.run(2)
knob(128); e.run(400); e.shot(D+'lang0.png')
sweep(128,200); e.run(10); e.shot(D+'lang1.png')   # +72 -> 3 flags right
sweep(200,128); e.run(10); e.shot(D+'lang2.png')   # back to English
a(600)                       # A = X: confirm
sym={l.split()[1]:int(l.split()[0],16) for l in open(ROOT+'/out/work_EN/final.sym') if re.match(r'^[0-9A-F]{8} \w',l)}
def st(p,off,n=4):
    ad=sym['state']+0x50*p+off
    return e.r8(ad) if n==1 else e.r32(ad)
print('EN running:', e.r32(sym['v_frame'])>0, 'type',st(0,0,1),'vol',st(0,0x47,1),'neg',st(0,0x49,1))
e.shot(D+'boot1.png')
a(600); e.shot(D+'boot2.png')
ab(400); e.shot(D+'boot3.png'); ab(400); e.shot(D+'menu.png')
a(300); a(400); e.shot(D+'csel0.png')
sweep(128,180); e.run(20); e.shot(D+'csel1.png')
a(300)
for i in range(6): ab(300)
e.run(200)
def ingame(): return e.r32(sym['v_frame'])-st(0,0x24)<3
for k in range(4):
    if ingame(): break
    ab(120)
print('ingame',ingame(),'type',st(0,0,1),'vol',st(0,0x47,1),'neg',st(0,0x49,1))
e.shot(D+'g0.png')
for v in (180,0,255,128):
    sweep(e.analog[0][0]/32767*128+128, v, 10); e.run(20)
    print('knob',v,'units',st(0,4),'col',st(0,0x20))
    e.shot(D+'g_%d.png'%v)
print('mbtn before',st(0,1,1)); e.pad[0].add(START); e.run(2); print('A held: mbtn',st(0,1,1)); e.pad[0].discard(START); e.run(30)
open(out,'wb').write(e.save())
