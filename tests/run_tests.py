"""Run the project's RTL regression with the installed AMD XSim tools."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
bin_dir=Path(sys.argv[1]) if len(sys.argv)>1 else Path('C:/AMDDesignTools/2025.2/Vivado/bin')
def tool(name,args,log):
 r=subprocess.run([str(bin_dir/(name+'.bat')),*args],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 (root/log).write_bytes(r.stdout)
 if r.returncode:raise RuntimeError(f'{name} failed; see {log}')
 return r.stdout.decode('utf-8',errors='replace')
for generator in ['generate_fixtures.py','generate_osd_golden.py']:
 subprocess.run([sys.executable,str(root/'tests'/generator)],cwd=root,check=True)
rtl=['tmds.v','tmds_encoder.v','sdram_ctrl_clean.v','bmp_sdram_loader.v','video_reader.v','bc1_row_decode.v','signage_osd.v','number_bcd.v','audio_scope.v','audio_synth.v','hdmi_tx.v','tmds_serializer.v']
tbs=['tmds','sdram','loader','video','osd','hdmi','audio','serializer']
tool('xvlog',rtl+['tests/tb_'+x+'.v' for x in tbs],'tests/compile.log')
cases=[('tmds','tmds',[]),('sdram','sdram',[]),('loader','loader',[]),('loader_mbr','loader',['-testplusarg','MBR']),('video','video',[]),('osd','osd',[]),('hdmi','hdmi',[]),('audio','audio',[]),('bcd','bcd',[]),('serializer','serializer',[]),('serializer_phase','serializer',['-testplusarg','PHASE_SHIFT'])]
for name,top,plus in cases:
 snapshot='tb_'+top+'_sim'
 tool('xelab',['tb_'+top,'-s',snapshot],'tests/'+name+'_elab.log')
 output=tool('xsim',[snapshot,'-runall',*plus],'tests/'+name+'_run.log')
 if 'PASS' not in output or 'Fatal:' in output or 'Error:' in output:raise RuntimeError(f'{name} failed; see tests/{name}_run.log')
 print(next(line for line in output.splitlines() if 'PASS' in line),flush=True)
print('PASS REGRESSION: all 11 runs passed',flush=True)
