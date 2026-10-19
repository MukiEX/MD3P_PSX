#!/usr/bin/env python3
"""Build Magical Drop III (PS1, Europe) Paddle Edition executables.

  build.py <dir with original MD3xx.EXE files> <out dir> [--ntsc] [LANG ...]

For every language EXE the hook addresses are located by masked
instruction signatures taken from the English EXE, free space is taken
from statically unreachable library code, and the payload chunks are
packed into it before armips assembles the final EXE.
"""
import sys, os, struct, re, subprocess, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ps import Exe

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, 'src')
ARMIPS = os.environ.get('ARMIPS', 'armips')

# ---------------------------------------------------------------- signatures
def mask(w):
    op = w >> 26
    if op in (2, 3):
        return w & 0xFC000000
    if op == 0:
        return w
    if op in (0x10, 0x12):          # cop0 / cop2: keep
        return w
    return w & 0xFFFF0000            # I-type: drop the immediate

def masked(e, a, n):
    return [mask(e.w(a + 4 * i)) for i in range(n)]

def find_sig(ref, a, tgt, before=8, after=12, hint=None):
    """locate EN address a in tgt by a masked window; returns target address"""
    for (b, f) in ((before, after), (16, 24), (24, 40)):
        sig = masked(ref, a - 4 * b, b + f)
        ws = [mask(w) for _, w in tgt.words()]
        hits = []
        n = len(sig)
        first = sig[0]
        for i in range(len(ws) - n):
            if ws[i] == first and ws[i:i + n] == sig:
                hits.append(tgt.base + 4 * i + 4 * b)
        if len(hits) == 1:
            return hits[0]
        if hint is not None and hits:
            hits.sort(key=lambda h: abs(h - hint))
            if len(hits) > 1 and abs(hits[0] - hint) < abs(hits[1] - hint) // 4:
                return hits[0]
    raise RuntimeError('signature for %08x: %d hits' % (a, len(hits)))

def lui_value(e, a):
    """value of the absolute address referenced by the load/store/addiu at a"""
    w = e.w(a); rs = (w >> 21) & 31; imm = w & 0xFFFF
    s = imm - 0x10000 if imm & 0x8000 else imm
    for k in range(1, 24):
        p = e.w(a - 4 * k)
        if (p >> 26) == 0xF and ((p >> 16) & 31) == rs:
            return ((p & 0xFFFF) << 16) + s & 0xFFFFFFFF
    raise RuntimeError('no lui before %08x' % a)

# EN reference addresses
CODE = {
    'G_PadInitTail':    0x8006cb80,
    'G_PadInitEpi':     0x8006cb9c,
    'G_InitPAD':        0x80063d4c,
    'G_StartPAD':       0x80063ddc,
    'G_ChangeClearPad': 0x800637e0,
    'G_PadRead':        0x8006cbac,
    'G_InputCall':      0x8001447c,
    'G_InputFn':        0x80014394,
    'G_ClownHook':      0x8003575c,
    'G_ClownX':         0x80025130,
    'G_AimX':           0x80024d84,
    'G_CellX':          0x80024564,
    'G_CellEnd':        0x80024990,
    'G_Cursor':         0x8005e5bc,
    'G_Sound':          0x80015674,
    'G_Unlock1':        0x8005e748,
    'G_Unlock2':        0x8005e7c8,
    'G_Unlock3':        0x8005e800,
    'G_OptTabRef':      0x8005fe18,
    'G_OptLoopCnt':     0x8005fe4c,
    'G_OptCursorCall':  0x8005d084,
    'G_OptCursorFn':    0x8005d1dc,
    'G_OptDrawEnd':     0x8005ff54,
    'G_DrawText':       0x80061830,
    'G_OptArrows':      0x800603b8,
    'G_NamePressed':    0x8003be74,
    'G_VidMode':        0x80013fa8,
    'G_ScrX':           0x80014064,
    'G_ScrY':           0x8001407c,
    'G_MovX':           0x8001be4c,
    'G_MovY':           0x8001be54,
}
# data symbol: EN address of an instruction using it (lui-pair)
DATA = {
    'G_Held':    0x800143a8,
    'G_Pressed': 0x800143d4,
    'G_NCols':   0x800358a4,
    'G_NRows':   0x800356d4,
    'G_Bright':  0x8001587c,
    'G_Mode':    0x8005e680,
    'G_OptSndTab': 0x8005d320,
    'G_OptTab':  0x8005fe1c,
}
GPDATA = {'G_OptSndIdx': 0x8005d30c}
EXPECT_EN = {'G_Held': 0x800a911c, 'G_Pressed': 0x800a9144, 'G_NCols': 0x800a913c,
             'G_NRows': 0x800a9140, 'G_Bright': 0x800a918e, 'G_Mode': 0x800a91b0}
