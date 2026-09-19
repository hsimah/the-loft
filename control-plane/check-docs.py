#!/usr/bin/env python3
"""Check local links/heading anchors in active docs; no external requests."""
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
HISTORICAL = (ROOT / "docs/archive", ROOT / "docs/audits")


def prose(text):
    """Remove fenced examples before looking for headings and links."""
    return re.sub(r"^```[^\n]*\n.*?^```[^\n]*$", "", text,
                  flags=re.MULTILINE | re.DOTALL)


def headings(path):
    anchors, counts = set(), {}
    for title in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", prose(path.read_text()), re.MULTILINE):
        slug = re.sub(r"[^\w\- ]", "", title.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(f"{slug}-{count}" if count else slug)
    return anchors


def main():
    errors, checked = [], 0
    for path in sorted(ROOT.rglob("*.md")):
        if ".git" in path.parts or any(path.is_relative_to(p) for p in HISTORICAL):
            continue
        for match in re.finditer(r"\[[^\]\n]*\]\(([^)\s]+)\)", prose(path.read_text())):
            dest = match.group(1).strip("<>")
            url = urlsplit(dest)
            if url.scheme or url.netloc:
                continue
            target = (path.parent / unquote(url.path)).resolve() if url.path else path
            checked += 1
            label = f"{path.relative_to(ROOT)}: {dest}"
            if not target.is_relative_to(ROOT):
                errors.append(f"{label}: escapes the repository")
            elif not target.exists():
                errors.append(f"{label}: missing target")
            elif url.fragment and target.suffix == ".md" and unquote(url.fragment) not in headings(target):
                errors.append(f"{label}: missing heading")
    for error in errors:
        print(error, file=sys.stderr)
    print(f"Checked {checked} active-document local links; {len(errors)} errors.")
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
