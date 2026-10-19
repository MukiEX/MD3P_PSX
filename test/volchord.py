# Namco Volume in play: A then B = pull down, both held 2 s = pause
import sys, os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from env import *
src=open(ROOT+'/test/voltest.py').read().split("e.shot(D+'g0.png')")[0]
sys.argv=[sys.argv[0],sys.argv[1],'/dev/null']
exec(src)
e.shot(D+'c0.png')
ps=st(0,0x54,4); print('player struct %08x pull mask %04x'%(ps,e.r16(ps+0x35C)))
def chord(first,second,frames):
    e.pad[0].add(first); e.run(6); e.pad[0].add(second)
    outs=set()
    for k in range(frames):
        e.run(1); outs.add(e.r16(sym['state']+0x4C))
    e.pad[0]-={first,second}; e.run(20)
    return sorted('%04x'%o for o in outs)
print('A then B, short:', chord(START,A,10)); e.shot(D+'c1.png')
print('B then A, short:', chord(A,START,10)); e.shot(D+'c2.png')
print('B then A, 2.2 s:', chord(A,START,110)); e.run(30); e.shot(D+'c3.png')
e.pad[0]|={START,A}
for k in range(150):
    e.run(1)
    if k in (90,105,130,149): e.shot(D+'h%d.png'%k)
print('during hold: last %04x vch %d vhold %d'%(e.r16(sym['state']+0x4C),st(0,0x52,1),st(0,0x53,1)))
e.pad[0]-={START,A}; e.run(60); e.shot(D+'h_after.png')
