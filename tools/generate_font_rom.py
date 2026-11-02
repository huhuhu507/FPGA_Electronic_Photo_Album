from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
import json
p=Path(__file__).resolve().parents[1];chars=''.join(dict.fromkeys('光映影廊本地像自动播放暂停亮度音频波形加载中就绪错误测试画面适配'))
assert len(chars)<=33
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',13)
cjk=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',15)
rows=[]
for code in range(128):
 im=Image.new('L',(16,16));d=ImageDraw.Draw(im)
 if code<95:d.text((0,-1),chr(code+32),font=font,fill=255,stroke_width=0)
 elif code-95<len(chars):d.text((0,-1),chars[code-95],font=cjk,fill=255)
 for y in range(16):
  v=0
  for x in range(16):v|=min(3,(im.getpixel((x,y))+42)//85)<<(2*x)
  rows.append(v)
# Explicit synchronous ROM initialization is accepted by TD and is portable.
init='\n'.join(f'  font_rom[{i}]=32\'h{v:08x};' for i,v in enumerate(rows))
(p/'font_rom_init.vh').write_text(init+'\n',encoding='utf-8')
(p/'tools/font_manifest.json').write_text(json.dumps({'ascii':'glyph index = ASCII - 32; 0..94','cjk':{ch:95+i for i,ch in enumerate(chars)},'cell':'ASCII 8x16 / CJK 16x16; 2-bit alpha','fonts':['Windows Consolas 13px','Microsoft YaHei 15px']},ensure_ascii=False,indent=2),encoding='utf-8')
# The generated bitmap ROM is sufficient to build; generating fonts is optional.
Image.new('RGB',(1,1))
print('Glyphs:',95+len(chars),'ROM rows:',len(rows))
