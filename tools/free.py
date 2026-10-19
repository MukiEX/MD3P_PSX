import numpy as np, sys
w=None
for f in sys.argv[1:]:
    c=np.load(f); w=c if w is None else (w|c)
# free runs of >=1KB (word aligned)
i=0; n=len(w); runs=[]
idx=np.flatnonzero(np.diff(np.concatenate(([1],w.astype(np.int8),[1]))))
starts=idx[0::2]; ends=idx[1::2]
for a,b in zip(starts,ends):
    if b-a>=0x400: runs.append((a,b))
for a,b in runs: print(f'{0x80000000+a:08x}-{0x80000000+b:08x} {b-a:#x}')
