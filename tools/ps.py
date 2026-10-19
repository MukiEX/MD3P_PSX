import struct,sys,re
try:   # capstone is only needed for Exe.dis()
    import capstone as C
    md=C.Cs(C.CS_ARCH_MIPS, C.CS_MODE_MIPS32|C.CS_MODE_LITTLE_ENDIAN)
except ImportError:
    md=None
class Exe:
    def __init__(s,path):
        s.raw=bytearray(open(path,'rb').read())
        s.pc,s.gp,s.base,s.size=struct.unpack_from('<4I',s.raw,0x10)
        s.img=s.raw[0x800:0x800+s.size]
    def w(s,a): return struct.unpack_from('<I',s.img,a-s.base)[0]
    def h(s,a): return struct.unpack_from('<H',s.img,a-s.base)[0]
    def b(s,a): return s.img[a-s.base]
    def dis(s,a,n=32):
        out=[]
        for i in range(n):
            ad=a+4*i; word=s.w(ad)
            ins=list(md.disasm(struct.pack('<I',word),ad))
            out.append(f'{ad:08x}: {word:08x}  '+(f'{ins[0].mnemonic} {ins[0].op_str}' if ins else '.word'))
        return '\n'.join(out)
    def find(s,pat):  # bytes
        return [s.base+m.start() for m in re.finditer(re.escape(pat),bytes(s.img))]
    def words(s):
        for i in range(0,s.size,4): yield s.base+i, struct.unpack_from('<I',s.img,i)[0]
    def xrefs_jal(s,target):
        t=0x0C000000|((target>>2)&0x3FFFFFF)
        return [a for a,w in s.words() if w==t]
    def xrefs_hilo(s,addr):
        """find lui/addiu or lui/lw pairs referencing addr (approx: within 16 instr)"""
        hi=(addr+0x8000)>>16; lo=addr&0xFFFF; res=[]
        ws=list(s.words())
        for i,(a,w) in enumerate(ws):
            if (w>>26)==0xF and (w&0xFFFF)==hi:
                rt=(w>>16)&31
                for j in range(i+1,min(i+24,len(ws))):
                    a2,w2=ws[j]
                    if ((w2>>21)&31)==rt and (w2&0xFFFF)==lo and (w2>>26) in (0x9,0x20,0x21,0x23,0x24,0x25,0x28,0x29,0x2b): res.append(a2); break
        return res
