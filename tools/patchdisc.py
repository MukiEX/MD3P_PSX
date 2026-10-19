# patchdisc.py in.bin out.bin NAME=file [NAME=file...]  (replaces same-size files in place)
import sys,os,shutil
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from iso import Disc
import cdsec
src,dst=sys.argv[1],sys.argv[2]
if os.path.abspath(src)!=os.path.abspath(dst): shutil.copyfile(src,dst)
d=Disc(src); files={p.split(';')[0]:(l,s) for p,l,s,_ in d.walk()}
f=open(dst,'r+b')
for arg in sys.argv[3:]:
    name,path=arg.split('=',1); lba,size=files[name]
    data=open(path,'rb').read(); assert len(data)==size,(name,len(data),size)
    n=0
    for i in range((size+2047)//2048):
        f.seek((lba+i)*2352); sec=bytearray(f.read(2352))
        chunk=data[i*2048:(i+1)*2048].ljust(2048,b'\0')
        if sec[24:24+2048]!=chunk:
            sec[24:24+2048]=chunk; cdsec.fix_mode2form1(sec); f.seek((lba+i)*2352); f.write(sec); n+=1
    print(name,'sectors changed',n)
f.close()
