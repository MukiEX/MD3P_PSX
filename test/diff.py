# usage: diff.py state "seq1" "seq2" ... : find bytes that change consistently: prints candidates with values after each step
import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
names={'x':B,'o':A,'sq':Y,'tri':X,'start':START,'u':UP,'d':DOWN,'l':LEFT,'r':RIGHT}
e=Emu(ROOT+'/work/md3.cue'); e.load(open(sys.argv[1],'rb').read())
lo=int(sys.argv[2],16); hi=int(sys.argv[3],16)
steps=sys.argv[4:]
def snap(): return np.frombuffer(e.rb(lo,hi-lo),dtype=np.uint8).copy()
vals=[snap()]
for s in steps:
    e.press(0,names[s],4,25); vals.append(snap())
V=np.array(vals).astype(int)
ch=np.nonzero((np.diff(V,axis=0)!=0).sum(0)>=len(steps)-1)[0]
for i in ch[:60]: print(hex(lo+i), list(V[:,i]))
print('--- pattern')
D=np.diff(V,axis=0)
for i in range(V.shape[1]):
    d=D[:,i]
    if d[0]==1 and d[1]==1 and d[2]==1 and d[4]==-1 and d[3]>1: print(hex(lo+i), list(V[:,i]))
