from pathlib import Path
import struct,math
out=Path('tests')
files=[];refs=[]
for w,h,off,top in [(1280,16,2048,False),(18,16,54,True)]:
 rows=[];packed=[]
 for y in range(h):
  row=bytearray()
  for x in range(w):
   r,g,b=(x*17+y*13)&255,(x*7+y*11)&255,(x*3+y*19)&255
   row+=bytes([b,g,r]);packed.append(((r>>3)<<11)|((g>>2)<<5)|(b>>3))
  row+=bytes((-len(row))%4);rows.append(row)
 hdr=bytearray(off);hdr[:2]=b'BM';struct.pack_into('<I',hdr,2,off+sum(map(len,rows)));struct.pack_into('<I',hdr,10,off)
 struct.pack_into('<IiiHHI',hdr,14,40,w,-h if top else h,1,24,0)
 files.append(hdr+b''.join(rows));refs.append([packed[i]|(packed[i+1]<<16) for i in range(0,len(packed),2)])
# An unsupported compressed BMP must fail cleanly, without emitting a word.
bad=bytearray(files[1]);struct.pack_into('<I',bad,30,1);files.append(bad)
for mbr in [False,True]:
 base=17 if mbr else 0;fatstart=base+1;datastart=base+5
 disk=bytearray((datastart+420)*512)
 boot=memoryview(disk)[base*512:(base+1)*512]
 struct.pack_into('<H',boot,11,512);boot[13]=1;struct.pack_into('<H',boot,14,1);boot[16]=1
 struct.pack_into('<I',boot,36,4);struct.pack_into('<I',boot,44,2);boot[510:512]=b'\x55\xaa'
 if mbr:
  disk[450]=0x0c;struct.pack_into('<I',disk,454,base);disk[510:512]=b'\x55\xaa'
 fat=memoryview(disk)[fatstart*512:(fatstart+4)*512]
 def setfat(c,v):struct.pack_into('<I',fat,c*4,v)
 setfat(0,0xffffff8);setfat(1,0xfffffff);setfat(2,4);setfat(4,0xfffffff)
 # Fill first root cluster with deleted entries, forcing directory-chain traversal.
 for n in range(16):disk[(datastart)*512+n*32]=0xe5
 starts=[]
 for i,f in enumerate(files):
  n=math.ceil(len(f)/512);clusters=([3+3*j for j in range(n)] if i==0 else ([400,402] if i==1 else [410,412]))[:n]
  starts.append(clusters[0])
  for j,c in enumerate(clusters):
   setfat(c,clusters[j+1] if j+1<n else 0xfffffff)
   pos=(datastart+c-2)*512;chunk=f[j*512:(j+1)*512];disk[pos:pos+len(chunk)]=chunk
  e=(datastart+2)*512+i*32;disk[e:e+11]=f'TEST{i:04d}BMP'.encode();disk[e+11]=0x20
  struct.pack_into('<H',disk,e+20,clusters[0]>>16);struct.pack_into('<H',disk,e+26,clusters[0]&65535);struct.pack_into('<I',disk,e+28,len(f))
 (out/('disk_mbr.hex' if mbr else 'disk.hex')).write_text('\n'.join(f'{v:02x}' for v in disk)+'\n')
for i,r in enumerate(refs):(out/f'expected{i}.hex').write_text('\n'.join(f'{v:08x}' for v in r)+'\n')
print('Generated FAT32 fixtures: chained root, fragmented files, BMP offsets, row padding, signed height, invalid compression')
