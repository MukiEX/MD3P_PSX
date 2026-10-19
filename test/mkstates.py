# build fresh savestates for the current patched disc: menu (mouse on port 1), card select, game
import sys; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
cue=sys.argv[1] if len(sys.argv)>1 else ROOT+'/build/md3p.cue'
pfx=sys.argv[2] if len(sys.argv)>2 else 'n_'
e=Emu(cue)
e.run(400); e.press(0,B,4,20); e.run(600); e.press(0,B,4,20); e.run(600)
e.press(0,START,4,20); e.run(400); e.press(0,START,4,20); e.run(400)
D=ROOT+'/st/'
open(D+pfx+'menu.bin','wb').write(e.save()); e.shot(ROOT+'/shots/'+pfx+'menu.png')
e.lib.retro_set_controller_port_device(0,0x102); e.run(30)
def click(k,n):
    e.mouse[0][k]=1; e.run(5); e.mouse[0][k]=0; e.run(n)
click(2,300); click(2,400)
open(D+pfx+'csel.bin','wb').write(e.save()); e.shot(ROOT+'/shots/'+pfx+'csel.png')
click(2,300)
for i in range(6):
    e.mouse[0][2]=e.mouse[0][3]=1; e.run(5); e.mouse[0][2]=e.mouse[0][3]=0; e.run(300)
e.run(200)
import re,struct
sym={l.split()[1]:int(l.split()[0],16) for l in open(ROOT+'/out/work_EN/final.sym') if re.match(r'^[0-9A-F]{8} \w',l)}
def ingame():
    f=e.r32(sym['v_frame']); g=e.r32(sym['state']+0x24); return f-g<3
for k in range(4):
    if ingame(): break
    e.mouse[0][2]=e.mouse[0][3]=1; e.run(5); e.mouse[0][2]=e.mouse[0][3]=0; e.run(120)
print('ingame',ingame())
open(D+pfx+'game.bin','wb').write(e.save()); e.shot(ROOT+'/shots/'+pfx+'game.png')