# original instruction checks (EN words) at the patched sites
CHECK = {
    'G_PadInitTail': [0x3c042000, 0x3c05800c],
    'G_PadRead':     [0x27bdffe8, 0xafbf0010],
    'G_InputCall':   [0x0c0050e5],
    'G_ClownHook':   [0x96120366],
    'G_ClownX':      [0x8e620018, 0x8e630010, 0x8e640014, 0x00021500],
    'G_AimX':        [0x8c227500],
    'G_CellX':       [0x8c237500],
    'G_CellEnd':     [0x8e4200cc, 0x00000000],
    'G_Cursor':      [0x27bdffb0, 0xafb10044],
    'G_Unlock1':     [0x904284ec],
    'G_Unlock2':     [0x904284ec],
    'G_Unlock3':     [0x904284ec],
    'G_OptTabRef':   [0x3c10800a, 0x2610a758],
    'G_OptLoopCnt':  [0x2a220008],
    'G_OptCursorCall': [0x0c017477],
    'G_OptDrawEnd':  [0x8fbf002c, 0x8fb40028],
    'G_NamePressed': [0x94259144, 0x3c01800b],
    'G_VidMode':     [0x34040001],
    'G_ScrX':        [0x34020005],
    'G_ScrY':        [0x3402001a],
    'G_MovX':        [0x34020005],
    'G_MovY':        [0x3402001a],
}

def derive(ref, tgt, lang):
    syms = {}
    for k, a in CODE.items():
        syms[k] = a if tgt is ref else find_sig(ref, a, tgt)
    for k, a in DATA.items():
        site = a if tgt is ref else find_sig(ref, a, tgt)
        syms[k] = lui_value(tgt, site)
    gp = gp_of(tgt)
    for k, a in GPDATA.items():
        site = a if tgt is ref else find_sig(ref, a, tgt)
        w = tgt.w(site); assert (w >> 21) & 31 == 28, (k, hex(w))
        imm = w & 0xFFFF
        syms[k] = gp + (imm - 0x10000 if imm & 0x8000 else imm)
    syms['G_OptDrawRet'] = syms['G_OptDrawEnd'] + 8
    syms['G_OptScoreY'] = syms['G_OptTab'] + 5 * 12 + 6
    if tgt is ref:
        assert syms['G_OptSndIdx'] == 0x800a8e10, hex(syms['G_OptSndIdx'])
        for k, v in EXPECT_EN.items():
            assert syms[k] == v, (k, hex(syms[k]))
    # verify patch sites hold the expected instructions (modulo relocation)
    for k, ws in CHECK.items():
        for i, w in enumerate(ws):
            got = tgt.w(syms[k] + 4 * i)
            if mask(got) != mask(w):
                raise RuntimeError('%s: %s+%d is %08x, expected %08x' % (lang, k, i, got, w))
    syms['G_Entry'] = tgt.pc
    # heap start (InitHeap writes a header there): the 'lui a0 / addiu a0'
    # pair after the BSS clear loop
    bss_end = lui_value(tgt, tgt.pc + 12)
    for a in range(tgt.pc + 16, tgt.pc + 0x80, 4):
        if (tgt.w(a) >> 16) == 0x3C04 and (tgt.w(a + 4) >> 16) == 0x2484 and lui_value(tgt, a + 4) == bss_end:
            syms['G_HeapLui'] = a
            break
    else:
        raise RuntimeError('heap start not found')
    return syms

