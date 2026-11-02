from pathlib import Path
from PIL import Image
import numpy as np
v=np.loadtxt('tests/osd_frame.hex',dtype=str)
a=np.array([int(x,16) for x in v],dtype=np.uint16).reshape(720,1280)
im=np.stack([((a>>11)&31)*255//31,((a>>5)&63)*255//63,(a&31)*255//31],axis=-1).astype('uint8')
Image.fromarray(im).save('reports/LUMA_RTL_preview.png')
