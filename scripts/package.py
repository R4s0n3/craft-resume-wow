#!/usr/bin/env python3
"""Build a deterministic ZIP containing exactly one installable addon folder."""
from pathlib import Path
import re
import zipfile

root = Path(__file__).resolve().parents[1]
addon = root / "CraftResume"
manifest = (addon / "CraftResume.toc").read_text()
version = re.search(r"^## Version: (.+)$", manifest, re.MULTILINE).group(1)
files = ["CraftResume.toc"] + [line.strip() for line in manifest.splitlines()
    if line.strip() and not line.startswith("#")]
for name in files:
    if not (addon / name).is_file():
        raise SystemExit(f"Missing addon file: {name}")
destination = root / "dist" / f"CraftResume-{version}.zip"
destination.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name in files:
        info = zipfile.ZipInfo(f"CraftResume/{name}", date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o100644 << 16
        archive.writestr(info, (addon / name).read_bytes())
print(destination)
