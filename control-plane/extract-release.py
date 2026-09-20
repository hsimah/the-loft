#!/usr/bin/env python3
"""Extract static releases without links, special files or path traversal."""
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile


def extract(archive, destination):
    root = Path(destination)
    with tarfile.open(archive, 'r:gz') as tar:
        members = tar.getmembers()
        total = 0
        for member in members:
            path = PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Archive path escapes destination')
            if not (member.isdir() or member.isfile()):
                raise ValueError('Links and special files are not allowed')
            total += member.size
            if total > 512 * 1024 * 1024 or len(members) > 100000:
                raise ValueError('Static release exceeds extraction limits')
        for member in members:
            target = root / member.name
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as source, target.open('wb') as out:
                    shutil.copyfileobj(source, out)
    entries = list(root.iterdir())
    if len(entries) == 1 and entries[0].is_dir():
        wrapper = entries[0]
        for child in wrapper.iterdir():
            child.rename(root / child.name)
        wrapper.rmdir()
    if not (root / 'index.html').is_file():
        raise ValueError('Static release must contain index.html')


if __name__ == '__main__':
    extract(*sys.argv[1:])
