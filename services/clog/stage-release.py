#!/usr/bin/env python3
"""Verify and stage an immutable Clog archive; never touch live data or services."""
import argparse
import hashlib
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile
import tempfile


def inventory(root):
    result = {}
    for path in root.rglob('*'):
        if path.is_symlink() or not (path.is_file() or path.is_dir()):
            raise ValueError(f'Unexpected file in existing release: {path}')
        if path.is_dir():
            result[str(path.relative_to(root))] = None
        else:
            with path.open('rb') as src:
                result[str(path.relative_to(root))] = hashlib.file_digest(src, 'sha256').hexdigest()
    return result


def stage(archive, digest, releases, reuse=False):
    if not re.fullmatch(r'[a-f0-9]{64}', digest):
        raise ValueError('Expected a lowercase SHA-256 checksum')
    # Verify and extract the same open file, avoiding a path replacement race.
    with archive.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != digest:
            raise ValueError('Archive checksum mismatch')
        source.seek(0)
        releases.mkdir(parents=True, exist_ok=True)
        target = releases / digest
        if target.is_symlink() or (target.exists() and not reuse):
            raise ValueError('Release already exists; never overwrite a staged release')
        with tempfile.TemporaryDirectory(prefix='.stage-', dir=releases) as temp:
            root = Path(temp)
            with tarfile.open(fileobj=source, mode='r:gz') as bundle:
                members = bundle.getmembers()
                seen, total = set(), 0
                for member in members:
                    path = PurePosixPath(member.name)
                    if (path.is_absolute() or '..' in path.parts or not path.parts
                            or path.parts[0] not in {'server', 'client', 'hosting'}
                            or not (member.isfile() or member.isdir())
                            or path in seen):
                        raise ValueError(f'Unsafe or duplicate archive entry: {member.name}')
                    seen.add(path)
                    total += member.size
                if len(members) > 30000 or total > 256 * 1024 * 1024:
                    raise ValueError('Archive exceeds the release size limit')
                # Copy regular files ourselves: no symlinks, devices or archive ownership.
                for member in members:
                    dest = root / member.name
                    if member.isdir():
                        dest.mkdir(parents=True, exist_ok=True)
                    else:
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        with bundle.extractfile(member) as src, dest.open('xb') as out:
                            shutil.copyfileobj(src, out)
                        dest.chmod(0o644)
            for required in ('server/standalone/public/index.php', 'server/standalone/cli.php',
                             'server/vendor/autoload.php', 'client/dist/.vite/manifest.json',
                             'client/dist/assets/stylex.css'):
                if not (root / required).is_file():
                    raise ValueError(f'Missing release file: {required}')
            for directory in [root, *[p for p in root.rglob('*') if p.is_dir()]]:
                directory.chmod(0o755)
            if target.exists():
                if not target.is_dir() or inventory(target) != inventory(root):
                    raise ValueError('Existing release differs from the verified archive')
                return target
            # Keep the temporary directory manager separate from the renamed tree.
            root.rename(target)
    return target


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('sha256')
    parser.add_argument('--releases', type=Path, default=Path('/opt/clog/releases'))
    args = parser.parse_args()
    try:
        print(stage(args.archive, args.sha256, args.releases))
    except (ValueError, OSError, tarfile.TarError) as error:
        parser.exit(1, f'ERROR: {error}\n')
