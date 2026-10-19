#!/usr/bin/env python3
"""extract_exes.py <md3.bin> <outdir> : copy SLES_029.64 and MD3xx.EXE out of the BIN"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from iso import Disc
d = Disc(sys.argv[1]); out = sys.argv[2]; os.makedirs(out, exist_ok=True)
for p, l, s, _ in d.walk():
    n = p.split(';')[0]
    if n.endswith('.EXE') or n.startswith('SLES') or n == 'SYSTEM.CNF':
        open(os.path.join(out, n), 'wb').write(d.data(l, (s + 2047) // 2048)[:s])
        print(n, s)
