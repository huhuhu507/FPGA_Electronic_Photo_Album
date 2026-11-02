from pathlib import Path
import sys,struct,tempfile,subprocess,wave,json
import numpy as np
from PIL import Image
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'tools'))
from lav_format import pack_clip,inspect_clip,SDRAM_BYTES
from prepare_motion import rgb565,image_frames,audio_pcm

assert rgb565(np.array([[[255,0,0],[0,255,0],[0,0,255],[255,255,255]]],dtype=np.uint8)).tolist()==[[0xf800,0x07e0,0x001f,0xffff]]
frames=np.zeros((3,16,32),dtype='<u2');frames[0]=0xf800;frames[1]=0x07e0;frames[2]=0x001f
pcm=np.arange(9600,dtype='<i2').reshape(4800,2)
raw=pack_clip(frames,pcm,30)
assert inspect_clip(raw)['samples']==4800
assert raw[512:516]==b'\x00\xf8\x00\xf8'
assert raw[512+frames.nbytes:512+frames.nbytes+4]==pcm[0].tobytes()
for field,value in [(0,0),(1,256),(2,641),(4,0),(5,1599),(8,2097153),(9,44100),(10,29),(11,2),(12,0)]:
    bad=bytearray(raw);struct.pack_into('<I',bad,field*4,value)
    try:inspect_clip(bad)
    except ValueError:pass
    else:raise AssertionError(('accepted invalid field',field))
for bad in [raw[:-1],raw+b'\0',raw[:100],raw[:-1]+bytes([raw[-1]^1])]:
    try:inspect_clip(bad)
    except ValueError:pass
    else:raise AssertionError('accepted damaged/truncated file')
try:pack_clip(np.zeros((120,180,320),dtype=np.uint16),np.zeros((192000,2),dtype=np.int16),30)
except ValueError:pass
else:raise AssertionError('accepted oversized clip')
with tempfile.TemporaryDirectory() as td:
    td=Path(td);gif=td/'source.gif';wav=td/'source.wav';out=td/'TEST0001.LAV'
    images=[Image.new('RGB',(32,16),c) for c in ['red','green','blue']]
    images[0].save(gif,save_all=True,append_images=images[1:],duration=[100,200,100],loop=0)
    selected=image_frames(gif,12,30,32,16,'cover')
    assert selected[0,0,0]==0xf800 and selected[3,0,0]==0x0400 and selected[9,0,0]==0x001f
    with wave.open(str(wav),'wb') as f:
        f.setparams((1,2,44100,4410,'NONE','not compressed'))
        f.writeframes((np.sin(np.arange(4410)*2*np.pi*440/44100)*10000).astype('<i2').tobytes())
    converted,present=audio_pcm(wav,4800);assert present and converted.shape==(4800,2)
    assert np.array_equal(converted[:,0],converted[:,1]) and 8000<abs(converted.astype(np.int32)).max()<11000
    assert np.all(converted[0]==0) and np.all(converted[-1]==0)
    cmd=[sys.executable,str(root/'tools/prepare_motion.py'),str(gif),str(out),'--audio',str(wav),'--width','32','--height','16','--fps','30','--seconds','.1']
    subprocess.run(cmd,check=True,stdout=subprocess.PIPE);info=inspect_clip(out.read_bytes());assert info['frames']==3 and info['audio_present']
    original=out.read_bytes();result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    assert result.returncode and out.read_bytes()==original
    # FFmpeg path: user video + audio is converted into the same strict LAV1 payload.
    ffmpeg=root/'tools/ffmpeg.exe'
    if ffmpeg.exists():
        video=td/'source.mp4'
        subprocess.run([str(ffmpeg),'-v','error','-f','lavfi','-i','testsrc=size=64x36:rate=30','-f','lavfi','-i','sine=frequency=440:sample_rate=44100',
            '-t','0.2','-c:v','libx264','-pix_fmt','yuv420p','-c:a','aac',str(video)],check=True)
        out2=td/'TEST0002.LAV'
        subprocess.run([sys.executable,str(root/'tools/prepare_motion.py'),str(video),str(out2),'--width','64','--height','36','--fps','30','--seconds','.2'],check=True,stdout=subprocess.PIPE)
        vi=inspect_clip(out2.read_bytes());assert vi['frames']==6 and vi['audio_present']
print('PASS MEDIA TOOLS: RGB565 byte order, 13 header invariants, checksum/truncation/capacity rejection, GIF timing, 44.1k mono resample, no-overwrite CLI, video+audio conversion')
