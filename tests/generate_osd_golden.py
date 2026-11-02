from pathlib import Path
import re,json
p=Path(__file__).resolve().parents[1]
# Golden text samples are produced from the ROM and explicit cell definitions,
# independent of the RTL's address/column selection. They cover complete cells,
# including gaps where the previous design incorrectly re-painted glyphs.
import re,json
fontrows=[int(x,16) for x in re.findall(r"32'h([0-9a-f]+)",(p/'font_rom_init.vh').read_text())]
cjk=json.loads((p/'tools/font_manifest.json').read_text(encoding='utf-8'))['cjk']
bgs=[(10,24,34),(15,34,45),(11,27,37)];fgs=[(235,244,244),(139,166,178),(84,226,185),(245,185,96)]
def c565(c):r,g,b=c;return ((r>>3)<<11)|((g>>2)<<5)|(b>>3)
# alpha0 uses the exact background chosen by RTL; alpha>0 uses its semantic palette.
def ink(ctx,tone,alpha):return c565(tuple((bgs[ctx][i]*(3-alpha)+fgs[tone][i]*alpha+1)//3 for i in range(3)))
regions=[(80,24,'LUMA',1,False,0,0,0x08c4),(168,32,'光映影廊',0,True,1,0,0x08c4),(272,32,'FPGA MULTIMEDIA',0,False,1,0,0x08c4),(1040,112,'NOW SHOWING',0,False,1,1,0x1105),(1040,140,'02',1,False,0,1,0x1105),(1096,152,'/ 04',0,False,1,1,0x1105),(1040,192,'本地影像',0,True,0,1,0x1105),(1040,224,'1280 X 0720',0,False,1,1,0x1105),(1040,248,'ASPECT FILL / RGB565 '.ljust(20),0,False,1,1,0x1105),(1040,296,'PLAYBACK',0,False,1,1,0x1105),(1040,320,'自动播放',0,True,2,1,0x1105),(1040,384,'BRIGHTNESS',0,False,1,1,0x1105),(1040,408,'100%',1,False,2,1,0x1105),(1040,576,'48 KHZ / STEREO',0,False,1,1,0x1105),(1040,608,'K2 NEXT  K3 PREV',0,False,1,1,0x1105)]
regions.append((480,32,'SD 25.0M  LOAD 001.2S',0,False,1,0,0x08c4))
gold={}
for x0,y0,text,scale,chinese,tone,ctx,bg in regions:
 cell=16 if chinese else 8;factor=1<<scale
 for dy in range(16*factor):
  for dx in range(len(text)*cell*factor):
   index=dx//(cell*factor);col=(dx//factor)%cell;row=dy//factor;ch=text[index]
   code=ord(ch)-32 if ord(ch)<127 else cjk[ch]
   alpha=(fontrows[code*16+row]>>(2*col))&3
   color=ink(ctx,tone,alpha) if alpha else bg
   gold[(x0+dx,y0+dy)]=color
# A packed address in the 1280x720 frame and expected RGB565.
(p/'tests/osd_golden.hex').write_text('\n'.join(f'{((y*1280+x)<<16)|c:010x}' for (x,y),c in sorted(gold.items(),key=lambda kv:kv[0][1]*1280+kv[0][0]))+'\n')
(p/'tests/osd_golden_count.vh').write_text(f'localparam GOLDEN_COUNT={len(gold)};\n')
print('UI golden samples:',len(gold))
