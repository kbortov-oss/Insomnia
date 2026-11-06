#!/usr/bin/env python3
"""Read-only lid/display recorder. No screenshots, network, or power changes."""
import argparse
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', default='display-test.jsonl')
parser.add_argument('--duration', type=int, default=1800, help='Maximum seconds, 1..3600')
args=parser.parse_args()
if not 1 <= args.duration <= 3600: parser.error('--duration must be 1..3600')
import ctypes, datetime, json, pathlib, re, subprocess, time
cg=ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
u=ctypes.c_uint32
cg.CGGetOnlineDisplayList.argtypes=[u,ctypes.POINTER(u),ctypes.POINTER(u)]
for name in ['CGDisplayIsAsleep','CGDisplayIsBuiltin','CGDisplayIsOnline','CGDisplayIsActive']:
 f=getattr(cg,name); f.argtypes=[u];f.restype=u
out=pathlib.Path(args.output).expanduser().resolve()
out.parent.mkdir(parents=True, exist_ok=True)
if out.exists(): raise SystemExit('Output already exists; choose another --output filename.')
print('Recording:', out, flush=True)
print('Close the lid only after the active Insomnia mode is enabled. Ctrl+C stops recording.', flush=True)
known=set(); closed_seen=False; opened_at=None
started=time.monotonic()
with out.open('x',buffering=1) as log:
 while time.monotonic()-started<args.duration:
  now=time.monotonic()
  row={'time':datetime.datetime.now(datetime.timezone.utc).isoformat(),'elapsed':round(now-started,2)}
  try:
   root=subprocess.check_output(['/usr/sbin/ioreg','-r','-c','IOPMrootDomain','-d','1','-l','-w','0'],text=True,timeout=3)
   for key in ['AppleClamshellState','SleepDisabled']:
    m=re.search(r'"'+key+r'"\s*=\s*(Yes|No)',root)
    row[key]=m.group(1)=='Yes' if m else None
   fb=subprocess.check_output(['/usr/sbin/ioreg','-r','-c','IOMobileFramebuffer','-d','1','-l','-w','0'],text=True,timeout=3)
   row['framebuffers']=[x.strip() for x in fb.splitlines() if ('<class AppleCLCD2' in x or re.search(r'"(?:IOPowerManagement|IOMFBBrightnessLevel)"\s*=',x))]
   ids=(u*16)();count=u()
   error=cg.CGGetOnlineDisplayList(16,ids,ctypes.byref(count))
   known.update(ids[:count.value])
   row['display_query_error']=error
   if error != 0: row['error']='CoreGraphics unavailable (code %s); run in the normal logged-in Mac session' % error
   elif count.value == 0: row['error']='No online displays reported; display sleep cannot be concluded from this sample'
   row['displays']=[{'id':n,'builtin':bool(cg.CGDisplayIsBuiltin(n)),'online':bool(cg.CGDisplayIsOnline(n)),'active':bool(cg.CGDisplayIsActive(n)),'asleep':bool(cg.CGDisplayIsAsleep(n))} for n in sorted(known)]
   if row['AppleClamshellState'] is True: closed_seen=True;opened_at=None
   elif row['AppleClamshellState'] is False and closed_seen and opened_at is None:opened_at=now
  except Exception as e:row['error']=str(e)
  log.write(json.dumps(row)+'\n')
  if opened_at is not None and now-opened_at>=5:break
  time.sleep(max(0,1-(time.monotonic()-now)))

print('Recording finished:', out, flush=True)
previous=None
rows=[json.loads(line) for line in out.read_text().splitlines()]
for row in rows:
    state=(row.get('AppleClamshellState'),row.get('SleepDisabled'),str(row.get('displays')),row.get('error'))
    if state != previous:
        print(json.dumps({key:row.get(key) for key in ['time','elapsed','AppleClamshellState','SleepDisabled','displays','error']}),flush=True)
        print('Brightness:',[line for line in row.get('framebuffers',[]) if 'IOMFBBrightnessLevel"' in line],flush=True)
        previous=state
print('Maximum sampling gap:', max((b['elapsed']-a['elapsed'] for a,b in zip(rows,rows[1:])), default=0),flush=True)
