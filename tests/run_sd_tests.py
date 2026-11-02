from pathlib import Path
import subprocess
r=Path(__file__).resolve().parents[1]
b=Path('C:/AMDDesignTools/2025.2/Vivado/bin')
def tool(name,args,log):
 p=subprocess.run([str(b/(name+'.bat')),*args],cwd=r,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (r/'tests'/log).write_bytes(p.stdout)
 if p.returncode:raise RuntimeError(log)
 return p.stdout.decode(errors='replace')
tool('xvlog',['sd_ctrl.v','tests/tb_sd_crc.v'],'sd_compile.log')
for name,top,args in [('sd_crc','tb_sd_crc',[]),('sd_clean25','tb_sd_crc',['-testplusarg','CLEAN']),('sd_clean12','tb_sd_crc_slow',['-testplusarg','CLEAN'])]:
 snapshot=top+'_sim'
 tool('xelab',[top,'-s',snapshot],name+'_elab.log')
 s=tool('xsim',[snapshot,'-runall',*args],name+'_run.log')
 if 'PASS' not in s or 'Fatal:' in s:raise RuntimeError(name)
 print(next(line for line in s.splitlines() if 'PASS' in line),flush=True)
