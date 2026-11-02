"""New-feature regression. Keep baseline regression separate and reproducible."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
bin_dir=Path(sys.argv[1]) if len(sys.argv)>1 else Path('C:/AMDDesignTools/2025.2/Vivado/bin')
def tool(name,args,log):
 r=subprocess.run([str(bin_dir/(name+'.bat')),*args],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (root/log).write_bytes(r.stdout)
 if r.returncode:raise RuntimeError(f'{name} failed; see {log}')
 return r.stdout.decode('utf-8',errors='replace')
subprocess.run([sys.executable,str(root/'tests/generate_motion_fixtures.py')],cwd=root,check=True)
rtl=['bmp_sdram_loader.v','video_reader.v','bc1_row_decode.v','sdram_ctrl_clean.v','async_audio_fifo.v','motion_player.v','sdram_read_arbiter.v','sd_ctrl.v','album_ui.v','clip_done_sync.v']
tbs=['motion_loader','motion_player','motion_system','spi_speed','album_auto']
tool('xvlog',rtl+['tests/tb_'+x+'.v' for x in tbs],'tests/motion_compile.log')
for name,top,extra in [('motion_loader','motion_loader',[]),('motion_loader_mbr','motion_loader',['-testplusarg','MBR']),('motion_player','motion_player',[]),('spi_speed','spi_speed',[]),('album_auto','album_auto',[]),('motion_system','motion_system',[])]:
 snapshot='tb_'+top+'_sim'
 tool('xelab',['tb_'+top,'-s',snapshot],'tests/'+name+'_elab.log')
 output=tool('xsim',[snapshot,'-runall',*extra],'tests/'+name+'_run.log')
 if 'PASS' not in output or 'Fatal:' in output or 'Error:' in output:raise RuntimeError(f'{name} failed; see tests/{name}_run.log')
 print(next(line for line in output.splitlines() if 'PASS' in line),flush=True)
print('PASS MOTION REGRESSION: all 6 runs passed',flush=True)
