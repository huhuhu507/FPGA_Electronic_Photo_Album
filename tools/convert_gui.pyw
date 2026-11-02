"""Small local file picker for the LAV1/LAV2 converter; no board access."""
from pathlib import Path
import tkinter as tk
from tkinter import ttk,filedialog,messagebox
import subprocess,sys,threading

app=tk.Tk();app.title('智能电子相册 · 动画与音频素材制作');app.geometry('650x430');app.resizable(False,False)
panel=ttk.Frame(app,padding=22);panel.pack(fill='both',expand=True)
source=tk.StringVar();audio=tk.StringVar();output=tk.StringVar();seconds=tk.StringVar(value='3')
profile=tk.StringVar(value='640×480 / 15 帧（高清）');status=tk.StringVar(value='选择 GIF 或短视频，可另选一段音乐／语音。')
def choose_source():
 p=filedialog.askopenfilename(title='选择 GIF 或视频',filetypes=[('图片与视频','*.gif *.mp4 *.mov *.avi *.mkv *.webm *.png *.jpg *.bmp'),('全部文件','*.*')])
 if p:source.set(p);output.set(str(Path(p).with_name('ANIM0001.LAV')))
def choose_audio():
 p=filedialog.askopenfilename(title='可选：配套声音',filetypes=[('声音文件','*.wav *.mp3 *.m4a *.aac *.flac *.ogg'),('全部文件','*.*')])
 if p:audio.set(p)
def choose_output():
 p=filedialog.asksaveasfilename(title='保存 LAV 素材（ASCII 文件名最多8字）',initialfile='ANIM0001.LAV',defaultextension='.LAV',filetypes=[('相册动画','*.LAV')])
 if p:output.set(p)
for row,(label,var,callback) in enumerate([('动画 / 视频',source,choose_source),('配套声音（可选）',audio,choose_audio),('保存位置',output,choose_output)]):
 ttk.Label(panel,text=label).grid(row=row*2,column=0,columnspan=2,sticky='w',pady=(4,2))
 ttk.Entry(panel,textvariable=var,width=67).grid(row=row*2+1,column=0,sticky='ew');ttk.Button(panel,text='选择',command=callback).grid(row=row*2+1,column=1,padx=(8,0))
settings=ttk.Frame(panel);settings.grid(row=6,column=0,columnspan=2,sticky='w',pady=18)
ttk.Label(settings,text='规格').pack(side='left');ttk.Combobox(settings,textvariable=profile,values=['640×480 / 15 帧（高清）','640×360 / 15 帧（宽屏）','480×360 / 15 帧（较快）','320×180 / 15 帧（旧格式）'],state='readonly',width=27).pack(side='left',padx=8)
ttk.Label(settings,text='时长（秒）').pack(side='left',padx=(10,4));ttk.Entry(settings,textvariable=seconds,width=7).pack(side='left')
ttk.Label(panel,text='默认3秒。新版640×480最多3.33秒；640×360最多4.33秒；480×360最多5.60秒。\nLAV 文件放 FAT32 卡根目录；原始 GIF、MP4 和音乐文件留在电脑上。',wraplength=600).grid(row=7,column=0,columnspan=2,sticky='w')
ttk.Label(panel,textvariable=status,wraplength=600).grid(row=9,column=0,columnspan=2,sticky='w',pady=(15,0))
def finish(ok,text):
 button.state(['!disabled']);status.set('完成，可复制 LAV 文件到 SD 卡。' if ok else '未完成，请检查输入或时长。')
 if ok:messagebox.showinfo('制作完成',output.get()+'\n\n复制这个 LAV 文件到 SD 卡根目录，重新上电即可。')
 else:messagebox.showerror('制作失败',text[-3000:])
def convert():
 if not source.get() or not output.get():messagebox.showinfo('需要文件','请先选择动画和保存位置。');return
 profiles={'640×480 / 15 帧（高清）':(640,480,15,True),'640×360 / 15 帧（宽屏）':(640,360,15,True),'480×360 / 15 帧（较快）':(480,360,15,True),'320×180 / 15 帧（旧格式）':(320,180,15,False)}
 w,h,fps,compressed=profiles[profile.get()]
 python=Path(sys.executable)
 if python.name.lower()=='pythonw.exe':python=python.with_name('python.exe')
 args=[str(python),str(Path(__file__).with_name('prepare_motion.py')),source.get(),output.get(),'--width',str(w),'--height',str(h),'--fps',str(fps),'--seconds',seconds.get()]
 if compressed:args.append('--compressed')
 if audio.get():args.extend(['--audio',audio.get()])
 button.state(['disabled']);status.set('正在制作，请稍候……')
 def worker():
  try:
   result=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
   text=result.stdout.decode('utf-8',errors='replace');app.after(0,finish,result.returncode==0,text)
  except Exception as error:app.after(0,finish,False,str(error))
 threading.Thread(target=worker,daemon=True).start()
button=ttk.Button(panel,text='制作动画素材',command=convert);button.grid(row=8,column=0,columnspan=2,sticky='w',pady=(17,0))
app.mainloop()
