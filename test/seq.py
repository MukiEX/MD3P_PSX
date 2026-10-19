# usage: seq.py [-p ports] [-c cue] in_state|- out_state|- cmds...
# cmds: w N (wait), p BTN [hold] [after], s name (shot), h BTN on/off, m dx dy (mouse move one frame), n twist (negcon twist -128..127 held), r ADDR LEN
import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
args=sys.argv[1:]; ports=('standard','standard'); cue=ROOT+'/work/md3.cue'
while args and args[0].startswith('-'):
    if args[0]=='-p': ports=tuple(args[1].split(',')); args=args[2:]
    elif args[0]=='-c': cue=args[1]; args=args[2:]
e=Emu(cue,ports=ports)
if args[0]!='-': e.load(open(args[0],'rb').read())
out=args[1]; cmds=' '.join(args[2:]).replace(';',' ').split()
names={'x':B,'o':A,'sq':Y,'tri':X,'start':START,'sel':SELECT,'u':UP,'d':DOWN,'l':LEFT,'r':RIGHT,'l1':L,'r1':R,'l2':L2,'r2':R2}
i=0; port=0
while i<len(cmds):
    c=cmds[i]; i+=1
    if c=='w': e.run(int(cmds[i])); i+=1
    elif c=='P': port=int(cmds[i]); i+=1
    elif c=='p':
        b=names[cmds[i]]; i+=1; e.press(port,b,4,20)
    elif c=='s': e.shot(f'{ROOT}/shots/{cmds[i]}.png'); i+=1
    elif c=='h':
        b=names[cmds[i]]; on=cmds[i+1]=='on'; i+=2
        (e.pad[port].add if on else e.pad[port].discard)(b)
    elif c=='m':
        dx,dy,n=int(cmds[i]),int(cmds[i+1]),int(cmds[i+2]); i+=3
        for k in range(n): e.mouse[port][0]=dx; e.mouse[port][1]=dy; e.run(1)
    elif c in ('cl','cr','cb'):
        idx={'cl':[2],'cr':[3],'cb':[2,3]}[c]
        for k in idx: e.mouse[port][k]=1
        e.run(5)
        for k in idx: e.mouse[port][k]=0
        e.run(int(cmds[i])); i+=1
    elif c=='n':
        e.analog[port][0]=int(cmds[i])*256; i+=1
    elif c=='r':
        a=int(cmds[i],16); n=int(cmds[i+1]); i+=2; print(hex(a), e.rb(a,n).hex())
if out!='-': open(out,'wb').write(e.save())
