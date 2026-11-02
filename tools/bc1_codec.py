"""Opaque 4-colour 4x4 blocks; native 565 channel interpolation matches RTL.

This is lossy image compression. One RGB565 frame becomes one quarter its
original size. Text and the independent OSD remain uncompressed.
"""
import numpy as np

def unpack565(a):
 a=np.asarray(a,dtype=np.uint16)
 return np.stack(((a>>11)&31,(a>>5)&63,a&31),axis=-1).astype(np.int32)

def pack565(a):
 a=np.clip(np.rint(a),0,(31,63,31)).astype(np.uint16)
 return (a[...,0]<<11)|(a[...,1]<<5)|a[...,2]

def palette565(c0,c1):
 a,b=unpack565(c0),unpack565(c1)
 return np.stack((a,b,(2*a+b)//3,(a+2*b)//3),axis=-2)

def encode_frame(frame):
 frame=np.asarray(frame,dtype='<u2');h,w=frame.shape
 if w%4 or h%4:raise ValueError('BC1 dimensions must be multiples of four')
 # [block row, block col, 16 pixels, RGB565 channel].
 blocks=frame.reshape(h//4,4,w//4,4).transpose(0,2,1,3).reshape(-1,16)
 rgb=unpack565(blocks);mean=rgb.mean(axis=1,keepdims=True)
 centered=rgb-mean
 # PCA gives an endpoint axis; iterate least squares after palette assignment.
 cov=np.einsum('npi,npj->nij',centered,centered)
 _,vectors=np.linalg.eigh(cov)
 axis=vectors[:,:,-1];projection=np.einsum('npi,ni->np',centered,axis)
 a=rgb[np.arange(len(rgb)),projection.argmax(1)].astype(float)
 b=rgb[np.arange(len(rgb)),projection.argmin(1)].astype(float)
 weights=np.array([1.,0.,2/3,1/3])
 best_error=np.full(len(rgb),np.inf);best0=np.zeros(len(rgb),dtype='<u2');best1=best0.copy();bests=np.zeros((len(rgb),16),dtype=np.uint32)
 for iteration in range(4):
  qa,qb=pack565(a),pack565(b);c0=np.maximum(qa,qb);c1=np.minimum(qa,qb)
  equal=c0==c1
  c0=np.where(equal & (c0<65535),c0+1,c0).astype(np.uint16)
  c1=np.where(equal & (c0==65535),np.minimum(c1,65534),c1).astype(np.uint16)
  palette=palette565(c0,c1)
  # Weight channels by 8-bit magnitude and perceptual luminance.
  distances=(((rgb[:,:,None,:]-palette[:,None,:,:])*np.array([2.,1.,2.]))**2).sum(-1)
  selectors=distances.argmin(-1)
  error=np.take_along_axis(distances,selectors[...,None],axis=-1).sum(axis=(1,2))
  better=error<best_error;best_error[better]=error[better];best0[better]=c0[better];best1[better]=c1[better];bests[better]=selectors[better]
  u=weights[selectors];v=1-u
  aa=(u*u).sum(1);bb=(v*v).sum(1);ab=(u*v).sum(1);det=aa*bb-ab*ab
  ar=np.einsum('np,npc->nc',u,rgb);br=np.einsum('np,npc->nc',v,rgb)
  safe=np.where(det>1e-5,det,1)[:,None]
  fit_a=(ar*bb[:,None]-br*ab[:,None])/safe;fit_b=(br*aa[:,None]-ar*ab[:,None])/safe
  a=np.where((det>1e-5)[:,None],fit_a,unpack565(c0));b=np.where((det>1e-5)[:,None],fit_b,unpack565(c1))
 idx=np.zeros(len(rgb),dtype='<u4')
 for j in range(16):idx|=bests[:,j] << (2*j)
 result=np.empty((len(rgb),2),dtype='<u4');result[:,0]=best0.astype(np.uint32)|(best1.astype(np.uint32)<<16);result[:,1]=idx
 return result.tobytes()

def decode_frame(data,w,h):
 words=np.frombuffer(data,dtype='<u4').reshape(-1,2)
 if len(words)!=w*h//16:raise ValueError('Wrong block data length')
 palette=palette565((words[:,0]&65535).astype(np.uint16),(words[:,0]>>16).astype(np.uint16))
 selectors=(words[:,1,None] >> (np.arange(16,dtype=np.uint32)*2))&3
 decoded=palette[np.arange(len(words))[:,None],selectors]
 pixels=pack565(decoded)
 return pixels.reshape(h//4,w//4,4,4).transpose(0,2,1,3).reshape(h,w)
