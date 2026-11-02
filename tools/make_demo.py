"""Create reproducible moving graphics and a stereo melody; no downloaded assets."""
from pathlib import Path
import math,wave,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from lav_format import pack_clip,inspect_clip
from prepare_motion import rgb565

def make_demo(folder,w,h,fps,name):
    folder=Path(folder);folder.mkdir(parents=True,exist_ok=True)
    seconds=4;count=seconds*fps;images=[];packed=[]
    try: font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',max(9,w//18))
    except OSError:font=ImageFont.load_default()
    yy,xx=np.mgrid[0:h,0:w]
    background=np.stack((10+xx*12//w,24+yy*18//h,37+xx*15//w),axis=-1).astype(np.uint8)
    for n in range(count):
        t=n/fps;im=Image.fromarray(background.copy());d=ImageDraw.Draw(im)
        # A moving orbit and beat squares make frame changes easy to see on hardware.
        cx=int(w*(0.5+0.32*math.sin(2*math.pi*t/seconds)))
        cy=int(h*(0.53+0.20*math.sin(4*math.pi*t/seconds)));radius=max(5,w//18)
        d.line([(int(w*.18),int(h*.75)),(int(w*.82),int(h*.75))],fill=(48,79,92),width=1)
        d.ellipse((cx-radius,cy-radius,cx+radius,cy+radius),fill=(76,219,191))
        for j in range(8):
            active=int(t*2)%8==j;x0=int(w*(0.12+j*.10));y0=int(h*.83);side=max(3,w//40)
            d.rectangle((x0,y0,x0+side,y0+side),fill=(246,187,81) if active else (43,65,80))
        d.text((w*.05,h*.06),'LUMA / MOTION',font=font,fill=(221,235,240))
        d.text((w*.05,h*.20),f'{fps:02d} FPS  FRAME {n:03d}',font=font,fill=(120,162,180))
        images.append(im);packed.append(rgb565(im))
    samples=np.arange(seconds*48000);time=samples/48000
    beat=np.floor(time*2).astype(int);phase=time%0.5
    freq=np.asarray([523.251,659.255,783.991,659.255,587.330,698.456,880.,698.456])[beat%8]
    # Separate channels help digital verification and a future physical listening test.
    env=np.minimum(phase/.015,1)*np.minimum((.5-phase)/.04,1)*np.exp(-phase*3)
    left=7000*np.sin(2*np.pi*freq*phase)*env
    right=6500*np.sin(2*np.pi*freq*1.5*phase)*env
    pcm=np.stack((left,right),axis=1).round().astype('<i2')
    payload=pack_clip(np.stack(packed),pcm,fps,True)
    path=folder/(name+'.LAV');path.write_bytes(payload)
    # GIF and WAV are examples for the PC-side conversion utility, not board formats.
    images[0].save(folder/(name+'.gif'),save_all=True,append_images=images[1:],duration=[round((i+1)*100/fps)*10-round(i*100/fps)*10 for i in range(count)],loop=0)
    with wave.open(str(folder/(name+'.wav')),'wb') as out:
        out.setparams((2,2,48000,len(pcm),'NONE','not compressed'));out.writeframes(pcm.tobytes())
    info=inspect_clip(payload);info['file']=path.name
    return info

if __name__=='__main__':
    folder=Path(__file__).resolve().parents[1]/'media'
    infos=[make_demo(folder,320,180,15,'DEMO001'),make_demo(folder,160,90,30,'DEMO030')]
    (folder/'manifest.json').write_text(json.dumps(infos,indent=2),encoding='utf-8')
    print(json.dumps(infos,indent=2))
