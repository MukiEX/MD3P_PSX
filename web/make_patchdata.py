#!/usr/bin/env python3
# make_patchdata.py original.bin patched.bin out.b64
# Patch blob for the browser patcher: u32 count, then per record u32 offset,
# u16 length, bytes (records never cross a 2352-byte sector); raw-deflated, base64.
import sys, zlib, base64, struct
import numpy as np
o = np.fromfile(sys.argv[1], dtype=np.uint8)
p = np.fromfile(sys.argv[2], dtype=np.uint8)
assert len(o) == len(p)
d = np.nonzero(o != p)[0]
recs = []; s = e = int(d[0])
for x in d[1:]:
    x = int(x)
    if x - e <= 16 and x // 2352 == s // 2352: e = x
    else: recs.append((s, e + 1)); s = e = x
recs.append((s, e + 1))
blob = bytearray(struct.pack('<I', len(recs)))
for a, b in recs: blob += struct.pack('<IH', a, b - a) + p[a:b].tobytes()
c = zlib.compressobj(9, zlib.DEFLATED, -15)
open(sys.argv[3], 'w').write(base64.b64encode(c.compress(bytes(blob)) + c.flush()).decode())
print(sys.argv[3], len(recs), 'records')
