#!/usr/bin/env python3
"""Comprueba que la versión del producto es coherente en todo el repositorio.

Fuente única: `app/pubspec.yaml` (`version: X.Y.Z+N`).
- `X.Y.Z` debe seguir el versionado semántico y coincidir con `backend/pyproject.toml`.
- `N` (número de compilación = versionCode de Android) debe ser un entero positivo.
- `app/lib/core/app_version.dart` debe repetir `X.Y.Z+N` (se anota en las copias).
- Con `--tag vX.Y.Z` comprueba además que el tag coincide.

Uso: python3 tool/check_versions.py [--tag v0.4.0]
"""

import argparse
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
_APP_VERSION = re.compile(r"^const appVersion = '([^']+)';", re.MULTILINE)
_PUBSPEC = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.MULTILINE)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--tag", help="tag a comprobar (p. ej. v0.4.0)")
    args = parser.parse_args()

    match = _PUBSPEC.search((ROOT / "app" / "pubspec.yaml").read_text(encoding="utf-8"))
    if not match:
        print("ERROR: app/pubspec.yaml debe tener 'version: X.Y.Z+N'")
        return 1
    version, build = match.group(1), int(match.group(2))
    if build < 1:
        print("ERROR: el número de compilación N debe ser >= 1")
        return 1

    with (ROOT / "backend" / "pyproject.toml").open("rb") as file:
        backend = tomllib.load(file)["project"]["version"]

    errors = []
    if backend != version:
        errors.append(f"backend/pyproject.toml tiene {backend}; app/pubspec.yaml tiene {version}")
    dart = _APP_VERSION.search(
        (ROOT / "app" / "lib" / "core" / "app_version.dart").read_text(encoding="utf-8")
    )
    if not dart or dart.group(1) != f"{version}+{build}":
        found = dart.group(1) if dart else "nada"
        errors.append(
            f"app/lib/core/app_version.dart tiene {found}; "
            f"app/pubspec.yaml tiene {version}+{build}"
        )
    if args.tag is not None and args.tag != f"v{version}":
        errors.append(f"el tag {args.tag} no coincide con v{version}")

    for error in errors:
        print(f"ERROR: {error}")
    if not errors:
        print(f"OK: versión {version}, compilación {build}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
