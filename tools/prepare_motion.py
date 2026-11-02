"""Convert GIF + optional audio, or a video clip, to a board-ready .LAV file.

Usage: python tools/prepare_motion.py animation.gif media/ANIM0001.LAV --audio music.wav
Requires Pillow/numpy/scipy. Video, MP3 and compressed audio additionally need
ffmpeg on PATH, tools/ffmpeg.exe, or the optional imageio-ffmpeg Python package.
"""
from pathlib import Path
import argparse,math,shutil,subprocess,sys,wave,json
import numpy as np
from PIL import Image,ImageOps
from scipy.signal import resample_poly
from lav_format import pack_clip,inspect_clip,FPS_CHOICES,SDRAM_BYTES

def ffmpeg_path():
    candidates=[Path(__file__).with_name('ffmpeg.exe'),shutil.which('ffmpeg')]
    for p in candidates:
        if p and Path(p).is_file(): return str(p)
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        raise ValueError('This input needs FFmpeg. Install with: python -m pip install imageio-ffmpeg')

def rgb565(rgb):
    a=np.asarray(rgb,dtype=np.uint16)
    return ((a[...,0]>>3)<<11)|((a[...,1]>>2)<<5)|(a[...,2]>>3)

def fit_image(im,w,h,fit):
    im=ImageOps.exif_transpose(im).convert('RGB')
    return ImageOps.fit(im,(w,h),Image.Resampling.LANCZOS) if fit=='cover' else ImageOps.pad(im,(w,h),Image.Resampling.LANCZOS,color='black')

def image_frames(path,count,fps,w,h,fit):
    with Image.open(path) as source:
        # Pillow composites GIF local frames, transparency and disposal before conversion.
        frames=[];ends=[];duration=0
        for n in range(getattr(source,'n_frames',1)):
            source.seek(n);frames.append(fit_image(source.copy(),w,h,fit))
            duration+=max(10,int(source.info.get('duration',100)));ends.append(duration)
    result=[]
    for n in range(count):
        t=(n*1000/fps)%duration
        index=min(int(np.searchsorted(ends,t,side='right')),len(frames)-1)
        result.append(rgb565(frames[index]))
    return np.stack(result)

def video_frames(path,count,fps,w,h,fit):
    if fit=='cover':
        vf=f'fps={fps},scale={w}:{h}:force_original_aspect_ratio=increase,crop={w}:{h},setsar=1'
    else:
        vf=f'fps={fps},scale={w}:{h}:force_original_aspect_ratio=decrease,pad={w}:{h}:(ow-iw)/2:(oh-ih)/2,setsar=1'
    args=[ffmpeg_path(),'-v','error','-stream_loop','-1','-i',str(path),'-an','-vf',vf,
          '-frames:v',str(count),'-f','rawvideo','-pix_fmt','rgb24','pipe:1']
    r=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    if r.returncode: raise ValueError(r.stderr.decode(errors='replace'))
    if len(r.stdout)!=count*w*h*3: raise ValueError('Could not decode the requested video frames')
    return rgb565(np.frombuffer(r.stdout,dtype=np.uint8).reshape(count,h,w,3))

