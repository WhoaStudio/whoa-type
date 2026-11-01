#!/usr/bin/env python3
"""Validate a release version and optionally update Xcode build settings."""
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("version")
parser.add_argument("--bump", action="store_true")
args = parser.parse_args()
if not re.fullmatch(r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){0,2}", args.version):
    parser.error("version must contain one to three numeric components, e.g. 1, 1.2 or 1.2.3 (without v)")
if args.bump:
    project = Path(__file__).resolve().parents[1] / "whoa-type.xcodeproj/project.pbxproj"
    text = project.read_text()
    for setting in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        text, count = re.subn(rf"{setting} = [^;]+;", f"{setting} = {args.version};", text)
        if count != 2:
            raise SystemExit(f"Expected two {setting} settings; found {count}")
    project.write_text(text)
