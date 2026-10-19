import sys,struct; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from ps import Exe
e=Exe(sys.argv[1])
W=dict(e.words())
code_end=0x80076000
# function starts: address after 'jr ra; delay' or after nop padding, beginning with non-nop
starts=set()
addrs=sorted(W)
for a in addrs:
    if a>=code_end: break
    w=W[a]
    if w==0x03e00008: 
        b=a+8
        while W.get(b,1)==0 and b<code_end: b+=4
        starts.add(b)
    if (w>>16)==0x27bd and (w&0x8000): starts.add(a)
jal=set(); refs=set()
for a,w in W.items():
    if (w>>26) in (2,3): jal.add(((w&0x3ffffff)<<2)|0x80000000)
    if 0x80010000<=w<0x80110000: refs.add(w)
# lui/addiu pairs
lui={}
for a in addrs:
    w=W[a]; op=w>>26; rt=(w>>16)&31; rs=(w>>21)&31; imm=w&0xffff; s=imm-0x10000 if imm&0x8000 else imm
    if op==0xf: lui[rt]=(imm<<16,a)
    elif op in (9,0xd) and rs in lui and a-lui[rs][1]<64:
        refs.add((lui[rs][0]+(imm if op==0xd else s))&0xffffffff)
dead=[]
ss=sorted(starts)
for i,s in enumerate(ss):
    if s not in jal and s not in refs:
        end=ss[i+1] if i+1<len(ss) else s
        dead.append((s,end-s))
# merge to contiguous: a dead function bounded by next start
tot=0
for s,l in dead:
    tot+=l
    if l>=0x100: print(hex(s),hex(l))
print('total',hex(tot))
