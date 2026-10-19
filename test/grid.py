import sys
from PIL import Image
fs=sys.argv[2:]; ims=[Image.open(f).convert('RGB').resize((320,240)) for f in fs]
cols=3; rows=(len(ims)+cols-1)//cols
w=Image.new('RGB',(320*cols,240*rows))
for i,im in enumerate(ims): w.paste(im,((i%cols)*320,(i//cols)*240))
w.save(sys.argv[1])
