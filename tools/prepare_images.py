"""python prepare_images.py SOURCE OUTPUT --fit contain|cover"""
from pathlib import Path
import argparse
from PIL import Image, ImageOps
p=argparse.ArgumentParser(description='Make 1280x720 uncompressed 24-bit BMPs for the FPGA.')
p.add_argument('source',type=Path);p.add_argument('output',type=Path);p.add_argument('--fit',choices=['contain','cover'],default='cover');a=p.parse_args()
files=sorted(x for x in a.source.iterdir() if x.suffix.lower() in {'.jpg','.jpeg','.png','.bmp','.webp'})[:8]
a.output.mkdir(parents=True,exist_ok=True)
for i,f in enumerate(files,1):
 im=ImageOps.exif_transpose(Image.open(f)).convert('RGB')
 if a.fit=='cover':im=ImageOps.fit(im,(1280,720),Image.Resampling.LANCZOS)
 else:
  im=ImageOps.contain(im,(1280,720),Image.Resampling.LANCZOS)
  canvas=Image.new('RGB',(1280,720),(8,16,24));canvas.paste(im,((1280-im.width)//2,(720-im.height)//2));im=canvas
 dest=a.output/f'SHOW{i:04d}.BMP'
 if dest.exists():raise FileExistsError(f'Refusing to overwrite {dest}')
 im.save(dest,'BMP');print(f'{f.name} -> {dest.name}')
if not files:raise SystemExit('No supported source images found')
