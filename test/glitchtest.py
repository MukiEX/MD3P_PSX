# Namco Volume with a flaky link: failed reads and garbled analog bytes
import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
import re, random
random.seed(1)
cue=sys.argv[1]; symdir=sys.argv[2]
e=Emu(cue,ports=('negcon','standard'))
D=ROOT+'/shots/vol/'
def knob(v): e.analog[0][0]=int((v-128)/128*32767)
stats={'bad':0,'garb':0}
def corrupt(raw):
    r=random.random()
    if r<0.33: e.ram[raw&0x1FFFFF]=0xFF; stats['bad']+=1          # failed read
    elif r<0.40:
        if random.random()<0.7:
            for k in (5,6,7): e.ram[(raw+k)&0x1FFFFF]=0xFF      # all-FF garbage
        else: e.ram[(raw+5+random.randrange(3))&0x1FFFFF]=0xFF   # one garbled analog byte
        stats['garb']+=1
def sles_cb(regs,pc): corrupt(0x8001f4c0)
bp(e,[0x800122b4],sles_cb)
knob(128); e.run(400)
for k in range(41): knob(128+72*k/40); e.run(2)
e.run(10)
e.pad[0].add(START); e.run(6); e.pad[0].discard(START)
bp(e,[],lambda r,p:None); e.run(600)
print('selector glitches',stats)
lang=None
for L in ['EN','FR','GE','IT','SP','NL']:
    sym={l.split()[1]:int(l.split()[0],16) for l in open(f'{symdir}/work_{L}/final.sym') if re.match(r'^[0-9A-F]{8} \w',l)}
    if e.rb(sym['cfg'],4)==b'PDCF':
        f0=e.r32(sym['v_frame']); e.run(2)
        if 0 < e.r32(sym['v_frame'])-f0 <= 3: lang=L; S=sym
print('language loaded:',lang)
st=lambda off:e.r8(S['state']+off)
hist=[]
def game_cb(regs,pc):
    if regs[4]==0:
        corrupt(S['raw1'])
        hist.append((e.nframes,e.rb(S['raw1'],8).hex(),e.r8(S['state']+0x49),e.r8(S['state']+0x4B),e.r8(S['state']+0x4E)))
        if e.r8(S['state']+0x49) and not getattr(e,'_dumped',0):
            e._dumped=1
            for h in hist[-6:]: print('HIST',h)
bp(e,[S['pad_one']],game_cb)
def a(n=300): e.pad[0].add(START); e.run(5); e.pad[0].discard(START); e.run(n)
def ab(n=300): e.pad[0]|={START,A}; e.run(5); e.pad[0]-={START,A}; e.run(n)
a(600); ab(400); ab(400); e.shot(D+'gl_menu.png')
print('menu: type',st(0),'vol',st(0x47),'neg',st(0x49))
a(300); a(400)
for k in range(21): knob(128-128*k/20); e.run(3)
e.run(20); e.shot(D+'gl_csel0.png')
for k in range(41): knob(0+255*k/40); e.run(3)
e.run(20); e.shot(D+'gl_csel255.png')
print('csel zone',st(0x48),'vol',st(0x47),'neg',st(0x49),'glitches',stats)
if len(sys.argv)>3:
    H=S['g_held']; P=S['g_pressed']
    for f in range(12):
        if f==2: e.pad[0]|={START,A}
        if f==8: e.pad[0]-={START,A}
        e.run(1); print(f,'held %04x pressed %04x mbtn %d bad %d'%(e.r16(H),e.r16(P),st(1),st(0x4A)))
