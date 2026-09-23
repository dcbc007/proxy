from pathlib import Path
import re, sys

p = Path(__file__).resolve().parents[1] / 'pubspec.yaml'
text = p.read_text(encoding='utf-8')
m = re.search(r'version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', text)
if not m:
    raise SystemExit('version not found')
major, minor, patch, build = map(int, m.groups())
kind = (sys.argv[1] if len(sys.argv)>1 else 'patch').lower()
if kind == 'major':
    major, minor, patch = major+1, 0, 0
elif kind == 'minor':
    minor, patch = minor+1, 0
else:
    patch += 1
build += 1
new = f'version: {major}.{minor}.{patch}+{build}'
p.write_text(text[:m.start()] + new + text[m.end():], encoding='utf-8')
print(new)
