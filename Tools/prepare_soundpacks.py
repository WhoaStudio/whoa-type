# Rebuild named PCM packs from the original switch recordings using macOS afconvert.
from pathlib import Path
import argparse
import subprocess,json,wave,struct,math
parser = argparse.ArgumentParser(description='Rebuild packs from an external directory of original OGG recordings.')
parser.add_argument('originals', type=Path)
originals = parser.parse_args().originals
r=Path(__file__).resolve().parents[1]
names=['Amber','Birch','Cedar','Dune','Ember','Flint','Granite','Hazel','Ivory','Jade','Kelp','Linen','Maple','Nimbus','Onyx','Pebble','Quartz','Reed','Slate','Terra','Umber','Velvet','Willow','Zephyr','Acorn','Bamboo','Copper','Drift','Elm','Fern','Grove','Honey','Indigo','Juniper','Larch','Moss','Nutmeg','Opal']
base=r/'whoa-type/Resources/SoundPacks'
for i,name in enumerate(names,1):
 p=base/name; p.mkdir(exist_ok=True)
 wav=p/'sample.wav'
 subprocess.run(['afconvert','-f','WAVE','-d','LEI16@44100','-c','1',str(originals/f'switch{i}.ogg'),str(wav)],check=True,capture_output=True)
 with wave.open(str(wav),'rb') as f:
  n=f.getnframes(); data=list(struct.unpack('<'+'h'*n,f.readframes(n)))
 # Asset preparation: trim digital onset silence, apply 1ms boundary fades.
 first=next((j for j,x in enumerate(data) if abs(x)>32),0)
 last=next((j for j in range(len(data)-1,-1,-1) if abs(data[j])>32),len(data)-1)
 data=data[max(0,first-22):min(len(data),last+45)]
 data=data[:22050]
 for j in range(min(44,len(data)//2)):
  data[j]=round(data[j]*j/44); data[-1-j]=round(data[-1-j]*j/44)
 with wave.open(str(wav),'wb') as f:
  f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100); f.writeframes(struct.pack('<'+'h'*len(data),*data))
 manifest=dict(schemaVersion=1,id=f'switch-{i:02}',displayName=name,gainDB=-12,pitchCents=dict(min=-35,max=35),samples=dict(standard=dict(down=['sample.wav'],up=['sample.wav'])),fallbackGroup='standard',keyGroups={},keys={},preview=[dict(atMs=t,keyCode=k,phase=phase) for t,k,phase in [(0, 0, 'down'), (90, 0, 'up'), (220, 5, 'down'), (310, 5, 'up'), (440, 37, 'down'), (530, 37, 'up'), (660, 49, 'down'), (760, 49, 'up')]])
 (p/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

# The pointer group is shared in character across keyboard switch selections.
# It uses distinct existing press/release recordings, prepared off the event path.
import tempfile
with tempfile.TemporaryDirectory() as temporary:
 prepared = {}
 for phase, original in [('down', 'mouseclick1.ogg'), ('up', 'mouserelease1.ogg')] + [(f'down-{i}', f'click{i}.ogg') for i in range(1, 6)]:
  wav = Path(temporary) / f'pointer-{phase}.wav'
  subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@44100', '-c', '1', str(originals / original), str(wav)], check=True, capture_output=True)
  with wave.open(str(wav), 'rb') as f:
   count = f.getnframes()
   data = list(struct.unpack('<' + 'h' * count, f.readframes(count)))
  first = next((j for j, x in enumerate(data) if abs(x) > 32), 0)
  last = next((j for j in range(len(data) - 1, -1, -1) if abs(data[j]) > 32), len(data) - 1)
  data = data[max(0, first - 22):min(len(data), last + 45)][:22050]
  if phase.startswith('down'):
   peak = max((abs(x) for x in data), default=0)
   if peak:
    data = [round(x * 18000 / peak) for x in data]
  for j in range(min(44, len(data) // 2)):
   data[j] = round(data[j] * j / 44)
   data[-1-j] = round(data[-1-j] * j / 44)
  with wave.open(str(wav), 'wb') as f:
   f.setnchannels(1); f.setsampwidth(2); f.setframerate(44100)
   f.writeframes(struct.pack('<' + 'h' * len(data), *data))
  prepared[phase] = wav.read_bytes()
 for pack_dir in (base/name for name in names):
  manifest_path = pack_dir / 'manifest.json'
  manifest = json.loads(manifest_path.read_text())
  manifest['samples']['pointer'] = {'down': ['pointer-down.wav'] + [f'pointer-down-{i}.wav' for i in range(1, 6)], 'up': ['pointer-up.wav']}
  for phase, content in prepared.items():
   (manifest_path.parent / f'pointer-{phase}.wav').write_bytes(content)
  manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
