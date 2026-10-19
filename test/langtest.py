# langtest.py cue lang_index outprefix [NTSC]
import sys,re; sys.path.insert(0,__import__('os').path.dirname(__import__('os').path.abspath(__file__)))
from env import *
from retro import *
cue,li,pfx=sys.argv[1],int(sys.argv[2]),sys.argv[3]
opts={'pcsx_rearmed_region':'NTSC'} if len(sys.argv)>4 else None
e=Emu(cue,opts=opts,ports=('standard','standard'))
S=ROOT+'/shots/'
def click(k=2,n=20):
    e.mouse[0][k]=1; e.run(6); e.mouse[0][k]=0; e.run(n)
def chord(n=20):
    e.mouse[0][2]=e.mouse[0][3]=1; e.run(6); e.mouse[0][2]=e.mouse[0][3]=0; e.run(n)
def mv(dx,dy,frames=4):
    for i in range(frames): e.mouse[0][0]=dx; e.mouse[0][1]=dy; e.run(1)
    e.run(20)
e.run(400)
for i in range(li): e.press(0,RIGHT,4,20)
e.press(0,B,4,30)
e.lib.retro_set_controller_port_device(0,0x102); e.run(500)
for k in range(6): click(n=150)
e.run(300); chord(500); chord(500)
e.shot(S+pfx+'_menu.png')
menu=e.save()
for i in range(4): mv(0,5)
click(n=200)
for i in range(5): mv(0,5)
mv(5,0); e.shot(S+pfx+'_opt.png')
e.load(menu); e.run(5)
click(n=360); click(n=480); click(n=360)
for i in range(6): chord(360)
e.run(200)
L=['EN','FR','GE','IT','SP','NL'][li]
d='out_ntsc' if len(sys.argv)>4 else 'out'
sym={l.split()[1]:int(l.split()[0],16) for l in open(f'{ROOT}/{d}/work_{L}/final.sym') if re.match(r'^[0-9A-F]{8} \w',l)}
def ingame():
    return e.r32(sym['v_frame'])-e.r32(sym['state']+0x24)<3
for k in range(4):
    if ingame(): break
    chord(120)
print(L,'ingame',ingame())
u0=e.r32(sym['state']+4)
e.shot(S+pfx+'_game0.png')
for k in range(4): mv(12,0,2)
e.run(30); e.shot(S+pfx+'_game.png')
import numpy as np
print(L,'units',u0,'->',e.r32(sym['state']+4),'tcol',e.r32(sym['state']+0x20))
