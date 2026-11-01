#!/usr/bin/env python3
"""Import filename-based Neptune packs without changing source archives.

Usage: python3 Tools/import_soundpacks.py /path/to/zips
Mechvibes sprite/defines configs are intentionally rejected: these archives use
name/support-events configs and named WAV recordings, with no numeric key map.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import wave
import zipfile

ROOT = Path(__file__).resolve().parents[1] / 'whoa-type/Resources/SoundPacks'
# macOS physical virtual-key codes (not ASCII or Mechvibes scan codes).
KEYS = {'enter': 36, 'space': 49, 'backspace': 51, 'tab': 48}


def prepare(archive, staging):
    with zipfile.ZipFile(archive) as zipped:
        for entry in zipped.infolist():
            path = Path(entry.filename)
            if path.is_absolute() or '..' in path.parts or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('unsafe archive entry')
        zipped.extractall(staging)
    configs = [p for p in staging.rglob('config.json') if '__MACOSX' not in p.parts]
    if len(configs) != 1:
        raise ValueError('expected exactly one config.json')
    source = configs[0].parent
    config = json.loads(configs[0].read_text())
    if (set(config) != {'name', 'support-events'} or
            not isinstance(config['name'], str) or not config['name'].strip() or
            type(config['support-events']) is not bool):
        raise ValueError('unsupported config; expected name/support-events format')
    generated = source / 'prepared'
    generated.mkdir()
    with wave.open(str(generated / 'silence.wav'), 'wb') as audio:
        audio.setparams((1, 2, 44100, 0, 'NONE', 'not compressed'))
        audio.writeframes(b'\0\0' * 44)
    groups = {}
    def group(name, files):
        down, up = [], []
        for file in files:
            down.append('prepared/' + file.name)
            release = file.with_name(file.stem + '-up.wav')
            if config['support-events']:
                if not release.is_file():
                    raise ValueError('missing release: ' + release.name)
                up.append('prepared/' + release.name)
            else:
                up.append('prepared/silence.wav')
        groups[name] = {'down': down, 'up': up}
    fallback = sorted(p for p in source.glob('*.wav') if re.fullmatch(r'fallback\d*', p.stem))
    if not fallback:
        raise ValueError('missing fallback recordings')
    group('standard', fallback)
    mapping = {}
    for name, code in KEYS.items():
        names = ['space', 'spacebar'] if name == 'space' else [name]
        files = [source / (n + '.wav') for n in names if (source / (n + '.wav')).is_file()]
        if files:
            group(name, files)
            mapping[str(code)] = name
    # key_N files lack a documented keycode domain; retain originals without
    # guessing which physical keys they describe.
    paths = {p for g in groups.values() for phase in g.values() for p in phase if p != 'prepared/silence.wav'}
    for path in sorted(paths):
        output = source / path
        subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@44100', '-c', '1',
                        str(source / output.name), str(output)], check=True, capture_output=True)
        with wave.open(str(output), 'rb') as audio:
            if not 0 < audio.getnframes() <= 22050:
                raise ValueError('sample exceeds supported 500 ms: ' + output.name)
    pointer = json.loads((ROOT / 'Amber/manifest.json').read_text())['samples']['pointer']
    groups['pointer'] = pointer
    for path in set(pointer['down'] + pointer['up']):
        shutil.copyfile(ROOT / 'Amber' / path, source / path)
    manifest = dict(schemaVersion=1, id='neptune-' + archive.stem, displayName=config['name'],
                    gainDB=-12, pitchCents=dict(min=0, max=0), samples=groups,
                    fallbackGroup='standard', keyGroups={}, keys=mapping,
                    preview=[dict(atMs=t, keyCode=k, phase=phase)
                             for t, k, phase in [(0, 0, 'down'), (90, 0, 'up'),
                             (220, 49, 'down'), (310, 49, 'up'), (440, 36, 'down'), (530, 36, 'up')]])
    (source / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archives', type=Path)
    args = parser.parse_args()
    archives = sorted(args.archives.glob('*.zip'))
    if not archives:
        parser.error('no ZIP archives found')
    report = []
    for archive in archives:
        destination = ROOT / archive.stem
        try:
            if destination.exists():
                raise ValueError('destination already exists; refusing to overwrite')
            with tempfile.TemporaryDirectory() as temporary:
                source = prepare(archive, Path(temporary))
                shutil.copytree(source, destination)
            message = f'IMPORTED {archive.name} -> {destination.name}'
        except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
            message = f'SKIPPED {archive.name}: {error}'
        print(message)
        report.append(message)
    (ROOT / 'neptune-import.log').write_text('\n'.join(report) + '\n')


if __name__ == '__main__':
    main()
