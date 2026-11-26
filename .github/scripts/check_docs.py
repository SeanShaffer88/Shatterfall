"""Consistency checks for the Shatterfall design docs.

Run from the repo root: python .github/scripts/check_docs.py
Exits 1 and lists every problem found, or exits 0 when the docs agree.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
PIN = "4.7.2"
errors: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


docs = {p.name: p.read_text(encoding="utf-8") for p in sorted(ROOT.glob("*.md"))}
blueprint = docs.get("BLUEPRINT.md")
art = docs.get("ART_DIRECTION.md")
if blueprint is None or art is None:
    sys.exit("BLUEPRINT.md and ART_DIRECTION.md must exist at the repo root")

# 1. Decision Log rows are contiguous from D1, and every D# reference exists.
defined = [int(n) for n in re.findall(r"^\| D(\d+) \|", blueprint, re.M)]
if defined != list(range(1, len(defined) + 1)):
    fail(f"BLUEPRINT.md: Decision Log rows are not contiguous from D1: {defined}")
for name, text in docs.items():
    # (?<!#) skips hex colors such as #D92638.
    for n in sorted({int(n) for n in re.findall(r"(?<!#)\bD(\d+)\b", text)}):
        if n not in defined:
            fail(f"{name}: references D{n}, which is not in the Decision Log")

# 2. Every AD# reference exists in ART_DIRECTION.md.
ads = {int(n) for n in re.findall(r"^### AD(\d+)\b", art, re.M)}
for name, text in docs.items():
    for n in sorted({int(n) for n in re.findall(r"\bAD(\d+)\b", text)}):
        if n not in ads:
            fail(f"{name}: references AD{n}, which ART_DIRECTION.md does not define")

# 3. Code fences are balanced (earlier drafts broke on nested fences).
for name, text in docs.items():
    if len(re.findall(r"^\s*```", text, re.M)) % 2:
        fail(f"{name}: unbalanced ``` code fences")

# 4. Retired terms (D26, codename) appear only where they are retired.
for name, text in docs.items():
    for i, line in enumerate(text.splitlines(), 1):
        if re.search(r"\btiers?\b", line, re.I) and "retired" not in line:
            fail(f"{name}:{i}: uses 'tier' (retired by D26; say rarity or evo_stage)")
        if "Shattered Reliquary" in line and "retired" not in line:
            fail(f"{name}:{i}: uses the retired 'Shattered Reliquary' codename")
for path in ROOT.rglob("*"):
    if "reliquary" in path.name.lower() and ".git" not in path.parts:
        fail(f"{path.relative_to(ROOT)}: filename uses the retired codename")

# 5. Every Godot version mention matches the D22 pin.
for name, text in docs.items():
    for i, line in enumerate(text.splitlines(), 1):
        for v in re.findall(r"(?:Godot[ _]v?|Godot \*\*)(4\.\d+(?:\.(?:\d+|x))?)", line):
            if not PIN.startswith(v) and v != PIN:
                fail(f"{name}:{i}: Godot {v} does not match the D22 pin {PIN}")

# 6. Relative markdown links point at files that exist.
for name, text in docs.items():
    for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", text):
        if "://" in target or target.startswith("mailto:"):
            continue
        if not (ROOT / target).exists():
            fail(f"{name}: link to missing file '{target}'")

if errors:
    print(f"{len(errors)} docs problem(s):")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)
print(f"docs OK: {len(docs)} files, D1-D{len(defined)}, AD1-AD{max(ads)}")