def gp_of(e):
    for a in range(e.pc, e.pc + 0x100, 4):
        w = e.w(a)
        if (w >> 16) == 0x3C1C:
            lo = e.w(a + 4) & 0xFFFF
            return ((w & 0xFFFF) << 16) + (lo - 0x10000 if lo & 0x8000 else lo)
    raise RuntimeError('gp not found')

MOUSE_SPEED = {'EN': 'Mouse speed', 'FR': 'Vitesse souris', 'GE': 'Maus-Tempo',
               'IT': 'Velocita mouse', 'SP': 'Vel. raton', 'NL': 'Muissnelheid'}

def opttab_asm(e, syms, lang):
    t = syms['G_OptTab']
    ent = [struct.unpack_from('<4HI', e.img, t - e.base + 12 * i) for i in range(8)]
    out = ['opttab:']
    def row(h, y=None, ptr=None):
        return '    .halfword 0x%x, 0x%x, 0x%x, 0x%x\n    .word %s' % (
            h[0], h[1], h[2], h[3] if y is None else y, ptr or '0x%08x' % h[4])
    for i in range(7):
        out.append(row(ent[i], 0xA0 if i == 5 else None))
    out.append(row((0, 0x10, 0, 0x88, 0), ptr='optlabel'))
    out.append(row(ent[7]))
    out.append('optlabel:\n    .ascii "%s", 0' % MOUSE_SPEED[lang])
    return '\n'.join(out) + '\n'

# ---------------------------------------------------------------- free space
def holes(e, protect, min_size=0x40, code_lo=0x80013000):
    """statically unreachable code runs (library functions nobody calls)"""
    CODE_LO, CODE_HI = code_lo, code_end(e)
    W = {a: w for a, w in e.words()}
    roots = set([e.pc])
    for a, w in W.items():
        if CODE_LO <= w < CODE_HI and w % 4 == 0:
            roots.add(w)
    lui = {}
    for a in sorted(W):
        w = W[a]; op = w >> 26; rt = (w >> 16) & 31; rs = (w >> 21) & 31; imm = w & 0xFFFF
        s = imm - 0x10000 if imm & 0x8000 else imm
        if op == 0xF:
            lui[rt] = (imm << 16, a)
        elif op in (9, 0xD) and rs in lui and a - lui[rs][1] < 128:
            v = (lui[rs][0] + (imm if op == 0xD else s)) & 0xFFFFFFFF
            if CODE_LO <= v < CODE_HI and v % 4 == 0:
                roots.add(v)
    roots |= set(protect)
    seen = set(); work = list(roots)
    while work:
        a = work.pop()
        while CODE_LO <= a < CODE_HI and a not in seen:
            seen.add(a); w = W.get(a, 0); op = w >> 26; fn = w & 63
            rs = (w >> 21) & 31; rt = (w >> 16) & 31; imm = w & 0xFFFF
            s = imm - 0x10000 if imm & 0x8000 else imm
            if op == 0 and fn == 8:
                seen.add(a + 4); break
            if op == 2:
                seen.add(a + 4); work.append(((w & 0x3FFFFFF) << 2) | 0x80000000); break
            if op == 3:
                work.append(((w & 0x3FFFFFF) << 2) | 0x80000000)
            if op in (4, 5, 6, 7) or (op == 1 and rt in (0, 1, 16, 17)):
                work.append(a + 4 + (s << 2))
                if op == 4 and rs == 0 and rt == 0:
                    seen.add(a + 4); break
            a += 4
    runs = []
    a = CODE_LO
    while a < CODE_HI:
        if a not in seen:
            b = a
            while b < CODE_HI and b not in seen:
                b += 4
            # start at the first function prologue inside the run
            p = a
            while p < b and not ((W.get(p, 0) >> 16) == 0x27BD and W.get(p, 0) & 0x8000):
                p += 4
            if b - p >= min_size and p >= min(seen):
                runs.append((p, b))
            a = b
        else:
            a += 4
    return runs

