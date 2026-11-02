"""Reject any failing clock group, rather than checking only the first summary."""
from pathlib import Path
import re,hashlib,json
r=Path(__file__).resolve().parents[1]
t=(r/'reports/timing.rpt').read_text(encoding='utf-8',errors='replace')
groups=re.findall(r'(\d+) errors detected : (\d+) setup errors.*?(\d+) hold errors',t)
if not groups or any(any(int(n) for n in group) for group in groups):
 raise SystemExit('FAIL: timing errors or missing timing summary; do not download')
setup=[float(x) for x in re.findall(r'Slack \(setup check\)\s+([\d.-]+)',t)]
hold=[float(x) for x in re.findall(r'Slack \(hold check\)\s+([\d.-]+)',t)]
if not setup or not hold or min(setup)<0 or min(hold)<0:raise SystemExit('FAIL: negative/missing slack')
b=r/'bitstream/hd_fixed.bit'
print(json.dumps(dict(result='PASS',clock_groups=len(groups),minimum_setup_slack_ns=min(setup),
 minimum_hold_slack_ns=min(hold),bitstream_sha256=hashlib.sha256(b.read_bytes()).hexdigest()),indent=2))