def wav_pcm(path):
    with wave.open(str(path),'rb') as f:
        channels=f.getnchannels();width=f.getsampwidth();rate=f.getframerate();raw=f.readframes(f.getnframes())
    if channels not in (1,2) or width not in (1,2): raise ValueError('Use 8/16-bit mono/stereo PCM WAV, or install FFmpeg')
    a=(np.frombuffer(raw,dtype=np.uint8).astype(np.float64)-128)*256 if width==1 else np.frombuffer(raw,dtype='<i2').astype(np.float64)
    a=a.reshape(-1,channels)
    if channels==1:a=np.repeat(a,2,axis=1)
    divisor=math.gcd(rate,48000)
    if rate!=48000:a=resample_poly(a,48000//divisor,rate//divisor,axis=0)
    return a

def audio_pcm(path,samples,optional=False):
    if path is None:return np.zeros((samples,2),dtype='<i2'),False
    try:
        a=None
        if path.suffix.lower()=='.wav':
            try:a=wav_pcm(path)
            except (ValueError,wave.Error):pass
        if a is None:
            r=subprocess.run([ffmpeg_path(),'-v','error','-i',str(path),'-vn','-map','0:a:0',
                '-t',str(samples/48000),'-ar','48000','-ac','2','-f','s16le','pipe:1'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            if r.returncode or not r.stdout:raise ValueError(r.stderr.decode(errors='replace') or 'No audio stream')
            a=np.frombuffer(r.stdout,dtype='<i2').reshape(-1,2).astype(np.float64)
    except (ValueError,wave.Error):
        if optional:return np.zeros((samples,2),dtype='<i2'),False
        raise
    if len(a)<samples:a=np.pad(a,((0,samples-len(a)),(0,0)))
    a=a[:samples].copy()
    # Short fades make independently looping clips quiet at both ends.
    fade=min(480,len(a)//2)
    if fade:
        a[:fade]*=np.linspace(0,1,fade)[:,None];a[-fade:]*=np.linspace(1,0,fade)[:,None]
    return np.clip(np.rint(a),-32768,32767).astype('<i2'),True

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('source',type=Path);ap.add_argument('output',type=Path)
    ap.add_argument('--compressed',action='store_true',help='LAV2 block compression, needs FAST firmware')
    ap.add_argument('--audio',type=Path);ap.add_argument('--width',type=int,default=320);ap.add_argument('--height',type=int,default=180)
    ap.add_argument('--fps',type=int,choices=FPS_CHOICES,default=15);ap.add_argument('--seconds',type=float,default=4)
    ap.add_argument('--fit',choices=['cover','contain'],default='cover')
    args=ap.parse_args()
    if not args.source.is_file():ap.error('Source file does not exist')
    if args.audio and not args.audio.is_file():ap.error('Audio file does not exist')
    if args.output.exists():ap.error('Refusing to overwrite an existing output file')
    if args.output.suffix.upper()!='.LAV' or len(args.output.stem)>8 or not args.output.stem.isascii() or not args.output.stem.replace('_','').isalnum():
        ap.error('Use an ASCII 8.3 output filename, for example ANIM0001.LAV')
    if not math.isfinite(args.seconds) or args.seconds<=0:ap.error('--seconds must be positive')
    count=max(1,round(args.seconds*args.fps));spf=48000//args.fps
    geometry=(16<=args.width<=1280 and 16<=args.height<=720 and args.width%4==0 and args.height%4==0) if args.compressed else (16<=args.width<=640 and args.width%2==0 and 16<=args.height<=360)
    if not geometry or count>240:ap.error('Invalid dimensions/frame count; LAV2 width/height must be multiples of 4')
    required=count*((args.width*args.height//2 if args.compressed else args.width*args.height*2)+spf*4)
    if required>SDRAM_BYTES:ap.error(f'{required:,} bytes exceeds 8 MiB. Reduce --seconds, dimensions or --fps.')
    is_image=args.source.suffix.lower() in ('.gif','.png','.jpg','.jpeg','.bmp','.webp','.apng')
    try:
        frames=image_frames(args.source,count,args.fps,args.width,args.height,args.fit) if is_image else video_frames(args.source,count,args.fps,args.width,args.height,args.fit)
        audio_source=args.audio if args.audio else (None if is_image else args.source)
        pcm,present=audio_pcm(audio_source,count*spf,optional=not args.audio)
        data=pack_clip(frames,pcm,args.fps,present,compressed=args.compressed);info=inspect_clip(data)
    except (ValueError,OSError) as e:ap.error(str(e))
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_bytes(data)
    info.update(file=str(args.output.resolve()),file_bytes=len(data))
    print(json.dumps(info,ensure_ascii=True,indent=2))

if __name__=='__main__':main()
