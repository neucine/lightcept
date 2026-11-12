#!/usr/bin/env python3
"""Reject Neiv package imports that do not name a bundled frontend asset."""

from __future__ import annotations

import re
import sys
from pathlib import Path

PACKAGE_IMPORT = re.compile(
    r"""(?:\bfrom\s*|\bimport\s*\(\s*)["'](/__weiv_packages/[^"']+)["']"""
)


def check(web_root: Path) -> list[str]:
    failures: list[str] = []
    for source in sorted((*web_root.rglob("*.mjs"), *web_root.rglob("*.js"))):
        text = source.read_text()
        for match in PACKAGE_IMPORT.finditer(text):
            request = match.group(1).split("?", 1)[0].split("#", 1)[0]
            target = web_root / request.removeprefix("/")
            if not target.is_file():
                line = text.count("\n", 0, match.start()) + 1
                failures.append(
                    f"{source.relative_to(web_root)}:{line}: package import has no bundled asset: {request}"
                )
    return failures


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-neiv-bundle.py <NeivApp Resources/web>", file=sys.stderr)
        return 2
    web_root = Path(sys.argv[1]).resolve()
    if not web_root.is_dir():
        print(f"Neiv web resource directory is missing: {web_root}", file=sys.stderr)
        return 2
    failures = check(web_root)
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
