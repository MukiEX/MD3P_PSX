# make_ppf.py original.bin patched.bin out.ppf "description"
import sys
a=open(sys.argv[1],'rb'); b=open(sys.argv[2],'rb'); out=open(sys.argv[3],'wb')
desc=sys.argv[4].encode('ascii')[:50].ljust(50,b' ')
out.write(b'PPF30'+bytes([2])+desc+bytes([0,0,0,0]))   # imagetype BIN, no blockcheck, no undo, dummy
CH=1<<20; off=0; n=0
while True:
    x=a.read(CH); y=b.read(CH)
    if not x and not y: break
    assert len(x)==len(y)
    i=0
    while i<len(x):
        if x[i]!=y[i]:
            j=i
            while j<len(x) and j-i<255 and (x[j]!=y[j] or (j+1<len(x) and x[j+1]!=y[j+1] and j-i<254)): j+=1
            if j==i: j=i+1
            out.write((off+i).to_bytes(8,'little')+bytes([j-i])+y[i:j]); n+=1; i=j
        else: i+=1
    off+=len(x)
print('records',n)
