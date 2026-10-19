import struct,sys
class Disc:
    def __init__(s,path): s.f=open(path,'rb'); 
    def sec(s,lba): s.f.seek(lba*2352); return s.f.read(2352)
    def data(s,lba,n=1): return b''.join(s.sec(lba+i)[24:24+2048] for i in range(n))
    def walk(s,lba=None,size=None,path=''):
        if lba is None:
            pvd=s.data(16); r=pvd[156:156+34]; lba=struct.unpack_from('<I',r,2)[0]; size=struct.unpack_from('<I',r,10)[0]
        d=s.data(lba,(size+2047)//2048); o=0; out=[]
        while o<len(d):
            l=d[o]
            if l==0: o=(o//2048+1)*2048; continue
            el=struct.unpack_from('<I',d,o+2)[0]; sz=struct.unpack_from('<I',d,o+10)[0]; fl=d[o+25]; nl=d[o+32]; nm=d[o+33:o+33+nl]
            if nm not in (b'\0',b'\1'):
                n=nm.decode('latin1')
                if fl&2: out+=s.walk(el,sz,path+n+'/')
                else: out.append((path+n,el,sz,lba*2048+o))
            o+=l
        return out
if __name__=='__main__':
    d=Disc(sys.argv[1])
    for p,l,s,_ in d.walk(): print(f'{l:7d} {s:10d} {p}')
