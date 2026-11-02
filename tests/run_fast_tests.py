from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
bin_dir=Path('C:/AMDDesignTools/2025.2/Vivado/bin')
def tool(name,args,log):
 r=subprocess.run([str(bin_dir/(name+'.bat')),*args],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (root/'tests'/log).write_bytes(r.stdout)
 if r.returncode:raise RuntimeError(f'{name} failed: {log}')
 return r.stdout.decode('utf-8',errors='replace')
subprocess.run([sys.executable,str(root/'tests/generate_fast_fixtures.py')],cwd=root,check=True)
tool('xvlog',['bc1_row_decode.v','video_reader.v','bmp_sdram_loader.v','sd_ctrl.v','motion_player.v','async_audio_fifo.v','sdram_ctrl_clean.v','sdram_read_arbiter.v','tests/tb_sd_crc.v','tests/tb_bc1_system.v','tests/tb_fast_loader.v'],'fast_compile.log')
for name,top,extra in [('sd_crc','sd_crc',[]),('sd_clean25','sd_crc',['-testplusarg','CLEAN']),('sd_clean12','sd_crc_slow',['-testplusarg','CLEAN']),('fast_loader','fast_loader',[]),('fast_loader_mbr','fast_loader',['-testplusarg','MBR']),('bc1_system','bc1_system',[]),('bc1_system_fit','bc1_system',['-testplusarg','FIT'])]:
 snapshot='tb_'+top+'_sim'
 tool('xelab',['tb_'+top,'-s',snapshot],name+'_elab.log')
 output=tool('xsim',[snapshot,'-runall',*extra],name+'_run.log')
 if 'PASS' not in output or 'Fatal:' in output or 'Error:' in output:raise RuntimeError(f'{name} failed: tests/{name}_run.log')
 print(next(line for line in output.splitlines() if 'PASS' in line),flush=True)
print('PASS FAST REGRESSION: 7 runs',flush=True)
