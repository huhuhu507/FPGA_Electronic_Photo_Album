from pathlib import Path
import sys,struct,math,runpy
import numpy as np
out=Path(__file__).resolve().parent
sys.path.insert(0,str(out.parent/'tools'))
from lav_format import pack_clip,inspect_clip
from bc1_codec import decode_frame
# Reuse only the directory/FAT layout recipe; generate a compressed primary file.
recipe=(out/'generate_motion_fixtures.py').read_text()
recipe=recipe.replace('good=pack_clip(frames,pcm,fps);','good=pack_clip(frames,pcm,fps,compressed=True);')
recipe=recipe.replace('motion_disk','fast_disk').replace('motion_expected','fast_expected')
exec(compile(recipe,str(out/'generate_motion_fixtures.py'),'exec'),{'__file__':str(out/'generate_motion_fixtures.py')})
# Independent compressed blocks: all selector positions, all four subrows,
# distinct blocks and frames. Expected pixels computed directly from integers.
w,h,count=640,480,2
blocks=[];gold=[]
for f in range(count):
 image=np.zeros((h,w),dtype=np.uint16)
 for by in range(h//4):
  for bx in range(w//4):
   n=f*(w//4)*(h//4)+by*(w//4)+bx
   c0=(0x8401+n*31)&65535;c1=(0x3bde+n*13)&65535
   c0,c1=max(c0,c1),min(c0,c1)
   if c0==c1:c0=(c0+1)&65535
   def channels(c):return ((c>>11)&31,(c>>5)&63,c&31)
   a,b=channels(c0),channels(c1)
   pal=[a,b,tuple((2*x+y)//3 for x,y in zip(a,b)),tuple((x+2*y)//3 for x,y in zip(a,b))]
   pal=[(r<<11)|(g<<5)|b for r,g,b in pal]
   selectors=0
   for ry in range(4):
    for rx in range(4):
     i=((rx+ry+n)^(n>>3))&3
     selectors|=i<<(2*(ry*4+rx));image[by*4+ry,bx*4+rx]=pal[i]
   blocks.extend([c0|(c1<<16),selectors])
 gold.extend(image.ravel().tolist())
(out/'bc1_memory.hex').write_text('\n'.join(f'{v:08x}' for v in blocks)+'\n')
(out/'bc1_expected.hex').write_text('\n'.join(f'{v:04x}' for v in gold)+'\n')
print('Generated BC1 640x480 two-frame independent pixel fixture',flush=True)
