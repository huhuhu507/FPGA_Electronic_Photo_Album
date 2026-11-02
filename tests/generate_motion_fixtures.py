from pathlib import Path
import sys,struct,math
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from lav_format import pack_clip,inspect_clip
out=Path(__file__).resolve().parent
w,h,n,fps=32,16,3,30
frames=np.arange(n*h*w,dtype=np.uint16).reshape(n,h,w)^0xa55a
samples=np.arange(n*1600,dtype=np.int32)
pcm=np.stack(((samples*73)%60000-30000,(samples*97)%58000-29000),axis=1).astype('<i2')
good=pack_clip(frames,pcm,fps);info=inspect_clip(good)
bad=bytearray(good);bad[-7]^=1
invalid=bytearray(good);struct.pack_into('<I',invalid,8,641)
# A small top-down BMP, to verify recovery to the original image path.
pixels=bytes((80,120,200))*16*16
bmp=bytearray(54);bmp[:2]=b'BM';struct.pack_into('<I',bmp,2,54+len(pixels));struct.pack_into('<I',bmp,10,54)
struct.pack_into('<IiiHHI',bmp,14,40,16,-16,1,24,0)
files=[good,bytes(bad),bytes(invalid),bytes(bmp)+pixels]
for mbr in (False,True):
 base=17 if mbr else 0;fat_start=base+1;data_start=base+5
 disk=bytearray((data_start+640)*512)
 boot=memoryview(disk)[base*512:(base+1)*512]
 struct.pack_into('<H',boot,11,512);boot[13]=1;struct.pack_into('<H',boot,14,1);boot[16]=1
 struct.pack_into('<I',boot,36,4);struct.pack_into('<I',boot,44,2);boot[510:512]=b'\x55\xaa'
 if mbr:disk[450]=0x0c;struct.pack_into('<I',disk,454,base);disk[510:512]=b'\x55\xaa'
 fat=memoryview(disk)[fat_start*512:(fat_start+4)*512]
 def setfat(c,v):struct.pack_into('<I',fat,c*4,v)
 setfat(0,0xffffff8);setfat(1,0xfffffff);setfat(2,4);setfat(4,0xfffffff)
 for j in range(16):disk[data_start*512+j*32]=0xe5
 for index,data in enumerate(files):
  clusters=[10+index*150+j*3 for j in range(math.ceil(len(data)/512))]
  for j,c in enumerate(clusters):
   setfat(c,clusters[j+1] if j+1<len(clusters) else 0xfffffff)
   chunk=data[j*512:(j+1)*512];offset=(data_start+c-2)*512;disk[offset:offset+len(chunk)]=chunk
  entry=(data_start+2)*512+index*32
  disk[entry:entry+11]=f'MEDIA{index:03d}'.encode()+(b'BMP' if index==3 else b'LAV');disk[entry+11]=0x20
  struct.pack_into('<H',disk,entry+20,clusters[0]>>16);struct.pack_into('<H',disk,entry+26,clusters[0]&65535);struct.pack_into('<I',disk,entry+28,len(data))
 (out/('motion_disk_mbr.hex' if mbr else 'motion_disk.hex')).write_text('\n'.join(f'{x:02x}' for x in disk)+'\n')
payload=np.frombuffer(good,dtype='<u4',offset=512)
(out/'motion_expected.hex').write_text('\n'.join(f'{int(v):08x}' for v in payload)+'\n')
print('Generated LAV1 fixtures:',info)