def code_end(e):
    # the library code ends with BIOS call stubs; use the entry + a margin
    # (data follows right after the last 'jr' block). Scan for the last jr ra
    # before the first long run of non-code data after the entry point.
    a = e.pc
    last = a
    while a < e.base + e.size - 4:
        w = e.w(a)
        if w == 0x03E00008:
            last = a + 8
        a += 4
        if a - last > 0x2000:
            break
    return last

# ---------------------------------------------------------------- assembling
def split_chunks(text):
    head, rest = text.split(';@chunks\n', 1)
    body, tail = rest.split(';@endchunks\n', 1)
    parts = re.split(r'^;@chunk (\w+)\n', body, flags=re.M)
    chunks = []
    for i in range(1, len(parts), 2):
        chunks.append((parts[i], parts[i + 1]))
    return head, chunks, tail

def write_syms(path, syms, extra):
    with open(path, 'w') as f:
        for k, v in sorted(syms.items()):
            f.write('.definelabel %s, 0x%08x\n' % (k, v))
        for k, v in extra.items():
            f.write('%s equ %s\n' % (k, v))

def armips(asm, defs, cwd):
    cmd = [ARMIPS, asm]
    for k, v in defs.items():
        cmd += ['-strequ', k, v]
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0 or 'error' in r.stdout.lower():
        raise RuntimeError(r.stdout + r.stderr)
    return r.stdout

def read_sym(path):
    d = {}
    for line in open(path):
        p = line.split()
        if len(p) == 2 and re.match(r'^[0-9A-Fa-f]{8}$', p[0]):
            d[p[1]] = int(p[0], 16)
    return d

