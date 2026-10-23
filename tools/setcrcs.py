#!/usr/bin/env python3
"""setcrcs.py : after a build that changes the output, write the new CRC32/SHA-1s
of build/md3{p,pe,n,ne}.bin into web/core.js (moving the old ones to crcOld),
the patcher template, README.md and docs/CHANGES.txt."""
import re, zlib, hashlib, os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
KEYS = (('pal', 'p'), ('pale', 'pe'), ('ntsc', 'n'), ('ntsce', 'ne'))
new, sha = {}, {}
for k, f in KEYS:
    c, h = 0, hashlib.sha1()
    with open('build/md3%s.bin' % f, 'rb') as x:
        for b in iter(lambda: x.read(1 << 24), b''): c = zlib.crc32(b, c); h.update(b)
    new[k] = '%08X' % c; sha[k] = h.hexdigest()
core = open('web/core.js').read()
old = {k: '%08X' % int(v, 16) for k, v in re.findall(r'(\w+): 0x([0-9A-Fa-f]{8})', re.search(r'crcPatched: \{([^}]*)\}', core).group(1))}
if old == new: print('unchanged'); raise SystemExit
core = re.sub(r'crcPatched: \{[^}]*\}', 'crcPatched: { ' + ', '.join('%s: 0x%s' % (k, new[k]) for k, _ in KEYS) + ' }', core)
for grp, ks in (('pal', ('pal', 'pale')), ('ntsc', ('ntsc', 'ntsce'))):
    core = re.sub(r'(crcOld: \{.*?%s: \[)([^\]]*)\]' % grp, lambda m: m.group(1) + m.group(2) + ''.join(', 0x' + old[k] for k in ks) + ']', core, count=1, flags=re.S)
open('web/core.js', 'w').write(core)
for p in ('web/patcher.tpl.html', 'README.md'):
    s = open(p).read()
    for k in old: s = s.replace(old[k], new[k])
    open(p, 'w').write(s)
s = open('docs/CHANGES.txt').read()
for k in old: s = re.sub(r'CRC32 %s, SHA-1 [0-9a-f]{40}' % old[k], 'CRC32 %s, SHA-1 %s' % (new[k], sha[k]), s)
open('docs/CHANGES.txt', 'w').write(s)
print(old, '->', new)
