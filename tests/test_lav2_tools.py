from pathlib import Path
import sys,struct
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from bc1_codec import encode_frame,decode_frame
from lav_format import pack_clip,inspect_clip,SDRAM_BYTES
# Every possible RGB565 flat colour, including black and white and endpoint ties.
colours=np.arange(65536,dtype=np.uint16).reshape(256,256)
image=np.repeat(np.repeat(colours,4,axis=0),4,axis=1)
encoded=encode_frame(image)
assert len(encoded)==image.size//2
assert np.array_equal(image,decode_frame(encoded,1024,1024))
frames=np.stack([image[:16,:32],image[16:32,:32]])
pcm=np.arange(6400*2,dtype=np.int16).reshape(6400,2)
for compressed in (False,True):
 data=pack_clip(frames,pcm,15,True,compressed)
 info=inspect_clip(data)
 assert info['compressed']==compressed and info['audio_present']
 assert data[-len(pcm.tobytes()):]==pcm.tobytes()
 bad=bytearray(data);bad[-1]^=1
 try:inspect_clip(bad)
 except ValueError:pass
 else:raise AssertionError('Bad payload accepted')
 for offset,value in [(44,1 if compressed else 3),(8,31),(32,2097153)]:
  bad=bytearray(data);struct.pack_into('<I',bad,offset,value)
  try:inspect_clip(bad)
  except ValueError:pass
  else:raise AssertionError('Bad metadata accepted')
print('PASS LAV2 TOOLS: all 65536 flat RGB565 colours lossless, exact 4:1 video ratio, LAV1/LAV2 roundtrip metadata, untouched PCM, checksum/flags/alignment/memory rejection')
