#!/usr/bin/env python3
"""Generate a cask from an actual DMG; regenerate after signing/stapling."""
import argparse
import hashlib
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('artifact', type=Path)
parser.add_argument('--version', required=True)
parser.add_argument('--repository', default='WhoaStudio/Whoa-Typer')
parser.add_argument('--url', help='Override download URL for local validation')
parser.add_argument('--output', type=Path, default=Path('Casks/whoa-type.rb'))
args = parser.parse_args()
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', args.version):
    parser.error('Invalid version')
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
    parser.error('Invalid repository')
checksum = hashlib.sha256(args.artifact.read_bytes()).hexdigest()
url = args.url if args.url else f'https://github.com/{args.repository}/releases/download/v#{{version}}/WhoaType-#{{version}}-macOS.dmg'
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(f'''cask "whoa-type" do
  version "{args.version}"
  sha256 "{checksum}"

  url "{url}"
  name "Whoa Type"
  desc "Menu bar keyboard and mouse sound utility"
  homepage "https://github.com/{args.repository}"

  depends_on macos: :tahoe

  app "Whoa Type.app"

  zap trash: "~/Library/Containers/ugolin-olle.whoa-type"
end
''')
