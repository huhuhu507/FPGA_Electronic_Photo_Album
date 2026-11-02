"""LAV1/LAV2: 512-byte header, raw RGB565 or compressed blocks, stereo PCM.

All integers/pixels/samples are little-endian. Audio is fixed at 48000 Hz,
16 bits/channel; every audio sample contains left then right. The payload
fits the EG4S20's 8 MiB SDRAM. This is an offline prepared format, not GIF/MP4.
"""
import struct
import numpy as np

HEADER_BYTES=512
SDRAM_BYTES=8*1024*1024
FPS_CHOICES=(10,12,15,20,24,30)

def pack_clip(frames,pcm,fps,audio_present=True,compressed=False):
    if fps not in FPS_CHOICES: raise ValueError(f'fps must be one of {FPS_CHOICES}')
    frames=np.asarray(frames,dtype='<u2')
    if frames.ndim!=3: raise ValueError('frames must have shape (count,height,width)')
    count,h,w=frames.shape
    geometry=(16<=w<=1280 and 16<=h<=720 and w%4==0 and h%4==0) if compressed else (16<=w<=640 and w%2==0 and 16<=h<=360)
    if not (geometry and 1<=count<=240):
        raise ValueError('width: even 16..640; height: 16..360; frame count: 1..240')
    spf=48000//fps
    pcm=np.asarray(pcm,dtype='<i2')
    if pcm.shape!=(count*spf,2): raise ValueError('PCM length must exactly match animation duration')
    if compressed:
        from bc1_codec import encode_frame
        video=b''.join(encode_frame(f) for f in frames)
    else:video=frames.tobytes(order='C')
    payload=video+pcm.tobytes(order='C')
    if len(payload)>SDRAM_BYTES:
        max_frames=SDRAM_BYTES//((w*h//2 if compressed else w*h*2)+spf*4)
        raise ValueError(f'Clip needs {len(payload):,} bytes; SDRAM permits {SDRAM_BYTES:,}. '
                         f'At {w}x{h}/{fps} fps use at most {max_frames} frames ({max_frames/fps:.2f} seconds).')
    checksum=int(np.frombuffer(payload,dtype='<u4').sum(dtype=np.uint64))&0xffffffff
    fields=(0x3256414c if compressed else 0x3156414c,HEADER_BYTES,w,h,count,spf,len(pcm),len(video)//4,len(payload)//4,
            48000,fps,int(audio_present)|(2 if compressed else 0),checksum)
    header=struct.pack('<13I',*fields).ljust(HEADER_BYTES,b'\0')
    return header+payload

def inspect_clip(data):
    if len(data)<HEADER_BYTES: raise ValueError('Short LAV header')
    f=struct.unpack_from('<13I',data)
    magic,header,w,h,count,spf,samples,vwords,words,rate,fps,flags,checksum=f
    if magic not in (0x3156414c,0x3256414c) or header!=512: raise ValueError('Not a LAV file')
    compressed=magic==0x3256414c
    geometry=(16<=w<=1280 and 16<=h<=720 and w%4==0 and h%4==0) if compressed else (16<=w<=640 and w%2==0 and 16<=h<=360)
    if not (geometry and 1<=count<=240 and fps in FPS_CHOICES):
        raise ValueError('Unsupported geometry/frame rate')
    if rate!=48000 or spf!=48000//fps or samples!=count*spf: raise ValueError('Invalid audio timing')
    if vwords!=(w*h*count//8 if compressed else w*h*count//2) or words!=vwords+samples or words*4>SDRAM_BYTES or flags not in ((2,3) if compressed else (0,1)):
        raise ValueError('Invalid memory layout')
    if len(data)!=HEADER_BYTES+words*4: raise ValueError('File length does not match header')
    actual=int(np.frombuffer(data,dtype='<u4',offset=HEADER_BYTES).sum(dtype=np.uint64))&0xffffffff
    if actual!=checksum: raise ValueError('Payload checksum mismatch')
    return dict(width=w,height=h,frames=count,fps=fps,seconds=count/fps,
                samples=samples,video_words=vwords,payload_words=words,audio_present=bool(flags&1),checksum=checksum,compressed=compressed,format='LAV2' if compressed else 'LAV1')
