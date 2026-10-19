import sys,struct; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from ps import Exe, md
import capstone as C
e=Exe(sys.argv[1]); out=open(sys.argv[2],'w')
md.detail=False
lui={}  # reg->value, reset at branches roughly
regn=['zero','at','v0','v1','a0','a1','a2','a3','t0','t1','t2','t3','t4','t5','t6','t7','s0','s1','s2','s3','s4','s5','s6','s7','t8','t9','k0','k1','gp','sp','fp','ra']
for a,w in e.words():
    op=w>>26; rs=(w>>21)&31; rt=(w>>16)&31; imm=w&0xFFFF; simm=imm-0x10000 if imm&0x8000 else imm
    ins=list(md.disasm(struct.pack('<I',w),a))
    txt=f'{ins[0].mnemonic} {ins[0].op_str}' if ins else '.word'
    cm=''
    if op==0xF: lui[rt]=(imm<<16, a)
    elif op in (0x9,0x20,0x21,0x23,0x24,0x25,0x28,0x29,0x2b,0x22,0x26,0xd) and rs in lui and a-lui[rs][1]<0x80:
        v=(lui[rs][0]+ (imm if op==0xd else simm))&0xFFFFFFFF; cm=f'  ; ={v:08x}'
        if op in (0x9,0xd) and rt!=rs: lui[rt]=(v,a)
        if rt==rs and op in (0x9,0xd): lui.pop(rt,None); 
    elif rs==28 and op in (0x20,0x21,0x23,0x24,0x25,0x28,0x29,0x2b,0x9): cm=f'  ; =({0x800a8a04+simm:08x})'
    out.write(f'{a:08x}: {w:08x}  {txt}{cm}\n')
