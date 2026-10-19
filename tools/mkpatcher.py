#!/usr/bin/env python3
# mkpatcher.py <patchdata dir> <out.html>
# Inlines chd.js, core.js and the four patch blobs into the single-file patcher.
import re, sys, os
d = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'web') + '/'
pd = sys.argv[1].rstrip('/') + '/'
strip = lambda s: re.sub(r'^if \(typeof module.*$', '', s, flags=re.M)
t = open(d + 'patcher.tpl.html').read()
t = t.replace('/*CHD_JS*/', strip(open(d + 'chd.js').read())).replace('/*CORE_JS*/', strip(open(d + 'core.js').read()))
for k in ('pal', 'pale', 'ntsc', 'ntsce'):
    t = t.replace('/*PATCH_%s*/' % k.upper(), open(pd + 'patch_%s.b64' % k).read().strip())
assert '</script' not in t.split('id="worker-src">')[1].split('</script>')[0]
open(sys.argv[2], 'w').write(t)
print(sys.argv[2], len(t), 'bytes')
