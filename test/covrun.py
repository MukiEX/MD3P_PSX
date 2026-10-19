import sys,random; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
e=Emu(ROOT+'/work/md3.cue'); cv=Cov(e)
rnd=random.Random(int(sys.argv[2]) if len(sys.argv)>2 else 1)
def P(b,n=20,port=0): e.pad[port].add(b); cv.run(4,4); e.pad[port].discard(b); cv.run(n,4)
def W(n): cv.run(n,4)
def shot(n): e.shot(f'{ROOT}/shots/{n}.png')
def play(frames,ports=(0,)):
    for i in range(frames//6):
        for p in ports: e.pad[p]=set(rnd.sample([LEFT,RIGHT,B,A,X,Y,LEFT,RIGHT,0],2))-{0}
        cv.run(6,6)
    for p in ports: e.pad[p]=set()
def load(f): e.load(open(ROOT+'/st/'+f,'rb').read()); cv.prev=np.frombuffer(e.rb(0x80000000,0x200000),dtype=np.uint8).copy()
seg=sys.argv[1]
if seg=='attract':
    W(400); P(B,600); P(B,300); W(4000); shot('cv_attract')
elif seg=='1p':
    load('menu.bin'); P(B,300); P(B,400); P(B,300)
    for i in range(6): P(START,250)
    play(6000); shot('cv_1p_a')
    for k in range(3):
        P(START,200); play(3000)
    for i in range(30): P(rnd.choice([B,START,LEFT,RIGHT,UP,DOWN]),60)
    shot('cv_1p_b')
elif seg=='2p':
    load('menu.bin'); P(DOWN); P(B,300); P(B,400)
    P(B,100,0); P(B,100,1); W(300)
    for i in range(6): P(START,250); P(B,100,1)
    play(6000,(0,1)); shot('cv_2p_a')
    for i in range(30): P(rnd.choice([B,START,LEFT,RIGHT,UP,DOWN]),60,rnd.choice([0,1]))
    shot('cv_2p_b')
elif seg in ('solo','comp'):
    load('menu.bin'); P(DOWN); P(DOWN)
    if seg=='comp': P(DOWN)
    P(B,300)
    for i in range(8): P(B,200)
    play(6000); shot(f'cv_{seg}_a')
    for i in range(30): P(rnd.choice([B,START,LEFT,RIGHT,UP,DOWN]),60)
    play(3000); shot(f'cv_{seg}_b')
elif seg=='opt':
    load('menu.bin')
    for i in range(4): P(DOWN)
    P(B,300)
    for item in range(7):
        P(B,200)
        for i in range(6): P(rnd.choice([LEFT,RIGHT,UP,DOWN,B]),30)
        P(X,200); P(DOWN,30)
        shot(f'cv_opt{item}')
np.save(f'{ROOT}/cov/w_{seg}.npy',cv.words()); np.save(f'{ROOT}/cov/x_{seg}.npy',xmap(e))
