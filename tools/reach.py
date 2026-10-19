# static reachability: which code words can execute
import sys,struct; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from ps import Exe
e=Exe(sys.argv[1]); entry=e.pc
CODE_LO=0x80010000; CODE_HI=int(sys.argv[2],16) if len(sys.argv)>2 else 0x80076000
W={a:w for a,w in e.words()}
roots=set([entry])
# data words pointing into code (anywhere in the image, incl. code itself for jump tables)
for a,w in W.items():
    if CODE_LO<=w<CODE_HI and w%4==0: roots.add(w)
# lui/addiu|ori pairs producing code addresses
lui={}
for a in sorted(W):
    w=W[a]; op=w>>26; rt=(w>>16)&31; rs=(w>>21)&31; imm=w&0xffff; s=imm-0x10000 if imm&0x8000 else imm
    if op==0xf: lui[rt]=(imm<<16,a)
    elif op in (9,0xd) and rs in lui and a-lui[rs][1]<128:
        v=(lui[rs][0]+(imm if op==0xd else s))&0xffffffff
        if CODE_LO<=v<CODE_HI and v%4==0: roots.add(v)
seen=set(); work=list(roots)
while work:
    a=work.pop()
    while CODE_LO<=a<CODE_HI and a not in seen:
        seen.add(a); w=W.get(a,0); op=w>>26; fn=w&63; rs=(w>>21)&31; rt=(w>>16)&31
        imm=w&0xffff; s=imm-0x10000 if imm&0x8000 else imm
        if op==0 and fn==8:   # jr
            seen.add(a+4); break
        if op==2:             # j
            seen.add(a+4); work.append(((w&0x3ffffff)<<2)|0x80000000); break
        if op==3:             # jal
            work.append(((w&0x3ffffff)<<2)|0x80000000)
        if op in (4,5,6,7) or (op==1 and rt in (0,1,16,17)):
            work.append(a+4+(s<<2))
            if op==4 and rs==0 and rt==0:  # b (beq zero,zero)
                seen.add(a+4); break
        if op==0 and fn==0xd: # break
            pass
        a+=4
dead=[a for a in range(CODE_LO,CODE_HI,4) if a not in seen and W.get(a,0)!=0]
# group
runs=[];
for a in dead:
    if runs and a-runs[-1][1]<=8: runs[-1][1]=a+4
    else: runs.append([a,a+4])
tot=sum(b-a for a,b in runs)
for a,b in runs:
    if b-a>=0x100: print(hex(a),hex(b-a))
print('total dead',hex(tot))