def build(lang, src_exe, out_exe, ref, opts, log):
    tgt = ref if lang == 'EN' else Exe(src_exe)
    syms = derive(ref, tgt, lang)
    text = open(os.path.join(SRC, 'md3psx_paddle.asm')).read()
    head, chunks, tail = split_chunks(text)
    work = os.path.join(os.path.dirname(out_exe), 'work_' + lang)
    os.makedirs(work, exist_ok=True)
    extra = {'NTSC': '1' if opts.get('ntsc') else '0', 'UNLOCK': '0' if opts.get('nounlock') else '1'}
    write_syms(os.path.join(work, 'syms.asm'), syms, extra)
    open(os.path.join(work, 'opttab.asm'), 'w').write(opttab_asm(tgt, syms, lang))
    # pass 1: measure chunk sizes
    meas = head.split('.open INFILE')[0]
    meas += '.create "measure.bin", 0x80300000\n'
    for n, c in chunks:
        meas += '.align 4\n__s_%s:\n%s\n.align 4\n__e_%s:\n' % (n, c, n)
    meas += '.close\n'
    open(os.path.join(work, 'measure.asm'), 'w').write(meas.replace('.include "syms.asm"', '.include "syms.asm"'))
    r = subprocess.run([ARMIPS, 'measure.asm', '-sym', 'measure.sym'], cwd=work, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stdout + r.stderr)
    ms = read_sym(os.path.join(work, 'measure.sym'))
    ms = {k.lower(): v for k, v in ms.items()}
    sizes = {n: ms['__e_' + n.lower()] - ms['__s_' + n.lower()] for n, _ in chunks}
    # free space
    protect = [syms[k] for k in ('G_InitPAD', 'G_StartPAD', 'G_ChangeClearPad', 'G_Sound', 'G_InputFn')]
    hs = holes(tgt, protect)
    bss_end = lui_value(tgt, tgt.pc + 12)
    if bss_end < 0x8010B000:
        hs.append((bss_end, 0x8010B000))
    hs = [[a, b] for a, b in sorted(hs, key=lambda h: h[1] - h[0], reverse=True)]
    def pack(order):
        free = [list(h) for h in hs]
        place = {}
        for n in order:
            need = sizes[n] + 4
            # best fit: the smallest hole that still takes the chunk
            fits = [h for h in free if h[1] - h[0] >= need]
            if not fits:
                return None
            h = min(fits, key=lambda h: (h[1] - h[0], h[0]))
            place[n] = h[0]; h[0] += (need + 3) & ~3
        return place
    order = sorted(sizes, key=lambda n: (-sizes[n], n))
    place = pack(order)
    if place is None:
        # best fit largest-first didn't work: search (largest chunks first,
        # trying each hole that takes them, smallest first)
        need = {n: ((sizes[n] + 4) + 3) & ~3 for n in order}
        free = [list(h) for h in hs]
        place = {}
        steps = [0]
        def dfs(i):
            if i == len(order):
                return True
            steps[0] += 1
            if steps[0] > 200000:
                return False
            n = order[i]
            if sum(need[m] for m in order[i:]) > sum(h[1] - h[0] for h in free):
                return False
            tried = set()
            for h in sorted(free, key=lambda h: (h[1] - h[0], h[0])):
                room = h[1] - h[0]
                if room < need[n] or room in tried:
                    continue
                tried.add(room)
                place[n] = h[0]; h[0] += need[n]
                if dfs(i + 1):
                    return True
                h[0] -= need[n]; del place[n]
            return False
        if not dfs(0):
            raise RuntimeError('%s: the payload chunks do not fit the free space\n  holes %s\n  chunks %s' % (
                lang, sorted([h[1] - h[0] for h in hs], reverse=True), sorted(need.values(), reverse=True)))
    final = head + '\n'
    for n, c in chunks:
        final += '.org 0x%08x\n.align 4\n%s\n' % (place[n], c)
    final += tail
    open(os.path.join(work, 'final.asm'), 'w').write(final)
    import shutil
    shutil.copy(os.path.join(SRC, 'md3psx_paddle.asm'), os.path.join(work, 'src_copy.asm'))
    r = subprocess.run([ARMIPS, 'final.asm', '-strequ', 'INFILE', os.path.abspath(src_exe),
                        '-strequ', 'OUTFILE', os.path.abspath(out_exe), '-sym', 'final.sym'],
                       cwd=work, capture_output=True, text=True)
    if r.returncode != 0 or 'error' in (r.stdout + r.stderr).lower():
        raise RuntimeError(r.stdout + r.stderr)
    used = sum(sizes.values())
    log.append({'lang': lang, 'syms': {k: '%08x' % v for k, v in syms.items()},
                'chunks': {n: ['%08x' % place[n], sizes[n]] for n in sizes}, 'payload_bytes': used})
    return syms, place, sizes

def main():
    args = sys.argv[1:]
    opts = {'ntsc': '--ntsc' in args, 'nounlock': '--nounlock' in args}
    args = [a for a in args if not a.startswith('--')]
    srcdir, outdir = args[0], args[1]
    langs = args[2:] or ['EN', 'FR', 'GE', 'IT', 'SP', 'NL']
    os.makedirs(outdir, exist_ok=True)
    ref = Exe(os.path.join(srcdir, 'MD3EN.EXE'))
    log = []
    for L in langs:
        syms, place, sizes = build(L, os.path.join(srcdir, 'MD3%s.EXE' % L),
                                   os.path.join(outdir, 'MD3%s.EXE' % L), ref, opts, log)
        print(L, 'ok', sum(sizes.values()), 'bytes in', len(set(place.values())), 'chunks')
    json.dump(log, open(os.path.join(outdir, 'build_log.json'), 'w'), indent=1)

if __name__ == '__main__':
    main()
