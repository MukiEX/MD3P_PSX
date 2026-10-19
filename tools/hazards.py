# load-delay check: a load whose result is used by the very next executed instruction
import re,sys
LOADS=('lb','lbu','lh','lhu','lw','lwl','lwr')
BR=re.compile(r'^(b|beq|bne|beqz|bnez|bgez|bltz|bgtz|blez|j|jal|jr|jalr|bal)$')
def parse(fn):
    out=[]
    for ln,l in enumerate(open(fn),1):
        l=l.split(';')[0].strip()
        if not l: continue
        if l.endswith(':'): out.append(('label',l[:-1],ln)); continue
        if l.startswith('.'): out.append(('dir',l,ln)); continue
        m=re.match(r'(\w+)\s*(.*)',l)
        out.append(('ins',(m.group(1),[x.strip() for x in m.group(2).split(',')] if m.group(2) else []),ln))
    return out
def uses(ins,reg):
    op,args=ins
    if not args: return False
    if op in ('sw','sh','sb'): return any(reg in re.findall(r'\b\w+\b',a) for a in args)
    if op in ('j','jal','b','bal'): return False
    if op in ('li','la','lui'): return False
    src=args[1:] if op not in ('beq','bne','beqz','bnez','bgez','bltz','bgtz','blez','jr','jalr','mult','multu','div','divu','mthi','mtlo') else args
    return any(reg in re.findall(r'\b\w+\b',a) for a in src)
for fn in sys.argv[1:]:
    items=parse(fn)
    labels={}
    ins=[]
    scope=0
    for it in items:
        if it[0]=='label':
            if not it[1].startswith('@@'): scope+=1
            labels[(scope,it[1]) if it[1].startswith('@@') else it[1]]=len(ins)
        elif it[0]=='ins': ins.append(it+(scope,))
    for i,(k,(op,args),ln,sc) in enumerate(ins):
        if op in LOADS and args:
            reg=args[0]
            nxt=[i+1]
            if i>0 and BR.match(ins[i-1][1][0]):
                tgt=ins[i-1][1][1][-1] if ins[i-1][1][1] else None
                key=(sc,tgt) if tgt and tgt.startswith('@@') else tgt
                if key in labels: nxt.append(labels[key])
            for n in nxt:
                if n<len(ins) and uses(ins[n][1],reg):
                    print(f'{fn}:{ln}: {op} {",".join(args)}  ->  line {ins[n][2]}: {ins[n][1][0]} {",".join(ins[n][1][1])}')
